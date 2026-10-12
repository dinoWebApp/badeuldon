# 비밀번호 재설정(AUTH-8) — 이메일로 1회성 만료 링크 발송(has_secure_password reset token, 15분).
# 발송 서비스는 EXT 표 미확정 — Action Mailer 기본 발송(개발 환경 로그), 실발송 연결은 후속 작업.
class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_password_path, alert: "너무 많은 요청이 있었습니다. 잠시 후 다시 시도해 주세요." }

  def new
  end

  # 가입 여부와 무관하게 동일 응답 — 사용자 열거 방지
  def create
    if user = User.find_by(email: params.expect(:email))
      PasswordsMailer.reset(user).deliver_later
    end
    redirect_to new_session_path, status: :see_other, notice: "비밀번호 재설정 안내를 이메일로 보냈습니다. (가입된 이메일인 경우)"
  end

  def edit
  end

  def update
    if @user.update(password_params)
      @user.sessions.destroy_all
      redirect_to new_session_path, status: :see_other, notice: "비밀번호가 변경되었습니다. 새 비밀번호로 로그인해 주세요."
    else
      flash.now[:alert] = "비밀번호를 확인해 주세요."
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_user_by_token
    @user = User.find_by_password_reset_token!(params[:token])
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to new_password_path, alert: "비밀번호 재설정 링크가 만료되었거나 잘못되었습니다."
  end

  def password_params
    password, password_confirmation = params.expect(:password, :password_confirmation)
    { password:, password_confirmation: }
  end
end
