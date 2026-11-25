require "test_helper"
require_relative "../../test_helpers/baro_bill_stubbing"
require_relative "../../test_helpers/fake_baro_bill_client"

# 전자세금계산서 발행 컨트롤러(/app/tax_invoices — TAX-1/2·Q21·C-1·C-2) HTTP 통합 테스트.
# AUTH-1 비인증 가드·발행 가드 사슬 안내·C-2 이중 결제 차단·취소 경계·소유권 격리·
# SURF-3 noindex·청구 상세 패널 4분기를 검증한다. 바로빌 SOAP는 스텁(실호출 금지).
# TAX-4 — 이 파일은 스위치 켜짐을 전제로 한다(test_helper 기본 켬 — 꺼짐 케이스는
# tax_invoice_gate_test.rb가 with_tax_invoice_feature(false)로 격리해 검증한다).
class App::TaxInvoicesControllerTest < ActionDispatch::IntegrationTest
  include BaroBillStubbing

  setup do
    @user = users(:delta)
    @invoice = invoices(:delta_paid)                       # paid 청구 — 발행 대상
    travel_to(Time.zone.parse("2026-10-12 09:00"))
  end

  teardown do
    travel_back
  end

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

  # ── AUTH-1 · SURF-3 ──
  test "비인증 접근은 로그인 화면으로 302 리다이렉트된다 (AUTH-1)" do
    get new_app_tax_invoice_path(invoice_id: @invoice.id)

    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "설정·발행 화면은 noindex 메타를 출력한다 (SURF-3)" do
    sign_in_as @user

    get app_tax_invoice_setting_path
    assert_response :ok
    assert_match(/noindex/, response.body)

    make_ready!
    get new_app_tax_invoice_path(invoice_id: @invoice.id)
    assert_response :ok
    assert_match(/noindex/, response.body)
  end

  # ── new(미리보기) ──
  test "미리보기는 paid 청구 한정이다 — 미수 청구는 목록으로 되돌린다 (TAX-1 가드)" do
    sign_in_as @user
    make_ready!

    get new_app_tax_invoice_path(invoice_id: invoices(:delta_issued).id)

    assert_redirected_to app_invoices_path
    assert_match(/수금이 마감된 청구서만/, flash[:alert])
  end

  test "미리보기는 타인의 청구로 접근할 수 없다 (소유권 격리)" do
    sign_in_as users(:gamma)
    make_ready!

    get new_app_tax_invoice_path(invoice_id: @invoice.id)

    assert_redirected_to app_invoices_path                    # find_by 미일치 — unpaid 경로로 흡수
  end

  # ── create(주문 생성 — 가드 사슬) ──
  test "발행 가능 상태면 300원 주문을 만들고 체크아웃으로 전환한다 (Q21)" do
    sign_in_as @user
    make_ready!

    assert_difference -> { @user.orders.tax_invoices.count }, 1 do
      post app_tax_invoices_path, params: { invoice_id: @invoice.id }
    end

    assert_response :redirect
    order = @user.orders.tax_invoices.sole
    assert_redirected_to app_tax_invoice_path(order)
    assert_equal TaxInvoice::ISSUE_FEE, order.amount
    assert_equal @invoice.id, order.metadata["invoice_id"]
  end

  test "가드: 설정 미완료는 발행 설정 안내로 차단되고 주문을 만들지 않는다" do
    sign_in_as @user                                          # delta — 설정 미완료

    assert_no_difference -> { @user.orders.count } do
      post app_tax_invoices_path, params: { invoice_id: @invoice.id }
    end

    # TAX-3 ②(리뷰 C-1) — 가드에 막히면 발행 화면(결제 버튼이 남은 막다른 길)이 아니라
    # 청구서 상세로 되돌린다 — 패널이 같은 사유를 안내한다.
    assert_redirected_to app_invoice_path(@invoice)
    assert_match(/발행 설정을 먼저 완료/, flash[:alert])
  end

  test "가드: 거래처 사업자번호 없음(개인)은 안내로 차단된다" do
    sign_in_as @user
    make_ready!
    clients(:delta_main).update!(business_number: nil)

    post app_tax_invoices_path, params: { invoice_id: @invoice.id }

    assert_match(/개인 거래처는 비대상/, flash[:alert])
    assert_empty @user.orders.tax_invoices
  end

  test "가드: 이미 발행 요청된 청구는 안내로 차단된다 (1건 1발행 — TAX-1)" do
    sign_in_as @user
    make_ready!
    TaxInvoice.create!(invoice: @invoice, user: @user, mgt_num: "TI-DUP-1",
                       supply_total: 100_000, tax_total: 10_000, grand_total: 110_000)

    assert_no_difference -> { @user.orders.count } do
      post app_tax_invoices_path, params: { invoice_id: @invoice.id }
    end

    assert_match(/이미 발행 요청된 청구서입니다/, flash[:alert])
  end

  # C-2 — paid 주문 존재(발행 기록 미생성 — SOAP 실패 후 상태)에서 재결제 create 차단.
  test "C-2: paid tax_invoice 주문이 있으면 새 주문을 만들지 않고 기존 주문으로 안내한다" do
    sign_in_as @user
    make_ready!
    paid_order = create_tax_order(status: :paid)
    @user.orders.update_all(status: :paid)

    assert_no_difference -> { @user.orders.count } do
      post app_tax_invoices_path, params: { invoice_id: @invoice.id }
    end

    assert_redirected_to app_tax_invoice_path(paid_order)
    assert_match(/이미 결제가 완료되었습니다/, flash[:notice])
    assert_predicate paid_order.reload, :paid?
  end

  # ── show(체크아웃·TAX-2 상태) ──
  test "발행 주문 상세는 본인만 볼 수 있다 — 타인 주문은 404다 (소유권 격리)" do
    sign_in_as users(:gamma)
    order = create_tax_order

    get app_tax_invoice_path(order)

    assert_response :not_found
  end

  test "발행 주문 상세는 결제 실패 안내와 발행 상태를 보여준다 (TAX-2)" do
    sign_in_as @user
    make_ready!
    order = create_tax_order

    get app_tax_invoice_path(order, params: { payment_failed: "1" })

    assert_response :ok
    assert_match(/결제가 승인되지 않았습니다/, response.body)
  end

  # ── cancel(발급 취소 — PATCH member) ──
  test "pending 발행의 취소 성공 — canceled 전이 후 청구로 돌아간다 (TAX-1)" do
    sign_in_as @user
    make_ready!
    order = create_tax_order(status: :paid)
    tax_invoice = TaxInvoice.create!(invoice: @invoice, user: @user, mgt_num: "TI-C1",
                                     order_id: order.id, supply_total: 100_000,
                                     tax_total: 10_000, grand_total: 110_000)

    with_baro_bill_client(FakeBaroBillClient.new) do
      patch cancel_app_tax_invoice_path(order)
    end

    assert_redirected_to app_invoice_path(@invoice)
    assert_match(/발급이 취소되었습니다/, flash[:notice])
    assert_predicate tax_invoice.reload, :canceled?
  end

  test "이미 취소된 발행의 재취소는 안내로 차단된다" do
    sign_in_as @user
    order = create_tax_order(status: :paid)
    tax_invoice = TaxInvoice.create!(invoice: @invoice, user: @user, mgt_num: "TI-C2",
                                     order_id: order.id, status: :canceled,
                                     supply_total: 100_000, tax_total: 10_000, grand_total: 110_000)

    with_baro_bill_client(FakeBaroBillClient.new) do
      patch cancel_app_tax_invoice_path(order)
    end

    assert_redirected_to app_tax_invoice_path(order)
    assert_match(/이미 취소된 발행입니다/, flash[:alert])
    assert_predicate tax_invoice.reload, :canceled?
  end

  test "타인의 발행 주문 cancel은 404다 (소유권 격리)" do
    sign_in_as users(:gamma)
    order = create_tax_order(status: :paid)

    patch cancel_app_tax_invoice_path(order)

    assert_response :not_found
  end

  # ── 청구 상세 패널(_tax_invoice_panel — 4분기) ──
  test "패널: 설정 미완료는 설정 안내 분기다" do
    sign_in_as @user                                          # delta — 설정 미완료

    get app_invoice_path(@invoice)

    assert_response :ok
    assert_match(/발행 설정 필요/, response.body)
    assert_match(/발행 설정하기/, response.body)
  end

  test "패널: 발행 가능(ready)이면 발행 버튼과 300원 고지를 보여준다 (Q21)" do
    sign_in_as @user
    make_ready!

    get app_invoice_path(@invoice)

    assert_response :ok
    assert_match(/전자세금계산서 발행/, response.body)
    assert_match(/300/, response.body)
    assert_match(new_app_tax_invoice_path(invoice_id: @invoice.id), response.body)
  end

  test "패널: 개인 거래처는 비대상 안내 분기다" do
    sign_in_as @user
    make_ready!
    clients(:delta_main).update!(business_number: nil)

    get app_invoice_path(@invoice)

    assert_match(/발행 비대상/, response.body)
    assert_match(/사업자번호가 등록되어 있지 않습니다/, response.body)
  end

  test "패널: 발행 기록이 있으면 상태·승인번호·내역 링크(W-6)를 보여준다 (TAX-2)" do
    sign_in_as @user
    make_ready!
    order = create_tax_order(status: :paid)
    TaxInvoice.create!(invoice: @invoice, user: @user, mgt_num: "TI-P1", order_id: order.id,
                       status: :issued, nts_send_key: "20261116-888888888-TESTKEY",
                       write_date: Date.new(2026, 10, 10),
                       supply_total: 100_000, tax_total: 10_000, grand_total: 110_000)

    get app_invoice_path(@invoice)

    assert_match(/발행 완료/, response.body)
    assert_match(/20261116-888888888-TESTKEY/, response.body)
    assert_match(app_tax_invoice_path(order), response.body)   # W-6 — 발행 주문 상세 링크
    assert_no_match(/발행 설정 필요/, response.body)
  end

  test "패널: 결제 완료·발행 기록 미생성은 paid_pending 분기로 재결제 버튼을 노출하지 않는다 (C-2)" do
    sign_in_as @user
    make_ready!
    order = create_tax_order(status: :paid)                    # SOAP 실패 시나리오 — 레코드 없음

    get app_invoice_path(@invoice)

    assert_match(/발행 처리 확인/, response.body)
    assert_match(/재결제는 필요 없습니다/, response.body)
    assert_match(app_tax_invoice_path(order), response.body)
    assert_no_match(/전자세금계산서 발행</, response.body)      # 발행 버튼 미노출
  end

  # ── PLAN-9 환불 실행 — 회원 표기(Q27·W-5f) ──

  test "환불된 발행 주문 상세는 환불 안내를 보여주고 다시 발행 요청 링크가 없다 (PLAN-9·W-5f)" do
    sign_in_as @user
    order = create_tax_order(status: :paid)
    order.update!(paid_at: Time.current, status: :cancelled,
                  refunded_at: Time.current, refund_reason: "이중 결제 정정")

    get app_tax_invoice_path(order)

    assert_response :success
    assert_match "이 발행 주문은 환불되었습니다.", response.body
    assert_match "고객지원(문의)으로 연락해 주세요", response.body, "재발행은 고객지원 경로로 안내한다"
    assert_no_match "다시 발행 요청", response.body, "발행 이력 가드에 막혀 막다른 글이 되는 링크는 노출하지 않는다"
  end
end
