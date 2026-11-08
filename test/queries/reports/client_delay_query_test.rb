require "test_helper"

# DASH-5 — 거래처별 지연 리포트 쿼리(Reports::ClientDelayQuery).
# 시나리오 기준: 05_review.md 「Tester 중점 테스트 제안」 1·2·4번 —
# ① 부분입금 2회 이상 청구의 평균 지급 지연일은 마감(최종) 입금일 기준이어야 한다(리뷰 C-1 재현 —
#   조기 부분입금 −7일 + 지연 마감 +5일 / 단일 +7일 → 평균 +6일, 행 단위 가중이 남으면 음수로 반전),
# ② 소유권 격리(타 사용자 거래처·청구·입금 비포함),
# ④ 만기일=오늘 연체 배타, PAY-2 잔액 기준, 마감 0건 거래처 nil.
# 시간은 travel_to로 2026-11-09(KST) 고정(TIME-1).
class Reports::ClientDelayQueryTest < ActiveSupport::TestCase
  test "부분입금 2회 청구의 평균 지급 지연일은 마감 입금일 기준이다 — 행 가중·조기 입금 혼입 금지 (DASH-5·리뷰 C-1)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      client = clients(:gamma_main)
      # 청구 A — 조기 부분입금(만기 −7일) 후 지연 마감(만기 +5일): 지연일은 +5 하나만 유효
      invoice_a = seed_invoice(gamma, client, label: "delay-a", due_on: Date.new(2026, 11, 1), status: :paid)
      Payment.create!(invoice: invoice_a, amount: 10_000, paid_on: Date.new(2026, 10, 25))
      Payment.create!(invoice: invoice_a, amount: 100_000, paid_on: Date.new(2026, 11, 6))
      # 청구 B — 단일 입금 +7일
      invoice_b = seed_invoice(gamma, client, label: "delay-b", due_on: Date.new(2026, 11, 2), status: :paid)
      Payment.create!(invoice: invoice_b, amount: 110_000, paid_on: Date.new(2026, 11, 9))

      row = Reports::ClientDelayQuery.call(gamma.id).find { |r| r.client_name == client.name }

      # PRD 기대: (5 + 7) / 2 = +6 — 입금 행 3개를 가중 평균하면 −7·+5·+7 → +2로 반전 검출된다
      assert_equal 6, row.avg_delay_days
    end
  end

  test "마감이 만기보다 빠른 청구는 음수 지연일(조기)로 반환된다 (DASH-5)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      client = clients(:gamma_main)
      invoice = seed_invoice(gamma, client, label: "early", due_on: Date.new(2026, 11, 5), status: :paid)
      Payment.create!(invoice: invoice, amount: 110_000, paid_on: Date.new(2026, 11, 2))

      row = Reports::ClientDelayQuery.call(gamma.id).find { |r| r.client_name == client.name }

      assert_equal(-3, row.avg_delay_days)
    end
  end

  test "마감 이력이 없는 거래처의 평균 지연일은 nil이고 진행 청구수는 채워진다 (DASH-5)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      client = clients(:gamma_main)
      seed_invoice(gamma, client, label: "open", due_on: Date.current + 10)

      row = Reports::ClientDelayQuery.call(gamma.id).find { |r| r.client_name == client.name }

      assert_nil row.avg_delay_days
      assert_equal 1, row.unsettled_count
      assert_equal 0, row.overdue_count
    end
  end

  test "연체 금액은 부분입금을 차감한 잔액 기준이다 (PAY-2)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      client = clients(:gamma_main)
      invoice = seed_invoice(gamma, client, label: "partial", due_on: Date.current - 3)  # total 110,000
      Payment.create!(invoice: invoice, amount: 10_000, paid_on: Date.current)

      row = Reports::ClientDelayQuery.call(gamma.id).find { |r| r.client_name == client.name }

      assert_equal 1, row.overdue_count
      # 잔액 = 110,000 − 10,000 — 총액 기준(110,000)이면 PAY-2 위반으로 검출된다
      assert_equal 100_000, row.overdue_amount
    end
  end

  test "만기일이 오늘인 청구는 연체에 포함되지 않는다 (DASH-5 경계)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      client = clients(:gamma_main)
      seed_invoice(gamma, client, label: "today", due_on: Date.current)

      row = Reports::ClientDelayQuery.call(gamma.id).find { |r| r.client_name == client.name }

      assert_equal 1, row.unsettled_count
      assert_equal 0, row.overdue_count
      assert_equal 0, row.overdue_amount
    end
  end

  test "다른 사용자의 거래처·청구·입금은 집계에 포함되지 않는다 (소유권 격리)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      beta = users(:beta)
      # gamma — 마감 +6일 1건(연체 없음)
      gamma_client = clients(:gamma_main)
      gamma_invoice = seed_invoice(gamma, gamma_client, label: "iso-g", due_on: Date.new(2026, 11, 3), status: :paid)
      Payment.create!(invoice: gamma_invoice, amount: 110_000, paid_on: Date.new(2026, 11, 9))
      # beta — 다른 거래처·연체 1건·마감 +1일
      beta_client = clients(:beta_secret)
      seed_invoice(beta, beta_client, label: "iso-b1", due_on: Date.current - 5)
      beta_paid = seed_invoice(beta, beta_client, label: "iso-b2", due_on: Date.new(2026, 11, 1), status: :paid)
      Payment.create!(invoice: beta_paid, amount: 110_000, paid_on: Date.new(2026, 11, 2))

      gamma_rows = Reports::ClientDelayQuery.call(gamma.id)
      beta_rows = Reports::ClientDelayQuery.call(beta.id)

      assert_equal [ gamma_client.name ], gamma_rows.map(&:client_name)
      assert_equal [ beta_client.name ], beta_rows.map(&:client_name)
      # gamma 평균 지연일은 gamma 마감(+6)만 — beta +1이 섞이면 불일치로 검출된다
      assert_equal 6, gamma_rows.first.avg_delay_days
      assert_equal 1, beta_rows.first.overdue_count
      assert_equal 0, gamma_rows.first.overdue_count
    end
  end

  private

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
