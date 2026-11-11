require "test_helper"

# LEGAL-1·REF-1 배너 노출 경계(HTTP) — 청구서 상세 상단의 내용증명·추심 안내 배너는
# 만기 +30일 "초과" unsettled 청구에만 노출된다(legal_target? 단일 출처·referral_banner
# 동일 조건). 배너가 임시 통합 테스트로만 검증됐던 회귀를 정식 테스트로 고정한다.
# 노출 여부는 배너 고유 문구로 응답 본문에서 판정한다(Assigns 폐기 — Rails 8).
class App::InvoicesLegalReferralBannerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:delta)
    sign_in_as @user
  end

  test "D+31 경과 unsettled 청구에는 내용증명·추심 배너가 모두 노출된다" do
    invoice = travel_to(Time.zone.parse("2026-10-12 09:00")) do
      create_banner_invoice(due_on: Date.new(2026, 9, 11)) # 기준일에 31일 경과
    end
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      get app_invoice_path(invoice)
    end

    assert_response :success
    assert_match "내용증명·추심 안내", response.body # legal 배너(LEGAL-1)
    assert_match "내용증명 양식 발급", response.body # new 진입 링크 헬퍼(3-S 결선)
    assert_match "장기 미수금 안내", response.body   # referral 배너(REF-1)
    assert_match "우체국", response.body             # LEGAL-4 직접 발송 고지
  end

  test "D+30 당일·29일 경과 청구에는 배너가 노출되지 않는다 (초과 경계)" do
    d30 = travel_to(Time.zone.parse("2026-10-12 09:00")) do
      create_banner_invoice(due_on: Date.new(2026, 9, 12)) # due+30 == 오늘 — 아직 초과 아님
    end
    d29 = travel_to(Time.zone.parse("2026-10-12 09:00")) do
      create_banner_invoice(due_on: Date.new(2026, 9, 13)) # 29일 경과
    end

    [ d30, d29 ].each do |invoice|
      travel_to(Time.zone.parse("2026-10-12 09:00")) do
        get app_invoice_path(invoice)
      end
      assert_response :success
      assert_no_match "내용증명·추심 안내", response.body
      assert_no_match "장기 미수금 안내", response.body
    end
  end

  test "D+31 경과라도 마감(paid)·draft 청구에는 배너가 노출되지 않는다 (unsettled 한정)" do
    paid = travel_to(Time.zone.parse("2026-10-12 09:00")) do
      create_banner_invoice(due_on: Date.new(2026, 9, 1), status: :paid)
    end
    draft = travel_to(Time.zone.parse("2026-10-12 09:00")) do
      create_banner_invoice(due_on: Date.new(2026, 9, 1), status: :draft)
    end

    [ paid, draft ].each do |invoice|
      travel_to(Time.zone.parse("2026-10-12 09:00")) do
        get app_invoice_path(invoice)
      end
      assert_response :success
      assert_no_match "내용증명·추심 안내", response.body
      assert_no_match "장기 미수금 안내", response.body
    end
  end

  private

  # 배너 경계 검증용 최소 청구 생성 — referrals_controller_test 헬퍼와 동일 구성(INV-1 통과).
  def create_banner_invoice(status: :overdue, due_on:)
    invoice = Invoice.new(
      user: @user,
      client: clients(:delta_main),
      status: status,
      issue_number: "BANNER-#{SecureRandom.hex(4)}",
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
