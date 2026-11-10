# 관리자 보안 통보 메일(AUTH-7.3·7.4·7.6) — 이메일 서비스 미지정으로
# Action Mailer 기본 발송(개발/운영 로그). 실발송 연결은 U1과 동일 기술 부채 항목.
class AdminMailer < ApplicationMailer
  def locked_out(admin)
    @admin = admin
    mail subject: "[받을돈 관리자] 계정 잠금 통보", to: admin.email
  end

  def new_login(admin, ip)
    @admin = admin
    @ip = ip
    mail subject: "[받을돈 관리자] 신규 IP 로그인 통보", to: admin.email
  end

  def password_reset(admin, token_url)
    @admin = admin
    @token_url = token_url
    mail subject: "[받을돈 관리자] 비밀번호 재설정 안내", to: admin.email
  end
end
