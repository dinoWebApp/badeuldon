# 수금 패스 구매(F-PLAN — PLAN-4/5) — 리다이렉트 콜백의 결제 결과를 포트원 단건 승인으로
# 확정하고 주문(paid)과 수금 패스 발급을 한 트랜잭션으로 묶는다. 주문 행을 with_lock으로
# 직렬화하고 pending 재판정을 잠금 하에서 다시 해 이중 콜백·웹훅 경합에도 패스가 정확히
# 1회만 발급된다(SEC-5와 같은 멱등 원칙). 승인 금액은 위젯 호출 시 주문 레코드의 원값을
# 사용하며(포트원이 검증), 콜백 파라미터 금액은 신뢰하지 않는다. 실패는 PurchaseError로
# 예외화한다.
#
# 승인 모호 실패(이슈 #1) — 타임아웃·접속 실패는 요청이 포트원에 도달한 뒤 응답만 유실됐을 수
# 있어 실제 승인이 완료됐을 수 있다. 이때 failed 확정을 하지 않는다: ① 결제 조회로 실제 상태를
# 재확인해 PAID면 정상 발급 경로로 합류하고, ② 그 밖에는 pending 유지로 웹훅 자동 회복 경로를
# 연다. 명확한 비즈니스 거부(카드 한도 초과 등 — 포트원·PG 응답 코드)만 failed로 확정한다.
# 모호 실패를 failed로 굳히면 결제는 됐는데 패스는 없는 상태에서 재구매로 이중 결제가 된다.
#
# 즉시 승인 채널 — 수동 승인 설정이 아닌 채널은 위젯 응답에 paymentToken이 없다. 이때는
# 결제 조회로 승인 사실을 확정한다(같은 재확인 패턴).
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
    # 웹훅 회복을 기다린다(실패 확정 금지 — 이중 결제 방지).
    class PendingApprovalError < StandardError; end

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
    rescue PendingApprovalError
      keep_pending_for_webhook_recovery!(nil)
      raise PurchaseError, recovery_message
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

    # 결제 확정 — 수동 승인 토큰(paymentToken)이 있으면 승인 API로 확정하고, 없으면(즉시
    # 승인 채널) 결제 조회로 승인 사실을 확인한다.
    def approve!
      @portone_response = if @payment_token.present?
        @client.confirm_payment(payment_id: @order.pg_order_id, payment_token: @payment_token)
      else
        recheck_payment!
      end
    end

    # 결제 조회 재확인 — PAID면 정상 발급 경로로 합류(paid+발급)한다. 모호 실패와
    # ALREADY_PAID(이미 승인됨)의 공통 합류 경로다. 아직 승인 전이거나 조회 실패면
    # false — pending 유지로 회복을 연다. 경합으로 웹훅이 먼저 확정한 경우에도
    # FulfillPassService의 pending 재판정이 흡수한다.
    def recover_from_recheck!
      FulfillPassService.new(order: @order.reload, payment_id: @order.pg_order_id,
                             response: recheck_payment!).call
      true
    rescue PortOne::ApiError, PendingApprovalError
      false
    end

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

      order.update!(pg_payment_id: order.pg_order_id,
                    metadata: { code: error&.code, message: error&.message,
                                pending_recovery: true })
    end

    def recovery_message
      "결제 확인이 지연되고 있습니다. 승인 결과는 잠시 후 자동으로 반영됩니다"
    end

    # 승인 실패 주문 기록 — 웹훅 재시도·CS 조사를 위한 원본 오류 보존. 이미 paid로 바뀐
    # 뒤(경합)라면 실패로 되돌리지 않는다.
    def record_failure!(error)
      return unless @order.reload.pending?

      @order.update!(status: :failed,
                     metadata: { code: error.code, message: error.message,
                                 pg_code: error.pg_code, pg_message: error.pg_message })
    end
  end
end
