module Reports
  # DASH-5 — 월간 수금 추이. 최근 12개월(이번 달 포함 소급)의 입금액(Payment paid_on 기준 —
  # 02_prd_update 확정)을 월별 집계한다. 그래프 축 고정을 위해 빈 달은 0원으로 채워
  # 항상 12행을 반환한다. 소유권은 청구서의 user_id로 격리한다.
  class MonthlyCollectionQuery
    MONTHS = 12

    Row = Struct.new(:month, :label, :amount, keyword_init: true)

    def self.call(user_id)
      current = Date.current  # TIME-1 — KST 기준
      start_month = Date.new(current.year, current.month) << (MONTHS - 1)
      range = start_month..current

      sums = Payment.joins(:invoice)
                    .where(invoices: { user_id: }, paid_on: range)
                    .group(Arel.sql("strftime('%Y-%m', payments.paid_on)"))
                    .sum(:amount)

      (0...(MONTHS)).map do |offset|
        month = start_month >> offset
        key = month.strftime("%Y-%m")
        Row.new(month:, label: month.strftime("%Y.%m"), amount: sums.fetch(key, 0))
      end
    end
  end
end
