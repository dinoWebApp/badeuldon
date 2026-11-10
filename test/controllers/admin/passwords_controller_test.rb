require "test_helper"

# 관리자 비밀번호 재설정 — AUTH-7.6(1회성 토큰 15분·전 세션 파기·감사)·W-8(pending 정리)
class Admin::PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { setup_admin_totp_secrets }

  test "재설정 요청은 303과 password_reset 메일 발송을 큐잉한다 (AUTH-7.6 B-2)" do
    post admin_passwords_path, params: { email: admins(:ops).email }
    assert_enqueued_emails 1
    # 토큰은 getter 호출마다 exp가 재생성되어 다르므로 — 수신자와 URL 형태만 검증한다
    mail_job = enqueued_jobs.find { |j| j[:job] == ActionMailer::MailDeliveryJob }
    assert mail_job, "password_reset 메일이 큐잉된다"
    mailer_args = mail_job[:args][3]["args"]
    assert_equal "gid://badeuldon/Admin/#{admins(:ops).id}", mailer_args[0]["_aj_globalid"]
    assert_match %r{/admin/passwords/[^/]+/edit\z}, mailer_args[1]
    assert_response :see_other
    assert_redirected_to new_admin_session_url
    assert_not_nil admins(:ops).reload.password_reset_token
  end

  test "미가입 이메일 요청도 동일 응답이고 메일은 발송되지 않는다 (열거 방지)" do
    assert_enqueued_emails 0 do
      post admin_passwords_path, params: { email: "ghost@example.com" }
    end
    assert_response :see_other
  end

  test "토큰 edit은 200으로 폼을 렌더한다 (AUTH-7.6)" do
    token = admins(:ops).password_reset_token
    get edit_admin_password_path(token)
    assert_response :success
    assert_select "form[action=?]", admin_password_path(token)
  end

  test "잘못된 토큰은 재설정 요청 화면으로 되돌려진다 (AUTH-7.6)" do
    get edit_admin_password_path("invalid-token")
    assert_redirected_to new_admin_password_url
  end

  test "15분 경과 토큰은 만료로 거부된다 (AUTH-7.6)" do
    token = admins(:ops).password_reset_token
    travel 16.minutes do
      get edit_admin_password_path(token)
      assert_redirected_to new_admin_password_url
    end
  end

  test "재설정 성공은 구비밀번호 무효화·전 세션 파기·pending 정리·감사 기록 (AUTH-7.6·W-8)" do
    t0 = Time.current
    admin_login(admins(:ops), at: t0)
    assert_equal 1, AdminSession.count

    # pending 쿠키 도용 시나리오 — 1단계만 통과한 상태에서 재설정(W-8)
    travel_to t0 + 1.minute do
      post admin_session_path, params: { email: admins(:ops).email, password: "password" }
    end
    assert_equal admins(:ops).id, session[:pending_admin_id]

    token = admins(:ops).password_reset_token
    assert_difference -> { AuditLog.where(action: "password_reset").count }, +1 do
      patch admin_password_path(token), params: { password: "new_password_123",
                                                   password_confirmation: "new_password_123" }
    end
    assert_response :see_other
    assert_redirected_to new_admin_session_url

    assert_equal 0, AdminSession.count, "발급된 admin_sessions가 전부 파기된다"
    assert_nil session[:pending_admin_id], "pending 키도 함께 정리된다(W-8)"
    assert admins(:ops).reload.authenticate("new_password_123")
    assert_not admins(:ops).authenticate("password")

    # 구세션 토큰으로 재진입 불가
    get admin_root_path
    assert_redirected_to new_admin_session_url
  end

  test "사용한 토큰은 재사용할 수 없다 (AUTH-7.6 1회성)" do
    token = admins(:ops).password_reset_token
    patch admin_password_path(token), params: { password: "new_password_123",
                                                 password_confirmation: "new_password_123" }
    assert_response :see_other

    patch admin_password_path(token), params: { password: "another_password",
                                                 password_confirmation: "another_password" }
    assert_redirected_to new_admin_password_url, "digest 변경으로 토큰 무효화"
  end

  test "확인 불일치 비밀번호는 422로 재렌더된다 (AUTH-7.6)" do
    token = admins(:ops).password_reset_token
    patch admin_password_path(token), params: { password: "new_password_123",
                                                 password_confirmation: "different" }
    assert_response 422
    assert_select "p#alert"
  end
end
