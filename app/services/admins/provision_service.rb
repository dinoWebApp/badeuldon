# 관리자 최초 계정 생성(AUTH-7.2 — 공개 가입 경로 없음, runner 절차 전용).
#
#   bin/rails runner 'Admins::ProvisionService.new(email: "ops@badeuldon.kr",
#     password: "...", role: :owner).call'
#
# 검증 실패 시 저장되지 않은 Admin을 반환 — runner에서 admin.errors.full_messages로 확인.
# otp_secret은 생성하지 않는다 — 최초 로그인 시 2FA 등록 화면에서 발급(AUTH-7.1).
module Admins
  class ProvisionService
    def initialize(email:, password:, role: :owner)
      @email = email
      @password = password
      @role = role
    end

    def call
      Admin.new(email: @email, password: @password, role: @role).tap(&:save)
    end
  end
end
