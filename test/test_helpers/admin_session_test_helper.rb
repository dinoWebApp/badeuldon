module AdminSessionTestHelper
  # fixture 로딩은 Active Record Encryption(encrypts)을 우회하므로 otp_secret을
  # fixture로 넣을 수 없다 — 테스트 setup에서 이 헬퍼로 암호화 경유 주입한다.
  OPS_TOTP_SECRET = "JBSWY3DPEHPK3PXP"
  STAFF_TOTP_SECRET = "KRSXG5CTMVRXEZLU"

  def setup_admin_totp_secrets
    admins(:ops).update!(otp_secret: OPS_TOTP_SECRET)
    admins(:staffuser).update!(otp_secret: STAFF_TOTP_SECRET)
  end

  # 2단계 로그인 플로우 전체를 통과해 관리자 세션을 발급받는다(AUTH-7.1).
  # at — TOTP 스텝 카운터(after:) 재사용 차단을 피하려면 로그인마다 30초 이상
  # 떨어진 시각을 지정한다(리뷰 제안 3 — ±1 창과 `after:` 상호작용).
  def admin_login(admin, password: "password", ip: nil, at: Time.current)
    headers = ip ? { "REMOTE_ADDR" => ip } : {}
    travel_to at do
      post admin_session_path, params: { email: admin.email, password: }, headers: headers
      assert_response :see_other, "1단계 자격증명이 통과해야 한다"
      post totp_verify_admin_session_path, params: { code: totp_code(admin.otp_secret) }, headers: headers
      assert_response :see_other, "2단계 TOTP 검증이 통과해야 한다"
      assert_redirected_to admin_root_url
    end
  end

  # TOTP 시크릿에서 해당 시각의 코드 산출.
  def totp_code(secret, at = Time.current)
    ROTP::TOTP.new(secret).at(at.to_i)
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include AdminSessionTestHelper
end
