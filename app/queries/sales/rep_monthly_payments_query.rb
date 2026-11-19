module Sales
  # SALES-6 — 영업 직원 월별 결제 총액(대시보드 그래프 원천). 본인 유치 사용자의 Plus 월결제
  # (paid·환불 제외) 실차감액을 최근 12개월(이번 달 포함)로 집계한다. 수수료가 아니라
  # "유치 사용자 결제 총액"이며(수수료는 SalesCommission 스냅샷이 단일 소스), 역할 캡
  # (sales 12개월) 판정과 무관한 참고 지표다 — 스코프 격리는 rep의 referred_users로 보장.
  class RepMonthlyPaymentsQuery
    MONTHS = 12

    Row = Struct.new(:month, :label, :amount, keyword_init: true)

    def self.call(sales_rep_id)
      current = Date.current  # TIME-1 — KST 기준
      start_month = Date.new(current.year, current.month) << (MONTHS - 1)
      range = start_month..current

      sums = Order.joins(:user)
                  .where(users: { referred_by_sales_rep_id: sales_rep_id })
                  .plus_monthly.paid.not_refunded
                  .where(paid_at: month_range(start_month, current))
                  .group(Arel.sql("strftime('%Y-%m', orders.paid_at)"))
                  .sum(:amount)

      (0...(MONTHS)).map do |offset|
        month = start_month >> offset
        key = month.strftime("%Y-%m")
        Row.new(month:, label: month.strftime("%y.%m"), amount: sums.fetch(key, 0))
      end
    end

    def self.month_range(start_month, current)
      Time.zone.local(start_month.year, start_month.month, 1)..Time.current
    end
  end
end
