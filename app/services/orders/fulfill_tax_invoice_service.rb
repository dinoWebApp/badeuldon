# TAX-1(Q21) — 전자세금계산서 발행 수수료 주문 확정. 웹훅(Webhooks::PortOneController)·콜백
# (PurchaseService) 어느 경로가 먼저 도착해도 발행은 정확히 1회다(SEC-5 멱등 —
# FulfillPassService 선례). metadata는 결제 응답으로 덮어쓰지 않고 병합한다(B-1 —
# orders.metadata["invoice_id"]가 청구 역참조의 유일 경로). paid 확정 후
# TaxInvoices::IssueService를 호출해 발행 요청까지 수행한다(결제 완료 후에만 발행 — PRD 전제).
module Orders
  class FulfillTaxInvoiceService
    def initialize(order:, payment_id:, response: {}, client: BaroBill::ClientService.new)
      @order = order
      @payment_id = payment_id
      @response = response || {}
      @client = client
    end

    def call
      @order.with_lock do
        next unless @order.reload.pending? # 이미 확정된 주문 — 무변경(멱등)

        ActiveRecord::Base.transaction do
          @order.update!(status: :paid, paid_at: Time.current,
                         pg_payment_id: @payment_id, metadata: merged_metadata)
        end
      end
      issue_after_payment
      @order
    end

    private

    # B-1(LEGAL-2 선례) — 기존 metadata 보존 + 결제 응답 병합. invoice_id 역참조 보호.
    def merged_metadata
      (@order.metadata || {}).stringify_keys.merge(@response.stringify_keys)
    end

    # 결제 확정 후 발행. 발행 실패는 주문 paid 상태를 되돌리지 않는다(결제는 성립 —
    # 발행 실패는 tax_invoices.status: failed·P4 기록으로 추적하며 CS 재시도 경로는 후속).
    def issue_after_payment
      invoice_id = @order.metadata.is_a?(Hash) ? @order.metadata["invoice_id"] : nil
      invoice = Invoice.find_by(id: invoice_id)
      return if invoice.nil?

      TaxInvoices::IssueService.new(invoice:, order: @order, client: @client).call
    rescue BaroBill::ClientService::ApiError => e
      Rails.logger.error("[TAX-1] 발행 실패(order=#{@order.id}): #{e.code} #{e.message}")
    rescue TaxInvoices::IssueService::GuardFailed => e
      # 가드 위반(설정 미완료·중복 발행 등) — 결제는 성립했으므로 paid를 되돌리지 않고
      # P4 관점 로그로 추적한다(세금계산서 레코드 미생성 — CS 재시도 경로는 후속).
      Rails.logger.error("[TAX-1] 발행 가드 위반(order=#{@order.id}): #{e.message}")
    end
  end
end
