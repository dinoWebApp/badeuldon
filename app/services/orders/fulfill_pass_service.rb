# 수금 패스 발급 확정(F-PLAN — PLAN-4) — 주문(paid 전환)과 패스 발급을 한 트랜잭션으로 묶고
# with_lock + pending 재판정으로 직렬화한다. 콜백(PurchaseService)·웹훅(PortOneController) 어느
# 경로가 먼저 도착해도 발급은 정확히 1회다(SEC-5와 같은 멱등 원칙 — 이슈 #1·#4 회복 경로가
# 공유하는 확정점).
module Orders
  class FulfillPassService
    def initialize(order:, payment_id:, response: {})
      @order = order
      @payment_id = payment_id
      @response = response || {}
    end

    def call
      @order.with_lock do
        next unless @order.reload.pending? # 이미 확정된 주문 — 무변경(멱등)

        ActiveRecord::Base.transaction do
          @order.update!(status: :paid, paid_at: Time.current,
                         pg_payment_id: @payment_id, metadata: merged_metadata)
          # LEGAL-2 — 내용증명 양식 주문은 발급물(패스)이 없다: paid 확정만으로 충분하고
          # PDF 생성은 다운로드 시점(App::LegalDocumentsController#download)에 순수 수행한다.
          issue_pass! unless @order.legal_doc?
        end
      end
      @order
    end

    private

    # B-1(LEGAL-2·F-LEGAL Phase 6) — 결제 응답으로 metadata를 통째로 덮어쓰지 않는다.
    # legal_doc 주문은 orders.metadata["invoice_id"]가 청구 역참조의 유일 경로이므로
    # (App::LegalDocumentsController#order_invoice → download), 기존 metadata를 보존하고
    # 결제 응답을 병합한다. 덮어쓰면 paid 이후 다운로드가 영구 파탄난다.
    def merged_metadata
      (@order.metadata || {}).stringify_keys.merge(@response.stringify_keys)
    end

    # PLAN-4 — 수금 패스 발급: 10건, 발급 시점으로 90일 유효.
    def issue_pass!
      @order.user.payment_passes.create!(
        total_uses: PaymentPass::TOTAL_USES, remaining_uses: PaymentPass::TOTAL_USES,
        expires_at: PaymentPass::VALIDITY_DAYS.days.from_now
      )
    end
  end
end
