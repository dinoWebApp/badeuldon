# ADMIN-3 회원 관리(Run B) — 목록·검색·상세·플랜 수동 변경·정지/해제.
# 행위 감사 기록은 Admins::MemberAdminService 내부에서 AuditLogs::RecordService 경유로 수행한다.
class Admin::MembersController < Admin::BaseController
  def index
    @users = filtered_users.includes(:subscription).order(created_at: :desc).limit(100) # W-3 N+1 방지
  end

  def show
    @user = User.find(params[:id])
    @invoice_count = @user.invoices.where.not(status: :draft).count
    @unsettled_amount = @user.invoices.unsettled.sum(:total_amount)
    @message_logs = MessageLog.where(user_id: @user.id).order(created_at: :desc).limit(10)
    @inquiries = Promise.joins(:invoice).where(invoices: { user_id: @user.id }, kind: :inquiry)
                        .order(created_at: :desc).limit(5)
    @audit_logs = AuditLog.where(target_type: "User", target_id: @user.id).recent.limit(10)
  end

  def toggle_suspension
    result = Admins::MemberAdminService.toggle_suspension!(admin: current_admin, user: User.find(params[:id]))
    redirect_to admin_member_path(params[:id]), status: :see_other,
                notice: (result.message if result.success?),
                alert: (result.errors.first unless result.success?)
  end

  def change_plan
    result = Admins::MemberAdminService.change_plan!(
      admin: current_admin, user: User.find(params[:id]), plan_params: plan_change_params
    )
    redirect_to admin_member_path(params[:id]), status: :see_other,
                notice: (result.message if result.success?),
                alert: (result.errors.first unless result.success?)
  end

  # ADMIN-3 ④ 계정 삭제·데이터 파기(Q13) — Admins::AccountPurgeService가 가드(2중 확인·미수 차단)와
  # 트랜잭션 삭제를 담당한다. 성공은 목록으로, 실패는 상세로 되돌린다(가드 사유 alert).
  def destroy
    result = Admins::AccountPurgeService.call(
      admin: current_admin, user: User.find(params[:id]), confirm_email: params[:confirm_email]
    )
    if result.success?
      redirect_to admin_members_path, status: :see_other, notice: result.message
    else
      redirect_to admin_member_path(params[:id]), status: :see_other, alert: result.errors.first
    end
  end

  private

  def filtered_users
    scope = User.left_joins(:subscription)
    scope = scope.where("display_name LIKE :q OR email LIKE :q", q: "%#{params[:q].strip}%") if params[:q].present?
    scope = scope.where(users: { status: params[:status] }) if params[:status].present?
    scope = scope.where(subscriptions: { plan: params[:plan] }) if params[:plan].present?
    scope
  end

  def plan_change_params
    params.expect(plan_change: [ :action, :months ])
  end
end
