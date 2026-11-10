require "test_helper"

# ADMIN-2 — 감사 로그 뷰 컨트롤러(Run B). 시나리오 기준: 05_review.md §4 제안 5 —
# ① 필터(action·관리자·기간) 각각과 조합, ② 무효 날짜(from=garbage·2026-13-45)는 500이 아닌
#   200으로 필터 생략(W-2), ③ 페이지네이션 상한 100행(@page 2 확인), ④ @admins 컨트롤러 로드
#   (W-4 — 뷰 쿼리 금지), ⑤ 비인증 차단.
class Admin::AuditLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_admin_totp_secrets
    @ops = admins(:ops)
    @staff = admins(:staffuser)
    @user = users(:alpha)
  end

  test "index는 전체 로그와 관리자 select 옵션(@admins)을 렌더한다 (ADMIN-2·W-4)" do
    seed_log(admin: @ops, action: "order_refund")
    seed_log(admin: @staff, action: "member_suspend")

    admin_login(@ops)

    get admin_audit_logs_path

    assert_response :success
    assert_select "option", text: /#{@ops.email}/
    assert_select "option", text: /#{@staff.email}/
    assert_select "td", text: /order_refund/
  end

  test "필터 — action·관리자·기간 각각이 동작한다 (ADMIN-2)" do
    seed_log(admin: @ops, action: "order_refund")
    seed_log(admin: @staff, action: "member_suspend")
    seed_log(admin: @ops, action: "order_refund", created_at: 3.days.ago) # 기간 필터에서 제외될 과거 로그
    admin_login(@ops)

    # action 필터 — 행 목록(td) 기준 판정(필터 select 옵션에도 action 문자열이 렌더되므로 본문 문자열 매치 불가)
    get admin_audit_logs_path, params: { action_filter: "member_suspend" }
    assert_response :success
    assert_select "td", text: /\Amember_suspend\z/, count: 1
    assert_select "td", text: /\Aorder_refund\z/, count: 0

    get admin_audit_logs_path, params: { admin_id: @staff.id }
    assert_response :success
    assert_select "td", text: /\Amember_suspend\z/, count: 1
    assert_select "td", text: /\Aorder_refund\z/, count: 0

    get admin_audit_logs_path, params: { from: Date.current.to_s, to: Date.current.to_s }
    assert_response :success
    assert_select "td", text: /\Amember_suspend\z/, count: 1
    # 당일 order_refund 1건만 — 과거 로그(3일 전)는 기간 밖
    assert_select "td", text: /\Aorder_refund\z/, count: 1
  end

  test "무효 날짜 파라미터는 500이 아닌 200으로 필터를 생략한다 (W-2)" do
    seed_log(admin: @ops, action: "order_refund")
    admin_login(@ops)

    get admin_audit_logs_path, params: { from: "garbage" }
    assert_response :success
    assert_match "order_refund", response.body, "파싱 실패 — 필터 생략(전체 목록)"

    get admin_audit_logs_path, params: { from: "2026-13-45" }
    assert_response :success
    assert_match "order_refund", response.body, "초과 월일 — 필터 생략"
  end

  test "페이지네이션은 100행 상한으로 2페이지를 제공한다 (ADMIN-2)" do
    101.times { |i| seed_log(admin: @ops, action: "order_refund", detail: "log-#{i}") }
    admin_login(@ops)

    get admin_audit_logs_path
    assert_response :success
    # admin_login이 login_success 감사 1건을 추가하므로 시드 101 + 1
    assert_equal 101, AuditLog.where(action: "order_refund").count

    get admin_audit_logs_path, params: { page: 2 }
    assert_response :success
    # 최신순(recent) 2페이지 — 101건 중 1건만 남는다
    assert_match "log-0", response.body, "가장 오래된 1건이 2페이지에 존재"
    assert_no_match "log-100", response.body
  end

  test "비인증 접근은 관리자 로그인으로 리다이렉트된다 (표면 격리)" do
    get admin_audit_logs_path
    assert_redirected_to new_admin_session_url
  end

  private

  def seed_log(admin:, action:, detail: "시드 감사", created_at: Time.current)
    AuditLog.create!(admin: admin, action: action, target_type: "User",
                     target_id: @user.id, detail: detail, ip: "127.0.0.1",
                     created_at: created_at)
  end
end
