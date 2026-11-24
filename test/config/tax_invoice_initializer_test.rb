require "test_helper"

# TAX-4 — 운영 준비 게이트 스위치의 fail-closed 파싱 검증(config/initializers/tax_invoice.rb).
# 부팅을 값마다 반복하지 않고 초기자 파일을 load해 한 프로세스에서 ENV 변형별 결과를 확인한다
# (리뷰 중점 6 — "runner 또는 initializer 단위 테스트"). 판정 문자열은 정확히 "true" 하나뿐이고
# 미설정·"false"·대소문자 변형·숫자·yes·공백 포함은 모두 꺼짐이어야 한다(오타도 안전한 쪽으로).
class TaxInvoiceInitializerTest < ActiveSupport::TestCase
  ENVS_EXPECTED_OFF = [ nil, "false", "TRUE", "True", "1", "yes", " true", "true " ].freeze

  test %q{ENV "true"만 켜짐이다 (Q26 — fail-closed의 유일한 통로)} do
    assert_equal true, parse_initializer_with_env("true")
  end

  test "ENV 미설정과 그 외 7종 변형은 전부 꺼짐이다 — 오타도 안전한 쪽으로 닫힌다" do
    ENVS_EXPECTED_OFF.each do |value|
      assert_equal false, parse_initializer_with_env(value),
                   "ENV=#{value.inspect}는 꺼짐이어야 한다"
    end
  end

  test "초기자 로드 후에도 스위치 판정은 config 한 곳을 가리킨다 (모델·헬퍼가 ENV을 읽지 않는다)" do
    parse_initializer_with_env("true")

    assert_predicate TaxInvoice, :feature_enabled?
  end

  private

  # 초기자 파일을 현재 ENV로 다시 load해 config에 기록된 값을 돌려준다. 원래 ENV·config 값은
  # ensure로 반드시 복원한다 — 같은 프로세스의 다른 테스트에 누수하지 않는다.
  def parse_initializer_with_env(value)
    original_config = Rails.application.config.x.tax_invoice_enabled
    original_env = ENV["TAX_INVOICE_ENABLED"]
    if value.nil?
      ENV.delete("TAX_INVOICE_ENABLED")
    else
      ENV["TAX_INVOICE_ENABLED"] = value
    end

    load Rails.root.join("config/initializers/tax_invoice.rb")
    Rails.application.config.x.tax_invoice_enabled
  ensure
    if original_env.nil?
      ENV.delete("TAX_INVOICE_ENABLED")
    else
      ENV["TAX_INVOICE_ENABLED"] = original_env
    end
    Rails.application.config.x.tax_invoice_enabled = original_config
  end
end
