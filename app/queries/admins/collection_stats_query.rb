module Admins
  # ADMIN-5 — 청구 발행·수금 마감 통계 + 북극성 지표.
  # 발행 계열 = draft·voided 제외(inv4 상태 모집단). 수금 마감 = status paid.
  # 마감일은 청구별 최종 입금일(payments MAX(paid_on) — 부분입금 행 가중 방지, v0.28 DASH-5 패턴).
  # 북극성 = "발행 후 30일 내 수금 완료율": paid 청구 중 (마감 paid_on − 발행일) ≤ 30일 비율.
  # 마감 건이 없으면(분모 0) north_star_rate는 nil — 뷰는 "-" 표기.
  class CollectionStatsQuery
    Row = Struct.new(:month_issued, :total_issued, :month_closed, :total_closed,
                     :month_closed_amount, :total_closed_amount, :north_star_rate,
                     keyword_init: true)

    def self.call
      issued_scope = Invoice.where.not(status: [ :draft, :voided ])
      paid_scope = Invoice.where(status: :paid)
      closing_payments = Payment.select("invoice_id, MAX(paid_on) AS paid_on")
                                .where(invoice_id: paid_scope.select(:id))
                                .group(:invoice_id)
      closed = paid_scope.joins(
        "INNER JOIN (#{closing_payments.to_sql}) closing_payments " \
        "ON closing_payments.invoice_id = invoices.id"
      )
      within_30 = closed.where(
        "julianday(closing_payments.paid_on) - julianday(invoices.issued_at) <= 30"
      )

      total_closed = closed.count
      Row.new(
        month_issued: issued_scope.where(issued_at: Date.current.beginning_of_month..).count,
        total_issued: issued_scope.count,
        month_closed: closed.where("closing_payments.paid_on >= ?", Date.current.beginning_of_month).count,
        total_closed: total_closed,
        month_closed_amount: month_closed_amount(closed),
        total_closed_amount: Payment.where(invoice_id: paid_scope.select(:id)).sum(:amount),
        north_star_rate: total_closed.zero? ? nil : (within_30.count * 100.0 / total_closed).round(1)
      )
    end

    def self.month_closed_amount(closed)
      Payment.joins(:invoice)
             .where(invoices: { status: :paid },
                    paid_on: Date.current.beginning_of_month..)
             .sum(:amount)
    end
  end
end
