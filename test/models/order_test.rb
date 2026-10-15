require "test_helper"

# 주문(F-PLAN — PLAN-2/4/5) 모델 — 상품 정가 단일 지점·기본 상태(pending)·금액·주문번호 검증.
# 시나리오 기준: PRD §6.10 PLAN-2·PLAN-4, _workspace/03_implementation.md §2. 외부 API 호출 없음.
class OrderTest < ActiveSupport::TestCase
  test "정가는 상품별 단일 지점에서만 산정된다 (PLAN-2 Plus 9,900원·PLAN-4 패스 4,000원)" do
    assert_equal 9_900, Order.amount_for(:plus_monthly)
    assert_equal 4_000, Order.amount_for(:collection_pass)
  end

  test "신규 주문은 결제 대기(pending) 상태로 시작한다" do
    order = Order.new(user: users(:delta), product: :collection_pass,
                      amount: 4_000, pg_order_id: "order-new-1")

    assert_predicate order, :pending?
  end

  test "금액은 0 이하·비정수를 거부하고 주문번호는 필수다" do
    base = { user: users(:delta), product: :collection_pass, pg_order_id: "order-new-2" }

    assert_not_predicate Order.new(**base, amount: 0), :valid?
    assert_not_predicate Order.new(**base, amount: -1), :valid?
    assert_not_predicate Order.new(**base, amount: 100.5), :valid?
    assert_not_predicate Order.new(user: users(:delta), product: :collection_pass,
                                   amount: 4_000), :valid?  # pg_order_id 누락
  end

  test "주문번호는 중복될 수 없다 (포트원 paymentId 고유)" do
    attrs = { user: users(:delta), product: :collection_pass, amount: 4_000,
              pg_order_id: "order-delta-pass-0001" }  # orders.yml fixture와 동일 값

    duplicate = Order.new(**attrs)
    assert_not_predicate duplicate, :valid?
    assert_predicate duplicate.errors[:pg_order_id], :any?
  end

  test "pg_* 결제 컬럼(pg_order_id·pg_payment_id·pg_billing_key)은 값을 유지한다 (rename 데이터 보존)" do
    # fixture — rename 전 값이 그대로 조회된다(orders.yml delta_pass_order 고정값)
    fixture_order = orders(:delta_pass_order)
    assert_equal "order-delta-pass-0001", fixture_order.pg_order_id
    assert_equal "pay-delta-pass-0001", fixture_order.pg_payment_id

    # 쓰기→재적재 — 세 컬럼 모두 라운드트립 보존(차감 주문이 세 값을 함께 남기는 형태)
    order = users(:delta).orders.create!(product: :plus_monthly, amount: 9_900,
                                         pg_order_id: "order-rename-rt-1")
    order.update!(status: :paid, pg_payment_id: "order-rename-rt-1",
                  pg_billing_key: "bk_rename_rt_1")

    reloaded = Order.find(order.id)
    assert_equal "order-rename-rt-1", reloaded.pg_order_id
    assert_equal "order-rename-rt-1", reloaded.pg_payment_id
    assert_equal "bk_rename_rt_1", reloaded.pg_billing_key
  end
end
