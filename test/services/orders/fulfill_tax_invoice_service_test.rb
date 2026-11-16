require "test_helper"
require_relative "../../test_helpers/fake_baro_bill_client"

# 세금계산서 주문 결제 확정(Orders::FulfillTaxInvoiceService — Q21·SEC-5 멱등·B-1 metadata 병합)
# 서비스 테스트. 웹훅·콜백 어느 경로가 와도 paid 전환 1회·발행 1회·metadata.invoice_id 보존,
# 발행 가드·SOAP 실패 흡수(500 없음 — 주문 paid 유지)를 검증한다.
class Orders::FulfillTaxInvoiceServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:delta)
    @invoice = invoices(:delta_paid)
    @order = @user.orders.create!(product: :collection_pass, item_type: :tax_invoice,
                                  amount: TaxInvoice::ISSUE_FEE, pg_order_id: "order-fulfill-ti-1",
                                  metadata: { invoice_id: @invoice.id })
    @client = FakeBaroBillClient.new
  end

  def make_ready!
    @user.update!(corp_num: "1234567890", corp_name: "델타디자인", ceo_name: "김델타",
                  corp_addr: "서울시 강남구", contact_name: "김델타", barobill_id: "bd001",
                  barobill_cert_registered: true)
  end

  test "확정 — 주문 paid·metadata 병합(invoice_id 보존)·발행 기록 생성 (SEC-5·B-1)" do
    make_ready!

    result = Orders::FulfillTaxInvoiceService.new(order: @order, payment_id: "order-fulfill-ti-1",
                                                  response: { "id" => "order-fulfill-ti-1",
                                                              "status" => "PAID" },
                                                  client: @client).call

    assert_equal @order.reload, result
    assert_predicate @order, :paid?
    assert_equal @invoice.id, @order.metadata["invoice_id"]     # B-1 — 결제 응답에 덮여 소실되지 않는다
    assert_equal "PAID", @order.metadata["status"]
    tax_invoice = TaxInvoice.find_by(invoice_id: @invoice.id)
    assert_not_nil tax_invoice
    assert_equal @order.id, tax_invoice.order_id
    assert_equal 1, @client.calls[:regist_and_issue_tax_invoice].count
  end

  test "가드 위반(설정 미완료)은 흡수된다 — 500 없음·주문 paid 유지·발행 기록 미생성 (C-2 전제 상태)" do
    result = Orders::FulfillTaxInvoiceService.new(order: @order, payment_id: "order-fulfill-ti-1",
                                                  client: @client).call

    assert_equal @order.reload, result
    assert_predicate @order, :paid?
    assert_nil TaxInvoice.find_by(invoice_id: @invoice.id)
    assert_empty @client.calls.values.flatten
  end

  test "SOAP 실패(ApiError)도 흡수된다 — 주문 paid 유지·발행 기록은 pending으로 P4 기록" do
    make_ready!
    client = FakeBaroBillClient.new(raise_on: { regist_and_issue_tax_invoice:
      BaroBill::ClientService::ApiError.new(code: "-871202", message: "전송 실패") })

    assert_nothing_raised do
      Orders::FulfillTaxInvoiceService.new(order: @order, payment_id: "order-fulfill-ti-1",
                                           client: client).call
    end

    assert_predicate @order.reload, :paid?
    assert_predicate TaxInvoice.find_by(invoice_id: @invoice.id), :pending?
  end

  test "중복 settle은 멱등으로 흡수된다 — paid 전환·발행 요청 정확히 1회 (SEC-5)" do
    make_ready!

    2.times do
      Orders::FulfillTaxInvoiceService.new(order: @order, payment_id: "order-fulfill-ti-1",
                                           response: { "id" => "order-fulfill-ti-1",
                                                       "status" => "PAID" },
                                           client: @client).call
    end

    assert_predicate @order.reload, :paid?
    assert_equal 1, @user.orders.tax_invoices.count
    assert_equal 1, TaxInvoice.where(invoice_id: @invoice.id).count
    assert_equal 1, @client.calls[:regist_and_issue_tax_invoice].count
    assert_equal 1, @user.payment_passes.count                  # tax_invoice 주문은 패스 발급 없음(fixture 1건 불변)
    assert_equal 10, @user.payment_passes.sole.remaining_uses
  end

  test "metadata에 invoice_id가 없으면 발행 없이 paid 확정만 수행한다" do
    order = @user.orders.create!(product: :collection_pass, item_type: :tax_invoice,
                                 amount: TaxInvoice::ISSUE_FEE, pg_order_id: "order-fulfill-ti-2")
    make_ready!

    assert_nothing_raised do
      Orders::FulfillTaxInvoiceService.new(order: order, payment_id: "order-fulfill-ti-2",
                                           client: @client).call
    end

    assert_predicate order.reload, :paid?
    assert_equal 0, TaxInvoice.count
    assert_empty @client.calls.values.flatten
  end
end
