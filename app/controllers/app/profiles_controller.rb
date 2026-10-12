# 프로필 설정(AUTH-1.3). App::BaseController의 프로필 완료 가드를 건너뛴다 —
# 이 화면 자체가 미완료 사용자가 완료해야 할 첫 화면이므로.
class App::ProfilesController < App::BaseController
  skip_before_action :require_complete_profile

  def edit
    @user = Current.user
  end

  def update
    @user = Current.user
    @user.assign_attributes(profile_params)
    if @user.save(context: :profile)
      # 완료 후 /app 대시보드로 안내 — welcome 임시 화면은 /app 셸로 대체되어 제거됨(플랜 A-3)
      redirect_to app_root_path, status: :see_other, notice: "프로필 설정이 완료되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.expect(user: [ :display_name, :business_type, :bank_name, :account_number, :account_holder, :phone ])
  end
end
