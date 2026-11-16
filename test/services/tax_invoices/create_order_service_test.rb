require "test_helper"

# 발행 수수료 주문 생성(TaxInvoices::CreateOrderService — Q21·W-2) 테스트.
# 300원 고정(Q21 상수 단일 출처)·pending 주문 재사용 멱등·metadata.invoice_id 결합을 검증한다.
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
end
