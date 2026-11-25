require "test_helper"
require_relative "../../test_helpers/fake_portone_client"

# ADMIN-5 — 매출·MRR 쿼리(Admins::RevenueStatsQuery).
# 시나리오 기준: PRD v0.31 ADMIN-5·05_review.md §4 —
# ① 매출 = Order.paid 합계(paid_at 기준 당월·누적), ② 환불 기록 주문 제외(ADMIN-4·3-S —
#   refunded_at 세팅 시 합계가 감소해야 하며 유지되면 리뷰 제안 2 위반), ③ MRR = active Plus × 9,900
#   (cancelled 제외 — PLAN-2 상수 인용), ④ pending·failed 주문은 집계 제외.
class Admins::RevenueStatsQueryTest < ActiveSupport::TestCase
  test "당월·누적 매출과 MRR을 집계한다 (ADMIN-5)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      clear_domain_tables
      User.delete_all
      buyer = User.create!(email: "rev-buyer@example.com", password: "password")
      buyer.subscription.update!(plan: :plus, status: :active)
      buyer.orders.create!(product: :plus_monthly, amount: 9_900,
                           pg_order_id: "order-rev-m1", status: :paid,
                           paid_at: Time.zone.parse("2026-11-03 10:00"))
      buyer.orders.create!(product: :collection_pass, amount: 4_000,
                           pg_order_id: "order-rev-prev", status: :paid,
                           paid_at: Time.zone.parse("2026-10-20 10:00"))
      buyer.orders.create!(product: :collection_pass, amount: 4_000,
                           pg_order_id: "order-rev-pending") # pending — 제외
      buyer.orders.create!(product: :collection_pass, amount: 4_000,
                           pg_order_id: "order-rev-failed", status: :failed) # failed — 제외

      row = Admins::RevenueStatsQuery.call

      assert_equal 9_900, row.month_revenue
      assert_equal 13_900, row.total_revenue
      assert_equal Subscription::PLUS_MONTHLY_PRICE, row.mrr
      assert_equal 9_900, row.mrr
    end
  end

  test "환불 기록 주문은 매출 집계에서 제외된다 (ADMIN-4·3-S — 리뷰 제안 2)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      clear_domain_tables
      User.delete_all
      buyer = User.create!(email: "rev-refund@example.com", password: "password")
      order = buyer.orders.create!(product: :plus_monthly, amount: 9_900,
                                   pg_order_id: "order-rev-ref", status: :paid,
                                   paid_at: Time.zone.parse("2026-11-01 10:00"))

      before = Admins::RevenueStatsQuery.call
      assert_equal 9_900, before.month_revenue

      order.mark_refunded!("이중 결제 정정")

      after = Admins::RevenueStatsQuery.call
      assert_equal 0, after.month_revenue, "환불 기록 후 당월 매출에서 제외되어야 한다"
      assert_equal 0, after.total_revenue
    end
  end

  test "MRR은 cancelled Plus 구독을 제외한다 (PLAN-5 기간 말 자동 만료 정합)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      clear_domain_tables
      User.delete_all
      buyer = User.create!(email: "rev-mrr@example.com", password: "password")
      buyer.subscription.update!(plan: :plus, status: :cancelled)

      row = Admins::RevenueStatsQuery.call

      assert_equal 0, row.mrr, "cancelled는 active MRR에서 제외되어야 한다"
    end
  end

  test "서비스로 환불 실행한 Plus 주문은 매출에서 제외되고 MRR이 감소한다 (ADMIN-5·PLAN-9)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      clear_domain_tables
      User.delete_all
      buyer = User.create!(email: "rev-srv-refund@example.com", password: "password")
      buyer.subscription.update!(plan: :plus, status: :active)
      order = buyer.orders.create!(product: :plus_monthly, amount: 9_900,
                                   pg_order_id: "order-rev-srv", status: :paid,
                                   pg_payment_id: "pay-rev-srv",
                                   paid_at: Time.zone.parse("2026-11-03 10:00"))
      assert_equal 9_900, Admins::RevenueStatsQuery.call.mrr, "전제: 환불 전 MRR 포함"

      result = Orders::RefundService.new(
        admin: admins(:ops), order: order, reason: "이중 결제 정정",
        client: FakePortOneClient.new(get_payment: { id: order.pg_order_id, status: "CANCELLED",
                                                     amount: { paid: order.amount,
                                                               cancelled: order.amount } })
      ).call
      assert result.success?, "전제: 환불 실행이 성공해야 한다"

      row = Admins::RevenueStatsQuery.call
      assert_equal 0, row.month_revenue, "환불 실행 건(status cancelled·refunded_at)은 매출에서 제외"
      assert_equal 0, row.total_revenue
      assert_equal 0, row.mrr, "구독 즉시 Free 전환으로 MRR이 감소한다"
    end
  end

  test "매출·MRR이 모두 비어 있으면 0이다 (빈 데이터)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      clear_domain_tables
      User.delete_all

      row = Admins::RevenueStatsQuery.call

      assert_equal 0, row.month_revenue
      assert_equal 0, row.total_revenue
      assert_equal 0, row.mrr
    end
  end
end
