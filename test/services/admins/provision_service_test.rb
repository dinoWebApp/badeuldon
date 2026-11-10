require "test_helper"

module Admins
  class ProvisionServiceTest < ActiveSupport::TestCase
    test "신규 관리자를 생성한다 — otp_secret은 발급하지 않는다 (AUTH-7.2)" do
      admin = ProvisionService.new(email: "run_a@example.com", password: "STRONG_PW_123", role: :owner).call
      assert admin.persisted?
      assert_equal "run_a@example.com", admin.email
      assert_nil admin.otp_secret, "시크릿은 최초 로그인 등록 화면에서 발급된다"
    end

    test "role을 지정할 수 있다 (ADMIN-1)" do
      admin = ProvisionService.new(email: "st@example.com", password: "STRONG_PW_123", role: :staff).call
      assert_equal "staff", admin.role
    end

    test "중복 이메일은 저장되지 않은 Admin과 오류를 반환한다 (AUTH-7.2)" do
      admin = ProvisionService.new(email: admins(:ops).email, password: "STRONG_PW_123").call
      assert_not admin.persisted?
      assert admin.errors.of_kind?(:email, :taken)
    end

    test "비밀번호 누락은 저장되지 않는다 (AUTH-7.2 — 강도 요건은 화면 안내 위임, 03 노트 17)" do
      admin = ProvisionService.new(email: "weak@example.com", password: nil).call
      assert_not admin.persisted?
      assert admin.errors[:password].present?
    end
  end
end
