# F-EMAIL — 자체 Outbound Mail API를 ActionMailer 배달 방식으로 등록(2026-11-20 구현 확정).
# 활성은 config/environments/production.rb의 config.action_mailer.delivery_method =
# :outbound_mail_api이며, 개발·테스트 환경은 기존 배달 방식(:test 등)을 유지한다 — 배달
# 방식 자체는 단위 검증으로 직접 호출한다. credentials outbound_mail.token 미등록 시에는
# OutboundMail::DeliveryMethod가 로그 폴백으로 흡수해 기존 동작을 유지한다(무중단 전환).
#
# add_delivery_method는 클래스 객체 자체를 저장하므로(Rails 8.1 delivery_methods.rb —
# symbol → klass 매핑) 등록 시점에 상수가 실재해야 한다. app 코드는 초기자 직후에 아직
# 자동 로딩 세팅 전이라 이 참조는 after_initialize(zeitwerk 세팅·eager_load 이후)로
# 미룬다 — 배달 시점에는 언제나 등록 완료 상태다.
Rails.application.config.after_initialize do
  ActionMailer::Base.add_delivery_method :outbound_mail_api, OutboundMail::DeliveryMethod
end
