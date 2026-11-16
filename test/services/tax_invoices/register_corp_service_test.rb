require "test_helper"
require_relative "../../test_helpers/fake_baro_bill_client"

# 발행 설정 1단계(TaxInvoices::RegisterCorpService — W-3 입력 하드닝·-32000 흡수) 서비스 테스트.
# 바로빌 아이디 채번(20자·결정적)·corp_num 포맷 선검증(외부 호출 전 422 수렴)·tax_type
# 화이트리스트(조작 POST 500 방지)를 검증한다. SOAP는 FakeBaroBillClient 주입(실호출 금지).
class TaxInvoices::RegisterCorpServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:gamma)   # 청구서·설정 fixture 없는 사용자 — 오염 없이 검증
    @client = FakeBaroBillClient.new
    @attributes = { corp_num: "123-45-67890", corp_name: "감마스튜디오", ceo_name: "김감마",
                    corp_addr: "서울시 성동구", contact_name: "김감마",
                    phone: "010-9876-5432", tax_type: "general" }
  end

  test "정상 저장 — corp_num 정규화(하이픈 제외)·barobill_id 채번(20자·결정적)" do
    result = TaxInvoices::RegisterCorpService.new(user: @user, attributes: @attributes,
                                                  client: @client).call

    assert result
    assert_equal "1234567890", @user.corp_num
    expected_id = format("bd%018d", @user.id)
    assert_equal expected_id, @user.barobill_id
    assert_equal 20, @user.barobill_id.length
    assert_equal expected_id, @client.calls[:register_corp].sole[:barobill_id]
  end

  test "재호출에도 barobill_id는 동일하다 (결정적 채번)" do
    TaxInvoices::RegisterCorpService.new(user: @user, attributes: @attributes, client: @client).call
    second_id = @user.barobill_id
    @user.update_columns(barobill_id: nil) # 재가입 시나리오 — 채번만 재수행
    TaxInvoices::RegisterCorpService.new(user: @user, attributes: @attributes, client: @client).call

    assert_equal second_id, @user.barobill_id
  end

  test "-32000(기가입 회원사)은 흡수해 설정 저장을 계속한다" do
    client = FakeBaroBillClient.new(raise_on: { register_corp:
      BaroBill::ClientService::ApiError.new(code: "-32000", message: "이미 가입된 사업자번호") })

    assert TaxInvoices::RegisterCorpService.new(user: @user, attributes: @attributes,
                                                client: client).call
    assert_predicate @user.reload, :barobill_id?
  end

  test "그 외 바로빌 오류는 false + base 에러로 422 수렴한다" do
    client = FakeBaroBillClient.new(raise_on: { register_corp:
      BaroBill::ClientService::ApiError.new(code: "-100", message: "인증키 오류") })

    result = TaxInvoices::RegisterCorpService.new(user: @user, attributes: @attributes,
                                                  client: client).call

    assert_not result
    assert_predicate @user.errors[:base].join, :present?
  end

  # W-3 — RegistCorp 외부 호출 전에 corp_num 포맷(10자리 숫자)을 검증한다(변조 POST 422).
  test "W-3: 9자리 corp_num은 외부 호출 없이 검증 실패(false)다" do
    @attributes[:corp_num] = "123-45-6789"

    result = TaxInvoices::RegisterCorpService.new(user: @user, attributes: @attributes,
                                                  client: @client).call

    assert_not result
    assert_match(/10자리 숫자/, @user.errors[:corp_num].join)
    assert_empty @client.calls.values.flatten                 # RegistCorp 미호출 — 외부 전파 차단
  end

  # W-3 — 조작된 tax_type 임의값은 enum 할당 ArgumentError(500) 대신 화이트리스트 검증으로 422.
  test "W-3: 조작된 tax_type POST는 500이 아니라 검증 실패(false)다" do
    @attributes[:tax_type] = "무관"

    result = TaxInvoices::RegisterCorpService.new(user: @user, attributes: @attributes,
                                                  client: @client).call

    assert_not result
    assert_predicate @user.errors[:tax_type].join, :present?
    assert_empty @client.calls.values.flatten
  end

  test "phone 미설정은 RegistCorp 필수 세트 검증으로 실패한다 (W-4 — 가짜 연락처 전송 없음)" do
    @attributes[:phone] = ""

    result = TaxInvoices::RegisterCorpService.new(user: @user, attributes: @attributes,
                                                  client: @client).call

    assert_not result
    assert_predicate @user.errors[:phone].join, :present?
    assert_empty @client.calls.values.flatten
  end
end
