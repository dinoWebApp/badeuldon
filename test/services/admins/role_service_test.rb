require "test_helper"

# ADMIN-1·AUTH-7.2 — 관리자 롤·계정 콘솔 서비스(Admins::RoleService) 계약 고정 테스트.
# 시나리오 기준: 01_plan.md T-C1·02_prd_update.md 확정 해석 4(owner 전용 경계) —
# ① change_role: staff actor 거부(admin_role_denied 감사)·자기 자신 staff 강등 금지
#   (최고 관리자 유일성 보장)·정상 변경 시 admin_role_change 감사, ② unlock: owner 전용
#   (staff 거부·admin_unlock_denied 감사)·잠금 아님 거부·해제 시 locked_at/failed_attempts 초기화,
# ③ create_admin: staff 거부(admin_create_denied 감사)·중복 이메일 Result 실패·
#   정상 생성 시 admin_create 감사·otp_secret 미발급, ④ 실패 시 감사 미기록 경계(롤 변경 실패).
class Admins::RoleServiceTest < ActiveSupport::TestCase
  setup do
    @owner = admins(:ops)
    @staff = admins(:staffuser)
    @newbie = admins(:newbie)
  end

  # ── change_role! ──

  test "owner가 staff를 owner로 승격하면 롤이 변경되고 감사가 기록된다 (ADMIN-1)" do
    result = Admins::RoleService.change_role!(admin: @staff, actor: @owner, role: :owner)

    assert_predicate result, :success?
    assert_predicate @staff.reload, :owner?
    assert_equal 1, audits_with_action("admin_role_change").count
  end

  test "staff actor의 롤 변경은 거부되고 admin_role_denied 감사가 기록된다 (ADMIN-1·확정 해석 4)" do
    result = Admins::RoleService.change_role!(admin: @newbie, actor: @staff, role: :staff)

    assert_not_predicate result, :success?
    assert_predicate @newbie.reload, :owner?
    assert_equal 1, audits_with_action("admin_role_denied").count
    assert_equal 0, audits_with_action("admin_role_change").count
  end

  test "owner가 자기 자신을 staff로 강등하면 거부된다 (최고 관리자 유일성 보장)" do
    result = Admins::RoleService.change_role!(admin: @owner, actor: @owner, role: :staff)

    assert_not_predicate result, :success?
    assert_predicate @owner.reload, :owner?
    assert_equal 0, audits_with_action("admin_role_change").count
  end

  test "owner가 다른 owner를 staff로 강등하는 것은 허용된다" do
    result = Admins::RoleService.change_role!(admin: @newbie, actor: @owner, role: :staff)

    assert_predicate result, :success?
    assert_predicate @newbie.reload, :staff?
  end

  test "알 수 없는 롤은 거부되고 감사를 남기지 않는다" do
    result = Admins::RoleService.change_role!(admin: @staff, actor: @owner, role: :superadmin)

    assert_not_predicate result, :success?
    assert_predicate @staff.reload, :staff?
    assert_equal 0, audits_with_action("admin_role_change").count
  end

  # ── unlock! ──

  test "owner가 잠긴 관리자를 해제하면 잠금 상태가 초기화되고 감사가 기록된다 (AUTH-7.3)" do
    @newbie.update!(locked_at: Time.current, failed_attempts: 5)

    result = Admins::RoleService.unlock!(admin: @newbie, actor: @owner)

    assert_predicate result, :success?
    assert_not_predicate @newbie.reload, :locked?
    assert_equal 0, @newbie.failed_attempts
    assert_equal 1, audits_with_action("admin_unlock").count
  end

  test "staff actor의 잠금 해제는 거부되고 admin_unlock_denied 감사가 기록된다 (확정 해석 4)" do
    @newbie.update!(locked_at: Time.current, failed_attempts: 5)

    result = Admins::RoleService.unlock!(admin: @newbie, actor: @staff)

    assert_not_predicate result, :success?
    assert_predicate @newbie.reload, :locked?
    assert_equal 1, audits_with_action("admin_unlock_denied").count
    assert_equal 0, audits_with_action("admin_unlock").count
  end

  test "잠금 상태가 아닌 계정의 unlock은 거부되고 감사를 남기지 않는다" do
    result = Admins::RoleService.unlock!(admin: @newbie, actor: @owner)

    assert_not_predicate result, :success?
    assert_equal 0, audits_with_action("admin_unlock").count
  end

  # ── create_admin! ──

  test "owner가 신규 관리자를 생성하면 계정이 만들어지고 감사가 기록된다 (AUTH-7.2)" do
    result = Admins::RoleService.create_admin!(
      actor: @owner, email: "newops@example.com", password: "password1234", role: :staff
    )

    assert_predicate result, :success?
    created = Admin.find_by(email: "newops@example.com")
    assert_not_nil created
    assert_predicate created, :staff?
    assert_not created.two_factor_enabled?, "otp_secret은 최초 로그인 시 2FA 등록 화면에서 발급(AUTH-7.1)"
    assert_equal 1, audits_with_action("admin_create").count
  end

  test "staff actor의 계정 생성은 거부되고 admin_create_denied 감사가 기록된다 (AUTH-7.2·확정 해석 4)" do
    result = Admins::RoleService.create_admin!(
      actor: @staff, email: "newops@example.com", password: "password1234", role: :staff
    )

    assert_not_predicate result, :success?
    assert_nil Admin.find_by(email: "newops@example.com")
    assert_equal 1, audits_with_action("admin_create_denied").count
    assert_equal 0, audits_with_action("admin_create").count
  end

  test "중복 이메일 생성은 Result 실패로 반환되고 감사를 남기지 않는다" do
    result = Admins::RoleService.create_admin!(
      actor: @owner, email: @staff.email, password: "password1234", role: :staff
    )

    assert_not_predicate result, :success?
    assert_equal 1, Admin.where(email: @staff.email).count
    assert_equal 0, audits_with_action("admin_create").count
  end

  private

  def audits_with_action(action)
    AuditLog.where(action: action, admin_id: [ @owner.id, @staff.id ])
  end
end
