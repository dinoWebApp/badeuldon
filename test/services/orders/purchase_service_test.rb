require "test_helper"
require_relative "../../test_helpers/fake_portone_client"

# 수금 패스 구매(F-PLAN — PLAN-4/5) — PurchaseService 승인 확정. 포트원 API는 FakePortOneClient
# 주입으로 대체한다(실호출 금지). 이중 콜백 흡수(SEC 멱등 — 발급 정확히 1회), 승인 금액·결제 ID의
# 서버 원값 기준, 즉시 승인 채널 폴백(조회 확정)을 검증한다. with_lock 실스레드 경합은
# purchase_service_concurrency_test.rb.
# 시나리오 기준: _workspace/03_implementation.md §1·§3 (수금 패스 구매 플로우).
class Orders::PurchaseServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:gamma)   # 주문·패스 fixture가 없는 사용자 — fixture 오염 없이 1:1 검증
    @order = @user.orders.create!(product: :collection_pass, amount: 4_000,
                                  pg_order_id: "order-pass-test-1")
  end

  test "승인 확정(paymentToken)은 주문을 paid로 바꾸고 10건 패스를 발급한다 (PLAN-4)" do
    fake = FakePortOneClient.new(confirm_payment: { id: "order-pass-test-1", status: "PAID" })

    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      result = Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1",
                                           client: fake).call

      assert_equal @order.reload, result
      assert_predicate @order, :paid?
      assert_equal "order-pass-test-1", @order.pg_payment_id  # paymentId = 서버 채번 주문번호
      assert_equal Time.zone.parse("2026-10-15 09:00"), @order.paid_at
      assert_equal({ "id" => "order-pass-test-1", "status" => "PAID" }, @order.metadata)

      pass = @user.payment_passes.sole
      assert_equal 10, pass.total_uses
      assert_equal 10, pass.remaining_uses
      assert_equal Time.zone.parse("2027-01-13 09:00"), pass.expires_at  # 발급일 +90일
    end
  end

  test "승인 요청은 주문 레코드의 결제 ID(paymentId)·위젯 토큰을 그대로 보낸다" do
    fake = FakePortOneClient.new

    Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1", client: fake).call

    assert_equal [ { payment_id: "order-pass-test-1", payment_token: "tok_widget_1",
                     store_id: nil } ],
                 fake.calls[:confirm_payment]
  end

  test "즉시 승인 채널(paymentToken 없음)은 결제 조회로 승인 사실을 확정한다" do
    fake = FakePortOneClient.new(get_payment: { id: "order-pass-test-1", status: "PAID" })

    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      result = Orders::PurchaseService.new(order: @order, payment_token: nil, client: fake).call

      assert_equal @order.reload, result
      assert_predicate @order, :paid?
      assert_equal 1, @user.payment_passes.count
    end

    # 승인 API 호출 없이 조회 한 번으로 확정한다
    assert_empty fake.calls[:confirm_payment]
    assert_equal [ { payment_id: "order-pass-test-1", store_id: nil } ],
                 fake.calls[:get_payment]
  end

  test "이미 처리된 주문의 재승인은 거부되고 패스가 추가 발급되지 않는다 (SEC 멱등)" do
    fake = FakePortOneClient.new
    Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1", client: fake).call

    error = assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order.reload, payment_token: "tok_widget_1",
                                  client: fake).call
    end

    assert_match(/이미 처리된 결제입니다/, error.message)
    assert_equal 1, @user.payment_passes.count              # 발급 정확히 1회
    assert_equal 1, @user.orders.count
  end

  test "명확한 승인 실패(PG 거절) 시 주문은 failed로 기록되고 PG 원문이 보존된다" do
    fake = FakePortOneClient.new(raise_on: { confirm_payment:
                            PortOne::ApiError.new(status: 400, code: "PG_PROVIDER_ERROR",
                                                  message: "PG사 처리 중 오류가 발생했습니다",
                                                  pg_code: "F1001", pg_message: "카드 한도 초과") })

    error = assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_bad", client: fake).call
    end

    assert_match(/결제 승인에 실패했습니다/, error.message)
    order = @order.reload
    assert_predicate order, :failed?
    assert_equal({ "code" => "PG_PROVIDER_ERROR", "message" => "PG사 처리 중 오류가 발생했습니다",
                   "pg_code" => "F1001", "pg_message" => "카드 한도 초과" }, order.metadata)
    assert_nil order.pg_payment_id                           # 승인 확정 전이라 미기록
    assert_empty @user.payment_passes
  end

  test "모호 실패(타임아웃) 후 재확인 PAID면 정상 발급 경로로 합류한다 (이슈 #1)" do
    fake = FakePortOneClient.new(
      raise_on: { confirm_payment:
                  PortOne::ApiError.new(status: nil, code: "TIMEOUT", message: "응답 시간 초과") },
      get_payment: { id: "order-pass-test-1", status: "PAID" }
    )

    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      result = Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1",
                                           client: fake).call

      assert_equal @order.reload, result                    # 예외 없이 정상 확정
      assert_predicate @order, :paid?
      assert_equal 1, @user.payment_passes.count
    end
  end

  test "모호 실패 후 미승인(READY)이면 pending·paymentId 보존으로 회복을 연다 (이슈 #1)" do
    fake = FakePortOneClient.new(
      raise_on: { confirm_payment:
                  PortOne::ApiError.new(status: nil, code: "TIMEOUT", message: "응답 시간 초과") },
      get_payment: { id: "order-pass-test-1", status: "READY" }
    )

    error = assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1", client: fake).call
    end

    assert_match(/결제 확인이 지연되고 있습니다/, error.message)
    order = @order.reload
    assert_predicate order, :pending?                       # failed 확정 금지 — 이중 결제 방지
    assert_equal "order-pass-test-1", order.pg_payment_id   # 웹훅 회복 대상 식별키 보존
    assert_predicate order.metadata["pending_recovery"], :present?
    assert_empty @user.payment_passes
  end
end
