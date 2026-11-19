# 관리자 보안 통보 메일(AUTH-7.3·7.4·7.6) — F-EMAIL(2026-11-20)로 자체 Outbound Mail API
# 실발송에 전환됐다(production: OutboundMail::DeliveryJob — 잡 식별자 멱등 키·retryable
# 5회 재시도. 개발·테스트 환경은 기존 배달 방식 유지).
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
