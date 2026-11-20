require "test_helper"
require_relative "../../test_helpers/portone_stubbing"
require_relative "../../test_helpers/fake_portone_client"

# 쿠폰 HTTP 플로우(ADMIN-4 — Q12). 2026-11-20 사용자 판정: 쿠폰은 가입 시(추천 코드 →
# Sales::AttachFirstChargeCouponService)로만 예약되고, 대시보드 수동 등록 경로는 제외됐다.
# 본 테스트는 ① 수동 등록 우회(coupon_code PATCH)가 예약으로 이어지지 않음을 회귀 방지하고
# ② 예약 쿠폰 존재 시 카드 등록(활성)의 coupon_redeemed 감사를 검증한다.
# 실제 used_count 소비는 첫 차감 성공 시점(서비스 테스트 — upgrade_service_coupon_test).
class App::SubscriptionsCouponTest < ActionDispatch::IntegrationTest
  include PortOneStubbing

  test "비인증 요청은 302로 로그인 화면에 리다이렉트된다 (AUTH-1)" do
    patch app_subscription_path, params: { coupon_code: "WELCOME2026" }

    assert_redirected_to new_session_path
  end

  test "coupon_code PATCH(수동 등록 우회)는 쿠폰을 예약하지 않고 발급 토큰 가드로 거부된다 (2026-11-20 판정 회귀)" do
    user = users(:gamma)
    user.create_subscription!(plan: :free)
    sign_in_as user

    patch app_subscription_path, params: { coupon_code: "welcome2026" }

    assert_redirected_to app_billing_path
    assert flash[:alert].present?, "발급 토큰 없는 PATCH는 서비스 가드로 alert 거부된다"
    assert_nil user.subscription.reload.coupon_id, "coupon_code로는 쿠폰이 예약되지 않는다"
  end

  test "쿠폰 예약 상태에서 카드 등록(활성) 성공 시 coupon_redeemed 감사가 기록된다 (ADMIN-4)" do
    user = users(:gamma)
    subscription = user.create_subscription!(plan: :free)
    subscription.update!(coupon_id: coupons(:amount_coupon).id)
    sign_in_as user

    with_portone_client(FakePortOneClient.new(issue_billing_key: { billingKey: "tok_billing_coupon_http" })) do
      patch app_subscription_path, params: { issue_token: "issue_card_coupon_1" }
    end

    assert_redirected_to app_billing_path
    audit = AuditLog.find_by(action: "coupon_redeemed")
    assert_not_nil audit
    assert_nil audit.admin                       # U1 행위 — admin 부재(nullable 완화)
    assert_equal "Subscription", audit.target_type
    assert_equal subscription.reload.id, audit.target_id
    assert_equal "SAVE2000", audit.detail
  end

  test "쿠폰 예약 없이 카드 등록 성공하면 감사가 기록되지 않는다" do
    user = users(:gamma)
    user.create_subscription!(plan: :free)
    sign_in_as user

    with_portone_client(FakePortOneClient.new(issue_billing_key: { billingKey: "tok_billing_plain_http" })) do
      patch app_subscription_path, params: { issue_token: "issue_card_plain_1" }
    end

    assert_redirected_to app_billing_path
    assert_nil AuditLog.find_by(action: "coupon_redeemed")
  end
end
