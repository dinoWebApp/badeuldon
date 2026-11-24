require "test_helper"
require_relative "../../test_helpers/baro_bill_stubbing"
require_relative "../../test_helpers/fake_baro_bill_client"

# TAX-4 — 운영 준비 게이트(기본 꺼짐·fail-closed) 꺼짐 상태 HTTP 통합 테스트.
# test_helper가 테스트 전역에서 기본 켬이므로 이 파일의 모든 요청은
# with_tax_invoice_feature(false) 블록 안에서 이뤄진다. 켜짐 상태의 회귀는 기존 세금계산서
# 테스트(tax_invoices·settings 컨트롤러·서비스·웹훅)와 켜짐 메뉴 순서 테스트가 담당한다.
#
# 커버 범위(Q26): 사이드바 메뉴 비노출·패널 "준비 중"(상수 문구)·발행 new·create·설정 4액션
# /app 리다이렉트·paid 주문 show/cancel 허용·pending 주문 결제 진입 차단(리뷰 C-2)·
# paid_pending 우선순위(리뷰 W-1)·청구 상세 패널 우선순위 매트릭스·소유권 격리 유지.
class App::TaxInvoiceGateTest < ActionDispatch::IntegrationTest
  include BaroBillStubbing

  setup do
    @user = users(:delta)
    @invoice = invoices(:delta_paid)                       # paid 청구 — 패널·발행 대상
    travel_to(Time.zone.parse("2026-10-12 09:00"))
  end

  teardown do
    travel_back
  end

  # ── 사이드바 메뉴(TAX-4 ①) ──
  test "꺼짐이면 사이드바에 전자세금계산서 메뉴가 없다 (TAX-4 ①)" do
    sign_in_as users(:gamma)

    with_tax_invoice_feature(false) do
      get app_root_path
    end

    assert_response :ok
    assert_no_match(/전자세금계산서/, sidebar_nav)
  end

  test "켜짐이면 전자세금계산서 메뉴가 '추심 안내'와 '공지' 사이에 있다 (TAX-4 켜짐 회귀)" do
    sign_in_as users(:gamma)

    get app_root_path

    assert_response :ok
    nav = sidebar_nav
    assert_match(/전자세금계산서/, nav)
    assert_operator nav.index("추심 안내"), :<, nav.index("전자세금계산서")
    assert_operator nav.index("전자세금계산서"), :<, nav.index("공지")
  end

  # ── 발행 진입 차단(TAX-4 ③) ──
  test "꺼짐이면 new 직접 접속은 대시보드로 되돌아간다 (TAX-4 ③)" do
    sign_in_as @user
    make_ready!

    with_tax_invoice_feature(false) do
      get new_app_tax_invoice_path(invoice_id: @invoice.id)
    end

    assert_redirected_to app_root_path
    assert_equal TaxInvoice::FEATURE_DISABLED_NOTICE, flash[:alert]
  end

  test "꺼짐이면 create 직접 접속은 주문을 만들지 않고 대시보드로 되돌아간다 (TAX-4 ③)" do
    sign_in_as @user
    make_ready!

    with_tax_invoice_feature(false) do
      assert_no_difference -> { @user.orders.count } do
        post app_tax_invoices_path, params: { invoice_id: @invoice.id }
      end
    end

    assert_redirected_to app_root_path
    assert_equal TaxInvoice::FEATURE_DISABLED_NOTICE, flash[:alert]
    assert_empty @user.orders.tax_invoices
  end

  # ── 발행 설정 차단(TAX-4 ③ — 전 액션) ──
  test "꺼짐이면 설정 화면(show)도 대시보드로 되돌아간다 (TAX-4 ③)" do
    sign_in_as @user

    with_tax_invoice_feature(false) do
      get app_tax_invoice_setting_path
    end

    assert_redirected_to app_root_path
    assert_equal TaxInvoice::FEATURE_DISABLED_NOTICE, flash[:alert]
  end

  test "꺼짐이면 설정 저장(update)은 저장 없이 대시보드로 되돌아간다 (TAX-4 ③)" do
    sign_in_as @user

    with_tax_invoice_feature(false) do
      patch app_tax_invoice_setting_path,
            params: { tax_invoice_setting: { corp_num: "123-45-67890", corp_name: "델타디자인",
                                             ceo_name: "김델타", corp_addr: "서울시 강남구",
                                             contact_name: "김델타", phone: "010-5555-1111",
                                             tax_type: "general" } }
    end

    assert_redirected_to app_root_path
    assert_equal TaxInvoice::FEATURE_DISABLED_NOTICE, flash[:alert]
    assert_nil @user.reload.barobill_id                        # 사업자 정보 저장 미수행
  end

  test "꺼짐이면 인증서 등록·확인 액션도 대시보드로 되돌아간다 (TAX-4 ③)" do
    sign_in_as @user

    with_tax_invoice_feature(false) do
      post register_certificate_app_tax_invoice_setting_path
      assert_redirected_to app_root_path
      assert_equal TaxInvoice::FEATURE_DISABLED_NOTICE, flash[:alert]

      post confirm_certificate_app_tax_invoice_setting_path
      assert_redirected_to app_root_path
      assert_equal TaxInvoice::FEATURE_DISABLED_NOTICE, flash[:alert]
    end
  end

  # ── 기존 주문 경로 유지(TAX-4 ④) ──
  test "꺼짐이어도 paid 주문의 show는 200으로 열려 있다 (TAX-4 ④)" do
    sign_in_as @user
    order = create_tax_order(status: :paid)
    create_tax_invoice_record(order_id: order.id)

    with_tax_invoice_feature(false) do
      get app_tax_invoice_path(order)
    end

    assert_response :ok
    assert_match(/발행 완료/, response.body)
  end

  test "꺼짐이어도 paid 발행의 취소는 성공한다 (TAX-4 ④ — 경로를 끊지 않는다)" do
    sign_in_as @user
    make_ready!
    order = create_tax_order(status: :paid)
    tax_invoice = create_tax_invoice_record(order_id: order.id, status: :pending)

    with_tax_invoice_feature(false) do
      with_baro_bill_client(FakeBaroBillClient.new) do
        patch cancel_app_tax_invoice_path(order)
      end
    end

    assert_redirected_to app_invoice_path(@invoice)
    assert_match(/발급이 취소되었습니다/, flash[:notice])
    assert_predicate tax_invoice.reload, :canceled?
  end

  test "꺼짐이어도 타인의 주문 show·cancel은 404다 (소유권 격리 유지)" do
    sign_in_as users(:gamma)
    order = create_tax_order(status: :paid)

    with_tax_invoice_feature(false) do
      get app_tax_invoice_path(order)
      assert_response :not_found

      patch cancel_app_tax_invoice_path(order)
      assert_response :not_found
    end
  end

  # ── pending 주문 결제 진입 차단(TAX-4·리뷰 C-2) ──
  test "꺼짐이면 pending 주문 show에 결제 위젯 대신 준비 중 안내를 그린다 (리뷰 C-2)" do
    sign_in_as @user
    order = create_tax_order(status: :pending)

    with_tax_invoice_feature(false) do
      get app_tax_invoice_path(order)
    end

    assert_response :ok                                        # 조회 자체는 유지 — ④ 준수
    assert_match(TaxInvoice::FEATURE_DISABLED_NOTICE, response.body)
    assert_no_match(/결제하기/, response.body)
    assert_no_match(/portone-payment/, response.body)          # 체크아웃 위젯(Stimulus) 미렌더
  end

  # ── 청구 상세 패널(TAX-4 ② — "준비 중") ──
  test "꺼짐이면 패널은 준비 중 안내를 보이고 발행 링크가 없다 (TAX-4 ②)" do
    sign_in_as @user
    make_ready!

    with_tax_invoice_feature(false) do
      get app_invoice_path(@invoice)
    end

    assert_response :ok
    assert_match("전자세금계산서 발행 준비 중", response.body)
    assert_match(TaxInvoice::FEATURE_DISABLED_NOTICE, response.body)
    assert_match(/준비가 되면 이 화면에서 발행할 수 있습니다/, response.body)
    assert_no_match(new_app_tax_invoice_path(invoice_id: @invoice.id), response.body)
  end

  test "꺼짐이어도 기존 발행 기록이 있는 패널은 기록 표시를 유지한다 (TAX-4 ②)" do
    sign_in_as @user
    order = create_tax_order(status: :paid)
    create_tax_invoice_record(order_id: order.id)

    with_tax_invoice_feature(false) do
      get app_invoice_path(@invoice)
    end

    assert_match(/발행 완료/, response.body)
    assert_match(/20261116-888888888-TESTKEY/, response.body)
    assert_match(app_tax_invoice_path(order), response.body)   # 주문 확인 링크 유지
    assert_no_match(TaxInvoice::FEATURE_DISABLED_NOTICE, response.body)
  end

  # ── 청구 상세 패널 판정 우선순위 매트릭스(리뷰 W-1·중점 7) ──
  #   기존 발행 기록 > paid_pending > 꺼짐 > 자격 없음 > settings_missing >
  #   client_missing > ready — 복합 조건마다 최상위 분기 하나만 이긴다.
  test "매트릭스: 기존 발행 기록은 paid_pending·꺼짐·자격 없음 모두보다 우위다" do
    sign_in_as @user                                           # 설정 미완료 + 간이과세로 조성
    @user.update!(tax_type: :simplified)
    order = create_tax_order(status: :paid)
    create_tax_invoice_record(order_id: order.id)

    with_tax_invoice_feature(false) do
      get app_invoice_path(@invoice)
    end

    assert_match(/발행 완료/, response.body)
    assert_no_match(/발행 처리 확인/, response.body)
    assert_no_match(TaxInvoice::FEATURE_DISABLED_NOTICE, response.body)
    assert_no_match(/지원하지 않습니다/, response.body)
    assert_no_match(/발행 설정 필요/, response.body)
  end

  test "매트릭스: paid 주문(paid_pending)은 꺼짐보다 우위다 — 주문 확인 링크를 잃지 않는다 (W-1)" do
    sign_in_as @user
    make_ready!
    order = create_tax_order(status: :paid)                    # SOAP 실패 시나리오 — 기록 없음

    with_tax_invoice_feature(false) do
      get app_invoice_path(@invoice)
    end

    assert_match(/발행 처리 확인/, response.body)
    assert_match(/재결제는 필요 없습니다/, response.body)
    assert_match(app_tax_invoice_path(order), response.body)
    assert_no_match(TaxInvoice::FEATURE_DISABLED_NOTICE, response.body)
  end

  test "매트릭스: paid 주문(paid_pending)은 자격 없음보다 우위다 (W-1)" do
    sign_in_as @user
    make_ready!
    @user.update!(tax_type: :simplified)
    order = create_tax_order(status: :paid)

    get app_invoice_path(@invoice)                             # 켜짐 상태

    assert_match(/발행 처리 확인/, response.body)
    assert_match(app_tax_invoice_path(order), response.body)
    assert_no_match(/지원하지 않습니다/, response.body)
  end

  test "매트릭스: 꺼짐은 자격 없음보다 우위다 (TAX-4 > TAX-3)" do
    sign_in_as @user
    make_ready!
    @user.update!(tax_type: :simplified)

    with_tax_invoice_feature(false) do
      get app_invoice_path(@invoice)
    end

    assert_match(TaxInvoice::FEATURE_DISABLED_NOTICE, response.body)
    assert_no_match(/지원하지 않습니다/, response.body)
    assert_no_match(/발급 불가/, response.body)
  end

  test "매트릭스: 꺼짐은 설정 미완료보다 우위다 (TAX-4 > settings_missing)" do
    sign_in_as @user                                           # delta — 설정 미완료

    with_tax_invoice_feature(false) do
      get app_invoice_path(@invoice)
    end

    assert_match(TaxInvoice::FEATURE_DISABLED_NOTICE, response.body)
    assert_no_match(/발행 설정 필요/, response.body)
  end

  test "매트릭스: 자격 없음은 설정 미완료보다 우위다 (TAX-3 > settings_missing)" do
    sign_in_as @user                                           # delta — 설정 미완료
    @user.update!(tax_type: :simplified)

    get app_invoice_path(@invoice)                             # 켜짐 상태

    assert_match(/전자세금계산서 발급 불가/, response.body)
    assert_match(@user.tax_invoice_ineligibility_notice, response.body)
    assert_no_match(/발행 설정 필요/, response.body)
  end

  test "매트릭스: 설정 미완료는 거래처 사업자번호 없음보다 우위다 (settings_missing > client_missing)" do
    sign_in_as @user                                           # delta — 설정 미완료
    clients(:delta_main).update!(business_number: nil)

    get app_invoice_path(@invoice)                             # 켜짐 상태

    assert_match(/발행 설정 필요/, response.body)
    assert_no_match(/발행 비대상/, response.body)
  end

  test "매트릭스: 거래처 사업자번호 없음은 ready보다 우위다 (client_missing > ready)" do
    sign_in_as @user
    make_ready!
    clients(:delta_main).update!(business_number: nil)

    get app_invoice_path(@invoice)                             # 켜짐 상태

    assert_match(/발행 비대상/, response.body)
    assert_match(/사업자번호가 등록되어 있지 않습니다/, response.body)
    assert_no_match(new_app_tax_invoice_path(invoice_id: @invoice.id), response.body)
  end

  test "매트릭스: 조건이 모두 충족되면 ready 분기가 된다 (켜짐 회귀)" do
    sign_in_as @user
    make_ready!

    get app_invoice_path(@invoice)                             # 켜짐 상태

    assert_match(/300/, response.body)
    assert_match(new_app_tax_invoice_path(invoice_id: @invoice.id), response.body)
    assert_no_match(TaxInvoice::FEATURE_DISABLED_NOTICE, response.body)
    assert_no_match(/지원하지 않습니다/, response.body)
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

  def create_tax_invoice_record(order_id:, status: :issued)
    TaxInvoice.create!(invoice: @invoice, user: @user, mgt_num: "TI-GATE-#{order_id}",
                       order_id: order_id, status: status, nts_send_key: status == :issued ? "20261116-888888888-TESTKEY" : nil,
                       supply_total: 100_000, tax_total: 10_000, grand_total: 110_000)
  end

  # 레이아웃 사이드바 <nav> 세그먼트만 추출한다 — 메뉴 비노출·순서 판정 대상.
  def sidebar_nav
    response.body[/<nav[^>]*aria-label="대시보드 메뉴"[^>]*>.*?<\/nav>/m]
  end
end
