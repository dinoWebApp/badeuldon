module Clients
  # CLIENT-4 — 거래처 지급 성적표. "지연"은 약속일 대비(마감 건의 입금 paid_on − 약속일
  # promised_on)이며 만기일 대비인 DASH-5(Reports::ClientDelayQuery)와 정의가 다르다 —
  # 화면에서도 "약속일 대비" 부제로 구분 표기한다(02_prd_update 확정 5).
  # 이행 판정은 결정 기록 Q14의 파생 계산(별도 기록 컬럼 없음 — PROMISE-5):
  #   이행     = paid && 마감 입금일 ≤ 약속일
  #   미이행   = 약속일 도과 후 미수(unsettled && promised_on < today) 또는
  #              도과 후 입금(paid && 마감 입금일 > 약속일 — Q14 3분류의 배타 귀결)
  #   판정 중  = 약속 유효(unsettled && promised_on ≥ today)
  # 규약 §3.2 — 집계·그룹핑은 Query Object가 담당하고 뷰는 결과만 소비한다.
  class PaymentScorecardQuery
    Result = Struct.new(:total_invoiced_amount, :unsettled_count, :avg_delay_days,
                        :compliance_rate, :monthly_trend, :all_clients_avg_delay,
                        :clients_count, keyword_init: true)

    # Q14 — 청구별 운영 약속: 약속일이 있는 응답(this_week·date_selected) 중 최신 1건.
    # 최신 응답 기준 원칙(P4 — 재응답도 기존 레코드 유지·약속 표시는 최신 약속 기준)을
    # 쿼리로 구현한다. 상수 SQL 보간이라 파라미터가 없어 인젝션 위험이 없다.
    OPERATIVE_PROMISE_JOIN = <<~SQL.squish
      INNER JOIN (
        SELECT invoice_id, MAX(id) AS id FROM promises
        WHERE promised_on IS NOT NULL GROUP BY invoice_id
      ) operative_promises ON operative_promises.invoice_id = invoices.id
      INNER JOIN promises ON promises.id = operative_promises.id
    SQL

    TREND_MONTHS = 6  # CLIENT-4 — 최근 6개월 지급 경향

    # 인자: client(소유권은 컨트롤러가 Current.user 스코프로 격리). 시간 판정은 KST
    # Date.current(TIME-1) — 테스트 주입을 위해 today 키워드를 둔다.
    # 반환: Result(avg_delay_days·compliance_rate는 약속 없는 거래처에서 nil — 뷰는 "-" 표기·배지 미노출).
    def self.call(client:, today: Date.current)
      client_scope = Invoice.where(client_id: client.id, user_id: client.user_id)
      user_scope = Invoice.where(user_id: client.user_id)

      new(client, client_scope, user_scope, today).call
    end

    def initialize(client, client_scope, user_scope, today)
      @client = client
      @client_scope = client_scope
      @user_scope = user_scope
      @today = today
    end

    def call
      Result.new(
        total_invoiced_amount: total_invoiced_amount,
        unsettled_count: @client_scope.unsettled.count,
        avg_delay_days: avg_delay_days(@client_scope),
        compliance_rate: compliance_rate,
        monthly_trend: monthly_trend,
        all_clients_avg_delay: avg_delay_days(@user_scope),
        clients_count: @client.user.clients.count
      )
    end

    private

    # 누적 청구액 — 발행 계열(draft·voided 제외) 합계. 초안은 미확정, 무효는 INV-6 폐기다.
    def total_invoiced_amount
      @client_scope.where.not(status: [ :draft, :voided ]).sum(:total_amount)
    end

    # 평균 지급 지연일 — 마감(paid) 건 중 약속이 있었던 청구만. 청구별 마감(최종) 입금일
    # (payments MAX paid_on — PAY-1/2·부분입금 행 가중 방지)을 서브쿼리로 한정해 행 가중을
    # 막는다(DASH-5 리뷰 C-1 선례와 동일 패턴). 음수는 조기 입금. 약속 없는 거래처는 nil.
    def avg_delay_days(scope)
      promise_paid_closing(scope)
          .average("CAST(julianday(closing_payments.paid_on) AS INTEGER) - CAST(julianday(promises.promised_on) AS INTEGER)")
          &.round
    end

    # 약속 이행률(%) — 판정이 확정된 약속 건(이행+미이행) 중 이행 비율. 판정 중은 분모에서
    # 제외하며 확정 건이 없으면 nil(뷰 "-"·배지 미노출).
    def compliance_rate
      fulfilled = promise_paid_closing(@client_scope)
                      .where("julianday(closing_payments.paid_on) <= julianday(promises.promised_on)").count
      broken = @client_scope.unsettled
                            .joins(OPERATIVE_PROMISE_JOIN)
                            .where("promises.promised_on < ?", @today).count +
               promise_paid_closing(@client_scope)
                   .where("julianday(closing_payments.paid_on) > julianday(promises.promised_on)").count
      decided = fulfilled + broken
      return nil if decided.zero?

      (fulfilled * 100.0 / decided).round
    end

    # 최근 6개월 월별 평균 지급 지연일 — 마감 입금월 기준 그룹핑. 부분입금은 마감월로 귀속된다
    # (PAY-1 최종 입금일 기준). 월 경계 밖 마감 건은 버리고, 해당 월 마감이 없으면 nil 채운다.
    def monthly_trend
      first_month = @today.beginning_of_month - (TREND_MONTHS - 1).months
      averages = promise_paid_closing(@client_scope)
                     .where("closing_payments.paid_on >= ?", first_month)
                     .group("strftime('%Y-%m', closing_payments.paid_on)")
                     .average("CAST(julianday(closing_payments.paid_on) AS INTEGER) - CAST(julianday(promises.promised_on) AS INTEGER)")

      (0...TREND_MONTHS).map do |offset|
        month = (@today.beginning_of_month - offset.months)
        [ month.strftime("%Y-%m"), averages[month.strftime("%Y-%m")]&.round ]
      end.reverse
    end

    # 마감(paid) + 약속 보유 + 청구별 마감 입금일 결합 scope — 위 지표들의 공통 모집단.
    def promise_paid_closing(scope)
      closing = Payment.select("invoice_id, MAX(paid_on) AS paid_on")
                       .where(invoice_id: scope.where(status: :paid).select(:id))
                       .group(:invoice_id)

      scope.where(status: :paid)
           .joins(OPERATIVE_PROMISE_JOIN)
           .joins("INNER JOIN (#{closing.to_sql}) closing_payments ON closing_payments.invoice_id = invoices.id")
    end
  end
end
