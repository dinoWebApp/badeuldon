require "application_system_test_case"

# CLIENT-4 — 발행 폼 거래처 선택 → 성적표 요약 fetch 갱신 E2E(Stimulus client-scorecard).
# 리뷰 Tester 중점 5번 — 컨트롤러 렌더 정적 확인을 넘어 실제 브라우저 경합(select change →
# fetch → 조각 삽입)을 검증한다. ① 선택 시 요약 조각 삽입·표시, ② 미선택(프롬프트) 복귀 시
# 조각 제거·hidden 복원. 외부 API 호출 없음(성적표는 내부 조회 — 솔라피·포트원 무관).
class AppInvoiceFormScorecardTest < ApplicationSystemTestCase
  test "발행 폼 거래처 선택 시 성적표 요약이 삽입되고 미선택 복귀 시 숨겨진다 (CLIENT-4)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      client = clients(:gamma_main)
      seed_paid_invoice(gamma, client, promised_on: Date.new(2026, 11, 3),
                        paid_on: Date.new(2026, 11, 4))   # 지연 +1 — 지표 존재

      log_in_as gamma
      visit new_app_invoice_path

      summary = find("[data-client-scorecard-target='summary']", visible: :all)  # hidden 요소 포함
      assert summary["hidden"], "초기 상태 — 거래처 미선택이므로 요약이 숨겨져야 한다"

      select "감마파트너스", from: "거래처"
      assert_selector "[data-client-scorecard-target='summary'] > div", visible: :all   # fetch 응답 조각 삽입 대기
      assert_text "평균 지급 지연일"
      assert_text "1일"

      select "거래처 선택", from: "거래처"                                # 프롬프트 복귀
      assert_no_selector "[data-client-scorecard-target='summary'] > div", visible: :all
      assert summary["hidden"], "미선택 복귀 시 hidden이 복원되어야 한다"
    end
  end

  private

  def log_in_as(user, password: "password")
    visit new_session_path
    fill_in "이메일", with: user.email
    fill_in "비밀번호", with: password
    click_button "로그인"
    assert_text "로그인되었습니다."
  end

  def seed_paid_invoice(user, client, promised_on:, paid_on:)
    invoice = user.invoices.create!(
      client: client, due_on: Date.new(2026, 11, 30), status: :paid,
      tax_mode: :separate, withholding_enabled: false,
      issuer_display_name: "테스트발행자",
      bank_name: "국민은행", account_number: "123-45-678901", account_holder: "테스트",
      issue_number: "BD-20990101-sys-#{SecureRandom.hex(4)}",
      token: SecureRandom.urlsafe_base64(32),
      issued_at: Time.current,
      items_attributes: { "0" => { description: "시드 품목", quantity: "1", unit_price: "100000" } }
    ).reload
    Payment.create!(invoice: invoice, amount: 110_000, paid_on: paid_on)
    Promise.new(invoice: invoice, kind: :date_selected,
                promised_on: promised_on).save(validate: false)
  end
end
