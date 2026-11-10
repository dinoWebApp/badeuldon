require "test_helper"

# ADMIN-3 — 회원 관리 서비스(Admins::MemberAdminService) 계약 고정 테스트.
# 시나리오 기준: PRD v0.31 ADMIN-3 확정 해석·05_review.md §4 제안 4·§6 W-5 —
# ① grant_trial: 활성(Plus) 구독 보유 금지·1회 가드(used_trial), ② extend_trial: months 1~12
#   경계(0·13 거부 — W-5, 12 성공)·trialing이면 trial_ends_at 동기화, ③ cancel_subscription:
#   Subscription#cancel!(기간 말까지 유효 — PLAN-5)·재해지 거부, ④ toggle_suspension: 정지 시
#   세션 전부 파기·해제 가능, ⑤ 성공 전건 감사(member_plan_change·member_suspend/unsuspend)·
#   실패 미기록(ADMIN-2), ⑥ 미지 action 거부. 컨트롤러 테스트와 중복 허용(서비스 계약 고정).
class Admins::MemberAdminServiceTest < ActiveSupport::TestCase
  setup do
    @admin = admins(:ops)
    @user = users(:alpha) # fixture 적재는 after_create를 우회 — Free 구독 행을 수동 보장
    @subscription = @user.subscription || Subscription.create!(user: @user, plan: :free)
  end

  # ── grant_trial ──

  test "grant_trial은 Free 사용자를 체험으로 전환하고 감사를 기록한다 (ADMIN-3)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      result = service_change(action: "grant_trial")

      assert_predicate result, :success?
      assert_predicate @subscription.reload, :trialing?
      assert_predicate @subscription.reload, :plus?
      assert_predicate @subscription, :used_trial?
      assert_equal 1, plan_change_audits.count
    end
  end

  test "활성 Plus 구독 보유자의 grant_trial은 거부되고 감사를 남기지 않는다 (ADMIN-3)" do
    @subscription.update!(plan: :plus, status: :active)

    result = service_change(action: "grant_trial")

    assert_not_predicate result, :success?
    assert_predicate @subscription.reload, :plus?
    assert_predicate @subscription.reload, :active?
    assert_equal 0, plan_change_audits.count, "실패는 감사 미기록"
  end

  test "체험 1회 가드 — used_trial이면 재체험이 거부된다 (ADMIN-3)" do
    @subscription.update!(used_trial: true, plan: :free, status: :active)

    result = service_change(action: "grant_trial")

    assert_not_predicate result, :success?
    assert_equal 0, plan_change_audits.count
  end

  # ── extend_trial (W-5 경계) ──

  test "extend_trial months 0·13은 거부되고 기간·감사가 불변이다 (W-5)" do
    @subscription.update!(plan: :plus, status: :trialing,
                          trial_ends_at: Time.zone.parse("2026-11-24 09:00"),
                          current_period_end: Time.zone.parse("2026-11-24 09:00"),
                          used_trial: true)

    [ "0", "13" ].each do |months|
      result = service_change(action: "extend_trial", months: months)
      assert_not_predicate result, :success?, "months=#{months}는 거부"
    end
    assert_equal Time.zone.parse("2026-11-24 09:00"), @subscription.reload.current_period_end
    assert_equal 0, plan_change_audits.count, "거부 2건 모두 미기록"
  end

  test "extend_trial months 12는 성공하고 감사를 기록한다 (W-5 성공 경계)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      @subscription.update!(plan: :plus, status: :trialing,
                            trial_ends_at: Time.zone.parse("2026-11-24 09:00"),
                            current_period_end: Time.zone.parse("2026-11-24 09:00"),
                            used_trial: true)

      result = service_change(action: "extend_trial", months: "12")

      assert_predicate result, :success?
      assert_equal Time.zone.parse("2027-11-24 09:00"), @subscription.reload.current_period_end
      assert_equal Time.zone.parse("2027-11-24 09:00"), @subscription.trial_ends_at,
                   "trialing이면 trial_ends_at 동기화"
      assert_equal 1, plan_change_audits.count
    end
  end

  test "extend_trial은 current_period_end·trial_ends_at·현재 중 최대값을 base로 연장한다 (ADMIN-3)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      # 만료된 Free 구독 — base는 현재 시각이 된다
      @subscription.update!(current_period_end: 1.month.ago, trial_ends_at: nil)

      result = service_change(action: "extend_trial", months: "3")

      assert_predicate result, :success?
      assert_in_delta Time.zone.parse("2027-02-10 09:00"), @subscription.reload.current_period_end, 1.second
    end
  end

  test "활성 Plus 구독 보유자의 extend_trial은 거부된다 (ADMIN-3)" do
    @subscription.update!(plan: :plus, status: :active)

    result = service_change(action: "extend_trial", months: "3")

    assert_not_predicate result, :success?
    assert_equal 0, plan_change_audits.count
  end

  # ── cancel_subscription ──

  test "cancel_subscription은 cancelled로 전환하고 plan은 plus를 유지한다 (PLAN-5)" do
    @subscription.update!(plan: :plus, status: :active)

    result = service_change(action: "cancel_subscription")

    assert_predicate result, :success?
    assert_predicate @subscription.reload, :cancelled?
    assert_predicate @subscription.reload, :plus?, "해지는 기간 말까지 Plus 유효 — PLAN-5"
    assert_equal 1, plan_change_audits.count
  end

  test "이미 해지된 구독의 재해지는 거부되고 감사를 남기지 않는다 (ADMIN-3)" do
    @subscription.update!(plan: :plus, status: :cancelled)

    result = service_change(action: "cancel_subscription")

    assert_not_predicate result, :success?
    assert_equal 0, plan_change_audits.count
  end

  # ── 공통 거부 ──

  test "미지 action은 거부되고 감사를 남기지 않는다 (ADMIN-3 방어)" do
    result = service_change(action: "hacked")

    assert_not_predicate result, :success?
    assert_equal 0, AuditLog.count
  end

  test "구독 행이 없으면 각 action은 거부된다 (ADMIN-3 방어)" do
    @user.reload.subscription.destroy!
    @user.reload # 캐시된 파기된 구독 연관 참조 제거 — user.subscription을 nil로 재조회

    [ "grant_trial", "extend_trial", "cancel_subscription" ].each do |action|
      result = service_change(action: action)
      assert_not_predicate result, :success?, "#{action} — 구독 행 없음 거부"
    end
    assert_equal 0, AuditLog.count
  end

  # ── toggle_suspension ──

  test "toggle_suspension 정지는 status 전환·세션 전부 파기·member_suspend 감사를 남긴다 (ADMIN-3)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      2.times { @user.sessions.create! }

      result = Admins::MemberAdminService.toggle_suspension!(admin: @admin, user: @user)

      assert_predicate result, :success?
      assert_predicate @user.reload, :suspended?
      assert_equal 0, @user.sessions.count, "정지 시 기존 세션 전부 파기"
      suspend = AuditLog.find_by(action: "member_suspend", target_type: "User", target_id: @user.id)
      assert_not_nil suspend, "member_suspend 감사 1건"
    end
  end

  test "toggle_suspension 해제는 active 복귀·member_unsuspend 감사를 남긴다 (ADMIN-3)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      @user.update!(status: :suspended)

      result = Admins::MemberAdminService.toggle_suspension!(admin: @admin, user: @user)

      assert_predicate result, :success?
      assert_predicate @user.reload, :active?
      assert AuditLog.exists?(action: "member_unsuspend", target_type: "User", target_id: @user.id)
    end
  end

  private

  def service_change(action:, months: nil)
    Admins::MemberAdminService.change_plan!(admin: @admin, user: @user,
                                            plan_params: { action: action, months: months }.compact)
  end

  def plan_change_audits
    AuditLog.where(action: "member_plan_change", target_type: "User", target_id: @user.id)
  end
end
