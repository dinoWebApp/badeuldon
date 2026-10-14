# 회원가입 — AUTH-1(이메일/비밀번호), 가입 즉시 활성화(이메일 인증 링크 없음)
class RegistrationsController < ApplicationController
  # VIEW-1 — 인증 진입 화면도 공개 표면: 구형·인앱 브라우저 허용(AllowAllBrowsers).
  include AllowAllBrowsers
  allow_unauthenticated_access only: %i[ new create ]
  before_action :redirect_if_authenticated, only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_registration_path, alert: "너무 많은 요청이 있었습니다. 잠시 후 다시 시도해 주세요." }

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)
    if @user.save
      start_new_session_for @user
      # 가입 직후 AUTH-1.3 최초 프로필 설정으로 안내 — welcome 임시 화면은 /app 셸로 대체되어 제거됨(플랜 A-3)
      redirect_to edit_app_profile_path, status: :see_other,
                  notice: "회원가입이 완료되었습니다. 받을돈에 오신 것을 환영합니다!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  # 로그인 사용자의 가입 화면 재진입을 /app 대시보드로 되돌린다(원클릭 복귀).
  def redirect_if_authenticated
    redirect_to app_root_url, status: :see_other if authenticated?
  end

  def registration_params
    params.expect(user: [ :email, :password, :password_confirmation ])
  end
end
