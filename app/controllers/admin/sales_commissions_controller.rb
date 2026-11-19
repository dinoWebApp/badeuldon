# SALES-5 — 수수료 정산 목록 콘솔. 연월 필터로 스냅샷을 열람하고 지급 처리(mark paid)는
# 상태 전이라 member PATCH로 수행한다(감사 전건 — ADMIN-2). 지급 자체(계좌 이체·원천징수
# 3.3% 공제)는 오프라인이며 이 콘솔은 상태 기록만 담당한다(Q24).
class Admin::SalesCommissionsController < Admin::BaseController
  def index
    @year = filter_year
    @month = params[:month].presence&.to_i
    scope = SalesCommission.for_year(@year).ordered.includes(:sales_rep)
    scope = scope.for_month(@year, @month) if @month
    @commissions = scope
    @pending_total = scope.pending.sum(:amount)
    @paid_total = scope.where(status: :paid).sum(:amount)
  end

  def mark_paid
    commission = SalesCommission.find(params[:id])
    if commission.mark_paid!
      AuditLogs::RecordService.call(admin: current_admin, action: "commission_marked_paid",
                                    target: commission,
                                    detail: "#{commission.sales_rep.email} · #{commission.period_label} · #{commission.amount}원",
                                    ip: request.remote_ip)
      redirect_to admin_sales_commissions_path(year: commission.year, month: commission.month),
                  status: :see_other, notice: "지급 처리했습니다."
    else
      redirect_to admin_sales_commissions_path(year: commission.year, month: commission.month),
                  status: :see_other, alert: "이미 지급 처리된 정산입니다."
    end
  end

  private

  # 연도 필터 — 기본 당해년(직전월 집계분 포함). 조작 입력은 기본값으로 흡수한다.
  def filter_year
    year = params[:year].presence&.to_i
    year&.between?(2000, 2100) ? year : Date.current.year
  end
end
