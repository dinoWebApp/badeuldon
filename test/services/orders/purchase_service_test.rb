require "test_helper"
require_relative "../../test_helpers/fake_toss_client"

# 수금 패스 구매(F-PLAN — PLAN-4/5) — PurchaseService 승인 확정. 토스 API는 FakeTossClient
# 주입으로 대체한다(실호출 금지). 이중 콜백 흡수(SEC 멱등 — 발급 정확히 1회)와 승인 금액의
# 서버 원값 기준을 검증한다. with_lock 실스레드 경합은 purchase_service_concurrency_test.rb.
# 시나리오 기준: _workspace/03_implementation.md §3 (수금 패스 구매 플로우).
class Orders::PurchaseServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:gamma)   # 주문·패스 fixture가 없는 사용자 — fixture 오염 없이 1:1 검증
    @order = @user.orders.create!(product: :collection_pass, amount: 4_000,
                                  toss_order_id: "order-pass-test-1")
  end

  test "승인 확정은 주문을 paid로 바꾸고 10건 패스를 발급한다 (PLAN-4)" do
    fake = FakeTossClient.new(confirm_payment: { paymentKey: "pay_1", status: "DONE" })

    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      result = Orders::PurchaseService.new(order: @order, payment_key: "pay_1", client: fake).call

      assert_equal @order.reload, result
      assert_predicate @order, :paid?
      assert_equal "pay_1", @order.toss_payment_key
      assert_equal Time.zone.parse("2026-10-15 09:00"), @order.paid_at
      assert_equal({ "paymentKey" => "pay_1", "status" => "DONE" }, @order.metadata)

      pass = @user.payment_passes.sole
      assert_equal 10, pass.total_uses
      assert_equal 10, pass.remaining_uses
      assert_equal Time.zone.parse("2027-01-13 09:00"), pass.expires_at  # 발급일 +90일
    end
  end

  test "승인 요청은 주문 레코드의 서버 원값(orderId·금액)을 사용한다 (콜백 값 미신뢰)" do
    fake = FakeTossClient.new

    Orders::PurchaseService.new(order: @order, payment_key: "pay_1", client: fake).call

    assert_equal [ { order_id: "order-pass-test-1", payment_key: "pay_1", amount: 4_000 } ],
                 fake.calls[:confirm_payment]
  end

  test "이미 처리된 주문의 재승인은 거부되고 패스가 추가 발급되지 않는다 (SEC 멱등)" do
    fake = FakeTossClient.new
    Orders::PurchaseService.new(order: @order, payment_key: "pay_1", client: fake).call

    error = assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order.reload, payment_key: "pay_1", client: fake).call
    end

    assert_match(/이미 처리된 결제입니다/, error.message)
    assert_equal 1, @user.payment_passes.count              # 발급 정확히 1회
    assert_equal 1, @user.orders.count
  end

  test "명확한 승인 실패 시 주문은 failed로 기록되고 패스가 발급되지 않는다" do
    fake = FakeTossClient.new(raise_on: { confirm_payment:
                            TossPayments::ApiError.new(status: 401, code: "UNAUTHORIZED_KEY",
                                                       message: "인증되지 않은 키") })

    error = assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order, payment_key: "pay_bad", client: fake).call
    end

    assert_match(/결제 승인에 실패했습니다/, error.message)
    order = @order.reload
    assert_predicate order, :failed?
    assert_equal({ "code" => "UNAUTHORIZED_KEY", "message" => "인증되지 않은 키" }, order.metadata)
    assert_nil order.toss_payment_key                        # 승인 확정 전이라 미기록
    assert_empty @user.payment_passes
  end

  test "모호 실패(타임아웃) 후 재확인 DONE이면 정상 발급 경로로 합류한다 (이슈 #1)" do
    fake = FakeTossClient.new(
      raise_on: { confirm_payment:
                  TossPayments::ApiError.new(status: nil, code: "TIMEOUT", message: "응답 시간 초과") },
      get_payment: { paymentKey: "pay_amb_1", status: "DONE", orderId: @order.toss_order_id }
    )

    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      result = Orders::PurchaseService.new(order: @order, payment_key: "pay_amb_1",
                                           client: fake).call

      assert_equal @order.reload, result                    # 예외 없이 정상 확정
      assert_predicate @order, :paid?
      assert_equal 1, @user.payment_passes.count
    end
  end

  test "모호 실패 후 미승인이면 pending·paymentKey 보존으로 회복을 연다 (이슈 #1)" do
    fake = FakeTossClient.new(
      raise_on: { confirm_payment:
                  TossPayments::ApiError.new(status: nil, code: "TIMEOUT", message: "응답 시간 초과") },
      get_payment: { paymentKey: "pay_amb_2", status: "IN_PROGRESS" }
    )

    error = assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order, payment_key: "pay_amb_2", client: fake).call
    end

    assert_match(/결제 확인이 지연되고 있습니다/, error.message)
    order = @order.reload
    assert_predicate order, :pending?                       # failed 확정 금지 — 이중 결제 방지
    assert_equal "pay_amb_2", order.toss_payment_key        # 웹훅 회복 대상 식별키 보존
    assert_predicate order.metadata["pending_recovery"], :present?
    assert_empty @user.payment_passes
  end
end
