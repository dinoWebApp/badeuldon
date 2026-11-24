require "test_helper"

# 발행 수수료 주문 생성(TaxInvoices::CreateOrderService — Q21·W-2) 테스트.
# 300원 고정(Q21 상수 단일 출처)·pending 주문 재사용 멱등·metadata.invoice_id 결합·
# TAX-3 부적격 사용자 주문 미생성(결제 전 차단 — ③ 핵심 지점)을 검증한다.
class TaxInvoices::CreateOrderServiceTest < ActiveSupport::TestCase
  test "300원 tax_invoice 주문을 만들고 metadata에 invoice_id를 기록한다 (Q21)" do
    user = users(:gamma)
    invoice = invoices(:delta_paid)

    order = TaxInvoices::CreateOrderService.call(user: user, invoice: invoice)

    assert_predicate order, :pending?
    assert_predicate order, :tax_invoice?
    assert_equal TaxInvoice::ISSUE_FEE, order.amount            # 300원 고정 — 상수 단일 출처
    assert_equal invoice.id, order.metadata["invoice_id"]
    assert_predicate order.pg_order_id, :present?
  end

  test "대기 주문이 있으면 재사용한다 — 연타에도 주문이 누적되지 않는다 (멱등)" do
    user = users(:gamma)
    invoice = invoices(:delta_paid)
    first = TaxInvoices::CreateOrderService.call(user: user, invoice: invoice)

    assert_no_difference -> { user.orders.count } do
      second = TaxInvoices::CreateOrderService.call(user: user, invoice: invoice)
      assert_equal first.id, second.id
    end
  end

  test "다른 청구의 pending 주문은 재사용하지 않는다" do
    user = users(:delta)
    invoice_a = invoices(:delta_paid)
    invoice_b = invoices(:delta_partially_paid)
    first = TaxInvoices::CreateOrderService.call(user: user, invoice: invoice_a)

    second = TaxInvoices::CreateOrderService.call(user: user, invoice: invoice_b)

    assert_not_equal first.id, second.id
    assert_equal invoice_b.id, second.metadata["invoice_id"]
  end

  # TAX-3 ③(2026-11-24·Q25) — 부적격 사용자의 주문은 만들지 않는다. 300원이 결제되기 전
  # 차단하는 핵심 지점이며 예외 message는 User 단일 출처 문구다(컨트롤러가 안내로 수렴).
  test "TAX-3: 간이과세 사용자는 주문을 만들지 않고 IneligibleUser다" do
    user = users(:gamma)
    user.update!(tax_type: :simplified)

    error = assert_raises(TaxInvoices::CreateOrderService::IneligibleUser) do
      TaxInvoices::CreateOrderService.call(user: user, invoice: invoices(:delta_paid))
    end

    assert_equal user.tax_invoice_ineligibility_notice, error.message
    assert_empty user.orders.tax_invoices
  end

  test "TAX-3: 면세사업자 사용자도 주문을 만들지 않고 IneligibleUser다" do
    user = users(:gamma)
    user.update!(tax_type: :exempt)

    error = assert_raises(TaxInvoices::CreateOrderService::IneligibleUser) do
      TaxInvoices::CreateOrderService.call(user: user, invoice: invoices(:delta_paid))
    end

    assert_equal user.tax_invoice_ineligibility_notice, error.message
    assert_empty user.orders.tax_invoices
  end
end
