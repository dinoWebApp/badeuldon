# ADMIN-1·AUTH-7.2 — 관리자 계정 콘솔(T-C1). 목록은 admin 전원, 생성·role 변경·
# 잠금 해제는 owner 전용(ADMIN-1 "부여·해제는 최고 관리자만"). 행위 감사는
# Admins::RoleService 내부에서 AuditLogs::RecordService 경유로 수행한다.
class Admin::AdminsController < Admin::BaseController
  before_action :require_owner, except: %i[ index ]

  def index
    @admins = Admin.order(created_at: :asc)
    # 최근 로그인 표시용 — 목록에서의 N+1 방지를 위해 한 번의 집계 쿼리로 조회.
    @last_logins = AdminSession.group(:admin_id).maximum(:created_at)
  end

  def new
    @admin = Admin.new
  end

  def create
    result = Admins::RoleService.create_admin!(
      actor: current_admin, email: admin_params[:email],
      password: admin_params[:password], role: admin_params[:role]
    )
    if result.success?
      redirect_to admin_admins_path, status: :see_other, notice: result.message
    else
      # C-1 — 무효 롤(조작 입력)은 enum 할당 시 ArgumentError가 나므로 유효 롤에 한해 재할당한다.
      @admin = Admin.new(email: admin_params[:email])
      @admin.role = admin_params[:role] if Admin.roles.key?(admin_params[:role].to_s)
      flash.now[:alert] = result.errors.first
      render :new, status: :unprocessable_entity
    end
  end

  def change_role
    result = Admins::RoleService.change_role!(
      admin: Admin.find(params[:id]), actor: current_admin, role: admin_params[:role]
    )
    redirect_to admin_admins_path, status: :see_other,
                notice: (result.message if result.success?),
                alert: (result.errors.first unless result.success?)
  end

  def unlock
    result = Admins::RoleService.unlock!(admin: Admin.find(params[:id]), actor: current_admin)
    redirect_to admin_admins_path, status: :see_other,
                notice: (result.message if result.success?),
                alert: (result.errors.first unless result.success?)
  end

  private

  # ADMIN-1 owner 전용 가드 — staff 접근은 403 + admin_*_denied 감사(기록은 RoleService 경유).
  def require_owner
    return if current_admin.owner?

    Admins::RoleService.record_denied!(actor: current_admin,
                                       action: "admin_console_denied",
                                       detail: "owner 전용 관리자 콘솔에 staff가 접근했습니다: #{current_admin.email}")
    redirect_to admin_root_path, status: :see_other,
                alert: "이 작업은 최고 관리자(owner)만 수행할 수 있습니다."
  end

  def admin_params
    params.expect(admin: [ :email, :password, :role ])
  end
end
