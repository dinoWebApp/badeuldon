require "test_helper"
require_relative "../../test_helpers/portone_stubbing"
require_relative "../../test_helpers/fake_portone_client"

# 수금 패스 주문(F-PLAN — PLAN-4/5) HTTP 테스트 — create(대기 주문 멱등 생성)·callback
# (포트원 위젯 결과 paymentId·paymentToken 수신 후 승인 확정). 승인 경로는
# PortOne::ClientService.new를 FakePortOneClient로 스텁한다(실호출 금지). 소유권 격리와
# 오류 흡수를 검증한다.
# 시나리오 기준: _workspace/03_implementation.md §1·§3 (수금 패스 구매 플로우).
class App::OrdersControllerTest < ActionDispatch::IntegrationTest
  include PortOneStubbing

  test "비인증 주문 생성은 302로 로그인 화면에 리다이렉트된다 (AUTH-1)" do
    post app_orders_path

    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "패스 구매는 4,000원 대기 주문을 만들고 체크아웃으로 전환한다 (PLAN-4 정가)" do
    sign_in_as users(:gamma)

    assert_difference -> { users(:gamma).orders.count }, 1 do
      post app_orders_path
    end

    assert_response :redirect
    order = users(:gamma).orders.sole
    assert_redirected_to app_billing_path(checkout: order.pg_order_id)
    assert_predicate order, :pending?
    assert_predicate order, :collection_pass?
    assert_equal 4_000, order.amount                    # 서버 정가 — 클라이언트 값 미사용
  end

  test "대기 주문이 있으면 재사용한다 — 버튼 연타에도 주문이 누적되지 않는다 (멱등)" do
    sign_in_as users(:gamma)
    post app_orders_path
    first_uuid = users(:gamma).orders.sole.pg_order_id

    assert_no_difference -> { users(:gamma).orders.count } do
      post app_orders_path
    end

    assert_equal first_uuid, users(:gamma).orders.sole.pg_order_id
  end

  test "포트원 승인 콜백(paymentToken)은 303으로 안내되고 주문 paid·패스 10건을 확정한다 (PLAN-4)" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-callback-1")
    fake = FakePortOneClient.new(confirm_payment: { id: "order-callback-1", status: "PAID" })
    sign_in_as users(:gamma)

    with_portone_client(fake) do
      get callback_app_orders_path,
          params: { paymentId: order.pg_order_id, paymentToken: "tok_cb_1" }
    end

    assert_response :redirect
    assert_redirected_to app_billing_path
    assert_equal "수금 패스(10건)가 발급되었습니다.", flash[:notice]
    order.reload
    assert_predicate order, :paid?
    assert_equal "order-callback-1", order.pg_payment_id     # paymentId = 주문번호 스냅샷
    pass = users(:gamma).payment_passes.sole
    assert_equal 10, pass.remaining_uses
    assert_not_nil pass.expires_at
  end

  test "paymentToken 없는 콜백(즉시 승인 채널)은 결제 조회로 승인을 확정한다" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-callback-instant-1")
    fake = FakePortOneClient.new(get_payment: { id: "order-callback-instant-1", status: "PAID" })
    sign_in_as users(:gamma)

    with_portone_client(fake) do
      get callback_app_orders_path, params: { paymentId: order.pg_order_id }
    end

    assert_response :redirect
    assert_redirected_to app_billing_path
    assert_equal "수금 패스(10건)가 발급되었습니다.", flash[:notice]
    assert_predicate order.reload, :paid?
    assert_equal 1, users(:gamma).payment_passes.count
    assert_empty fake.calls[:confirm_payment]           # 승인 API 없이 조회 한 번으로 확정
    assert_equal [ { payment_id: "order-callback-instant-1", store_id: nil } ],
                 fake.calls[:get_payment]
  end

  test "승인 실패 콜백은 303 알림으로 흡수되고 주문은 failed로 남는다" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-callback-2")
    fake = FakePortOneClient.new(raise_on: { confirm_payment:
                            PortOne::ApiError.new(status: 404, code: "PAYMENT_NOT_FOUND",
                                                  message: "존재하지 않는 결제입니다") })
    sign_in_as users(:gamma)

    with_portone_client(fake) do
      get callback_app_orders_path,
          params: { paymentId: order.pg_order_id, paymentToken: "tok_cb_bad" }
    end

    assert_response :redirect
    assert_redirected_to app_billing_path
    assert_match(/결제 승인에 실패했습니다/, flash[:alert])
    assert_predicate order.reload, :failed?
    assert_empty users(:gamma).payment_passes
  end

  test "code가 있는 콜백(사용자 취소)은 303 알림으로 흡수되고 주문이 유지된다" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-callback-3")
    sign_in_as users(:gamma)

    get callback_app_orders_path,
        params: { paymentId: order.pg_order_id, code: "PAY_PROCESS_CANCELED",
                  message: "사용자가 결제를 취소했습니다" }

    assert_response :redirect
    assert_redirected_to app_billing_path
    assert_match(/사용자가 결제를 취소했습니다/, flash[:alert])
    assert_predicate order.reload, :pending?            # 대기 유지 — 재시도 가능
    assert_empty users(:gamma).payment_passes
  end

  test "타인 주문의 콜백은 404로 거부된다 (소유권 격리)" do
    sign_in_as users(:gamma)

    get callback_app_orders_path,
        params: { paymentId: orders(:delta_pass_order).pg_order_id, paymentToken: "tok_steal_1" }

    assert_response :not_found
  end
end
