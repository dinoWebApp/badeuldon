# 회원가입 — AUTH-1(이메일/비밀번호), 가입 즉시 활성화(이메일 인증 링크 없음)
class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_registration_path, alert: "너무 많은 요청이 있었습니다. 잠시 후 다시 시도해 주세요." }

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)
    if @user.save
      start_new_session_for @user
      redirect_to welcome_path, status: :see_other, notice: "회원가입이 완료되었습니다. 받을돈에 오신 것을 환영합니다!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  # 가입 직후 임시 안내 화면 — 프로필(AUTH-1.3) 미설정 시 설정 안내, 설정 완료 시 완료 화면
  def welcome
    @user = Current.user
  end

  private

  def registration_params
    params.expect(user: [ :email, :password, :password_confirmation ])
  end
end
