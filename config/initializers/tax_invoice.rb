# TAX-4 — 전자세금계산서 발행 기능 전역 스위치(Q26 — 운영 준비 게이트, 2026-11-24).
# 부팅 시 ENV를 한 번만 읽어 config.x에 고정한다 — 모델·컨트롤러·뷰가 ENV를 직접 읽지 않게
# 하고, 판정은 TaxInvoice.feature_enabled? 한 곳에서만 수행한다(테스트는 config 값을 바꿔 토글).
# 문자열 "true"만 켜짐 — 그 외 값·미설정은 모두 꺼짐(fail-closed). 켜는 조건은 바로빌 운영
# 준비 완료(계약·포인트 충전·법인 등록 스모크)이며 운영에서는 config/deploy.yml의 env로 켠다.
Rails.application.config.x.tax_invoice_enabled = ENV["TAX_INVOICE_ENABLED"] == "true"
