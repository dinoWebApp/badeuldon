require "test_helper"

# 바로빌 SOAP 래퍼(BaroBill::ClientService) 단위 테스트 — savon_factory 주입으로 네트워크 계층을
# 대역화한다(실호출 금지 — 구조로 보장). 오류코드 정규화(ApiError)·-32000 코드 보존·SOAP 전송
# 실패 코드("SOAP")·TESTBED/RELEASE 환경 전환·구조체 파싱을 검증한다.
class BaroBill::ClientServiceTest < ActiveSupport::TestCase
  # savon client 대역 — call(method, message:) → 응답 객체(body: {:"{method}_result" => value})
  FakeSavonResponse = Struct.new(:body) do
    def dig(*keys) = body.dig(*keys)  # Savon::Response#dig 규약 대응
  end

  class FakeSavonClient
    attr_reader :calls

    def initialize(result_for: {}, raise_on: {})
      @result_for = result_for
      @raise_on = raise_on
      @calls = Hash.new { |hash, key| hash[key] = [] }
    end

    def call(method, message: {})
      @calls[method] << { message: message }
      raise @raise_on[method] if @raise_on[method]

      value = @result_for.fetch(method, 1)
      FakeSavonResponse.new({ "#{method}_response": { "#{method}_result": value } })
    end
  end

  def service(savon_client, release: false)
    captured_wsdl = nil
    factory = ->(wsdl) { captured_wsdl = wsdl; savon_client }
    client = BaroBill::ClientService.new(auth_key: "test-key", release: release,
                                         savon_factory: factory)
    [ client, -> { captured_wsdl } ]
  end

  test "register_corp 정상(1) — CERTKEY·CorpNum·ID가 메시지로 전송된다" do
    savon = FakeSavonClient.new(result_for: { regist_corp: 1 })
    client, wsdl = service(savon)

    result = client.register_corp(corp_num: "1234567890", corp_name: "감마", ceo_name: "김감마",
                                  biz_type: "서비스", biz_class: "프리랜서 서비스",
                                  addr1: "서울시", member_name: "김감마",
                                  barobill_id: "bd000000000000000001", barobill_pwd: "pw",
                                  tel: "010-0000-0000", email: "g@example.com")

    assert_equal 1, result
    assert_match(/BAROBILL\.asmx/, wsdl.call)
    assert_equal "test-key", savon.calls[:regist_corp].sole[:message][:CERTKEY]
    assert_equal "1234567890", savon.calls[:regist_corp].sole[:message][:CorpNum]
  end

  test "음수 반환은 ApiError로 정규화되고 코드가 보존된다 (-32000 흡수 판정용)" do
    savon = FakeSavonClient.new(result_for: { regist_corp: -32_000 })
    client, = service(savon)

    error = assert_raises(BaroBill::ClientService::ApiError) do
      client.register_corp(corp_num: "1234567890", corp_name: "g", ceo_name: "k",
                           biz_type: "s", biz_class: "f", addr1: "a", member_name: "m",
                           barobill_id: "bd1", barobill_pwd: "pw", tel: "010", email: "e@e")
    end

    assert_equal "-32000", error.code                           # RegisterCorpService 흡수 판정 키
    assert_match(/-32000/, error.message)
  end

  test "SOAP 전송 실패(Savon::Error)는 코드 'SOAP'의 ApiError로 정규화된다 (W-5 분기 키)" do
    savon = FakeSavonClient.new(raise_on: { regist_corp: Savon::Error.new("timeout") })
    client, = service(savon)

    error = assert_raises(BaroBill::ClientService::ApiError) do
      client.register_corp(corp_num: "1234567890", corp_name: "g", ceo_name: "k",
                           biz_type: "s", biz_class: "f", addr1: "a", member_name: "m",
                           barobill_id: "bd1", barobill_pwd: "pw", tel: "010", email: "e@e")
    end

    assert_equal "SOAP", error.code
  end

  test "check_cert_is_valid — 1이면 true, 0이면 false다" do
    client_valid, wsdl = service(FakeSavonClient.new(result_for: { check_cert_is_valid: 1 }))
    client_invalid, = service(FakeSavonClient.new(result_for: { check_cert_is_valid: 0 }))

    assert client_valid.check_cert_is_valid(corp_num: "1234567890")
    assert_not client_invalid.check_cert_is_valid(corp_num: "1234567890")
    assert_match(/BAROBILL\.asmx/, wsdl.call)
  end

  test "certificate_register_url — TOGO 'CERT'·URL 반환·음수 문자열은 ApiError다" do
    client_ok, = service(FakeSavonClient.new(
                           result_for: { get_baro_bill_url: "https://testws.baroservice.com/CERT?x" }))
    url = client_ok.certificate_register_url(corp_num: "1234567890", barobill_id: "bd1")
    assert_equal "https://testws.baroservice.com/CERT?x", url

    client_err, = service(FakeSavonClient.new(result_for: { get_baro_bill_url: "-32001" }))
    assert_raises(BaroBill::ClientService::ApiError) do
      client_err.certificate_register_url(corp_num: "1234567890", barobill_id: "bd1")
    end
  end

  test "get_corp_state — 구조체 파싱(state 정수)·음수 상태는 ApiError다" do
    client, wsdl = service(FakeSavonClient.new(
                             result_for: { get_corp_state_ex: { state: "3", corp_name: "폐업처" } }))

    state = client.get_corp_state(corp_num: "1234567890", check_corp_num: "8888888888")

    assert_equal 3, state[:state]
    assert_equal "폐업처", state[:corp_name]
    assert_match(/CORPSTATE\.asmx/, wsdl.call)

    client_err, = service(FakeSavonClient.new(
                            result_for: { get_corp_state_ex: { state: "-400" } }))
    error = assert_raises(BaroBill::ClientService::ApiError) do
      client_err.get_corp_state(corp_num: "1234567890", check_corp_num: "8888888888")
    end
    assert_equal "-400", error.code
  end

  test "get_tax_invoice_state — TaxInvoiceStateEX 구조체를 그대로 돌려준다" do
    struct = { barobill_state: 3014, nts_send_state: 4, nts_send_key: "KEY-1" }
    savon = FakeSavonClient.new(result_for: { get_tax_invoice_state_ex: struct })
    client, wsdl = service(savon)

    result = client.get_tax_invoice_state(corp_num: "1234567890", mgt_num: "TI-POLL-1")

    assert_equal struct, result
    assert_match(/TI\.asmx/, wsdl.call)
    assert_equal "TI-POLL-1", savon.calls[:get_tax_invoice_state_ex].sole[:message][:MgtKey]
  end

  test "release: true면 RELEASE 엔드포인트 wsdl을 사용한다 (환경 전환)" do
    savon = FakeSavonClient.new(result_for: { regist_corp: 1 })
    client, wsdl = service(savon, release: true)

    client.register_corp(corp_num: "1234567890", corp_name: "g", ceo_name: "k",
                         biz_type: "s", biz_class: "f", addr1: "a", member_name: "m",
                         barobill_id: "bd1", barobill_pwd: "pw", tel: "010", email: "e@e")

    assert_match(%r{\Ahttps://ws\.baroservice\.com/BAROBILL\.asmx}, wsdl.call)
  end
end
