require "test_helper"
require_relative "../../test_helpers/baro_bill_stubbing"
require_relative "../../test_helpers/fake_baro_bill_client"

# TAX-3 — 발급 자격(간이과세·면세사업자 미발급 — Q25) 켜짐 상태 HTTP 통합 테스트.
# 차단 4지점을 검증한다: ① 청구 상세 패널(발급 불가 안내·발행 링크 없음) ② 발행 화면 진입
# new·create(청구서 상세 리다이렉트 — 리뷰 C-1) ③ 주문 생성(IneligibleUser — 결제 전 차단)
# ④ 발행 서비스 가드는 issue_service_test.rb가 담당한다. 발행만 차단한다(과세 유형 선택·
# 사업자 정보 저장·기존 내역 조회·취소는 허용 — Q25). 스위치는 켜짐(test_helper 기본 켬).
# 바로빌 SOAP는 스텁(실호출 금지).
class App::TaxInvoiceEligibilityTest < ActionDispatch::IntegrationTest
  include BaroBillStubbing

  setup do
    @user = users(:delta)
    @invoice = invoices(:delta_paid)
    travel_to(Time.zone.parse("2026-10-12 09:00"))
  end

  teardown do
    travel_back
  end

  # ── TAX-3 정상(일반과세) — 기존 경로가 그대로 열려 있다 ──
  test "정상(일반과세): new는 200으로 발행 버튼을 보여준다" do
    sign_in_as @user
    make_ready!

    get new_app_tax_invoice_path(invoice_id: @invoice.id)

    assert_response :ok
    assert_match(/수수료 결제하고 발행 요청/, response.body)
    assert_no_match(/지원하지 않습니다/, response.body)
  end

  test "정상(일반과세): 설정 화면에 발급 불가 안내가 없고 인증서 완료 안내는 발행 가능 문언이다" do
    sign_in_as @user
    make_ready!

    get app_tax_invoice_setting_path

    assert_response :ok
    assert_no_match(/지원하지 않습니다/, response.body)
    assert_match(/인증서 등록 팝업 열기/, response.body)       # 2단계 안내 유지

    with_baro_bill_client(FakeBaroBillClient.new(returns: { check_cert_is_valid: true })) do
      post confirm_certificate_app_tax_invoice_setting_path
    end

    assert_match(/이제 전자세금계산서를 발행할 수 있습니다/, flash[:notice])
  end

  # ── TAX-3 경계 — 발행만 차단하고 나머지는 허용한다(Q25) ──
  test "경계(간이과세): 과세 유형 선택지는 3종이 유지되고 저장도 성공한다 (바로빌 스텁)" do
    sign_in_as @user
    @user.update!(tax_type: :simplified)

    get app_tax_invoice_setting_path

    assert_response :ok
    assert_select "select[name='tax_invoice_setting[tax_type]'] option", count: 3

    with_baro_bill_client(FakeBaroBillClient.new) do
      patch app_tax_invoice_setting_path,
            params: { tax_invoice_setting: { corp_num: "123-45-67890", corp_name: "델타디자인",
                                             ceo_name: "김델타", corp_addr: "서울시 강남구",
                                             contact_name: "김델타", phone: "010-5555-1111",
                                             tax_type: "simplified" } }
    end

    assert_redirected_to app_tax_invoice_setting_path
    assert_predicate @user.reload.barobill_id, :present?       # 사업자 정보 저장은 허용
    assert_equal "simplified", @user.tax_type
  end

  test "경계(간이과세): 기존 발행 내역 조회·취소는 허용된다 (Q25 — 발행만 차단)" do
    sign_in_as @user
    make_ready!
    @user.update!(tax_type: :simplified)
    order = create_tax_order(status: :paid)
    tax_invoice = create_tax_invoice_record(order_id: order.id)

    get app_invoice_path(@invoice)

    assert_match(/발행 완료/, response.body)                    # 내역 조회 허용 — 기록 분기
    assert_no_match(/발급 불가/, response.body)

    with_baro_bill_client(FakeBaroBillClient.new) do
      patch cancel_app_tax_invoice_path(order)
    end

    assert_redirected_to app_invoice_path(@invoice)
    assert_match(/발급이 취소되었습니다/, flash[:notice])
    assert_predicate tax_invoice.reload, :canceled?
  end

  # ── TAX-3 예외(간이과세) — 차단 4지점 ──
  test "예외(간이과세): 패널은 발급 불가 안내를 보이고 발행 링크가 없다 (①)" do
    sign_in_as @user
    make_ready!
    @user.update!(tax_type: :simplified)

    get app_invoice_path(@invoice)

    assert_match(/전자세금계산서 발급 불가/, response.body)
    assert_match(@user.tax_invoice_ineligibility_notice, response.body)
    assert_no_match(new_app_tax_invoice_path(invoice_id: @invoice.id), response.body)
  end

  test "예외(간이과세): new는 청구서 상세로 되돌려지고 안내 문구가 뜬다 (② — 리뷰 C-1)" do
    sign_in_as @user
    make_ready!
    @user.update!(tax_type: :simplified)

    get new_app_tax_invoice_path(invoice_id: @invoice.id)

    assert_redirected_to app_invoice_path(@invoice)
    assert_equal @user.tax_invoice_ineligibility_notice, flash[:alert]
  end

  test "예외(간이과세): create는 주문을 만들지 않고 청구서 상세로 되돌린다 (②·③)" do
    sign_in_as @user
    make_ready!
    @user.update!(tax_type: :simplified)

    assert_no_difference -> { @user.orders.count } do
      post app_tax_invoices_path, params: { invoice_id: @invoice.id }
    end

    assert_redirected_to app_invoice_path(@invoice)
    assert_equal @user.tax_invoice_ineligibility_notice, flash[:alert]
    assert_empty @user.orders.tax_invoices
  end

  test "예외(간이과세): pending 주문 show는 결제 위젯 대신 안내를 그린다 (리뷰 C-2)" do
    sign_in_as @user
    make_ready!
    @user.update!(tax_type: :simplified)
    order = create_tax_order(status: :pending)                 # 자격 상실 전 만들어진 주문 가정

    get app_tax_invoice_path(order)

    assert_response :ok
    assert_match(@user.tax_invoice_ineligibility_notice, response.body)
    assert_no_match(/결제하기/, response.body)
    assert_no_match(/portone-payment/, response.body)
  end

  test "예외(간이과세): 설정 화면은 2단계(인증서 등록) 대신 발급 불가 안내를 보인다 (리뷰 W-3)" do
    sign_in_as @user
    make_ready!
    @user.update!(tax_type: :simplified)

    get app_tax_invoice_setting_path

    assert_response :ok
    assert_match(@user.tax_invoice_ineligibility_notice, response.body)
    assert_no_match(/인증서 등록 팝업 열기/, response.body)     # 2단계 안내·버튼 숨김
    assert_no_match(/등록 완료 확인/, response.body)
  end

  test "예외(간이과세): 저장 성공 플래시에 인증서 등록 다음 단계 문언이 없다 (리뷰 W-3)" do
    sign_in_as @user
    @user.update!(tax_type: :simplified)

    with_baro_bill_client(FakeBaroBillClient.new) do
      patch app_tax_invoice_setting_path,
            params: { tax_invoice_setting: { corp_num: "123-45-67890", corp_name: "델타디자인",
                                             ceo_name: "김델타", corp_addr: "서울시 강남구",
                                             contact_name: "김델타", phone: "010-5555-1111",
                                             tax_type: "simplified" } }
    end

    assert_redirected_to app_tax_invoice_setting_path
    notice = flash[:notice]
    assert_match(/사업자 정보가 저장되었습니다/, notice)
    assert_match(@user.tax_invoice_ineligibility_notice, notice)
    assert_no_match(/공동인증서를 등록/, notice)
  end

  test "예외(간이과세): 인증서 확인 성공 안내에 발행 가능 문언이 없다 (리뷰 W-3)" do
    sign_in_as @user
    @user.update!(tax_type: :simplified, corp_num: "1234567890",
                  barobill_id: "bd#{format('%018d', @user.id)}")

    with_baro_bill_client(FakeBaroBillClient.new(returns: { check_cert_is_valid: true })) do
      post confirm_certificate_app_tax_invoice_setting_path
    end

    notice = flash[:notice]
    assert_match(/공동인증서 등록이 확인되었습니다/, notice)
    assert_match(@user.tax_invoice_ineligibility_notice, notice)
    assert_no_match(/이제 전자세금계산서를 발행할 수 있습니다/, notice)
  end

  # ── TAX-3 예외(면세사업자) — 간이과세와 동일 차단 ──
  test "예외(면세사업자): 패널·new·create·pending show가 간이과세와 동일하게 차단된다" do
    sign_in_as @user
    make_ready!
    @user.update!(tax_type: :exempt)
    notice = @user.tax_invoice_ineligibility_notice

    get app_invoice_path(@invoice)
    assert_match(/전자세금계산서 발급 불가/, response.body)
    assert_match(notice, response.body)
    assert_no_match(new_app_tax_invoice_path(invoice_id: @invoice.id), response.body)

    get new_app_tax_invoice_path(invoice_id: @invoice.id)
    assert_redirected_to app_invoice_path(@invoice)
    assert_equal notice, flash[:alert]

    assert_no_difference -> { @user.orders.count } do
      post app_tax_invoices_path, params: { invoice_id: @invoice.id }
    end
    assert_redirected_to app_invoice_path(@invoice)
    assert_equal notice, flash[:alert]

    order = create_tax_order(status: :pending)
    get app_tax_invoice_path(order)
    assert_response :ok
    assert_match(notice, response.body)
    assert_no_match(/결제하기/, response.body)
  end

  private

  def make_ready!
    @user.update!(corp_num: "1234567890", corp_name: "델타디자인", ceo_name: "김델타",
                  corp_addr: "서울시 강남구", contact_name: "김델타",
                  barobill_id: "bd#{format('%018d', @user.id)}", barobill_cert_registered: true)
  end

  def create_tax_order(status: :pending)
    @user.orders.create!(product: :collection_pass, item_type: :tax_invoice,
                         amount: TaxInvoice::ISSUE_FEE, pg_order_id: SecureRandom.uuid,
                         status: status, metadata: { invoice_id: @invoice.id })
  end

  def create_tax_invoice_record(order_id:)
    TaxInvoice.create!(invoice: @invoice, user: @user, mgt_num: "TI-ELIG-#{order_id}",
                       order_id: order_id, status: :issued,
                       nts_send_key: "20261116-888888888-TESTKEY",
                       supply_total: 100_000, tax_total: 10_000, grand_total: 110_000)
  end
end
