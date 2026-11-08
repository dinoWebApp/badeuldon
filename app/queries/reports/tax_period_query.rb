module Reports
  # DASH-6 — 신고 주기(1·4·7·10월 확정신고 시즌)별 집계표. 최근 4개 분기를 직전 분기
  # 확정신고 시기로 매핑한다(02_prd_update 확정 — 예정신고는 범위 밖):
  #   1~3월 → "4월 확정신고" · 4~6월 → "7월" · 7~9월 → "10월" · 10~12월 → "익년 1월"
  # 매출(공급가액 subtotal·부가세)은 청구 발생(issued_at, draft·voided 제외 — INV-1),
  # 수금액은 입금 시점(Payment paid_on) 기준 — 두 컬럼은 기준이 다르므로 절대 섞지 않는다.
  class TaxPeriodQuery
    QUARTERS = 4

    # quarter_start부터 3개월 단위 분기. 월 1·4·7·10에 시작한다.
    Row = Struct.new(:label, :period_label, :revenue, :tax_amount, :collected,
                     :start, :finish, keyword_init: true)

    def self.call(user_id)
      current_quarter = Date.new(Date.current.year, quarter_start_month(Date.current))
      rows = (0...(QUARTERS)).map do |offset|
        start = current_quarter << (3 * (QUARTERS - 1 - offset))
        finish = (start >> 3) - 1
        Row.new(label: filing_label(start), period_label: period_label(start, finish),
                revenue: 0, tax_amount: 0, collected: 0, start:, finish:)
      end

      fill_revenue!(rows, user_id)
      fill_collected!(rows, user_id)
      rows
    end

    def self.quarter_start_month(date)
      ((date.month - 1) / 3) * 3 + 1
    end

    # 확정신고 시기 라벨 — 분기 종료의 다음 달(1·4·7·10월). 10~12월 분기는 익년 1월.
    def self.filing_label(quarter_start)
      filing_month = quarter_start >> 3
      label = "#{filing_month.month}월"
      filing_month.year > quarter_start.year ? "익년 #{label} 확정신고" : "#{label} 확정신고"
    end

    def self.period_label(start, finish)
      "#{start.strftime('%Y-%m-%d')} ~ #{finish.strftime('%Y-%m-%d')}"
    end

    # 매출·부가세 — 발행 계열(issued_at 기준, draft·voided 제외)의 subtotal·tax_amount 합.
    def self.fill_revenue!(rows, user_id)
      scope = Invoice.where(user_id:).where.not(status: [ :draft, :voided ])
      rows.each do |row|
        sums = scope.where(issued_at: row.start.beginning_of_day..row.finish.end_of_day)
                    .pick(Arel.sql("SUM(subtotal), SUM(tax_amount)")) || [ 0, 0 ]
        row.revenue = sums.first.to_i
        row.tax_amount = sums.last.to_i
      end
    end

    # 수금액 — 분기 내 입금일(Payment paid_on) 기준 합계. 매출과 기준이 다른 별도 집계다.
    def self.fill_collected!(rows, user_id)
      sums = Payment.joins(:invoice)
                    .where(invoices: { user_id: })
                    .group(Arel.sql("strftime('%Y-%m', payments.paid_on)"))
                    .sum(:amount)
      rows.each do |row|
        row.collected = month_keys(row.start, row.finish).sum { |key| sums.fetch(key, 0) }
      end
    end

    def self.month_keys(start, finish)
      keys = []
      month = Date.new(start.year, start.month)
      while month <= finish
        keys << month.strftime("%Y-%m")
        month >>= 1
      end
      keys
    end
  end
end
