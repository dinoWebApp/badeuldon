# 영업 직원 대시보드(SALES-6 — /sales 루트). 모든 집계는 로그인 본인(rep)의 연관만 소비한다
# — 타 rep 데이터 접근이 성립하지 않는 스코프 격리(SALES-7). 결제 총액 그래프는 Query Object
# (Sales::RepMonthlyPaymentsQuery), 수수료는 SalesCommission 스냅샷(단일 소스)만 조회한다.
class Sales::DashboardsController < Sales::BaseController
  def show
    @rep = current_sales_rep
    @current_code = @rep.current_referral_code
    @referred_users = @rep.referred_users.order(created_at: :desc).limit(30)
    # W-3 — 목록은 최근 30명이지만 표기 총원은 별도 count로 산출한다(31명 이상 유치 시
    # limit(30).size로는 과소 표시). 단일 count 쿼리 — 목록 렌더와 N+1 없음.
    @referred_users_count = @rep.referred_users.count
    @monthly_rows = Sales::RepMonthlyPaymentsQuery.call(@rep.id)
    @latest_commission = @rep.sales_commissions.ordered.last
    @year_total = @rep.sales_commissions.for_year(Date.current.year).sum(:amount)
    @total_amount = @rep.sales_commissions.sum(:amount)
  end
end
