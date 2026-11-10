require "test_helper"

# ADMIN-5 — 발행·수금 통계 + 북극성 쿼리(Admins::CollectionStatsQuery).
# 시나리오 기준: PRD v0.31 ADMIN-5·05_review.md §4 제안 6 —
# ① 북극성 = paid 청구 중 (최종 입금일 − 발행일) ≤ 30일 비율(마감일은 Payment MAX(paid_on) —
#   부분입금 행 가중 방지), ② 마감 0건이면 north_star_rate nil(뷰 "-"), ③ draft·voided는
#   발행 모집단 제외, ④ 경계: 30일 이내/초과 혼합 시 비율이 정확히 나뉘는지.
class Admins::CollectionStatsQueryTest < ActiveSupport::TestCase
  test "북극성은 발행 후 30일 내 수금 완료 비율이다 (ADMIN-5)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      clear_domain_tables
      User.delete_all
      owner = User.create!(email: "ns-owner@example.com", password: "password")
      client = owner.clients.create!(name: "NS상사", contact_name: "김북극", phone: "010-1111-2222")
      fast = seed_invoice(owner, client, label: "ns-fast",
                          issued_at: Time.zone.parse("2026-11-01 10:00"), status: :paid)
      Payment.create!(invoice: fast, amount: 100_000, paid_on: Date.new(2026, 11, 8)) # +7일
      slow = seed_invoice(owner, client, label: "ns-slow",
                          issued_at: Time.zone.parse("2026-09-01 10:00"), status: :paid)
      Payment.create!(invoice: slow, amount: 100_000, paid_on: Date.new(2026, 10, 10)) # +39일

      row = Admins::CollectionStatsQuery.call

      assert_equal 2, row.total_issued
      assert_equal 2, row.total_closed
      assert_equal 50.0, row.north_star_rate
      assert_equal 1, row.month_closed, "마감 입금일이 당월인 건만 월간 마감 수에 포함"
    end
  end

  test "부분입금이 여러 번인 청구의 마감일은 최종 입금일 기준이다 (행 가중 방지)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      clear_domain_tables
      User.delete_all
      owner = User.create!(email: "ns-part@example.com", password: "password")
      client = owner.clients.create!(name: "PT상사", contact_name: "김부분", phone: "010-2222-3333")
      invoice = seed_invoice(owner, client, label: "ns-part",
                             issued_at: Time.zone.parse("2026-11-01 10:00"), status: :paid)
      Payment.create!(invoice: invoice, amount: 10_000, paid_on: Date.new(2026, 11, 2))
      Payment.create!(invoice: invoice, amount: 90_000, paid_on: Date.new(2026, 11, 9)) # 최종 +8일

      row = Admins::CollectionStatsQuery.call

      assert_equal 100.0, row.north_star_rate, "최종 입금일 기준 30일 이내 — 조기 부분입금 행 가중과 무관"
    end
  end

  test "마감(입금) 건이 없으면 north_star_rate는 nil이다 (뷰 '-' — 분모 0)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      clear_domain_tables
      User.delete_all
      owner = User.create!(email: "ns-empty@example.com", password: "password")
      client = owner.clients.create!(name: "EM상사", contact_name: "김빈", phone: "010-3333-4444")
      seed_invoice(owner, client, label: "ns-open", status: :issued) # 미수 청구만 존재

      row = Admins::CollectionStatsQuery.call

      assert_equal 1, row.total_issued
      assert_equal 0, row.total_closed
      assert_nil row.north_star_rate
    end
  end

  test "draft·voided 청구는 발행 모집단에서 제외되고 마감 금액은 입금 합계다 (ADMIN-5)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      clear_domain_tables
      User.delete_all
      owner = User.create!(email: "ns-draft@example.com", password: "password")
      client = owner.clients.create!(name: "DF상사", contact_name: "김초안", phone: "010-4444-5555")
      seed_invoice(owner, client, label: "ns-draft", status: :draft)
      seed_invoice(owner, client, label: "ns-void", status: :voided)
      paid = seed_invoice(owner, client, label: "ns-paid",
                          issued_at: Time.zone.parse("2026-11-01 10:00"), status: :paid)
      Payment.create!(invoice: paid, amount: 60_000, paid_on: Date.new(2026, 11, 5))
      Payment.create!(invoice: paid, amount: 40_000, paid_on: Date.new(2026, 11, 6))

      row = Admins::CollectionStatsQuery.call

      assert_equal 1, row.total_issued, "draft·voided 제외"
      assert_equal 100_000, row.month_closed_amount, "당월 입금 합계(부분입금 포함)"
      assert_equal 100_000, row.total_closed_amount
    end
  end

  private

  def seed_invoice(user, client, label:, status: :issued, issued_at: nil)
    issued_family = %w[issued paid overdue viewed promised partially_paid].include?(status.to_s)
    user.invoices.create!(
      client: client, due_on: Date.current + 10, status: status,
      tax_mode: :separate, withholding_enabled: false,
      issuer_display_name: "테스트발행자",
      bank_name: "국민은행", account_number: "123-45-678901", account_holder: "테스트",
      issue_number: (issued_family ? "BD-20990101-#{label}" : nil),
      token: (issued_family ? SecureRandom.urlsafe_base64(32) : nil),
      issued_at: (issued_family ? (issued_at || Time.current) : nil),
      items_attributes: { "0" => { description: "시드 품목", quantity: "1", unit_price: "100000" } }
    ).reload
  end
end
