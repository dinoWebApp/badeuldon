require "test_helper"
require_relative "../../test_helpers/portone_stubbing"
require_relative "../../test_helpers/fake_portone_client"

# 쿠폰 적용 HTTP 플로우(ADMIN-4 — Q12) — PATCH /app/subscription의 coupon_code 분기.
# 서버 검증 실패(부재·비활성·만료·한도·첫 결제 아님)는 각각 303 안내 flash이고, 성공 시
# 구독에 예약된다. 실제 used_count 소비는 첫 차감 성공 시점(서비스 테스트 참조).
class App::SubscriptionsCouponTest < ActionDispatch::IntegrationTest
  include PortOneStubbing

  test "비인증 쿠폰 적용은 302로 로그인 화면에 리다이렉트된다 (AUTH-1)" do
    patch app_subscription_path, params: { coupon_code: "WELCOME2026" }

    assert_redirected_to new_session_path
  end

  test "유효한 쿠폰은 구독에 예약되고 할인 안내와 함께 303으로 돌아온다" do
    user = users(:gamma)
    user.create_subscription!(plan: :free)
    sign_in_as user

    patch app_subscription_path, params: { coupon_code: "welcome2026" } # 소문자 입력 — 정규화

    assert_redirected_to app_billing_path
    assert_match(/WELCOME2026.*할인/, flash[:notice])
    assert_equal 1_980, Subscription::PLUS_MONTHLY_PRICE -
                        user.subscription.reload.coupon.final_price_for(Subscription::PLUS_MONTHLY_PRICE)
  end

  test "존재하지 않는 코드는 303 alert으로 거부된다 (서버 검증 — 불변식 1)" do
    user = users(:gamma)
    user.create_subscription!(plan: :free)
    sign_in_as user

    patch app_subscription_path, params: { coupon_code: "NOTEXIST1" }

    assert_redirected_to app_billing_path
    assert_match(/존재하지 않는 쿠폰/, flash[:alert])
    assert_nil user.subscription.reload.coupon_id
  end

  test "만료·한도 소진·비활성 쿠폰은 각각 사유 안내와 함께 거부된다 (서버 검증)" do
    user = users(:gamma)
    user.create_subscription!(plan: :free)
    sign_in_as user

    patch app_subscription_path, params: { coupon_code: "OLDCODE123" }
    assert_match(/만료된 쿠폰/, flash[:alert])

    patch app_subscription_path, params: { coupon_code: "EMPTY9999" }
    assert_match(/한도가 모두 소진/, flash[:alert])

    patch app_subscription_path, params: { coupon_code: "STOPEX01" }
    assert_match(/비활성화된 쿠폰/, flash[:alert])

    assert_nil user.subscription.reload.coupon_id
  end

  test "이미 성공한 Plus 결제가 있는 사용자의 쿠폰 적용은 거부된다 (첫 결제 한정 — 적용 1회)" do
    user = users(:gamma)
    subscription = user.create_subscription!(plan: :plus, status: :active,
                                             pg_billing_key: "tok_paid_1")
    user.orders.create!(product: :plus_monthly, amount: 9_900, status: :paid,
                        pg_order_id: "order-first-paid-1", paid_at: 1.month.ago)
    sign_in_as user

    patch app_subscription_path, params: { coupon_code: "WELCOME2026" }

    assert_redirected_to app_billing_path
    assert_match(/Plus 첫 결제에만/, flash[:alert])
    assert_nil subscription.reload.coupon_id
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
