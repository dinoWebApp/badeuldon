# TAX-1·Q21 — 세금계산서 발행 수수료(300원) 단건 주문 생성. 대기(pending) 주문이 있으면 재사용해
# 버튼 연타에도 주문이 누적되지 않는다(멱등 — OrdersController·LegalDocumentsController 선례).
# product는 단건 결제 채널 동작상 값 채움이며 품목 구분은 item_type(Order 주석 참조). 청구와의
# 결합은 orders.metadata(invoice_id)다. 컨트롤러 액션 축약을 위해 생성 책임을 이관했다(Phase 6 W-2).
module TaxInvoices
  class CreateOrderService
    # TAX-3 — 발급 자격 부적격(간이과세·면세사업자). message는 User 단일 출처 문구 그대로
    # (컨트롤러가 잡아 안내 리다이렉트로 수렴시킨다 — 500이 되지 않게).
    IneligibleUser = Class.new(StandardError)

    def self.call(user:, invoice:)
      # TAX-3 — 결제(300원)가 일어나기 전 차단하는 핵심 지점: 부적격 사용자의 주문은 만들지
      # 않는다(컨트롤러 가드의 이중 방어 — 호출 경로가 늘어도 결제가 시작되지 않는다).
      raise IneligibleUser, user.tax_invoice_ineligibility_notice unless user.tax_invoice_eligible?

      user.orders.pending.tax_invoices
          .find_by("JSON_EXTRACT(metadata, '$.invoice_id') = ?", invoice.id) ||
        user.orders.create!(
          product: :collection_pass,  # 단건 결제 채널 동작상 값 채움 — 품목 구분은 item_type(Order 주석 참조)
          item_type: :tax_invoice,
          amount: TaxInvoice::ISSUE_FEE,
          pg_order_id: SecureRandom.uuid,
          metadata: { invoice_id: invoice.id }
        )
    end
  end
end
