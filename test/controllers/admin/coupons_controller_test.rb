require "test_helper"

# ADMIN-4 쿠폰 관리 콘솔(T-C2) — destroy 가드 중심. used_count > 0 삭제 차단은 기존,
# W-2: 예약 보유(subscriptions.coupon_id 참조)도 restrict_with_error로 차단하고
# 컨트롤러가 destroy 반환값을 검사해 alert으로 안내한다(P4 — 조용한 nullify 금지).
class Admin::CouponsControllerTest < ActionDispatch::IntegrationTest
  include AdminSessionTestHelper

  setup do
    setup_admin_totp_secrets
    @owner = admins(:ops)
  end

  test "예약 보유 쿠폰 삭제 시도는 차단되고 alert 안내·예약 유지된다 (W-2)" do
    admin_login(@owner, at: Time.current)
    subscription = users(:gamma).create_subscription!(plan: :free)
    subscription.update!(coupon_id: coupons(:active_coupon).id)

    assert_no_difference "Coupon.count" do
      delete admin_coupon_path(coupons(:active_coupon))
    end

    assert_response :see_other
    assert_match "사용 예정인 쿠폰은 삭제할 수 없습니다", flash[:alert]
    assert_equal coupons(:active_coupon).id, subscription.reload.coupon_id
  end

  test "미사용·예약 없는 쿠폰은 삭제된다" do
    admin_login(@owner, at: Time.current)

    assert_difference "Coupon.count", -1 do
      delete admin_coupon_path(coupons(:expired_coupon))
    end

    assert_response :see_other
    assert_match "삭제되었습니다", flash[:notice]
  end
end
