require "test_helper"

module Admins
  class TotpServiceTest < ActiveSupport::TestCase
    setup { setup_admin_totp_secrets }

    test "qr_data_url은 PNG data URI를 반환한다 (AUTH-7.1)" do
      data_url = TotpService.qr_data_url(admins(:ops))
      assert_match %r{\Adata:image/png;base64,}, data_url
      assert_not_nil Base64.strict_decode64(data_url.sub("data:image/png;base64,", ""))
    end

    test "verify는 at 시계 인자를 받아 검증을 위임한다 (AUTH-7.1)" do
      admin = admins(:ops)
      now = Time.zone.at(Admin::OTP_STEP_SECONDS * 100_000)
      code = ROTP::TOTP.new(admin.otp_secret).at(now.to_i)
      assert TotpService.verify(admin, code, at: now)
      assert_not TotpService.verify(admin, "000000", at: now)
    end
  end
end
