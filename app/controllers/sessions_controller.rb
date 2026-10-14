# 로그인/로그아웃 — AUTH-1(이메일/비밀번호), AUTH-1.6(재인증 = 비밀번호 재로그인)
class SessionsController < ApplicationController
  # VIEW-1 — 인증 진입 화면도 공개 표면: 구형·인앱 브라우저 허용(AllowAllBrowsers).
  include AllowAllBrowsers
  allow_unauthenticated_access only: %i[ new create ]
  before_action :redirect_if_authenticated, only: :new
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_session_path, alert: "너무 많은 시도가 있었습니다. 잠시 후 다시 시도해 주세요." }

  def new
  end

  def create
    email, password = session_params
    if user = User.authenticate_by(email:, password:)
      start_new_session_for user
      redirect_to after_authentication_url, status: :see_other, notice: "로그인되었습니다."
    else
      flash.now[:alert] = "이메일 또는 비밀번호가 올바르지 않습니다."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other, notice: "로그아웃되었습니다."
  end

  private

  # 로그인 사용자의 로그인 화면 재진입을 /app 대시보드로 되돌린다(원클릭 복귀). create는 재로그인을 허용하기 위해 가드하지 않는다.
  def redirect_if_authenticated
    redirect_to app_root_url, status: :see_other if authenticated?
  end

  def session_params
    params.expect(:email, :password)
  end
end
