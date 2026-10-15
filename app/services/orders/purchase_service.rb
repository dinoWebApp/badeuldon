# 수금 패스 구매(F-PLAN — PLAN-4/5) — 리다이렉트 콜백의 paymentKey를 토스 단건 승인으로
# 확정하고 주문(paid)과 수금 패스 발급을 한 트랜잭션으로 묶는다. 주문 행을 with_lock으로
# 직렬화하고 pending 재판정을 잠금 하에서 다시 해 이중 콜백·웹훅 경합에도 패스가 정확히
# 1회만 발급된다(SEC-5와 같은 멱등 원칙). 승인 금액은 주문 레코드의 원값만 사용한다
# (콜백 파라미터 금액은 참고용 — 서버값이 기준). 실패는 PurchaseError로 예외화한다.
#
# 승인 모호 실패(이슈 #1) — 타임아웃·접속 실패는 요청이 토스에 도달한 뒤 응답만 유실됐을 수
# 있어 실제 승인이 완료됐을 수 있다. 이때 failed 확정을 하지 않는다: ① 결제 조회로 실제 상태를
# 재확인해 DONE이면 정상 발급 경로로 합류하고, ② 그 밖에는 pending 유지 + paymentKey 보존으로
# 웹훅(DONE) 자동 회복 경로를 연다. 명확한 비즈니스 거부(카드 한도 초과 등 — 토스 응답 코드)만
# failed로 확정한다. 모호 실패를 failed로 굳히면 결제는 됐는데 패스는 없는 상태에서 재구매로
# 이중 결제가 되고, paymentKey 미보존으로 웹훅 회복도 불가능했다.
module Orders
  class PurchaseService
    class PurchaseError < StandardError; end

    def initialize(order:, payment_key:, client: TossPayments::ClientService.new)
      @order = order
      @payment_key = payment_key
      @client = client
    end

    def call
      @order.with_lock do
        raise PurchaseError, "이미 처리된 결제입니다" unless @order.pending?

        confirm!
        FulfillPassService.new(order: @order, payment_key: @payment_key,
                               response: @toss_response).call
      end
      @order
    rescue TossPayments::ApiError => e
      # 모호 실패 + 재확인 DONE — 정상 발급 경로로 합류(예외 없이 주문을 돌려준다).
      return @order if e.ambiguous? && recover_from_recheck!

      keep_pending_for_webhook_recovery!(e) if e.ambiguous?
      record_failure!(e) unless e.ambiguous?
      raise PurchaseError, e.ambiguous? ? recovery_message : "결제 승인에 실패했습니다 (#{e.message})"
    end

    private

    def confirm!
      @toss_response = @client.confirm_payment(
        order_id: @order.toss_order_id, payment_key: @payment_key, amount: @order.amount
      )
    end

    # 모호 실패 직후 결제 조회 재확인 — DONE이면 정상 확정(paid+발급)한다. 경합으로 웹훅이
    # 먼저 확정한 경우에도 FulfillPassService의 pending 재판정이 흡수한다.
    def recover_from_recheck!
      payment = @client.get_payment(payment_key: @payment_key)
      return false unless payment[:status] == "DONE"

      FulfillPassService.new(order: @order.reload, payment_key: @payment_key,
                             response: payment).call
      true
    rescue TossPayments::ApiError
      false
    end

    # 회복 불가(아직 미승인·조회 실패) — pending 유지 + paymentKey 보존. 웹훅 DONE이 도착하면
    # TossController가 이 주문을 찾아 FulfillPassService로 확정한다(이슈 #1 회복 경로).
    def keep_pending_for_webhook_recovery!(error)
      order = @order.reload
      return unless order.pending? # 경합 — 이미 확정됨

      order.update!(toss_payment_key: @payment_key,
                    metadata: { code: error.code, message: error.message,
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
                     metadata: { code: error.code, message: error.message })
    end
  end
end
