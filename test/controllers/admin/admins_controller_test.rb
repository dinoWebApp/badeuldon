require "test_helper"

# ADMIN-1·AUTH-7.2 — 관리자 계정 콘솔 컨트롤러(T-C1).
# 시나리오 기준: 01_plan.md T-C1 — ① index는 admin 전원(staff 포함) 200, ② new/create는
# owner 전용 — staff 접근 시 403 리다이렉트 + admin_console_denied 감사, ③ create 정상은
# 303 see_other + admin_create 감사, 실패는 422, ④ change_role/unlock은 owner 전용
# 303 flash, ⑤ 비인증은 로그인 화면으로(base 가드). 서비스 계약은 RoleServiceTest가 고정.
#
# [3-S 결선 전 주의] routes :admins는 3-S(직렬 통합)가 결선한다 — 이 컨트롤러 HTTP 테스트는
# 라우트 결선 후 전체 테스트 단계(Phase 7)에서 유효해진다.
class Admin::AdminsControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_admin_totp_secrets
    @owner = admins(:ops)
    @staff = admins(:staffuser)
    @newbie = admins(:newbie)
  end

  # ── index — admin 전원 ──

  test "index는 owner가 목록을 렌더한다 (ADMIN-1)" do
    admin_login(@owner)

    get admin_admins_path

    assert_response :success
    assert_match "staff@example.com", response.body
    assert_match "ops@example.com", response.body
  end

  test "index는 staff도 조회할 수 있다 (목록 조회 = admin 전원)" do
    admin_login(@staff)

    get admin_admins_path

    assert_response :success
    assert_match "ops@example.com", response.body
    assert_no_match "신규 관리자 생성", response.body, "owner 전용 액션 버튼은 staff에게 노출하지 않는다"
  end

  test "비인증 접근은 로그인 화면으로 유도된다 (base 가드)" do
    get admin_admins_path

    assert_redirected_to new_admin_session_path
  end

  # ── owner 전용 가드 ──

  test "staff의 new 접근은 차단되고 admin_console_denied 감사가 기록된다 (ADMIN-1)" do
    admin_login(@staff)

    get new_admin_admin_path

    assert_redirected_to admin_root_path
    assert_equal 1, AuditLog.where(action: "admin_console_denied", admin_id: @staff.id).count
  end

  test "staff의 create 접근은 차단되고 계정이 생성되지 않는다 (AUTH-7.2)" do
    admin_login(@staff)

    post admin_admins_path, params: { admin: { email: "hacked@example.com", password: "password1234", role: "staff" } }

    assert_redirected_to admin_root_path
    assert_nil Admin.find_by(email: "hacked@example.com")
  end

  # ── create — owner ──

  test "owner의 정상 생성은 303 리다이렉트 + admin_create 감사 (AUTH-7.2)" do
    admin_login(@owner)

    post admin_admins_path, params: {
      admin: { email: "newops@example.com", password: "password1234", role: "staff" }
    }

    assert_redirected_to admin_admins_path
    assert_equal 303, response.status
    created = Admin.find_by(email: "newops@example.com")
    assert_not_nil created
    assert_predicate created, :staff?
    assert_equal 1, AuditLog.where(action: "admin_create").count
  end

  test "중복 이메일 생성은 422로 재렌더된다" do
    admin_login(@owner)

    post admin_admins_path, params: {
      admin: { email: @staff.email, password: "password1234", role: "staff" }
    }

    assert_response :unprocessable_entity
  end

  # ── change_role / unlock — owner 전용 ──

  test "owner의 롤 변경은 303 리다이렉트 + admin_role_change 감사 (ADMIN-1)" do
    admin_login(@owner)

    patch change_role_admin_admin_path(@staff), params: { admin: { role: "owner" } }

    assert_redirected_to admin_admins_path
    assert_equal 303, response.status
    assert_predicate @staff.reload, :owner?
    assert_equal 1, AuditLog.where(action: "admin_role_change").count
  end

  test "staff의 롤 변경 시도는 차단된다 (확정 해석 4)" do
    admin_login(@staff)

    patch change_role_admin_admin_path(@newbie), params: { admin: { role: "staff" } }

    assert_redirected_to admin_root_path
    assert_predicate @newbie.reload, :owner?
    assert_equal 0, AuditLog.where(action: "admin_role_change").count
  end

  test "owner의 잠금 해제는 303 리다이렉트 + admin_unlock 감사 (AUTH-7.3)" do
    admin_login(@owner)
    @newbie.update!(locked_at: Time.current, failed_attempts: 5)

    patch unlock_admin_admin_path(@newbie)

    assert_redirected_to admin_admins_path
    assert_not_predicate @newbie.reload, :locked?
    assert_equal 1, AuditLog.where(action: "admin_unlock").count
  end
end
