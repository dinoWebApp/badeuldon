module App
  # 표면 ②(/app) 공통 베이스 — 인증은 ApplicationController 가드(require_authentication)를 상속하고,
  # 프로필 미완료(AUTH-1.3 표시명 미설정) 사용자는 최초 프로필 설정 화면으로 안내한다.
  # 표면 ② 전용 레이아웃(app — 사이드바·헤더)을 공통 적용한다.
  class BaseController < ApplicationController
    layout "app"

    before_action :require_complete_profile

    private

    # AUTH-1.3 — 청구서 발행에 표시명·계좌가 필요하므로 미설정 사용자는 프로필 설정을 먼저 완료한다.
    def require_complete_profile
      redirect_to edit_app_profile_path if Current.user.display_name.blank?
    end
  end
end
