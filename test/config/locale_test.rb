require "test_helper"

class LocaleTest < ActiveSupport::TestCase
  # T2 ko locale — 기본 로케일·rails-i18n 사전 위임 검증
  test "default locale is ko" do
    assert_equal :ko, I18n.default_locale
    assert I18n.available_locales.include?(:ko)
  end

  test "rails-i18n supplies Korean datetime and error translations" do
    assert_equal "내용을 입력해 주세요", I18n.t("errors.messages.blank")
    assert_match(/년/, I18n.l(Date.current, format: :long))
    assert_match(/오류로 인해 저장되지 않았습니다/, I18n.t("errors.messages.not_saved.other", count: 2))
  end
end
