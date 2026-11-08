module Reports
  # DASH-5 — 거래처별 지연 리포트. "지연"은 만기일 대비 실입금일(마감 건의 입금 paid_on −
  # 청구 due_on)이며 CLIENT-4(약속일 대비·거래처 카드)와는 정의가 다르다(02_prd_update 확정 3).
  # 연체 금액은 잔액 기준(F-PAY 재계산 — 총액 − 입금 합계)으로 산출한다.
  # 규약 §3.2 — 집계·그룹핑은 Query Object가 담당하고 뷰는 결과 행만 소비한다.
  class ClientDelayQuery
    Row = Struct.new(:client_name, :unsettled_count, :overdue_count,
                     :overdue_amount, :avg_delay_days, keyword_init: true)

    # 인자는 소유권 격리를 위한 user_id(스칼라 — TIME-1 KST Date.current 기준 판정).
    # 반환: 거래처명 순 정렬 Row 배열(거래처가 있으면 항상 1행 이상 — 지표는 0으로 채움).
    def self.call(user_id)
      overdue_scope = Invoice.unsettled.where(user_id:).overdue

      unsettled_counts = Invoice.unsettled.where(user_id:).group(:client_id).count
      overdue_counts = overdue_scope.group(:client_id).count
      overdue_totals = overdue_scope.group(:client_id).sum(:total_amount)
      overdue_paid = Payment.where(invoice_id: overdue_scope.select(:id))
                            .joins(:invoice).group("invoices.client_id").sum(:amount)
      # 평균 지급 지연일 — 수금완료(paid) 건의 마감(최종) 입금일 대비 만기일. 음수는 조기 입금을 의미한다.
      # 마감 건 기준 — 부분입금 행 가중 방지(PRD v0.28 DASH-5·리뷰 C-1): 청구별 최종 paid_on만을
      # 서브쿼리로 한정한 뒤 청구 단위로 평균낸다(입금 행 수로 가중되지 않는다). 상수 SQL 보간이라
      # 파라미터가 없어 인젝션 위험이 없다.
      closing_payments = Payment.select("invoice_id, MAX(paid_on) AS paid_on")
                                .where(invoice_id: Invoice.where(user_id:, status: :paid).select(:id))
                                .group(:invoice_id)
      avg_delays = Invoice.joins("INNER JOIN (#{closing_payments.to_sql}) closing_payments ON closing_payments.invoice_id = invoices.id")
                          .where(user_id:)
                          .group(:client_id)
                          .average("CAST(julianday(closing_payments.paid_on) AS INTEGER) - CAST(julianday(invoices.due_on) AS INTEGER)")

      Client.where(user_id:).order(:name).map do |client|
        cid = client.id
        Row.new(
          client_name: client.name,
          unsettled_count: unsettled_counts[cid].to_i,
          overdue_count: overdue_counts[cid].to_i,
          overdue_amount: overdue_totals[cid].to_i - overdue_paid.fetch(cid, 0),
          avg_delay_days: avg_delays[cid]&.round
        )
      end
    end
  end
end
