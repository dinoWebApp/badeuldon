require "test_helper"

# 감사 로그 완전성 — ADMIN-2(5종 action이 각 시점에 기록)·RecordService 단일 진입점.
# 참고(리뷰어 관찰 1): 2FA 단계(totp_confirm/totp_verify) 실패는 login_failed 미기록이
# 현재 설계이며 Run B에서 action 확장 검토 대상 — 본 테스트에서 assert하지 않는다.
class Admin::AuditTrailTest < ActionDispatch::IntegrationTest
  setup { setup_admin_totp_secrets }

  test "핵심 여정에서 5종 감사 action이 각 시점에 기록된다 (ADMIN-2)" do
    t0 = Time.current
    # CI 경화(2026-11-24 실측) — 같은 작업 프로세스의 앞선 테스트가 트랜잭션 밖에서 남긴 감사 행이
    # 전역 카운트에 섞인다(payments_concurrency_test 가 별도 스레드로 커밋한 payment_over_recorded).
    # 이 여정이 만든 행만 세도록 여정 시작 전의 마지막 감사 행 id를 기준선으로 델타 검증한다
    # (8db0fe9 선례). 시각(created_at) 비교는 쓰지 않는다 — 로그인 시각을 t0으로 고정해 만든 행은
    # DB에 마이크로초로 절삭되어 t0보다 약간 앞선 시각이 되어 't0 이후' 조건에서 빠진다.
    audit_baseline = AuditLog.maximum(:id).to_i
    admin = admins(:ops)

    # login_failed — 1단계 비밀번호 실패
    post admin_session_path, params: { email: admin.email, password: "wrong" }
    assert_response 422

    # login_success — 첫 로그인(new_ip_login 없음)
    admin_login(admin, at: t0)

    # new_ip_login — IP 변경 로그인
    admin_login(admin, ip: "10.9.9.9", at: t0 + 1.minute)

    # lockout — 2FA 코드 5회 실패(2FA 실패 자체는 감사 미기록이 현재 설계)
    post admin_session_path, params: { email: admin.email, password: "password" }
    assert_response :see_other
    5.times do |i|
      post totp_verify_admin_session_path,
           params: { code: totp_code(admin.otp_secret, t0 + (i + 10) * 300) }
      assert_response 422
    end
    assert admin.reload.locked?

    # password_reset — 잠금 해제 후 재설정 성공
    admin.unlock!
    token = admin.password_reset_token
    patch admin_password_path(token), params: { password: "new_password_123",
                                                 password_confirmation: "new_password_123" }
    assert_response :see_other

    expected = {
      "login_failed" => 1, "login_success" => 2,
      "new_ip_login" => 1, "lockout" => 1, "password_reset" => 1
    }
    journey_audits = AuditLog.where("id > ?", audit_baseline)
    assert_equal expected, journey_audits.group(:action).count
    assert_equal 6, journey_audits.count, "감사 생성은 RecordService 단일 경로 — 이외 경로 없음"
  end
end
