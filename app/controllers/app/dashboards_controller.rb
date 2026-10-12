# 표면 ② 대시보드 — DASH-1 요약 실데이터, DASH-4 목록(연체일 내림차순 상위 N),
# ONB-1 CTA. 집계는 Invoice 스코프 조합으로 컨트롤러에서 산출하고 뷰는 @변수만 소비한다.
class App::DashboardsController < App::BaseController
  DASHBOARD_LIST_COUNT = 5

  def show
    @user = Current.user
    invoices = @user.invoices

    @has_invoices = invoices.exists?
    @unsettled_total = invoices.unsettled.sum(:total_amount)                 # DASH-1 미수 총액
    overdue_scope = invoices.overdue                                         # DASH-1 연체(파생 판정)
    @overdue_count = overdue_scope.count
    @overdue_total = overdue_scope.sum(:total_amount)
    @due_soon_count = invoices.due_within(Date.current..Date.current + 7).count  # 7일 내 만기
    @invoices = invoices.includes(:client).sorted_by_due.limit(DASHBOARD_LIST_COUNT)  # DASH-4
  end
end
