# 바로빌 SOAP 래퍼(BaroBill::ClientService) 테스트 대역 — 실호출 금지(TAX-1) 규약의 방어선.
# 서비스·컨트롤러가 기본 인자로 만드는 클라이언트에 주입하거나(생성자 client:),
# BaroBillStubbing으로 클래스 생성 경로를 가로챈다(컨트롤러·Job 내부 기본 생성 대응).
class FakeBaroBillClient
  DEFAULT_RETURNS = {
    register_corp: 1,
    check_cert_is_valid: true,
    certificate_register_url: "https://testws.baroservice.com/CERT?token=60s",
    get_corp_state: { state: 1, corp_name: "델타파트너스", type_of_business: "서비스" },
    regist_and_issue_tax_invoice: 1,
    get_tax_invoice_state: { barobill_state: 3014, nts_send_state: 4,
                             nts_send_key: "20261116123456789012345678" },
    cancel_tax_invoice: 1
  }.freeze

  attr_reader :calls

  def initialize(returns: {}, raise_on: {})
    @returns = DEFAULT_RETURNS.merge(returns)
    @raise_on = raise_on
    @calls = Hash.new { |hash, key| hash[key] = [] }
  end

  %i[
    register_corp
    check_cert_is_valid
    certificate_register_url
    get_corp_state
    regist_and_issue_tax_invoice
    get_tax_invoice_state
    cancel_tax_invoice
  ].each do |method_name|
    define_method(method_name) do |**kwargs|
      @calls[method_name] << kwargs
      raise @raise_on[method_name] if @raise_on[method_name]

      @returns.fetch(method_name)
    end
  end
end
