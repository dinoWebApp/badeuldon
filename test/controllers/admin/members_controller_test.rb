require "test_helper"

# ADMIN-3 — 회원 관리 컨트롤러(Run B). 시나리오 기준: 05_review.md §4 제안 4·7 —
# ① index 검색(q)·plan·status 필터·무효 enum은 빈 목록(200 — 500 금지), ② show 요약 섹션,
# ③ change_plan 4규칙(활성 Plus→체험 금지·연장 1~12 경계 W-5·해지=cancelled·체험 1회 가드)·
#   성공 전건 감사·실패 미기록, ④ toggle_suspension(정지→U1 로그인 차단+세션 0건→해제),
# ⑤ 비인증·U1 세션 차단. 서비스 계약 자체는 Admins::MemberAdminServiceTest가 고정한다.
class Admin::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_admin_totp_secrets
    @admin = admins(:ops)
    @user = users(:alpha)
    # fixture 적재는 after_create를 우회 — Free 구독 행을 수동 보장(1인 1구독)
    @subscription = @user.subscription || Subscription.create!(user: @user, plan: :free)
  end

  # ── 목록·검색 ──

  test "index는 전체 목록을 렌더한다 (ADMIN-3)" do
    admin_login(@admin)

    get admin_members_path

    assert_response :success
    assert_match "alpha@example.com", response.body
  end

  test "index 필터 — 검색(q)·plan·status·조합이 동작한다 (ADMIN-3·리뷰 제안 7)" do
    admin_login(@admin)

    get admin_members_path, params: { q: "alpha" }
    assert_response :success
    assert_match "alpha@example.com", response.body
    assert_no_match "gamma@example.com", response.body

    get admin_members_path, params: { plan: "free", q: "alpha" }
    assert_response :success
    assert_match "alpha@example.com", response.body

    get admin_members_path, params: { status: "active" }
    assert_response :success
    assert_match "alpha@example.com", response.body

    get admin_members_path, params: { q: "alpha", plan: "free", status: "active" }
    assert_response :success
    assert_match "alpha@example.com", response.body
  end

  test "무효 enum 필터는 500이 아닌 빈 목록(200)을 반환한다 (방어)" do
    admin_login(@admin)

    get admin_members_path, params: { status: "hacked" }

    assert_response :success
    assert_no_match "alpha@example.com", response.body
  end

  test "show는 청구·미수·발송·문의·감사 요약을 렌더한다 (ADMIN-3)" do
    admin_login(@admin)

    get admin_member_path(users(:delta)) # 청구서·발송 fixture 보유 사용자

    assert_response :success
    assert_match "delta@example.com", response.body
    assert_match "플랜", response.body
  end

  # ── change_plan 4규칙 ──

  test "change_plan 활성 Plus→체험 전환은 거부되고 감사를 남기지 않는다 (ADMIN-3)" do
    admin_login(@admin)
    @subscription.update!(plan: :plus, status: :active)

    patch change_plan_admin_member_path(@user), params: { plan_change: { action: "grant_trial" } }

    assert_response :see_other
    assert_predicate @subscription.reload, :active?
    assert_equal 0, plan_change_audits
  end

  test "change_plan 연장 months 0·13은 거부, 12는 성공+감사다 (W-5 경계)" do
    admin_login(@admin)
    base = Time.current + 1.day
    @subscription.update!(plan: :plus, status: :trialing, used_trial: true,
                          current_period_end: base, trial_ends_at: base)

    patch change_plan_admin_member_path(@user), params: { plan_change: { action: "extend_trial", months: "0" } }
    assert_response :see_other
    assert_in_delta base, @subscription.reload.current_period_end, 1.second
    assert_equal 0, plan_change_audits

    patch change_plan_admin_member_path(@user), params: { plan_change: { action: "extend_trial", months: "13" } }
    assert_response :see_other
    assert_equal 0, plan_change_audits

    patch change_plan_admin_member_path(@user), params: { plan_change: { action: "extend_trial", months: "12" } }
    assert_response :see_other
    assert_equal 1, plan_change_audits, "성공 전건 감사 — 거부 2건은 미기록"
    assert_in_delta base + 12.months, @subscription.reload.current_period_end, 1.second
    assert_in_delta base + 12.months, @subscription.trial_ends_at, 1.second,
                    "trialing이면 trial_ends_at 동기화"
  end

  test "change_plan 구독 해지는 cancelled 전환+감사이고 재해지는 거부+미기록이다 (PLAN-5)" do
    admin_login(@admin)
    @subscription.update!(plan: :plus, status: :active)

    patch change_plan_admin_member_path(@user), params: { plan_change: { action: "cancel_subscription" } }
    assert_response :see_other
    assert_predicate @subscription.reload, :cancelled?
    assert_predicate @subscription.reload, :plus?
    assert_equal 1, plan_change_audits

    patch change_plan_admin_member_path(@user), params: { plan_change: { action: "cancel_subscription" } }
    assert_response :see_other
    assert_equal 1, plan_change_audits, "재해지는 거부·미기록"
  end

  test "change_plan 체험 전환 성공 후 재요청은 1회 가드로 거부된다 (ADMIN-3)" do
    admin_login(@admin)

    patch change_plan_admin_member_path(@user), params: { plan_change: { action: "grant_trial" } }
    assert_response :see_other
    assert_predicate @subscription.reload, :trialing?
    assert_equal 1, plan_change_audits

    patch change_plan_admin_member_path(@user), params: { plan_change: { action: "grant_trial" } }
    assert_response :see_other
    assert_equal 1, plan_change_audits, "재체험 거부는 미기록"
  end

  # ── toggle_suspension ──

  test "toggle_suspension 정지는 U1 로그인 차단·세션 0건·감사이고 해제 후 재로그인된다 (ADMIN-3)" do
    admin_login(@admin)
    sign_in_as(@user) # 정지 대상 U1 세션 1건 확보

    patch toggle_suspension_admin_member_path(@user)

    assert_response :see_other
    assert_predicate @user.reload, :suspended?
    assert_equal 0, @user.sessions.count, "정지 시 기존 세션 전부 파기"
    assert AuditLog.exists?(action: "member_suspend", target_type: "User", target_id: @user.id)

    # 파기된 세션으로 /app 재접속 — 차단
    get app_root_path
    assert_redirected_to new_session_url

    # 재로그인 — 정지 차단(U1 세션 컨트롤러 422 전용 문구)
    sign_out
    post session_path, params: { email: @user.email, password: "password" }
    assert_response :unprocessable_entity
    assert_includes response.body, "이용이 정지된 계정입니다"

    # 해제 → 재로그인 성공
    patch toggle_suspension_admin_member_path(@user)
    assert_response :see_other
    assert_predicate @user.reload, :active?
    assert AuditLog.exists?(action: "member_unsuspend", target_type: "User", target_id: @user.id)

    post session_path, params: { email: @user.email, password: "password" }
    assert_response :see_other
  end

  # ── 접근 제어 ──

  test "비인증 접근은 관리자 로그인으로 리다이렉트된다 (표면 격리)" do
    get admin_members_path
    assert_redirected_to new_admin_session_url

    patch toggle_suspension_admin_member_path(@user)
    assert_redirected_to new_admin_session_url

    patch change_plan_admin_member_path(@user), params: { plan_change: { action: "grant_trial" } }
    assert_redirected_to new_admin_session_url
  end

  test "U1 세션으로는 진입할 수 없다 (표면 격리)" do
    sign_in_as users(:alpha)

    get admin_members_path

    assert_redirected_to new_admin_session_url
    assert_equal 0, AdminSession.count
  end

  private

  def plan_change_audits
    AuditLog.where(action: "member_plan_change", target_type: "User", target_id: @user.id).count
  end
end
