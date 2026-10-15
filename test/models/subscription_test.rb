require "test_helper"

# 구독(F-PLAN — PLAN-1/2) 모델 — 가입 시 Free 생성·생명주기 전이(체험→활성→해지→만료·재활성),
# 1인 1구독 불변식, 한도 판정점(Free 상수/Plus 무제한·구독 없는 사용자 폴백).
# 시나리오 기준: PRD §6.10 PLAN-1·PLAN-2, _workspace/03_implementation.md §2·§5.
# 시간 의존 검증은 travel_to로 KST를 고정한다(TIME-1). 외부 API 호출 없음.
class SubscriptionTest < ActiveSupport::TestCase
  test "가입 시 Free 구독이 자동 생성된다 (PLAN-1 — 모델 콜백)" do
    user = User.create!(email: "fplan-new@example.com", password: "password123")

    subscription = user.reload.subscription
    assert_not_nil subscription
    assert_predicate subscription, :free?
    assert_predicate subscription, :active?
  end

  test "생성된 구독에는 포트원 고객 키(customer.id)가 즉시 발급된다" do
    subscription = users(:gamma).create_subscription!(plan: :free)

    assert_not_nil subscription.pg_customer_key
    assert_match(/\A[0-9a-f-]{36}\z/, subscription.pg_customer_key)  # UUID 형식
  end

  test "1인 1구독 — 사용자당 두 번째 구독 행은 고유 인덱스로 거부된다" do
    users(:gamma).create_subscription!(plan: :free)

    assert_raises(ActiveRecord::RecordNotUnique) do
      Subscription.create!(user: users(:gamma), plan: :free)
    end
  end

  # ── 생명주기 (03 §2 다이어그램: trialing→active→cancelled→expired) ──

  test "체험 시작은 Plus 전환과 14일 후 체험 종료일을 기록한다 (PLAN-2)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      subscription = users(:gamma).create_subscription!(plan: :free)

      subscription.start_trial!

      assert_predicate subscription.reload, :plus?
      assert_predicate subscription, :trialing?
      assert_equal Time.zone.parse("2026-10-29 09:00"), subscription.trial_ends_at  # +14일
      assert_predicate subscription, :used_trial?   # 체험 이력 영구 기록 — 재체험 차단 근거
    end
  end

  test "무료 체험은 계정당 1회다 — 체험 이력이 있으면 재체험이 거부된다 (PLAN-2)" do
    subscription = users(:gamma).create_subscription!(plan: :free, status: :expired,
                                                      used_trial: true)

    error = assert_raises(Subscription::TrialAlreadyUsedError) { subscription.start_trial! }

    assert_match(/무료 체험은 이미 사용되었습니다/, error.message)
    assert_predicate subscription.reload, :expired?   # 전이 없음
  end

  test "카드 등록(활성)은 Plus 이용 중 전환과 1개월 과금 주기를 시작한다 (PLAN-2)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      subscription = users(:gamma).create_subscription!(plan: :free)

      subscription.activate!(billing_key: "tok_billing_1")

      assert_predicate subscription.reload, :plus?
      assert_predicate subscription, :active?
      assert_equal "tok_billing_1", subscription.pg_billing_key
      assert_equal Time.zone.parse("2026-11-15 09:00"), subscription.current_period_end  # +1개월
      assert_not_nil subscription.current_period_start
    end
  end

  test "체험 중 조기 카드 등록은 체험 종료 후부터 유료 주기를 시작한다 (체험 잔여일의 유료 편입 방지)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      subscription = users(:gamma).create_subscription!(plan: :plus, status: :trialing,
                                                        trial_ends_at: Time.zone.parse("2026-10-29 09:00"))

      subscription.activate!(billing_key: "tok_billing_1")

      assert_predicate subscription.reload, :active?
      # 주기 기준은 현재·체험 종료·기존 주기 종료 중 가장 미래 시점 — 체험 종료일
      assert_equal Time.zone.parse("2026-10-29 09:00"), subscription.current_period_start
      assert_equal Time.zone.parse("2026-11-29 09:00"), subscription.current_period_end
    end
  end

  test "해지는 취소 상태로 바꾸고 플랜·주기는 유지된다 (PLAN-5 — 기간 말까지 이용)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      subscription = users(:gamma).create_subscription!(plan: :plus, status: :active,
                                                        pg_billing_key: "tok_billing_1",
                                                        current_period_start: Time.current,
                                                        current_period_end: 1.month.from_now)

      subscription.cancel!

      assert_predicate subscription.reload, :cancelled?
      assert_predicate subscription, :plus?                       # 기간 종료까지 Plus 유지
      assert_equal "tok_billing_1", subscription.pg_billing_key # 카드 정보도 유지
      assert_not_nil subscription.current_period_end
    end
  end

  test "만료는 Free 강등과 카드·주기·체험 정보 폐기를 함께 수행하고 체험 이력은 유지한다" do
    subscription = users(:gamma).create_subscription!(plan: :plus, status: :trialing,
                                                      trial_ends_at: 1.day.from_now,
                                                      used_trial: true,
                                                      pg_billing_key: "tok_billing_1",
                                                      current_period_start: Time.current,
                                                      current_period_end: 1.month.from_now)

    subscription.expire!

    assert_predicate subscription.reload, :free?
    assert_predicate subscription, :expired?
    assert_nil subscription.pg_billing_key
    assert_nil subscription.trial_ends_at
    assert_nil subscription.current_period_start
    assert_nil subscription.current_period_end
    assert_predicate subscription, :used_trial?   # 재체험 차단용 이력 — 만료 후에도 유지
  end

  test "만료 후 재가입(카드 재등록)은 체험 없이 즉시 이용 중이다" do
    subscription = users(:gamma).create_subscription!(plan: :free, status: :expired)

    subscription.activate!(billing_key: "tok_billing_rejoin")

    assert_predicate subscription.reload, :active?   # trialing이 아니다 — 즉시 유료 이용
    assert_predicate subscription, :plus?
    assert_equal "tok_billing_rejoin", subscription.pg_billing_key
  end

  # ── PLAN-1 한도 판정점(단일 판정점 — Client·Invoice 검증이 공유) ──

  test "Free는 거래처 5개 한도다 — 4개는 미도달, 5개는 도달 (PLAN-1 — 경계)" do
    subscription = Subscription.new(user: users(:gamma), plan: :free)

    assert_not subscription.client_limit_reached?(4)
    assert subscription.client_limit_reached?(5)
  end

  test "Free는 월 청구 3건 한도다 — 2건은 미도달, 3건은 도달 (PLAN-1 — 경계)" do
    subscription = Subscription.new(user: users(:gamma), plan: :free)

    assert_not subscription.monthly_invoice_limit_reached?(2)
    assert subscription.monthly_invoice_limit_reached?(3)
  end

  test "Plus는 거래처·청구 한도가 없다 (PLAN-1 — 무제한)" do
    subscription = Subscription.new(user: users(:gamma), plan: :plus)

    assert_not subscription.client_limit_reached?(100)
    assert_not subscription.monthly_invoice_limit_reached?(100)
  end

  test "구독 없는 사용자(레거시)는 Free 상수로 폴백한다 — 무제한 우회 금지" do
    legacy_user = users(:gamma)
    assert_nil legacy_user.subscription  # fixture 적재는 콜백을 우회 — 구독 행 없음

    assert_not legacy_user.client_limit_reached?(4)
    assert legacy_user.client_limit_reached?(5)
    assert_not legacy_user.monthly_invoice_limit_reached?(2)
    assert legacy_user.monthly_invoice_limit_reached?(3)
  end

  test "포트원 고객 키는 구독 간 중복될 수 없다" do
    users(:gamma).create_subscription!(plan: :free)

    duplicate = Subscription.new(user: users(:delta), plan: :free,
                                 pg_customer_key: users(:gamma).subscription.pg_customer_key)

    assert_not_predicate duplicate, :valid?
    assert_predicate duplicate.errors[:pg_customer_key], :any?
  end
end
