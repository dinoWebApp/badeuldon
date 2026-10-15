# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, "\\1en"
#   inflect.singular /^(ox)en/i, "\\1"
#   inflect.irregular "person", "people"
#   inflect.uncountable %w( fish sheep )
# end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end

ActiveSupport::Inflector.inflections(:en) do |inflect|
  # 포트원 V2 결제 연동(PLAN-5) — 서비스 모듈(PortOne::ClientService)·웹훅
  # 컨트롤러(Webhooks::PortOneController)의 공식 표기. portone_controller.rb 같은
  # 파일명도 PortOne 상수로 정규화한다.
  inflect.acronym "PortOne"
end
