# 수금 패스 구매(F-PLAN — PLAN-4/5) — 리다이렉트 콜백의 결제 결과를 포트원 단건 승인으로
# 확정하고 주문(paid)과 수금 패스 발급을 한 트랜잭션으로 묶는다. 주문 행을 with_lock으로
# 직렬화하고 pending 재판정을 잠금 하에서 다시 해 이중 콜백·웹훅 경합에도 패스가 정확히
# 1회만 발급된다(SEC-5와 같은 멱등 원칙). 승인 요청에는 주문 레코드 원값을 totalAmount로,
# 환경 기대값(운영 false·그 외 true)을 isTest로 보내 포트원이 불일치 결제를 거절하게 한다
# (검증용 파라미터 — 재리뷰 R-1·R-2). 승인 응답(ConfirmedPaymentSummary — pgTxId·paidAt만)에는
# 금액·채널이 없어 검증에 쓸 수 없으므로, 승인 성공 뒤 반드시 get_payment로 재조회해 그 전체
# 결제 건을 확정 응답으로 삼고(콜백 경로 정정 — 2026-11-25), 확정점 FulfillPassService가
# PortOne::PaymentVerifier로 재조회한 결제 건의 실제 결제금액·채널 종류를 검증한다. 콜백
# 파라미터 금액은 신뢰하지 않는다. 실패는 PurchaseError로 예외화한다.
#
# 승인 모호 실패(이슈 #1) — 타임아웃·접속 실패는 요청이 포트원에 도달한 뒤 응답만 유실됐을 수
# 있어 실제 승인이 완료됐을 수 있다. 이때 failed 확정을 하지 않는다: ① 결제 조회로 실제 상태를
# 재확인해 PAID면 정상 발급 경로로 합류하고, ② 그 밖에는 pending 유지로 웹훅 자동 회복 경로를
# 연다. 명확한 비즈니스 거부(카드 한도 초과 등 — 포트원·PG 응답 코드)만 failed로 확정한다.
# 모호 실패를 failed로 굳히면 결제는 됐는데 패스는 없는 상태에서 재구매로 이중 결제가 된다.
#
# 즉시 승인 채널 — 수동 승인 설정이 아닌 채널은 위젯 응답에 paymentToken이 없다. 이때는
# 결제 조회로 승인 사실을 확정한다(같은 재조회 패턴).
#
# 승인 성공 뒤 재조회 실패(2026-11-25 콜백 경로 정정) — 승인(confirm)은 성공했는데 그 뒤
# 재조회가 실패하면(조회 오류·아직 PAID 아님) 결제가 이미 성립했을 수 있으므로 실패 확정
# 하지 않는다: pending 유지로 웹훅 자동 회복 경로를 연다. 승인 단계와 재조회 단계의 예외
# 처리는 섞지 않는다 — 승인 요청 자체의 ApiError는 call의 rescue PortOne::ApiError(모호
# 실패 재확인·ALREADY_PAID 회복·명확한 거부만 failed)가, 재조회 단계 실패는 rescue
# PendingApprovalError가 각각 담당한다.
#
# ALREADY_PAID(이슈 C1) — 모호 실패(타임아웃) 뒤 콜백을 재실행하면 이미 승인된 결제에
# 재승인을 요청하게 되고, 포트원은 ALREADY_PAID로 거부한다. 이는 실패가 아니라 결제 완료의
# 확정 신호다: 모호 실패와 마찬가지로 결제 조회로 PAID를 재확인해 정상 발급 경로로 합류하고,
# 재조회마저 실패하면 pending 유지로 웹훅 회복을 연다. ALREADY_PAID를 failed로 굳히면
# 결제는 됐는데 패스는 없는 상태가 된다(갱신 차감의 스티키 가드와 같은 원리).
module Orders
  class PurchaseService
    class PurchaseError < StandardError; end

    # 승인 전 상태 — 결제 조회 결과가 PAID가 아니면 아직 확정이 아니다. pending 유지로
    # 웹훅 회복을 기다린다(실패 확정 금지 — 이중 결제 방지). 승인 성공 뒤의 재조회 실패도
    # 같은 회복 대상이며, 이때는 조회 실패 원문(ApiError)을 함께 운반해 metadata에 보존한다.
    class PendingApprovalError < StandardError
      attr_reader :api_error

      def initialize(message = "결제가 아직 승인되지 않았습니다", api_error: nil)
        @api_error = api_error
        super(message)
      end
    end

    def initialize(order:, payment_token:, client: PortOne::ClientService.new)
      @order = order
      @payment_token = payment_token
      @client = client
    end

    def call
      @order.with_lock do
        raise PurchaseError, "이미 처리된 결제입니다" unless @order.pending?

        approve!
        FulfillPassService.new(order: @order, payment_id: @order.pg_order_id,
                               response: @portone_response).call
      end
      @order
    rescue PendingApprovalError => e
      # 아직 승인 전(즉시 승인 채널 재조회) 또는 승인 성공 뒤 재조회 실패 — 결제가 이미
      # 성립했을 수 있으므로 실패 확정 금지. pending 유지로 웹훅 회복을 연고, 재조회 단계의
      # 조회 실패(ApiError)는 원문을 metadata에 보존한다. 이 rescue는 with_lock 트랜잭션
      # 밖에서 실행되므로 metadata 기록이 롤백되지 않는다.
      keep_pending_for_webhook_recovery!(e.api_error)
      raise PurchaseError, recovery_message
    rescue PortOne::PaymentVerifier::VerificationError => e
      # 결제 확정 검증 실패(재리뷰 R-1·R-2) — 모호 실패가 아니다. pending으로 두면 웹훅도 같은
      # 검증으로 거절해 회복이 없고 사용자만 대기 화면에 갇히므로, 주문을 failed로 확정하고
      # 안내한다(사유는 metadata·로그에 보존 — Order#mark_verification_failed! R2-5 단일 구현).
      @order.mark_verification_failed!(reason: e.reason, detail: e.detail)
      raise PurchaseError, verification_message
    rescue PortOne::ApiError => e
      # 모호 실패 + 재확인 PAID, 또는 ALREADY_PAID(이미 승인됨 — confirm 재시도) — 정상
      # 발급 경로로 합류한다(예외 없이 주문을 돌려준다).
      recoverable = e.ambiguous? || e.already_paid?
      return @order if recoverable && recover_from_recheck!

      # 회복 불가 — 모호 실패·ALREADY_PAID는 pending 유지로 웹훅 회복을 열고(실패 확정 금지),
      # 명확한 비즈니스 거부만 failed로 확정한다.
      keep_pending_for_webhook_recovery!(e) if recoverable
      record_failure!(e) unless recoverable
      raise PurchaseError, recoverable ? recovery_message : "결제 승인에 실패했습니다 (#{e.message})"
    end

    private

    # 결제 확정 — 수동 승인 토큰(paymentToken)이 있으면 검증값(주문 금액·환경 기대 테스트
    # 여부)을 실어 승인 API로 확정한 뒤 반드시 재조회하고, 없으면(즉시 승인 채널) 결제 조회로
    # 승인 사실을 확인한다. 승인 응답(ConfirmedPaymentSummary — pgTxId·paidAt만)에는 금액·
    # 채널이 없어 검증에 쓸 수 없으므로, 두 경로 모두 확정 응답은 재조회한 전체 결제 건이다.
    def approve!
      @portone_response = if @payment_token.present?
        confirm_payment!
        recheck_after_confirm!
      else
        recheck_payment!
      end
    end

    # 승인 요청 — 이 줄의 ApiError는 여기서 잡지 않고 call의 rescue PortOne::ApiError(모호
    # 실패 재확인·ALREADY_PAID 회복·명확한 거부만 failed)로 그대로 흘려보낸다. 승인 단계와
    # 재조회 단계의 예외 처리를 섞지 않기 위한 분리다. currency는 KRW 단건 고정(R2-4).
    def confirm_payment!
      @client.confirm_payment(payment_id: @order.pg_order_id, payment_token: @payment_token,
                              total_amount: @order.amount,
                              is_test: !PortOne::ChannelKey.live_channel?,
                              currency: "KRW")
    end

    # 승인 성공 뒤의 재조회 — 실패(조회 오류·아직 PAID 아님)는 결제가 이미 성립했을 수 있는
    # 상태다. failed 확정 없이 PendingApprovalError(조회 실패 원문 동반)로 바꿔 올려 call의
    # rescue PendingApprovalError가 pending 유지로 웹훅 회복을 열게 한다.
    def recheck_after_confirm!
      recheck_payment!
    rescue PortOne::ApiError => e
      raise PendingApprovalError.new("승인 후 결제 재조회에 실패했습니다", api_error: e)
    end

    # 결제 조회 재확인 — PAID면 정상 발급 경로로 합류(paid+발급)한다. 모호 실패와
    # ALREADY_PAID(이미 승인됨)의 공통 합류 경로다. 아직 승인 전이거나 조회 실패면
    # false — pending 유지로 회복을 연다. 경합으로 웹훅이 먼저 확정한 경우에도
    # FulfillPassService의 pending 재판정이 흡수한다.
    def recover_from_recheck!
      FulfillPassService.new(order: @order.reload, payment_id: @order.pg_order_id,
                             response: recheck_payment!).call
      true
    rescue PortOne::PaymentVerifier::VerificationError => e
      # 재조회 응답도 주문과 일치하지 않는다 — pending 회복 대상이 아니다(웹훅도 같은 검증으로
      # 거절). failed로 확정한 뒤 컨트롤러로 안내 예외를 올린다(PurchaseError — call의
      # rescue PortOne::ApiError 절 안에서 호출되므로 그대로 전달된다).
      @order.mark_verification_failed!(reason: e.reason, detail: e.detail)
      raise PurchaseError, verification_message
    rescue PortOne::ApiError, PendingApprovalError
      false
    end

    # 결제 조회(재조회의 단일 지점) — PAID면 전체 결제 건을 돌려준다(확정 응답은 항상 이
    # 재조회 결과다). 아직 승인 전이면 PendingApprovalError, 조회 실패면 ApiError — 상위에서
    # 승인 단계(승인 성공 직후는 recheck_after_confirm!, 모호 실패·ALREADY_PAID 회복은
    # recover_from_recheck!)에 맞는 회복으로 처리한다.
    def recheck_payment!
      payment = @client.get_payment(payment_id: @order.pg_order_id)
      raise PendingApprovalError, "결제가 아직 승인되지 않았습니다" unless payment[:status] == "PAID"

      payment
    end

    # 회복 불가(아직 미승인·조회 실패) — pending 유지 + 결제 ID 보존. 웹훅이 도착하면
    # Webhooks::PortOneController가 이 주문을 찾아 FulfillPassService로 확정한다(이슈 #1).
    def keep_pending_for_webhook_recovery!(error)
      order = @order.reload
      return unless order.pending? # 경합 — 이미 확정됨

      # B-1(F-LEGAL Phase 6) — 기존 metadata(legal_doc 주문의 invoice_id 등)를 보존하고 병합한다.
      order.update!(pg_payment_id: order.pg_order_id,
                    metadata: (order.metadata || {}).stringify_keys.merge(
                      code: error&.code, message: error&.message,
                      pending_recovery: true
                    ))
    end

    def recovery_message
      "결제 확인이 지연되고 있습니다. 승인 결과는 잠시 후 자동으로 반영됩니다"
    end

    # 승인 실패 주문 기록 — 웹훅 재시도·CS 조사를 위한 원본 오류 보존. 이미 paid로 바뀐
    # 뒤(경합)라면 실패로 되돌리지 않는다.
    def record_failure!(error)
      return unless @order.reload.pending?

      # B-1(F-LEGAL Phase 6) — 기존 metadata(legal_doc 주문의 invoice_id 등)를 보존하고 병합한다.
      @order.update!(status: :failed,
                     metadata: (@order.metadata || {}).stringify_keys.merge(
                       code: error.code, message: error.message,
                       pg_code: error.pg_code, pg_message: error.pg_message
                     ))
    end

    def verification_message
      "결제 확인에 실패했습니다. 고객지원(문의)으로 연락해 주세요."
    end
  end
end
