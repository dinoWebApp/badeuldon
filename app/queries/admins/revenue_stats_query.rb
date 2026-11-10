module Admins
  # ADMIN-5 — 매출·MRR. 매출 = Order.paid 합계(paid_at 기준 당월·누적).
  # 환불 기록 주문 제외(ADMIN-4·3-S 통합 — T-B3 마이그레이션 적용 완료).
  # MRR = active Plus 구독 수 × Subscription::PLUS_MONTHLY_PRICE(PLAN-2 상수 인용).
  # cancelled는 active만 포함 권고(01_plan 리스크)에 따라 제외 — 해지는 기간 말 자동 만료.
  class RevenueStatsQuery
    Row = Struct.new(:month_revenue, :total_revenue, :mrr, keyword_init: true)

    def self.call
      paid_orders = Order.paid.not_refunded # 환불 기록 주문 제외 — ADMIN-4·3-S 통합
      Row.new(
        month_revenue: paid_orders.where(paid_at: Date.current.beginning_of_month..).sum(:amount),
        total_revenue: paid_orders.sum(:amount),
        mrr: Subscription.active.where(plan: :plus).count * Subscription::PLUS_MONTHLY_PRICE
      )
    end
  end
end
