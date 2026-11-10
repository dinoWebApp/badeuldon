# ADMIN-2 감사 로그 뷰(Run B) — 목록·필터(action·관리자·기간), 상한 100행 페이지네이션.
# 행위 기록은 각 관리 행위 컨트롤러·서비스가 RecordService 경유로 수행하며 이 컨트롤러는 읽기만 한다.
class Admin::AuditLogsController < Admin::BaseController
  PAGE_SIZE = 100

  def index
    scope = filtered_audit_logs
    @total_count = scope.count
    @page = [ params.fetch(:page, 1).to_i, 1 ].max
    @audit_logs = scope.limit(PAGE_SIZE).offset((@page - 1) * PAGE_SIZE)
    @admins = Admin.order(:email).pluck(:email, :id) # W-4 — 뷰 쿼리 금지(컨트롤러에서 로드)
  end

  private

  def filtered_audit_logs
    AuditLog.recent
            .by_action(params[:action_filter])
            .by_admin(params[:admin_id])
            .by_period(params[:from], params[:to])
  end
end
