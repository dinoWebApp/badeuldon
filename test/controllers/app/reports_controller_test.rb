require "test_helper"

# 표면 ② /app/report — DASH-5(거래처별 지연·월간 수금 추이)·DASH-6(신고 주기 집계 + 세무 고지).
# 시나리오 기준: 05_review.md 「Tester 중점 테스트 제안」 2·5번 —
# 비인증 가드(AUTH-1)·200 렌더·3섹션·세무 고지문·빈 상태(청구 0건 — ONB-1 CTA)·타인 데이터 미노출.
# 시간은 travel_to로 2026-11-09(KST) 고정(TIME-1).
class App::ReportsControllerTest < ActionDispatch::IntegrationTest
  test "비인증 /app/report 접근은 로그인 화면에 리다이렉트된다 (AUTH-1)" do
    get app_report_path
    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "청구 0건 사용자는 빈 상태 CTA만 노출되고 3섹션은 렌더되지 않는다 (ONB-1·DASH-5/6)" do
    sign_in_as users(:gamma)
    get app_report_path
    assert_response :success
    assert_select "h1", text: "리포트"

    assert_select "section[aria-labelledby='report-empty'] h2", text: "아직 리포트가 없습니다", count: 1
    assert_select "a", text: "첫 청구서 발행하기", count: 1
    # 데이터 섹션 3종 미노출 — 빈 상태에서 거짓 0원 표기를 하지 않는다
    assert_select "section[aria-labelledby='report-client-delay']", count: 0
    assert_select "section[aria-labelledby='report-monthly']", count: 0
    assert_select "section[aria-labelledby='report-tax']", count: 0
    assert_no_match(/0원/, response.body)
  end

  test "리포트는 3섹션(지연 리포트·월간 추이·신고 주기)과 세무 고지문을 렌더한다 (DASH-5/6)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      sign_in_as users(:gamma)
      seed_paid_invoice(label: "view", due_on: Date.new(2026, 11, 5))  # 마감 +4일 — 11월 수금
      paid = users(:gamma).invoices.find_by(issue_number: "BD-20990101-view")
      Payment.create!(invoice: paid, amount: 110_000, paid_on: Date.new(2026, 11, 9))

      get app_report_path
      assert_response :success

      assert_select "section[aria-labelledby='report-client-delay']", count: 1
      assert_select "section[aria-labelledby='report-monthly']", count: 1
      assert_select "section[aria-labelledby='report-tax']", count: 1
      # DASH-6 세무 고지문 — PRD 명시 문구 원문
      assert_select "p", text: "본 집계표는 세무 자문이 아닙니다. 신고 자료로 활용하기 전 세무대리인 확인을 권장합니다.", count: 1
      # 거래처별 지연 리포트 — 실데이터 행
      assert_select "th[scope=row]", text: "감마파트너스", count: 1
      assert_select "td", text: "+4일", count: 1
      # 월간 추이 — 12개월 라벨(2025.12 연간 경계 포함)과 이번 달 수금액 문구
      assert_select "span", text: "2025.12", count: 1
      assert_select "p", text: /이번 달 수금액은/, count: 1
    end
  end

  test "리포트에 다른 사용자의 거래처·수금 데이터는 노출되지 않는다 (소유권 격리)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      beta = users(:beta)
      seed_invoice(beta, clients(:beta_secret), label: "other", due_on: Date.new(2026, 11, 5), status: :paid)
      beta_paid = beta.invoices.find_by(issue_number: "BD-20990101-other")
      Payment.create!(invoice: beta_paid, amount: 110_000, paid_on: Date.new(2026, 11, 8))

      sign_in_as users(:gamma)
      seed_paid_invoice(label: "mine", due_on: Date.new(2026, 11, 5))
      my_paid = users(:gamma).invoices.find_by(issue_number: "BD-20990101-mine")
      Payment.create!(invoice: my_paid, amount: 110_000, paid_on: Date.new(2026, 11, 9))

      get app_report_path
      assert_response :success

      # beta의 거래처명·담당자가 페이지 어디에도 노출되지 않는다 — 거래처 테이블엔 자기 행 1개만 렌더된다
      assert_no_match(/베타비밀거래처|베타대표/, response.body)
      assert_select "section[aria-labelledby='report-client-delay']" do
        assert_select "th[scope=row]", count: 1
        assert_select "td", text: "+4일", count: 1
      end
    end
  end

  private

  def seed_paid_invoice(label:, due_on:)
    seed_invoice(users(:gamma), clients(:gamma_main), label: label, due_on: due_on, status: :paid)
  end

  def seed_invoice(user, client, label:, due_on:, status: :issued, rows: [ [ 1, 100_000 ] ])
    issued_family = Invoice.new(status: status).unsettled? || status.to_s == "paid"
    user.invoices.create!(
      client: client, due_on: due_on, status: status,
      tax_mode: :separate, withholding_enabled: false,
      issuer_display_name: "테스트발행자",
      bank_name: "국민은행", account_number: "123-45-678901", account_holder: "테스트",
      issue_number: (issued_family ? "BD-20990101-#{label}" : nil),
      token: (issued_family ? SecureRandom.urlsafe_base64(32) : nil),
      issued_at: (issued_family ? Time.current : nil),
      items_attributes: rows.each_with_index.to_h do |(quantity, unit_price), index|
        [ index.to_s, { description: "시드 품목#{index + 1}", quantity: quantity.to_s, unit_price: unit_price.to_s } ]
      end
    ).reload
  end
end
