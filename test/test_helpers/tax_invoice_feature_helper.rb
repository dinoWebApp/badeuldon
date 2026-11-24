# TAX-4 — 운영 준비 게이트(Rails.application.config.x.tax_invoice_enabled) 테스트 토글 헬퍼.
# 초기자(config/initializers/tax_invoice.rb)는 부팅 시 ENV["TAX_INVOICE_ENABLED"] == "true"만
# 켜짐으로 고정하기 때문에(fail-closed) 테스트 환경의 부팅 기본값은 꺼짐이다. 그런데 기존
# 세금계산서 테스트 대부분은 켜짐을 전제로 하므로 test_helper.rb의 ActiveSupport::TestCase
# setup에서 기본 켬으로 올리고, 꺼짐이 필요한 케이스는 with_tax_invoice_feature(false) 블록으로
# 격리한다. 값은 ensure로 복원한다 — 블록 종료·예외 어느 경로든 원래 값으로 되돌아간다.
module TaxInvoiceFeatureHelper
  # 블록 동안만 스위치를 바꾼다 — 블록 종료(예외 포함) 시 원래 값으로 복원한다.
  def with_tax_invoice_feature(enabled)
    original = Rails.application.config.x.tax_invoice_enabled
    Rails.application.config.x.tax_invoice_enabled = enabled
    yield
  ensure
    Rails.application.config.x.tax_invoice_enabled = original
  end
end
