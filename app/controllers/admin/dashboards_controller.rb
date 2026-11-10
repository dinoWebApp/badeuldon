# 관리자 운영 대시보드(ADMIN-1·5) — Run B: 쿼리 오브젝트 5종으로 실데이터 지표 확장.
# 컨트롤러는 호출 위임만(규약 §3.2 — 집계는 app/queries/admins/ 소관, 뷰는 @변수만 소비).
class Admin::DashboardsController < Admin::BaseController
  def show
    load_metrics
  end

  private

  def load_metrics
    @user_count = User.count
    @unsettled_invoice_count = Invoice.unsettled.count
    @today_message_count = MessageLog.sent.where(created_at: Time.current.all_day).count
    @signup_stats = Admins::SignupStatsQuery.call
    @collection_stats = Admins::CollectionStatsQuery.call
    @plan_funnel = Admins::PlanFunnelQuery.call
    @message_stats = Admins::MessageStatsQuery.call
    @revenue_stats = Admins::RevenueStatsQuery.call
  end
end
