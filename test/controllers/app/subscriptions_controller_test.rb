require "test_helper"
require_relative "../../test_helpers/portone_stubbing"
require_relative "../../test_helpers/fake_portone_client"

# 구독 상태 전환(F-PLAN) HTTP 테스트 — create(체험 시작)·update(카드 등록 위젯 콜백/수동·해지).
# 포트원 호출 경로(카드 등록)는 PortOne::ClientService.new를 FakePortOneClient로 스텁한다
# (실호출 금지). 흐름·가드는 UpgradeService가 담당하므로 응답 코드·리다이렉션·DB 전이를 검증한다.
# 시나리오 기준: PRD §6.10 PLAN-2·PLAN-5, _workspace/03_implementation.md §3.
class App::SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  include PortOneStubbing

  test "비인증 체험 시작은 302로 로그인 화면에 리다이렉트된다 (AUTH-1)" do
    post app_subscription_path

    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "Free 사용자의 체험 시작은 303으로 안내되고 Plus 체험 중으로 전환된다 (PLAN-2)" do
    sign_in_as users(:gamma)  # 구독 행 없음 — 서비스가 즉석 Free 생성 후 체험 전환

    post app_subscription_path

    assert_response :redirect
    assert_redirected_to app_billing_path
    assert_equal "Plus 14일 무료 체험이 시작되었습니다.", flash[:notice]
    subscription = users(:gamma).subscription.reload
    assert_predicate subscription, :plus?
    assert_predicate subscription, :trialing?
    assert_not_nil subscription.trial_ends_at
  end

  test "Plus 이용 중 사용자의 재체험 시작은 303 알림으로 거부되고 상태가 유지된다" do
    sign_in_as users(:epsilon)  # plus/active fixture

    post app_subscription_path

    assert_response :redirect
    assert_redirected_to app_billing_path
    assert_match(/이미 Plus를 이용 중입니다/, flash[:alert])
    assert_predicate users(:epsilon).subscription.reload, :active?   # 전이 없음
  end

  test "카드 등록(PATCH issue_token)은 303으로 안내되고 빌링키 저장과 즉시 활성화를 확인한다" do
    users(:gamma).create_subscription!(plan: :free)
    fake = FakePortOneClient.new(issue_billing_key: { billingKey: "tok_billing_http_1" })
    sign_in_as users(:gamma)

    with_portone_client(fake) do
      patch app_subscription_path, params: { issue_token: "issue_card_1" }
    end

    assert_response :redirect
    assert_redirected_to app_billing_path
    assert_equal "카드가 등록되어 Plus 이용이 활성화되었습니다.", flash[:notice]
    subscription = users(:gamma).subscription.reload
    assert_predicate subscription, :active?
    assert_predicate subscription, :plus?
    assert_equal "tok_billing_http_1", subscription.pg_billing_key
    assert_not_nil subscription.current_period_end
  end

  test "카드 인증 위젯 리다이렉트(issue_token GET 콜백)도 동일하게 활성화된다" do
    users(:gamma).create_subscription!(plan: :plus, status: :trialing,
                                       trial_ends_at: 10.days.from_now)
    fake = FakePortOneClient.new(issue_billing_key: { billingKey: "tok_billing_widget_1" })
    sign_in_as users(:gamma)

    with_portone_client(fake) do
      get card_callback_app_subscription_path, params: { issue_token: "issue_widget_1" }
    end

    assert_response :redirect
    assert_redirected_to app_billing_path
    subscription = users(:gamma).subscription.reload
    assert_predicate subscription, :active?
    assert_equal "tok_billing_widget_1", subscription.pg_billing_key
  end

  test "빌링키 발급 실패는 303 알림으로 흡수되고 구독이 유지된다 (포트원 ApiError)" do
    users(:gamma).create_subscription!(plan: :free)
    fake = FakePortOneClient.new(raise_on: { issue_billing_key:
                            PortOne::ApiError.new(status: 400, code: "PG_PROVIDER_ERROR",
                                                  message: "유효하지 않은 카드입니다") })
    sign_in_as users(:gamma)

    with_portone_client(fake) do
      patch app_subscription_path, params: { issue_token: "issue_bad" }
    end

    assert_response :redirect
    assert_redirected_to app_billing_path
    assert_match(/카드 등록에 실패했습니다/, flash[:alert])
    subscription = users(:gamma).subscription.reload
    assert_predicate subscription, :free?
    assert_nil subscription.pg_billing_key
  end

  test "해지 PATCH는 303으로 안내되고 취소 상태로 전환된다 (PLAN-5)" do
    sign_in_as users(:epsilon)  # plus/active fixture

    patch cancel_app_subscription_path  # 해지 전용 액션(이슈 #5 — update에서 분기 제거)

    assert_response :redirect
    assert_redirected_to app_billing_path
    assert_match(/Plus 구독이 해지되었습니다/, flash[:notice])
    subscription = users(:epsilon).subscription.reload
    assert_predicate subscription, :cancelled?
    assert_predicate subscription, :plus?            # 기간 종료까지 Plus 유지
    assert_not_nil subscription.current_period_end
  end

  test "Free 상태의 해지 PATCH는 303 알림으로 거부된다 (이슈 #6 — free/cancelled 방지)" do
    users(:gamma).create_subscription!(plan: :free)
    sign_in_as users(:gamma)

    patch cancel_app_subscription_path

    assert_response :redirect
    assert_redirected_to app_billing_path
    assert_match(/해지할 이용 중인 Plus/, flash[:alert])
    subscription = users(:gamma).subscription.reload
    assert_predicate subscription, :active?
    assert_predicate subscription, :free?
  end

  test "체험 이력이 있는 사용자의 재체험 POST는 303 알림으로 거부된다 (PLAN-2 — 1회 제한)" do
    users(:gamma).create_subscription!(plan: :free, status: :expired, used_trial: true)
    sign_in_as users(:gamma)

    post app_subscription_path

    assert_response :redirect
    assert_redirected_to app_billing_path
    assert_match(/무료 체험은 계정당 1회만/, flash[:alert])
    assert_predicate users(:gamma).subscription.reload, :expired?
  end

  test "체험 중 구독의 해지 PATCH도 303으로 취소 상태로 전환된다 (이슈 #6)" do
    users(:gamma).create_subscription!(plan: :plus, status: :trialing,
                                       trial_ends_at: 10.days.from_now)
    sign_in_as users(:gamma)

    patch cancel_app_subscription_path  # 해지는 전용 PATCH 액션으로(이슈 #5 — update는 카드 등록 전용)

    assert_response :redirect
    assert_redirected_to app_billing_path
    assert_match(/Plus 구독이 해지되었습니다/, flash[:notice])
    assert_predicate users(:gamma).subscription.reload, :cancelled?
  end
end
