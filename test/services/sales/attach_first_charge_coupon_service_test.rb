require "test_helper"
require_relative "../../test_helpers/fake_portone_client"

# 추천 가입 첫결제 할인 쿠폰 자동 부착(SALES-4 — F-SALES·Q12 재사용). percent 20·1회 전용
# 쿠폰 생성 → subscription.coupon_id 예약까지를 검증하고, 기존 결제 경로(UpgradeService)와
# 결합한 첫차감 7,920원 → 재과금 9,900원 E2E(Q12 불변식)를 재확인한다.
# 시나리오 기준: PRD §6.20 SALES-4·Q12·_workspace/05_review.md §4 Tester 중점 5번.
class Sales::AttachFirstChargeCouponServiceTest < ActiveSupport::TestCase
  setup do
    @rep = sales_reps(:sales_kim)
    @user = User.create!(email: "attach-coupon@example.com", password: "password123",
                         referred_by_sales_rep_id: @rep.id,
                         referral_code_snapshot: "KIM2026A")
  end

  test "쿠폰을 percent 20·1회 전용·활성으로 생성하고 구독에 예약한다 (SALES-4)" do
    result = Sales::AttachFirstChargeCouponService.new(user: @user).call

    assert_not_nil result
    coupon = Coupon.find(result.id)
    assert_equal "percent", coupon.discount_type
    assert_equal 20, coupon.discount_value
    assert_equal 1, coupon.max_redemptions
    assert coupon.active?
    assert_nil coupon.expires_at, "부착 계정 1회 한정이라 무만료다"
    assert_match(/\AREF[0-9A-F]{8}\z/, coupon.code, "코드는 REF+hex8(11자) — Coupon 형식 통과")
    assert_equal coupon.id, @user.subscription.reload.coupon_id, "Q12 예약 구조"
    assert_equal "추천 가입 첫 결제 할인", coupon.name
  end

  test "구독이 없는 사용자는 쿠폰을 생성하지 않고 nil을 반환한다 (SALES-4 폴백)" do
    plain = User.create!(email: "no-subscription@example.com", password: "password123")
    # PLAN-1 after_create로 Free 구독이 자동 생성되므로, "구독 없음" 표본은 구독 행을
    # 제거해 만든다(F-PLAN 이전 가입 레거시 유저 상태 재현).
    plain.subscription.destroy!
    assert_nil plain.reload.subscription

    assert_no_difference -> { Coupon.count } do
      assert_nil Sales::AttachFirstChargeCouponService.new(user: plain).call
    end
  end

  test "SALES-4 E2E — 예약 쿠폰의 첫 차감은 7,920원·재과금은 9,900원이다 (Q12 재사용 확인)" do
    Sales::AttachFirstChargeCouponService.new(user: @user).call
    subscription = @user.reload.subscription
    subscription.update!(plan: :plus, status: :active, pg_billing_key: "tok_sales_c1",
                         pg_customer_key: "cust_sales_c1",
                         current_period_start: Time.zone.parse("2026-11-01 00:00"),
                         current_period_end: Time.zone.parse("2026-11-30 23:59:59"))
    fake = FakePortOneClient.new(charge_billing_key: { payment: { id: "payment_sales_1", status: "PAID" } })

    travel_to(Time.zone.parse("2026-12-01 06:05")) do
      Subscriptions::UpgradeService.new(user: @user, action: :renew,
                                        channel_key: "test-channel-billing", client: fake).call
    end
    travel_to(Time.zone.parse("2027-01-01 06:05")) do
      Subscriptions::UpgradeService.new(user: @user, action: :renew,
                                        channel_key: "test-channel-billing", client: fake).call
    end

    amounts = fake.calls[:charge_billing_key].map { |call| call[:amount] }
    assert_equal [ 7_920, 9_900 ], amounts, "첫 결제만 20% 할인(7,920)·재과금 정상가"
    assert_equal 7_920, @user.orders.order(:paid_at).first.amount, "orders.amount = 실차감액"
    coupon = Coupon.find_by(name: "추천 가입 첫 결제 할인")
    assert_equal 1, coupon.reload.used_count, "1회 소비(SEC-5) — 2회차에서 증가 없음"
    assert_nil subscription.reload.coupon_id, "소비 후 예약 해제"
  end
end
