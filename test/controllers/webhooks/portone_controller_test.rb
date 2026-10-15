require "test_helper"
require_relative "../../test_helpers/portone_stubbing"
require_relative "../../test_helpers/fake_portone_client"

# 포트원 웹훅(PLAN-5) HTTP 테스트 — Transaction.* 이벤트 수신. 이벤트 값을 신뢰하지 않고
# get_payment 재조회로 무결성을 확정하는 동작(위조 이벤트 차단), 상품별 확정(수금 패스 발급·
# 갱신 주기 연장), 멱등 재시도 흡수, 미지원 type·깨진 JSON의 200 흡수를 검증한다.
# 재조회는 FakePortOneClient로 대체한다(실호출 금지).
# 시나리오 기준: _workspace/03_implementation.md §1(웹훅 이벤트)·§3.
class Webhooks::PortOneControllerTest < ActionDispatch::IntegrationTest
  include PortOneStubbing

  test "Transaction.Paid는 재조회 PAID로 수금 패스 주문을 확정하고 패스를 발급한다 (이슈 #1)" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-webhook-paid-1")
    fake = FakePortOneClient.new(get_payment: { id: "order-webhook-paid-1", status: "PAID" })

    with_portone_client(fake) do
      post_event "Transaction.Paid", "order-webhook-paid-1"
    end

    assert_response :ok
    order.reload
    assert_predicate order, :paid?
    assert_equal "order-webhook-paid-1", order.pg_payment_id
    pass = users(:gamma).payment_passes.sole
    assert_equal 10, pass.remaining_uses
    # 이벤트가 아니라 재조회 응답으로 확정했다 — paymentId로 정확히 1회 조회
    assert_equal [ { payment_id: "order-webhook-paid-1", store_id: nil } ],
                 fake.calls[:get_payment]
  end

  test "Transaction.Paid 재시도는 멱등으로 흡수되고 패스가 추가 발급되지 않는다 (SEC 멱등)" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-webhook-retry-1")
    fake = FakePortOneClient.new(get_payment: { id: "order-webhook-retry-1", status: "PAID" })

    with_portone_client(fake) do
      2.times { post_event "Transaction.Paid", "order-webhook-retry-1" }
    end

    assert_response :ok
    assert_equal 1, users(:gamma).payment_passes.count     # 발급 정확히 1회
    assert_predicate order.reload, :paid?
  end

  test "재조회 응답이 타 결제면 위조 이벤트로 무변경 흡수한다" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-webhook-forged-1")
    fake = FakePortOneClient.new(get_payment: { id: "payment-of-other-order", status: "PAID" })

    with_portone_client(fake) do
      post_event "Transaction.Paid", "order-webhook-forged-1"
    end

    assert_response :ok
    assert_predicate order.reload, :pending?               # 이벤트 값으로 확정하지 않는다
    assert_empty users(:gamma).payment_passes
  end

  test "Transaction.Paid는 pending Plus 갱신 주문을 settle_renewal로 확정하고 주기를 연장한다 (이슈 #4)" do
    users(:gamma).create_subscription!(plan: :plus, status: :active,
                                       pg_billing_key: "tok_billing_1",
                                       current_period_end: Time.zone.parse("2026-10-31 23:59:59"))
    order = users(:gamma).orders.create!(product: :plus_monthly, amount: 9_900,
                                         pg_order_id: "order-webhook-renew-1",
                                         metadata: { "ambiguous" => true })
    fake = FakePortOneClient.new(get_payment: { id: "order-webhook-renew-1", status: "PAID" })

    travel_to(Time.zone.parse("2026-11-02 09:00")) do
      with_portone_client(fake) do
        post_event "Transaction.Paid", "order-webhook-renew-1"
      end
    end

    assert_response :ok
    order.reload
    assert_predicate order, :paid?
    assert_equal "order-webhook-renew-1", order.pg_payment_id
    subscription = users(:gamma).subscription.reload
    assert_predicate subscription, :active?                # 웹훅 확정 — 만료 아님
    assert_equal Time.zone.parse("2026-10-31 23:59:59"), subscription.current_period_start
    assert_equal Time.zone.parse("2026-11-30 23:59:59"), subscription.current_period_end
  end

  test "Transaction.Cancelled는 paid 주문을 cancelled로 동기화한다 (콘솔 환불)" do
    fake = FakePortOneClient.new(get_payment: { id: orders(:delta_pass_order).pg_order_id,
                                                status: "CANCELLED" })

    with_portone_client(fake) do
      post_event "Transaction.Cancelled", orders(:delta_pass_order).pg_order_id
    end

    assert_response :ok
    assert_predicate orders(:delta_pass_order).reload, :cancelled?
  end

  test "Transaction.Failed는 pending 주문을 failed로 동기화한다" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-webhook-failed-1")
    fake = FakePortOneClient.new(get_payment: { id: "order-webhook-failed-1", status: "FAILED" })

    with_portone_client(fake) do
      post_event "Transaction.Failed", "order-webhook-failed-1"
    end

    assert_response :ok
    assert_predicate order.reload, :failed?
    assert_empty users(:gamma).payment_passes
  end

  test "Transaction.PartialCancelled도 cancelled로 동기화한다" do
    fake = FakePortOneClient.new(get_payment: { id: orders(:delta_pass_order).pg_order_id,
                                                status: "PARTIAL_CANCELLED" })

    with_portone_client(fake) do
      post_event "Transaction.PartialCancelled", orders(:delta_pass_order).pg_order_id
    end

    assert_response :ok
    assert_predicate orders(:delta_pass_order).reload, :cancelled?
  end

  test "미지원 type(BillingKey.*)는 포트원 호출 없이 200으로 흡수된다" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-webhook-billingkey-1")
    fake = FakePortOneClient.new

    with_portone_client(fake) do
      post_event "BillingKey.Issued", "order-webhook-billingkey-1"
    end

    assert_response :ok
    assert_empty fake.calls.values.flatten                 # 재조회 없음 — 동기화 대상 아님
    assert_predicate order.reload, :pending?
  end

  test "paymentId가 없는 이벤트는 재조회 없이 200으로 흡수된다" do
    fake = FakePortOneClient.new

    with_portone_client(fake) do
      post "/webhooks/portone", params: { type: "Transaction.Paid", data: {} }.to_json,
           headers: { "Content-Type" => "application/json" }
    end

    assert_response :ok
    assert_empty fake.calls.values.flatten
  end

  test "알 수 없는 결제의 이벤트는 200으로 흡수된다" do
    fake = FakePortOneClient.new

    with_portone_client(fake) do
      post_event "Transaction.Paid", "order-unknown-payment"
    end

    assert_response :ok                                    # 재시도해도 같은 결과 — 흡수
    assert_empty fake.calls.values.flatten                 # 주문 탐색 실패 — 재조회 없음
  end

  test "깨진 JSON 본문도 200으로 흡수된다 (재시도 유발 금지)" do
    fake = FakePortOneClient.new

    with_portone_client(fake) do
      post "/webhooks/portone", params: "{broken-json", headers: { "Content-Type" => "application/json" }
    end

    assert_response :ok
    assert_empty fake.calls.values.flatten
  end

  private

  def post_event(type, payment_id)
    post "/webhooks/portone",
         params: { type: type, data: { paymentId: payment_id } }.to_json,
         headers: { "Content-Type" => "application/json" }
  end
end
