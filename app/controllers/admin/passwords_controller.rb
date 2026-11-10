# 관리자 비밀번호 재설정(AUTH-7.6) — U1 PasswordsController(AUTH-8) 패턴 준용.
# 1회성 토큰(15분) + 재설정 성공 시 admin_sessions 전부 파기 + password_reset 감사 기록.
class Admin::PasswordsController < Admin::BaseController
  skip_before_action :require_admin_session
  before_action :set_admin_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_admin_password_path, alert: "너무 많은 요청이 있었습니다. 잠시 후 다시 시도해 주세요." }

  def new
  end

  # 가입 여부와 무관하게 동일 응답 — 관리자 존재 열거 방지.
  # Rails 8.1 has_secure_password reset token은 getter(admin.password_reset_token)가
  # 자동 생성한다 — bang 메서드는 없다(B-2 · U1 PasswordsController 패턴 준용).
  def create
    if admin = Admin.find_by(email: params.expect(:email))
      AdminMailer.password_reset(admin, edit_admin_password_url(admin.password_reset_token)).deliver_later
    end
    redirect_to new_admin_session_path, status: :see_other,
                notice: "비밀번호 재설정 안내를 이메일로 보냈습니다. (가입된 이메일인 경우)"
  end

  def edit
  end

  def update
    if @admin.update(password_params)
      @admin.admin_sessions.destroy_all
      clear_pending_keys
      AuditLogs::RecordService.call(admin: @admin, action: "password_reset", ip: request.remote_ip)
      redirect_to new_admin_session_path, status: :see_other,
                  notice: "비밀번호가 변경되었습니다. 새 비밀번호로 로그인해 주세요."
    else
      flash.now[:alert] = "비밀번호를 확인해 주세요."
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_admin_by_token
    @admin = Admin.find_by_password_reset_token!(params[:token])
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to new_admin_password_path, alert: "비밀번호 재설정 링크가 만료되었거나 잘못되었습니다."
  end

  def password_params
    password, password_confirmation = params.expect(:password, :password_confirmation)
    { password:, password_confirmation: }
  end

  # W-8 — 재설정 성공 시 1단계 pending 키도 정리한다(도용 pending 쿠키 재사용 차단).
  def clear_pending_keys
    session.delete(:pending_admin_id)
    session.delete(:pending_admin_expires_at)
  end
end
