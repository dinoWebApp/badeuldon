require "test_helper"

# CLIENT-3/4 — 거래처 상세(카드·지급 성적표·약속 이행 이력)와 발행 폼 성적표 엔드포인트
# 통합 테스트. 시나리오 기준: PRD v0.35 CLIENT-3/4·02_prd_update 확정 해석 3·4 —
# ① 렌더(카드·성적표·빈 상태), ② scorecard 엔드포인트 소유권 격리(타인 거래처 404),
# ③ 비인증 가드(AUTH-1), ④ 지표 null 표기("-").
class App::ClientsScorecardTest < ActionDispatch::IntegrationTest
  test "비인증 거래처 상세·성적표 엔드포인트는 로그인 화면으로 리다이렉트된다 (AUTH-1)" do
    get app_client_path(clients(:gamma_main))
    assert_redirected_to new_session_path

    get scorecard_app_invoices_path, params: { client_id: clients(:gamma_main).id }
    assert_redirected_to new_session_path
  end

  test "거래처 상세는 성적표 카드와 빈 상태 안내를 렌더한다 (CLIENT-3·4)" do
    sign_in_as users(:gamma)
    get app_client_path(clients(:gamma_main))

    assert_response :success
    assert_select "h2", text: "지급 성적표"
    assert_select "h2", text: "약속 이행 이력"
    # 빈 상태 — 마감·약속이 없으므로 "-" 표기와 안내 문구
    assert_match %r{아직 기록된 약속이 없습니다}, response.body
  end

  test "타인의 거래처 상세 조회는 404로 수렴한다 (소유권 격리)" do
    sign_in_as users(:gamma)
    get app_client_path(clients(:beta_secret))
    assert_response :not_found
  end

  test "성적표 엔드포인트는 본인 거래처 요약을 렌더한다 (CLIENT-4)" do
    sign_in_as users(:gamma)
    get scorecard_app_invoices_path, params: { client_id: clients(:gamma_main).id }

    assert_response :success
    assert_match %r{평균 지급 지연일}, response.body
    assert_match %r{약속 이행률}, response.body
  end

  test "성적표 엔드포인트의 타인 거래처 client_id는 404로 수렴한다 (소유권 격리)" do
    sign_in_as users(:gamma)
    get scorecard_app_invoices_path, params: { client_id: clients(:beta_secret).id }
    assert_response :not_found
  end

  test "조기 입금 거래처의 평균 지연일은 'N일 전'으로 렌더된다 (CLIENT-4 — '-' 오노출 방지)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      client = clients(:gamma_main)
      seed_paid_invoice(gamma, client, "vw-a", promised_on: Date.new(2026, 11, 8),
                        paid_on: Date.new(2026, 11, 5))   # −3
      seed_paid_invoice(gamma, client, "vw-b", promised_on: Date.new(2026, 11, 6),
                        paid_on: Date.new(2026, 11, 5))   # −1 → 평균 −2

      sign_in_as gamma
      get app_client_path(client)

      assert_response :success
      assert_match %r{2일 전}, response.body
      assert_no_match %r{평균보다}, response.body  # 거래처 1개 — 배지 미노출
    end
  end

  test "느린 거래처 비교 배지는 주황으로 렌더된다 (리뷰 W-1 — DESIGN-2 상태색)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      main = clients(:gamma_main)
      other = gamma.clients.create!(name: "감마제4", contact_name: "감책임", phone: "010-0000-0002")
      seed_paid_invoice(gamma, main, "wb-a", promised_on: Date.new(2026, 11, 3),
                        paid_on: Date.new(2026, 11, 6))   # +3
      seed_paid_invoice(gamma, other, "wb-b", promised_on: Date.new(2026, 11, 3),
                        paid_on: Date.new(2026, 11, 4))   # +1 → main 3 / 전체 (3+1)/2=2 → diff +1

      sign_in_as gamma
      get app_client_path(main)

      assert_response :success
      assert_match %r{평균보다 1일 느린 거래처}, response.body
      assert_match %r{text-orange-600}, response.body
    end
  end

  private

  # 쿼리 테스트와 동일 시드 규칙 — 마감(paid) 청구 + 약속 1건(validate 우회).
  def seed_paid_invoice(user, client, label, promised_on:, paid_on:)
    invoice = user.invoices.create!(
      client: client, due_on: Date.new(2026, 11, 30), status: :paid,
      tax_mode: :separate, withholding_enabled: false,
      issuer_display_name: "테스트발행자",
      bank_name: "국민은행", account_number: "123-45-678901", account_holder: "테스트",
      issue_number: "BD-20990101-#{label}",
      token: SecureRandom.urlsafe_base64(32),
      issued_at: Time.current,
      items_attributes: { "0" => { description: "시드 품목", quantity: "1", unit_price: "100000" } }
    ).reload
    Payment.create!(invoice: invoice, amount: 110_000, paid_on: paid_on)
    Promise.new(invoice: invoice, kind: :date_selected,
                promised_on: promised_on).save(validate: false)
    invoice
  end
end
