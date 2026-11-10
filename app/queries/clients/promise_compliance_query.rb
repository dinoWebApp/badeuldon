module Clients
  # CLIENT-3·PROMISE-5 — 거래처 약속 이행 이력 목록. 각 청구(운영 약속 보유)를 결정 기록 Q14의
  # 파생 계산 3상태(이행·미이행·판정 중)로 분류해 최신 약속순으로 반환한다. 판정 정의는
  # PaymentScorecardQuery(같은 도메인 쿼리 — 단일 출처)의 주석과 동일하며, 상태 키는
  # 3종(fulfilled·broken·pending)뿐이다. 규약 §3.2 — 뷰는 반환 행만 소비한다.
  class PromiseComplianceQuery
    Row = Struct.new(:invoice_id, :issue_number, :total_amount, :promised_on,
                     :status_key, :closing_paid_on, keyword_init: true)

    STATUS_KEYS = %w[ fulfilled broken pending ].freeze

    def self.call(client:, today: Date.current)
      # CLIENT-3·PROMISE-5·Q14·P1 — 모집단은 PaymentScorecardQuery(이행률·평균 지연일)와 동일
      # 발행 계열(draft·voided 제외 — INV-6 무효는 미청구 취급)로 한정한다. 목록과 성적표가
      # 같은 모집단이어야 화면의 이행률과 이력 행이 모순되지 않고, "채권자가 무효화한 청구의
      # 약속이 채무자 영구 미이행으로 기록되는" 표기를 원천 차단한다(P1 — 관계 보존 최우선).
      client_scope = Invoice.where(client_id: client.id, user_id: client.user_id)
                           .where.not(status: [ :draft, :voided ])
      closing_paid = Payment.where(invoice_id: client_scope.select(:id))
                            .group(:invoice_id).maximum(:paid_on)

      client_scope.joins(PaymentScorecardQuery::OPERATIVE_PROMISE_JOIN)
                  .order("promises.promised_on DESC", "invoices.id DESC")
                  .select("invoices.id", "invoices.issue_number", "invoices.total_amount",
                          "invoices.status", "promises.promised_on")
                  .map do |invoice|
        closing = closing_paid[invoice.id]
        Row.new(
          invoice_id: invoice.id,
          issue_number: invoice.issue_number,
          total_amount: invoice.total_amount,
          promised_on: invoice.promised_on,
          status_key: status_key(invoice.status, invoice.promised_on, closing, today),
          closing_paid_on: closing
        )
      end
    end

    # Q14 파생 판정 — 이행(paid && 마감 입금일 ≤ 약속일)·판정 중(unsettled && 약속일 도과 전)·
    # 미이행(나머지: 도과 후 미수 또는 도과 후 입금 — Q14 3분류 배타 귀결). 호출 스코프가
    # 발행 계열로 한정돼 있으므로 status는 issued~partially_paid·paid만 들어온다(C-1 —
    # voided·draft의 약속은 판정 자체를 하지 않는다).
    def self.status_key(status, promised_on, closing_paid_on, today)
      if status == "paid"
        closing_paid_on <= promised_on ? "fulfilled" : "broken"
      elsif promised_on < today
        "broken"
      else
        "pending"
      end
    end
  end
end
