# REF-1~4·P5 — 추심 상담 소개 화면(/app/referrals). routes 3-S 결선 전에는 라우팅이
# 없어 HTTP 테스트가 불가하므로, 결선을 감지하면 자동 활성화되고 그 전에는 skip 된다.
# 검증 항목: ① 비인증 차단 ② D+30 판정 경계(31일 경과만 대상 — 30일·29일 미포함,
# 판정식 due_on + 30 < Date.current) ③ unsettled 한정(paid·voided·draft 제외)
# ④ 소유권 격리(타인 청구 미포함) ⑤ P5·REF 고지 문구 노출.
# 기준 테스트 일자 = 2026-10-12(KST, TIME-1) — 픽스처 헤더의 전역 규약을 따른다.
require "test_helper"

class App::ReferralsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:delta) # profile 완료 — /app 가드 통과
    sign_in_as @user
    @eligible_invoice = invoices(:delta_overdue) # due 2026-09-01 → 기준일에 41일 경과
  end

  test "routes 3-S 결선 전에는 skip 하고 결선 후에 활성화된다" do
    skip "config/routes.rb에 GET /app/referrals 미결선 — 3-S 결선 후 이 테스트가 활성화된다" unless referrals_routed?
    get "/app/referrals"
    assert_response :success
  end

  test "비인증 접근은 로그인으로 리다이렉트된다" do
    skip unless referrals_routed?
    reset! # 세션 쿠키 제거 — 비인증 상태로 재요청
    get "/app/referrals"
    assert_redirected_to new_session_path
  end

  test "D+30 경계 — 31일 경과 청구만 목록에 포함된다" do
    skip unless referrals_routed?
    travel_to("2026-10-12 09:00".in_time_zone("Asia/Seoul")) do
      d31 = create_referral_invoice(due_on: "2026-09-11")  # due+30 = 10-11 < 10-12 → 대상
      d30 = create_referral_invoice(due_on: "2026-09-12")  # due+30 = 10-12 → 미포함
      d29 = create_referral_invoice(due_on: "2026-09-13")  # 29일 경과 → 미포함
      get "/app/referrals"
      assert_response :success
      # 3-S — Rails 8에서 assigns가 제거됨에 따라 목록 포함 여부를 응답 본문(청구번호)으로 검증한다.
      assert_match d31.issue_number, response.body
      assert_no_match d30.issue_number, response.body
      assert_no_match d29.issue_number, response.body
    end
  end

  test " unsettled 한정 — paid·voided·draft는 경과일과 무관하게 제외된다" do
    skip unless referrals_routed?
    travel_to("2026-10-12 09:00".in_time_zone("Asia/Seoul")) do
      paid = create_referral_invoice(status: :paid, due_on: "2026-09-01")
      voided = create_referral_invoice(status: :voided, due_on: "2026-09-01")
      draft = create_referral_invoice(status: :draft, due_on: "2026-09-01")
      get "/app/referrals"
      assert_response :success
      # 3-S — 응답 본문(청구번호)으로 제외 검증.
      assert_no_match paid.issue_number, response.body
      assert_no_match voided.issue_number, response.body
      assert_no_match draft.issue_number, response.body
    end
  end

  test "소유권 격리 — 타인(delta)의 D+30 청구는 다른 사용자 목록에 없다" do
    skip unless referrals_routed?
    gamma = users(:gamma)
    sign_in_as gamma
    travel_to("2026-10-12 09:00".in_time_zone("Asia/Seoul")) do
      get "/app/referrals"
      assert_response :success
      # gamma는 청구 0건 — delta의 대상 청구번호는 노출되지 않는다(3-S — 본문 기반 검증).
      assert_no_match invoices(:delta_overdue).issue_number, response.body
    end
  end

  test "P5·REF 고지 문구가 화면에 노출된다 (REF-2/3/4)" do
    skip unless referrals_routed?
    get "/app/referrals"
    assert_response :success
    assert_match "채권 수임·중개 행위를 수행하지 않습니다", response.body
    assert_match "의뢰·계약은 회원님과 제휴 상담사 사이에서 성립합니다", response.body
    assert_match "회원님이 동의한 항목으로 한정", response.body
    assert_match "수수료·의뢰 조건은 제휴사와의 계약에 따릅니다", response.body
    assert_match "제휴 상담사 연결은 준비 중입니다", response.body
  end

  private

  # routes 3-S 결선 감지 — GET /app/referrals 라우팅이 없으면 테스트를 skip 한다.
  def referrals_routed?
    Rails.application.routes.recognize_path("/app/referrals", method: :get)
    true
  rescue ActionController::RoutingError
    false
  end

  # D+30 경계·모집합 검증용 최소 청구 생성 — delta 소유, 품목 행 1행 포함(INV-1 최소 검증 통과).
  def create_referral_invoice(status: :overdue, due_on:)
    invoice = Invoice.new(
      user: @user,
      client: clients(:delta_main),
      status: status,
      issue_number: "REF-#{SecureRandom.hex(4)}", # 3-S — assigns 폐기(Rails 8)에 따라 목록 검증을 응답 본문의 청구번호로 수행한다
      due_on: due_on,
      tax_mode: :separate,
      withholding_enabled: false,
      issuer_display_name: "테스트발행자",
      bank_name: "신한은행",
      account_number: "110-234-567890",
      account_holder: "김델타",
      subtotal: 100_000,
      tax_amount: 10_000,
      total_amount: 110_000,
      withholding_amount: 0,
      net_amount: 110_000,
      items: [ InvoiceItem.new(description: "작업", quantity: 1, unit_price: 100_000) ]
    )
    invoice.save!
    invoice
  end
end
