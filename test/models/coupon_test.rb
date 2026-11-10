require "test_helper"

# 쿠폰 모델(ADMIN-4 — Q12) 검증 매트릭스·적용 판정·할인 계산·소비 원자성.
# 쿠폰은 Plus 첫 결제 1회 할인 한정이며 0원 방지(amount 상한 9,900 = 정가)와
# percent 절사(floor)를 함께 검증한다.
class CouponTest < ActiveSupport::TestCase
  test "활성·미만료·한도 잔여 쿠폰은 redeemable?이 참이다" do
    assert_predicate coupons(:active_coupon), :redeemable?
    assert_predicate coupons(:amount_coupon), :redeemable?
  end

  test "한도가 모두 소진된 쿠폰은 redeemable?이 거짓이다" do
    refute_predicate coupons(:depleted_coupon), :redeemable?
    assert_equal 0, coupons(:depleted_coupon).remaining_count
    assert_match(/한도가 모두 소진/, coupons(:depleted_coupon).unavailability_reason)
  end

  test "만료일이 지난 쿠폰은 redeemable?이 거짓이다 (date 경계 — 만료일 당일까지 유효)" do
    coupon = coupons(:active_coupon)
    coupon.update!(expires_at: Date.current)

    travel_to(Date.current.end_of_day) do
      assert_predicate coupon.reload, :redeemable?   # 만료일 당일은 유효
    end
    travel_to(1.day.from_now.beginning_of_day) do
      assert_predicate coupon.reload, :expired?
      refute_predicate coupon, :redeemable?
      assert_match(/만료된/, coupon.unavailability_reason)
    end
  end

  test "비활성 쿠폰은 redeemable?이 거짓이다" do
    refute_predicate coupons(:inactive_coupon), :redeemable?
    assert_match(/비활성화된/, coupons(:inactive_coupon).unavailability_reason)
  end

  test "정액 할인 후 결제 금액이 0원이 되는 쿠폰은 redeemable?이 거짓이다 (0원 방지)" do
    coupon = Coupon.create!(code: "ZEROED01", name: "정가 전액", discount_type: :amount,
                            discount_value: Subscription::PLUS_MONTHLY_PRICE,
                            max_redemptions: 10)
    refute_predicate coupon, :redeemable?
    assert_match(/0원/, coupon.unavailability_reason)
  end

  test "percent 할인은 절사(floor)로 계산한다" do
    assert_equal 7_920, coupons(:active_coupon).final_price_for(Subscription::PLUS_MONTHLY_PRICE) # 9,900 × 80%
    assert_equal 7_900, coupons(:amount_coupon).final_price_for(Subscription::PLUS_MONTHLY_PRICE) # 9,900 − 2,000
  end

  test "코드는 대문자 영숫자 8~16자 형식만 저장된다" do
    assert Coupon.new(code: "GOODCODE1", name: "정상", discount_type: :amount,
                      discount_value: 1_000, max_redemptions: 1).valid?

    refute Coupon.new(code: "short", name: "짧음", discount_type: :amount,
                      discount_value: 1_000, max_redemptions: 1).valid?
    refute Coupon.new(code: "HAS-DASH1", name: "기호", discount_type: :amount,
                      discount_value: 1_000, max_redemptions: 1).valid?
    refute Coupon.new(code: "SEVENTEENCHARSX17", name: "17자", discount_type: :amount,
                      discount_value: 1_000, max_redemptions: 1).valid?
  end

  test "코드는 저장 시 대문자로 정규화되고 중복은 대소문자 무관하게 거부된다" do
    coupon = Coupon.create!(code: "mixed01x", name: "정규화", discount_type: :amount,
                            discount_value: 1_000, max_redemptions: 1)
    assert_equal "MIXED01X", coupon.code

    duplicate = Coupon.new(code: "mixed01x", name: "중복", discount_type: :amount,
                           discount_value: 1_000, max_redemptions: 1)
    refute_predicate duplicate, :valid?
  end

  test "percent는 1~100 · amount는 1~9,900 범위만 허용한다 (PLAN-2 정가 상한)" do
    refute Coupon.new(code: "RANGE001", name: "0%", discount_type: :percent,
                      discount_value: 0, max_redemptions: 1).valid?
    refute Coupon.new(code: "RANGE001", name: "101%", discount_type: :percent,
                      discount_value: 101, max_redemptions: 1).valid?
    assert Coupon.new(code: "RANGE001", name: "100%", discount_type: :percent,
                      discount_value: 100, max_redemptions: 1).valid?

    refute Coupon.new(code: "RANGE002", name: "0원", discount_type: :amount,
                      discount_value: 0, max_redemptions: 1).valid?
    refute Coupon.new(code: "RANGE002", name: "9,901원", discount_type: :amount,
                      discount_value: 9_901, max_redemptions: 1).valid?
    assert Coupon.new(code: "RANGE002", name: "9,900원", discount_type: :amount,
                      discount_value: 9_900, max_redemptions: 1).valid?
  end

  test "max_redemptions는 1 이상이어야 하고 used_count는 음수가 될 수 없다" do
    refute Coupon.new(code: "LIMIT0001", name: "한도 0", discount_type: :amount,
                      discount_value: 1_000, max_redemptions: 0).valid?
    coupon = coupons(:active_coupon)
    assert_raise ActiveRecord::RecordInvalid do
      coupon.update!(used_count: -1)
    end
  end

  test "consume!은 used_count를 원자적으로 1 증가시킨다 (SEC-5 멱등 기반)" do
    coupon = coupons(:active_coupon)
    coupon.consume!
    assert_equal 1, coupon.used_count
    assert_equal 1, coupon.reload.used_count
    coupon.consume!
    assert_equal 2, coupon.reload.used_count
  end

  # W-2 — 예약 보유 쿠폰은 삭제가 차단된다(nullify 소멸 금지 — 첫 차감 정가 청구 불일치 방지).
  test "예약 보유 쿠폰의 삭제는 차단되고 예약이 유지된다 (W-2)" do
    user = users(:gamma)
    subscription = user.create_subscription!(plan: :free)
    coupon = coupons(:active_coupon)
    subscription.update!(coupon_id: coupon.id)

    refute coupon.destroy, "예약 보유 쿠폰은 삭제되어서는 안 된다"
    assert coupon.errors[:base].present?
    assert_equal coupon.id, subscription.reload.coupon_id
  end
end
