# 표면 ② 리포트(/app/report) — DASH-5 거래처별 지연·월간 수금 추이, DASH-6 신고 주기 집계.
# 집계는 app/queries/reports/의 Query Object로 위임하고 컨트롤러는 @변수 조립만 한다(규약 §3.2).
class App::ReportsController < App::BaseController
  def show
    @user = Current.user
    @has_invoices = @user.invoices.exists?
    @client_delay_rows = Reports::ClientDelayQuery.call(@user.id)
    @monthly_rows = Reports::MonthlyCollectionQuery.call(@user.id)
    @tax_rows = Reports::TaxPeriodQuery.call(@user.id)
    @this_month_collected = @monthly_rows.last&.amount.to_i  # DASH-3 문구 정합 — 이번 달 수금액
  end
end
