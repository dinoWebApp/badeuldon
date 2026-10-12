# 프로필 설정(AUTH-1.3) — 표면 ② 첫 화면. ApplicationController 기본 가드(require_authentication)의
# 첫 실전 적용: 비인증 접근은 로그인 화면으로 리다이렉트된다.
class App::ProfilesController < ApplicationController
  def edit
    @user = Current.user
  end

  def update
    @user = Current.user
    @user.assign_attributes(profile_params)
    if @user.save(context: :profile)
      # 완료 후 임시 완료 화면(가입 완료 화면)으로 안내 — /app 대시보드 본체는 후속 작업
      redirect_to welcome_path, status: :see_other, notice: "프로필 설정이 완료되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.expect(user: [ :display_name, :business_type, :bank_name, :account_number, :account_holder, :phone ])
  end
end
