class ApplicationMailer < ActionMailer::Base
  layout "mailer"

  # F-EMAIL — 봉투 파탄 방지 전용 폴백 발신 주소(운영과 동일 주소의 상수 — config 아님).
  # credentials outbound_mail.from_email 미등록 환경(로컬·테스트)에서 from이 nil이면
  # Mail 2.9.1 배달 방식(TestMailer 포함 — SmtpEnvelope 봉투 검증)이 ArgumentError로
  # 파탄한다. 이 상수로 메일러 봉투(from 헤더)가 항상 유효하게 유지된다. 실제 발신 주소는
  # 이 값과 무관하게 OutboundMail::DeliveryMethod가 페이로드에서 credentials로 재강제한다
  # (API 허용 발신 주소 정책 — 메일러의 from은 표시 참고일 뿐이며, credentials 부재 시
  # DeliveryMethod의 MISSING_CREDENTIALS fail-fast는 유지된다).
  DEFAULT_FROM_EMAIL = "badeuldon@veloloop.kr"

  def self.mailer_from_header
    email = Rails.application.credentials.dig(:outbound_mail, :from_email).presence || DEFAULT_FROM_EMAIL

    name = Rails.application.credentials.dig(:outbound_mail, :from_name).presence
    name ? "#{name} <#{email}>" : email
  end

  default from: mailer_from_header
end
