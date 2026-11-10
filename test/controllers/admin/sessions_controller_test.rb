require "test_helper"

# 관리자 2단계 로그인 플로우 — AUTH-7.1(2FA 등록·검증)·7.3(5회 잠금·열거 방지)·
# 7.4(신규 IP 통보)·7.5(세션)·ADMIN-2(감사). 시나리오는 _workspace/05_review.md
# "Tester에게 제안하는 중점 테스트 영역"의 리뷰 재현(B-3·C-1·C-2·W-2·W-6)을 테스트화했다.
class Admin::SessionsControllerTest < ActionDispatch::IntegrationTest
  UNIFIED_LOGIN_ERROR = "이메일 또는 비밀번호가 올바르지 않습니다."

  setup { setup_admin_totp_secrets }

  # ── ① 정상 1단계 ────────────────────────────────────────────────────────

  test "GET 로그인 폼은 200으로 렌더되고 noindex를 출력한다 (AUTH-7·SURF-3)" do
    get new_admin_session_path
    assert_response :success
    assert_select "form[action=?]", admin_session_path
    assert_select "meta[name=robots]" do |metas|
      assert_match(/noindex/, metas.first["content"])
    end
  end

  test "정상 자격증명 1단계는 303으로 2단계(totp_setup)로 진행한다 (AUTH-7.1)" do
    assert_no_difference -> { AdminSession.count } do
      post admin_session_path, params: { email: admins(:ops).email, password: "password" }
    end
    assert_response :see_other
    assert_redirected_to totp_setup_admin_session_url
    assert_equal admins(:ops).id, session[:pending_admin_id]
  end

  # ── ② 오류 자격증명 — 통일 문구·열거 방지 ──────────────────────────────

  test "오류 비밀번호는 422 통일 문구와 login_failed 감사, 실패 카운터 증가 (AUTH-7.3·ADMIN-2)" do
    assert_difference -> { admins(:ops).reload.failed_attempts }, +1 do
      assert_difference -> { AuditLog.where(action: "login_failed").count }, +1 do
        post admin_session_path, params: { email: admins(:ops).email, password: "wrong" }
      end
    end
    assert_response 422
    assert_select "p#alert", text: UNIFIED_LOGIN_ERROR
  end

  test "미존재 이메일도 동일 문구로 응답하고 감사를 남기지 않는다 (열거 방지)" do
    post admin_session_path, params: { email: "ghost@example.com", password: "wrong" }
    assert_response 422
    assert_select "p#alert", text: UNIFIED_LOGIN_ERROR
    assert_equal 0, AuditLog.count
    assert_equal 0, AdminSession.count
  end

  # ── ③ 5회 실패 잠금(W-2)·잠금 계정 차단 ────────────────────────────────

  test "5회 실패 시 잠금 전환·lockout 감사·통보 메일이 정확히 1회씩 발생한다 (AUTH-7.3·W-2)" do
    5.times do
      post admin_session_path, params: { email: admins(:ops).email, password: "wrong" }
      assert_response 422
    end
    assert_enqueued_emails 1
    assert_enqueued_email_with AdminMailer, :locked_out, args: [ admins(:ops) ]
    assert admins(:ops).reload.locked?
    assert_equal 1, AuditLog.where(action: "lockout").count, "lockout 감사는 정확히 1건"
    assert_equal 5, AuditLog.where(action: "login_failed").count

    # 6회차(이미 잠금) — 재전환·재통보 없음
    post admin_session_path, params: { email: admins(:ops).email, password: "wrong" }
    assert_response 422
    assert_equal 1, AuditLog.where(action: "lockout").count
    perform_enqueued_jobs # 메일 큐 비움 — 재통보 없음 검증을 위해
    assert_enqueued_emails 0
  end

  test "잠금 계정의 정상 비밀번호 1단계는 통일 문구로 거부된다 (AUTH-7.3 열거 방지)" do
    5.times { admins(:ops).record_failed_attempt! }
    post admin_session_path, params: { email: admins(:ops).email, password: "password" }
    assert_response 422
    assert_select "p#alert", text: UNIFIED_LOGIN_ERROR
    assert_nil session[:pending_admin_id]
  end

  # ── ④ B-3 — 최초 2FA 등록 플로우 ───────────────────────────────────────

  test "신규 관리자가 QR·시크릿 확인 후 totp_confirm으로 등록·진입한다 (AUTH-7.1 B-3)" do
    post admin_session_path, params: { email: admins(:newbie).email, password: "password" }
    assert_response :see_other

    get totp_setup_admin_session_path
    assert_response :success
    secret = admins(:newbie).reload.otp_secret
    assert_not_nil secret, "등록 화면에서 시크릿이 최초 발급된다"
    assert_match secret, response.body, "수동 시크릿이 병기된다"
    assert_match %r{data:image/png;base64,}, response.body, "QR이 렌더된다"

    post totp_confirm_admin_session_path, params: { code: totp_code(secret) }
    assert_response :see_other
    assert_redirected_to admin_root_url
    assert_not_nil admins(:newbie).reload.otp_confirmed_at
    assert_equal 1, AdminSession.count
    follow_redirect!
    assert_select "h1", text: "운영 현황"
  end

  # ── ⑤ 등록 계정 totp_verify 진입 ───────────────────────────────────────

  test "등록 계정은 totp_verify로 303 콘솔 진입과 login_success 감사를 남긴다 (AUTH-7.1·ADMIN-2)" do
    assert_difference -> { AuditLog.where(action: "login_success").count }, +1 do
      assert_difference -> { AdminSession.count }, +1 do
        admin_login(admins(:ops))
      end
    end
    follow_redirect!
    assert_select "h1", text: "운영 현황"
  end

  # ── ⑥ C-1 — pending 중 잠금 차단 ───────────────────────────────────────

  test "pending 유지 중 잠긴 계정은 2단계 화면 접근이 로그인으로 되돌려진다 (C-1)" do
    post admin_session_path, params: { email: admins(:ops).email, password: "password" }
    assert_response :see_other

    # 다른 경로(모델 5회 실패)로 pending 유지 중 잠금
    5.times { admins(:ops).record_failed_attempt! }

    get totp_setup_admin_session_path
    assert_response :redirect
    assert_redirected_to new_admin_session_url
    assert_nil session[:pending_admin_id], "잠금 시 pending 키가 정리된다"

    post totp_verify_admin_session_path, params: { code: totp_code(admins(:ops).otp_secret) }
    assert_response :redirect
    assert_redirected_to new_admin_session_url
  end

  test "플로우 중 5회 코드 실패로 잠기면 정상 코드로도 세션이 발급되지 않는다 (C-1·W-2)" do
    admin_login_step1(admins(:ops))
    now = Time.current
    5.times do |i|
      travel_to now do
        post totp_verify_admin_session_path,
             params: { code: totp_code(admins(:ops).otp_secret, now + (i + 10) * 300) }
      end
      assert_response 422, "#{i + 1}회차 코드 실패"
    end
    assert_equal 1, AuditLog.where(action: "lockout").count
    assert_enqueued_emails 1
    assert_enqueued_email_with AdminMailer, :locked_out, args: [ admins(:ops) ]

    # 잠금 후 정상 현재 코드 — 세션 발급 거부(리뷰 신규 제안 a)
    assert_no_difference -> { AdminSession.count } do
      travel_to now do
        post totp_verify_admin_session_path, params: { code: totp_code(admins(:ops).otp_secret) }
      end
    end
    assert_response :redirect
    assert_redirected_to new_admin_session_url
    assert admins(:ops).reload.locked?
  end

  # ── ⑦ C-2 — 신규 IP 통보(AUTH-7.4) ────────────────────────────────────

  test "첫 로그인은 통보 없이 last_login을 기록한다 (AUTH-7.4 C-2)" do
    t0 = Time.current
    assert_enqueued_emails 0 do
      admin_login(admins(:ops), at: t0)
    end
    assert_equal 0, AuditLog.where(action: "new_ip_login").count
    assert_equal "127.0.0.1", admins(:ops).reload.last_login_ip
    assert_not_nil admins(:ops).last_login_at
  end

  test "IP 변경 로그인은 new_login 메일·new_ip_login 감사·기록 갱신 (AUTH-7.4 C-2)" do
    t0 = Time.current
    admin_login(admins(:ops), at: t0)
    # 리뷰 제안 3 — 로그인 간 30초 이상 간격(after: 스텝 카운터 재사용 차단 회피)
    admin_login(admins(:ops), ip: "10.9.9.9", at: t0 + 1.minute)
    assert_enqueued_emails 1
    assert_enqueued_email_with AdminMailer, :new_login, args: [ admins(:ops), "10.9.9.9" ]
    assert_equal 1, AuditLog.where(action: "new_ip_login").count
    assert_equal "10.9.9.9", admins(:ops).reload.last_login_ip
    perform_enqueued_jobs # 메일 큐 비움 — 이후 무통보 검증을 위해

    # 동일 IP(10.9.9.9) 재로그인 — 무통보(리뷰 신규 제안 c)
    assert_enqueued_emails 0 do
      admin_login(admins(:ops), ip: "10.9.9.9", at: t0 + 2.minutes)
    end
    assert_equal 1, AuditLog.where(action: "new_ip_login").count
  end

  # ── ⑧ W-6 — 미등록 계정 totp_verify 차단 ──────────────────────────────

  test "미등록 계정의 totp_verify는 등록 플로우로 303 유도된다 (W-6)" do
    admin_login_step1(admins(:newbie))
    get totp_setup_admin_session_path # 시크릿 발급(아직 미등록)
    assert_response :success
    secret = admins(:newbie).reload.otp_secret

    assert_no_difference -> { AdminSession.count } do
      post totp_verify_admin_session_path, params: { code: totp_code(secret) }
    end
    assert_response :see_other
    assert_redirected_to totp_setup_admin_session_url
    assert_nil admins(:newbie).reload.otp_confirmed_at
    assert_equal 0, AuditLog.where(action: "login_success").count
  end

  # ── ⑨ 세션 만료(AUTH-7.5)·로그아웃 ────────────────────────────────────

  test "비활동 2시간 경과 세션은 재검증에서 만료된다 (AUTH-7.5)" do
    admin_login(admins(:ops))
    travel 2.hours do
      get admin_root_path
      assert_redirected_to new_admin_session_url
    end
  end

  test "활동이 이어지면 12시간 절대 만료 전까지 세션이 유지된다 (AUTH-7.5)" do
    admin_login(admins(:ops))
    # 1시간 간격 활동 — 비활동 만료(2시간)를 피하며 절대 만료에 접근한다.
    # travel은 블록 없이 호출해야 누적된다(블록 형태는 매번 원점 기준).
    11.times do
      travel 1.hour
      get admin_root_path
      assert_response :success, "활동 갱신으로 비활동 만료는 아님"
    end
    travel 1.hour + 1.second
    get admin_root_path
    assert_redirected_to new_admin_session_url, "절대 12시간 초과로 만료"
  end

  test "로그아웃은 세션을 파기하고 콘솔 재진입을 차단한다 (AUTH-7.5)" do
    admin_login(admins(:ops))
    delete admin_session_path
    assert_response :see_other
    assert_redirected_to new_admin_session_url
    assert_equal 0, AdminSession.count
    get admin_root_path
    assert_redirected_to new_admin_session_url
  end

  private

  def admin_login_step1(admin)
    post admin_session_path, params: { email: admin.email, password: "password" }
    assert_response :see_other
  end
end
