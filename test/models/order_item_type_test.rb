require "test_helper"

class OrderItemTypeTest < ActiveSupport::TestCase
  fixtures :orders, :users

  # LEGAL-2(Q5) — orders.item_type 추가의 무영향·동작 검증. 기존 주문은 default 0(pass)이며
  # 내용증명 주문은 item_type=legal_doc로 생성한다(product는 단건 결제 채널 동작상
  # collection_pass 값을 채운다 — Order 주석 참조).
  test "기존 주문은 item_type 기본값 pass다 — 수금 패스 결제 플로우 무영향" do
    assert orders(:delta_pass_order).pass?
    assert_not orders(:delta_pass_order).legal_doc?
  end

  test "legal_doc 주문을 건당 5,000원으로 생성한다" do
    user = users(:delta)
    order = user.orders.create!(
      product: :collection_pass, item_type: :legal_doc,
      amount: Order::LEGAL_DOC_PRICE, pg_order_id: SecureRandom.uuid,
      metadata: { invoice_id: 1 }
    )

    assert order.legal_doc?
    assert_equal 5_000, Order::LEGAL_DOC_PRICE
    assert_equal 1, order.metadata["invoice_id"]
  end

  test "legal_docs 스코프는 item_type=legal_doc 주문만 반환한다" do
    user = users(:delta)
    legal_order = user.orders.create!(product: :collection_pass, item_type: :legal_doc,
                                      amount: Order::LEGAL_DOC_PRICE, pg_order_id: SecureRandom.uuid)

    assert_includes user.orders.legal_docs, legal_order
    assert_not_includes user.orders.legal_docs, orders(:delta_pass_order)
  end

  # 결제 완료 전환 시나리오 — FulfillPassService가 legal_doc 주문은 발급물 없이 paid만 확정한다
  # (콜백·웹훅 어느 경로가 먼저 와도 동일 — SEC-5 멱등).
  test "FulfillPassService — legal_doc 주문은 paid 전환만 하고 수금 패스를 발급하지 않는다" do
    user = users(:delta)
    order = user.orders.create!(product: :collection_pass, item_type: :legal_doc,
                                amount: Order::LEGAL_DOC_PRICE, pg_order_id: SecureRandom.uuid)

    assert_no_changes -> { PaymentPass.count } do
      Orders::FulfillPassService.new(order: order, payment_id: order.pg_order_id,
                                     response: { id: order.pg_order_id, status: "PAID" }).call
    end
    assert order.reload.paid?
  end

  test "FulfillPassService — pass 주문은 기존대로 수금 패스를 발급한다(회귀 가드)" do
    user = users(:delta)
    order = user.orders.create!(product: :collection_pass, item_type: :pass,
                                amount: 4_000, pg_order_id: SecureRandom.uuid)

    assert_difference -> { PaymentPass.count }, 1 do
      Orders::FulfillPassService.new(order: order, payment_id: order.pg_order_id,
                                     response: { id: order.pg_order_id, status: "PAID" }).call
    end
    assert order.reload.paid?
  end

  test "FulfillPassService는 멱등이다 — legal_doc 주문 재확정 무변경" do
    user = users(:delta)
    order = user.orders.create!(product: :collection_pass, item_type: :legal_doc,
                                amount: Order::LEGAL_DOC_PRICE, pg_order_id: SecureRandom.uuid)
    service = -> {
      Orders::FulfillPassService.new(order: order, payment_id: order.pg_order_id,
                                     response: { status: "PAID" }).call
    }

    service.call
    assert_no_changes -> { order.reload.attributes["paid_at"] } do
      service.call
    end
  end
end
