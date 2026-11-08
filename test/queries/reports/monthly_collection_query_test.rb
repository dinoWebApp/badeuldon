require "test_helper"

# DASH-5 — 월간 수금 추이 쿼리(Reports::MonthlyCollectionQuery).
# 시나리오 기준: 05_review.md 「Tester 중점 테스트 제안」 2·5번 —
# 12행 고정(빈 달 0원)·월 경계(월말·연간 경계 12월→1월)·소유권 격리.
# 시간은 travel_to로 2026-11-09(KST) 고정(TIME-1) — 집계 창은 2025-12~2026-11.
class Reports::MonthlyCollectionQueryTest < ActiveSupport::TestCase
  test "항상 12행을 반환하고 이번 달이 마지막이다 (DASH-5)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      rows = Reports::MonthlyCollectionQuery.call(users(:gamma).id)

      assert_equal 12, rows.size
      assert_equal "2025.12", rows.first.label
      assert_equal Date.new(2025, 12, 1), rows.first.month
      assert_equal "2026.11", rows.last.label
      assert_equal Date.new(2026, 11, 1), rows.last.month
    end
  end

  test "빈 달은 0원으로 채워진다 (DASH-5 그래프 축 고정)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      invoice = seed_invoice(gamma, clients(:gamma_main), label: "m1", due_on: Date.current)
      Payment.create!(invoice: invoice, amount: 50_000, paid_on: Date.current)

      rows = Reports::MonthlyCollectionQuery.call(gamma.id)

      assert_equal 50_000, rows.last.amount
      assert_equal [ 0 ] * 11, rows.first(11).map(&:amount)
    end
  end

  test "집계 창 첫 달(12개월 전)과 창 바깥 이전 달을 정확히 가른다 — 연간 경계 (DASH-5)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      invoice = seed_invoice(gamma, clients(:gamma_main), label: "m2", due_on: Date.new(2026, 1, 10))
      # 창 안 — 2025-12(연간 경계 월) 입금 2건
      Payment.create!(invoice: invoice, amount: 11_000, paid_on: Date.new(2025, 12, 1))
      Payment.create!(invoice: invoice, amount: 22_000, paid_on: Date.new(2025, 12, 31))
      # 창 바깥 — 2025-11(13개월 전) 입금은 제외되어야 한다
      Payment.create!(invoice: invoice, amount: 999_000, paid_on: Date.new(2025, 11, 30))

      rows = Reports::MonthlyCollectionQuery.call(gamma.id)

      assert_equal 33_000, rows.first.amount  # 2025.12 — 월말 입금 포함(연간 경계)
      assert_equal 0, rows.second.amount      # 2026.01
      # 창 바깥 999,000이 어느 행에도 섞이지 않았는다
      assert_equal 33_000, rows.sum(&:amount)
    end
  end

  test "다른 사용자의 입금은 집계에 포함되지 않는다 (소유권 격리)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      beta = users(:beta)
      gamma_invoice = seed_invoice(gamma, clients(:gamma_main), label: "iso-g", due_on: Date.current)
      Payment.create!(invoice: gamma_invoice, amount: 10_000, paid_on: Date.current)
      beta_invoice = seed_invoice(beta, clients(:beta_secret), label: "iso-b", due_on: Date.current)
      Payment.create!(invoice: beta_invoice, amount: 777_000, paid_on: Date.current)

      gamma_rows = Reports::MonthlyCollectionQuery.call(gamma.id)

      assert_equal 10_000, gamma_rows.last.amount
      assert_equal 10_000, gamma_rows.sum(&:amount)
      assert_equal 777_000, Reports::MonthlyCollectionQuery.call(beta.id).last.amount
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
