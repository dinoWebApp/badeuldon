require "test_helper"
require_relative "../../test_helpers/portone_stubbing"
require_relative "../../test_helpers/fake_portone_client"

# 결제 콜백 착지(C-1 회귀 — GET /app/orders/callback) HTTP 테스트. tax_invoice 주문은 발행 주문
# 상세로 착지하고 세금계산서 전용 문구를 내보낸다(수금 패스 문구 오노출 교정의 회귀 방지).
# legal_doc·pass 주문의 기존 착지·문구는 유지된다. 승인은 FakePortOneClient 스텁(실호출 금지).
class App::TaxInvoiceCallbackTest < ActionDispatch::IntegrationTest
  include PortOneStubbing

  setup do
    @user = users(:delta)
    @invoice = invoices(:delta_paid)
    travel_to(Time.zone.parse("2026-10-12 09:00"))
  end

  teardown do
    travel_back
  end

  def create_order(item_type)
    @user.orders.create!(product: :collection_pass, item_type: item_type,
                         amount: 300, pg_order_id: "order-callback-#{item_type}",
                         metadata: { invoice_id: @invoice.id })
  end

  def confirm_via_callback(order)
    # paymentToken 없는 콜백(즉시 승인 채널) — 결제 조회로 확정한다. 재조회 응답은 결제 확정
    # 검증(FulfillPassService)을 통과하는 형태로 조립한다(재리뷰 R-1·R-2 — 금액·채널 포함).
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: order.pg_order_id, amount: order.amount)
    )
    with_portone_client(fake) do
      get callback_app_orders_path, params: { paymentId: order.pg_order_id }
    end
  end

  # C-1 — tax_invoice 주문 콜백 착지: 발행 주문 show + 세금계산서 문구(패스 문구 아님).
  test "C-1: tax_invoice 주문 콜백은 발행 주문 show로 착지하고 세금계산서 문구를 내보낸다" do
    sign_in_as @user
    order = create_order(:tax_invoice)

    confirm_via_callback(order)

    assert_redirected_to app_tax_invoice_path(order)
    assert_match(/전자세금계산서 발행 결제가 완료되었습니다/, flash[:notice])
    assert_no_match(/수금 패스/, flash[:notice])
    assert_predicate order.reload, :paid?
  end

  test "회귀 방지: legal_doc 주문 콜백은 기존 착지·문구를 유지한다" do
    sign_in_as @user
    order = create_order(:legal_doc)

    confirm_via_callback(order)

    assert_redirected_to app_legal_document_path(order)
    assert_match(/내용증명/, flash[:notice])
    assert_predicate order.reload, :paid?
  end

  test "회귀 방지: pass 주문 콜백은 요금제 화면·패스 문구를 유지한다" do
    sign_in_as @user
    order = @user.orders.create!(product: :collection_pass, item_type: :pass,
                                 amount: 4_000, pg_order_id: "order-callback-pass")

    confirm_via_callback(order)

    assert_redirected_to app_billing_path
    assert_match(/수금 패스/, flash[:notice])
    # delta_active_pass fixture 1건 + 신규 발급 1건 — 발급은 정확히 1회
    assert_equal 2, @user.reload.payment_passes.count
    assert_equal 10, @user.payment_passes.order(:id).last.remaining_uses
  end
end
