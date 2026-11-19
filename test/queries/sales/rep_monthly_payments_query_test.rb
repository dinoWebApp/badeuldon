require "test_helper"

# 영업 직원 월별 결제 총액 쿼리(SALES-6 — F-SALES). 12행 고정(빈 달 0원)·본인 유치 사용자만
# (스코프 격리 SALES-7)·paid·환불 제외·plus_monthly 한정.
# 시나리오 기준: PRD §6.20 SALES-6·_workspace/05_review.md §4 Tester 중점 12번.
class Sales::RepMonthlyPaymentsQueryTest < ActiveSupport::TestCase
  setup do
    @rep = sales_reps(:sales_kim)
  end

  def referred_plus_order(amount:, paid_at:)
    user = User.create!(email: "query-u#{paid_at.to_i}@example.com", password: "password123",
                        referred_by_sales_rep_id: @rep.id)
    user.orders.create!(product: :plus_monthly, amount:, status: :paid,
                        pg_order_id: "pg-q-#{paid_at.to_i}", paid_at:)
  end

  test "항상 12행을 반환하고 이번 달이 마지막이다 (SALES-6)" do
    travel_to(Time.zone.parse("2026-11-19 09:00")) do
      rows = Sales::RepMonthlyPaymentsQuery.call(@rep.id)

      assert_equal 12, rows.size
      assert_equal "25.12", rows.first.label
      assert_equal "26.11", rows.last.label
      assert_equal [ 0 ] * 12, rows.map(&:amount), "결제 없으면 전부 0원"
    end
  end

  test "본인 유치 사용자의 paid plus 결제만 월별 합산한다 (SALES-6·7)" do
    travel_to(Time.zone.parse("2026-11-19 09:00")) do
      referred_plus_order(amount: 7_920, paid_at: Time.zone.parse("2026-11-05 10:00"))
      referred_plus_order(amount: 9_900, paid_at: Time.zone.parse("2026-11-15 10:00"))
      referred_plus_order(amount: 9_900, paid_at: Time.zone.parse("2026-10-20 10:00"))

      rows = Sales::RepMonthlyPaymentsQuery.call(@rep.id)

      assert_equal 9_900, rows[-2].amount
      assert_equal 17_820, rows.last.amount, "같은 달 결제는 합산"
      assert_equal [ 0 ] * 10, rows.first(10).map(&:amount)
    end
  end

  test "환불·미결제·타 상품·타 rep 사용자는 제외한다 (스코프 격리 — SALES-7)" do
    travel_to(Time.zone.parse("2026-11-19 09:00")) do
      user = User.create!(email: "query-mixed@example.com", password: "password123",
                          referred_by_sales_rep_id: @rep.id)
      user.orders.create!(product: :plus_monthly, amount: 9_900, status: :paid,
                          pg_order_id: "pg-refund", paid_at: Time.zone.parse("2026-11-01 10:00"),
                          refunded_at: Time.zone.parse("2026-11-10 10:00"))
      user.orders.create!(product: :plus_monthly, amount: 9_900,
                          pg_order_id: "pg-q-pending", paid_at: nil)
      user.orders.create!(product: :collection_pass, amount: 4_000, status: :paid,
                          pg_order_id: "pg-q-pass", paid_at: Time.zone.parse("2026-11-02 10:00"))

      stranger = users(:epsilon) # 타 rep 소속 아님(referred_by nil)
      stranger.orders.create!(product: :plus_monthly, amount: 9_900, status: :paid,
                              pg_order_id: "pg-q-stranger", paid_at: Time.zone.parse("2026-11-03 10:00"))

      rows = Sales::RepMonthlyPaymentsQuery.call(@rep.id)
      assert_equal [ 0 ] * 12, rows.map(&:amount), "집계 대상이 없으면 전부 0원"
    end
  end
end
