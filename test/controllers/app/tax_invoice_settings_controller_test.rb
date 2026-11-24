require "test_helper"
require_relative "../../test_helpers/baro_bill_stubbing"
require_relative "../../test_helpers/fake_baro_bill_client"

# 전자세금계산서 발행 설정(/app/tax_invoice_setting — TAX-1 2단계 온보딩·W-3) HTTP 통합 테스트.
# 사업자 정보 저장(RegistCorp)·-32000 흡수·조작된 tax_type·9자리 corp_num의 422 수렴·
# 인증서 등록 URL(CERT)·CheckCERTIsValid 기반 마킹을 검증한다. SOAP는 스텁(실호출 금지).
# TAX-4 — 이 파일은 스위치 켜짐을 전제로 한다(test_helper 기본 켬 — 꺼짐 케이스는
# tax_invoice_gate_test.rb가 with_tax_invoice_feature(false)로 격리해 검증한다).
class App::TaxInvoiceSettingsControllerTest < ActionDispatch::IntegrationTest
  include BaroBillStubbing

  setup do
    @user = users(:gamma)   # 청구서 fixture 없는 사용자 — 설정 플로우 오염 없이 검증
    @valid_params = { corp_num: "123-45-67890", corp_name: "감마스튜디오", ceo_name: "김감마",
                      corp_addr: "서울시 성동구", contact_name: "김감마",
                      phone: "010-9876-5432", tax_type: "general" }
  end

  test "비인증 접근은 로그인 화면으로 리다이렉트된다 (AUTH-1)" do
    get app_tax_invoice_setting_path

    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "사업자 정보 저장 — RegistCorp 스텁 성공 시 barobill_id 채번·저장·2단계 안내" do
    sign_in_as @user

    with_baro_bill_client(FakeBaroBillClient.new) do
      patch app_tax_invoice_setting_path, params: { tax_invoice_setting: @valid_params }
    end

    assert_redirected_to app_tax_invoice_setting_path
    assert_match(/공동인증서를 등록/, flash[:notice])
    assert_equal "1234567890", @user.reload.corp_num
    assert_equal format("bd%018d", @user.id), @user.barobill_id
  end

  test "-32000(기가입 회원사)은 흡수해 저장을 계속한다" do
    sign_in_as @user

    with_baro_bill_client(FakeBaroBillClient.new(raise_on: { register_corp:
      BaroBill::ClientService::ApiError.new(code: "-32000", message: "이미 가입") })) do
      patch app_tax_invoice_setting_path, params: { tax_invoice_setting: @valid_params }
    end

    assert_redirected_to app_tax_invoice_setting_path
    assert_predicate @user.reload.barobill_id, :present?
  end

  test "W-3: 조작된 tax_type POST는 500이 아니라 422 재렌더다" do    sign_in_as @user
    assert_nothing_raised do
      with_baro_bill_client(FakeBaroBillClient.new) do
        patch app_tax_invoice_setting_path,
              params: { tax_invoice_setting: @valid_params.merge(tax_type: "무관") }
      end
    end

    assert_response :unprocessable_entity
    assert_nil @user.reload.barobill_id                         # 저장 미수행
  end

  test "W-3: 9자리 corp_num은 RegistCorp 외부 호출 없이 422로 수렴한다" do
    sign_in_as @user
    client = FakeBaroBillClient.new

    with_baro_bill_client(client) do
      patch app_tax_invoice_setting_path,
            params: { tax_invoice_setting: @valid_params.merge(corp_num: "123-45-6789") }
    end

    assert_response :unprocessable_entity
    assert_match(/10자리/, response.body)
    assert_empty client.calls.values.flatten                    # 외부 호출 차단
  end

  test "인증서 등록: 사업자 정보 미저장(barobill_id 없음)은 1단계로 되돌린다" do
    sign_in_as @user

    with_baro_bill_client(FakeBaroBillClient.new) do
      post register_certificate_app_tax_invoice_setting_path
    end

    assert_redirected_to app_tax_invoice_setting_path
    assert_match(/먼저 사업자 정보를 저장/, flash[:alert])
  end

  test "인증서 등록: GetBaroBillURL(CERT) URL을 안내 화면에 출력한다" do
    sign_in_as @user
    @user.update!(corp_num: "1234567890", barobill_id: "bd#{format('%018d', @user.id)}")

    with_baro_bill_client(FakeBaroBillClient.new(
                            returns: { certificate_register_url: "https://cert.example/POPUP" })) do
      post register_certificate_app_tax_invoice_setting_path
    end

    assert_response :ok
    assert_match(%r{https://cert\.example/POPUP}, response.body)
  end

  test "인증서 확인: CheckCERTIsValid 성공 시에만 barobill_cert_registered 마킹한다" do
    sign_in_as @user
    @user.update!(corp_num: "1234567890", barobill_id: "bd001")

    with_baro_bill_client(FakeBaroBillClient.new(
                            returns: { check_cert_is_valid: true })) do
      post confirm_certificate_app_tax_invoice_setting_path
    end

    assert_redirected_to app_tax_invoice_setting_path
    assert_match(/등록이 확인되었습니다/, flash[:notice])
    assert_predicate @user.reload, :barobill_cert_registered?
  end

  test "인증서 확인: 미등록(0)이면 마킹하지 않고 재시도를 안내한다 (오표시 방지)" do
    sign_in_as @user
    @user.update!(corp_num: "1234567890", barobill_id: "bd001")

    with_baro_bill_client(FakeBaroBillClient.new(returns: { check_cert_is_valid: false })) do
      post confirm_certificate_app_tax_invoice_setting_path
    end

    assert_redirected_to register_certificate_app_tax_invoice_setting_path
    assert_match(/아직 인증서가 확인되지 않았습니다/, flash[:alert])
    assert_not @user.reload.barobill_cert_registered?
  end
end
