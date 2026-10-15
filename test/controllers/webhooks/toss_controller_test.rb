require "test_helper"
require_relative "../../test_helpers/toss_stubbing"
require_relative "../../test_helpers/fake_toss_client"

# 토스페이먼츠 웹훅(F-PLAN — PLAN-5) HTTP 테스트 — paymentStatusChanged 상태 매핑·무결성
# (이벤트 값 미신뢰 — get_payment 재조회 확정)·항상 200·비인증 허용·멱등.
# 재조회는 TossPayments::ClientService.new를 FakeTossClient로 스텁한다(실호출 금지).
# 시나리오 기준: _workspace/03_implementation.md §3 (웹훅 플로우)·§4 (상태 매핑 표).
class Webhooks::TossControllerTest < ActionDispatch::IntegrationTest
  include TossStubbing

  test "DONE 이벤트는 재조회 응답 기준으로 주문을 paid로 갱신하고 200을 돌려준다" do
    fake = FakeTossClient.new(get_payment: { status: "DONE" })

    with_toss_client(fake) do
      post_toss_event(payment_key: orders(:delta_pass_order).toss_payment_key, status: "DONE")
    end

    assert_response :success
    assert_predicate orders(:delta_pass_order).reload, :paid?
    assert_equal [ { payment_key: "pay-delta-pass-0001" } ], fake.calls[:get_payment]
  end

  test "CANCELED·ABORTED 이벤트는 취소·실패로 매핑한다" do
    fake = FakeTossClient.new(get_payment: { status: "CANCELED" })

    with_toss_client(fake) do
      post_toss_event(payment_key: orders(:delta_pass_order).toss_payment_key, status: "CANCELED")
    end

    assert_response :success
    assert_predicate orders(:delta_pass_order).reload, :cancelled?

    orders(:delta_pass_order).update!(status: :paid)
    fake = FakeTossClient.new(get_payment: { status: "ABORTED" })

    with_toss_client(fake) do
      post_toss_event(payment_key: orders(:delta_pass_order).toss_payment_key, status: "ABORTED")
    end

    assert_response :success
    assert_predicate orders(:delta_pass_order).reload, :failed?
  end

  test "이벤트 값이 아니라 재조회 응답을 기준으로 확정한다 (위조 이벤트 차단)" do
    fake = FakeTossClient.new(get_payment: { status: "CANCELED" })  # 재조회는 취소

    with_toss_client(fake) do
      post_toss_event(payment_key: orders(:delta_pass_order).toss_payment_key, status: "DONE")  # 이벤트는 DONE 주장
    end

    assert_response :success
    assert_predicate orders(:delta_pass_order).reload, :cancelled?
  end

  test "이미 같은 상태면 무변경으로 흡수된다 (재시도 멱등)" do
    fake = FakeTossClient.new(get_payment: { status: "DONE" })

    with_toss_client(fake) do
      2.times do
        post_toss_event(payment_key: orders(:delta_pass_order).toss_payment_key, status: "DONE")
        assert_response :success
      end
    end

    assert_predicate orders(:delta_pass_order).reload, :paid?
    assert_equal 2, fake.calls[:get_payment].length     # 재조회는 매번 — 상태 갱신은 1회
  end

  test "paymentStatusChanged가 아닌 이벤트는 주문을 변경하지 않고 200을 돌려준다" do
    fake = FakeTossClient.new

    with_toss_client(fake) do
      post "/webhooks/toss", params: { eventType: "testMethod", data: { paymentKey: "pay-x" } }
    end

    assert_response :success
    assert_predicate orders(:delta_pass_order).reload, :paid?   # 무변경
    assert_empty fake.calls[:get_payment]
  end

  test "파싱 불가능한 본문도 200을 돌려준다 (토스 재시도 유발 금지)" do
    post "/webhooks/toss", params: "{not-json", headers: { "Content-Type" => "application/json" }

    assert_response :success
  end

  test "알 수 없는 paymentKey도 200을 돌려준다 (재시도 무의미 — 흡수)" do
    post_toss_event(payment_key: "pay-unknown-1", status: "DONE")

    assert_response :success
  end

  test "웹훅은 세션 인증 없이 수신된다 (토스 서버 간 호출 — 비인증 허용)" do
    fake = FakeTossClient.new(get_payment: { status: "DONE" })

    with_toss_client(fake) do
      post_toss_event(payment_key: orders(:delta_pass_order).toss_payment_key, status: "DONE")
    end

    assert_response :success   # sign_in_as 없이 — 302 리다이렉트가 아니다
  end

  test "paymentKey 보존 pending 패스 주문의 DONE은 재조회 확정 후 패스를 발급한다 (이슈 #1 회복)" do
    order = users(:delta).orders.create!(product: :collection_pass, amount: 4_000,
                                         toss_order_id: "order-webhook-pass-pending-1",
                                         toss_payment_key: "pay-webhook-amb-1",
                                         metadata: { "ambiguous" => true })
    fake = FakeTossClient.new(get_payment: { status: "DONE", orderId: order.toss_order_id })

    with_toss_client(fake) do
      post_toss_event(payment_key: "pay-webhook-amb-1", status: "DONE")
    end

    assert_response :success
    order.reload
    assert_predicate order, :paid?
    # fixture 보유 패스(delta_active_pass) + 회복 발급 1건
    assert_equal 2, users(:delta).payment_passes.count
    assert_equal 10, users(:delta).payment_passes.order(:id).last.remaining_uses
  end

  test "paymentKey를 모르는 pending 갱신 주문은 orderId 보조 매칭으로 회복된다 (이슈 #4)" do
    users(:gamma).create_subscription!(plan: :plus, status: :active,
                                       toss_billing_key: "tok_billing_1",
                                       current_period_end: Time.zone.parse("2026-10-10 12:00"))
    order = users(:gamma).orders.create!(product: :plus_monthly, amount: 9_900,
                                         toss_order_id: "order-webhook-renew-pending-1",
                                         metadata: { "ambiguous" => true })
    fake = FakeTossClient.new(get_payment: { status: "DONE", orderId: order.toss_order_id,
                                             paymentKey: "pay-webhook-renew-1" })

    with_toss_client(fake) do
      post "/webhooks/toss",
           params: { eventType: "paymentStatusChanged",
                     data: { paymentKey: "pay-webhook-renew-1", orderId: order.toss_order_id,
                             status: "DONE" } }.to_json,
           headers: { "Content-Type" => "application/json" }
    end

    assert_response :success
    order.reload
    assert_predicate order, :paid?
    assert_equal "pay-webhook-renew-1", order.toss_payment_key
    subscription = users(:gamma).subscription.reload
    assert_equal Time.zone.parse("2026-11-10 12:00"), subscription.current_period_end
  end

  test "orderId 보조 매칭 주문은 재조회 응답의 orderId가 일치할 때만 확정된다 (위조 결합 차단)" do
    order = users(:gamma).orders.create!(product: :plus_monthly, amount: 9_900,
                                         toss_order_id: "order-webhook-renew-pending-2")
    fake = FakeTossClient.new(get_payment: { status: "DONE", orderId: "order-of-another-payment" })

    with_toss_client(fake) do
      post "/webhooks/toss",
           params: { eventType: "paymentStatusChanged",
                     data: { paymentKey: "pay-webhook-forged-1", orderId: order.toss_order_id,
                             status: "DONE" } }.to_json,
           headers: { "Content-Type" => "application/json" }
    end

    assert_response :success
    assert_predicate order.reload, :pending?   # 다른 결제의 paymentKey 결합 — 무변경
  end

  test "paymentKey 없는 이벤트는 흡수된다 (재조회 불가 — 전체 스캔 방어)" do
    fake = FakeTossClient.new

    with_toss_client(fake) do
      post "/webhooks/toss",
           params: { eventType: "paymentStatusChanged", data: { status: "DONE" } }.to_json,
           headers: { "Content-Type" => "application/json" }
    end

    assert_response :success
    assert_empty fake.calls[:get_payment]
    assert_predicate orders(:delta_pass_order).reload, :paid?   # 무변경
  end

  private

  def post_toss_event(payment_key:, status:)
    post "/webhooks/toss",
         params: { eventType: "paymentStatusChanged",
                   data: { paymentKey: payment_key, status: status } }.to_json,
         headers: { "Content-Type" => "application/json" }
  end
end
