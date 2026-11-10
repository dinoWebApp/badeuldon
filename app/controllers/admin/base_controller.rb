# 관리자 콘솔 공통 베이스(표면 ④ — AUTH-7·ADMIN-1). U1 Authentication 가드를 해제하고
# 별도 admin_sessions 토큰으로 가드한다(U1 세션과 절대 공유하지 않는다 — session[:admin_session_token]).
class Admin::BaseController < ApplicationController
  layout "admin"
  skip_before_action :require_authentication
  before_action :require_admin_session
  helper_method :current_admin

  private

  # AUTH-7.5 — 쿠키 토큰 → admin_session 조회 후 만료 재검증. 유효하면 활동 시각을
  # 갱신하고 Current.admin_session에 적재한다. 만료·무효면 세션 파기 후 로그인 화면으로.
  def require_admin_session
    admin_session = find_admin_session
    if admin_session
      admin_session.touch_activity!
      Current.admin_session = admin_session
    else
      terminate_admin_session
      redirect_to new_admin_session_path, status: :see_other,
                  alert: "세션이 만료되었습니다. 다시 로그인해 주세요."
    end
  end

  def find_admin_session
    return @find_admin_session if defined?(@find_admin_session)

    token = session[:admin_session_token]
    candidate = token && AdminSession.find_by(token:)
    @find_admin_session = candidate if candidate && !candidate.expired?
  end

  def terminate_admin_session
    find_admin_session&.destroy
    Current.admin_session = nil
    session.delete(:admin_session_token)
  end

  def current_admin
    Current.admin
  end
end
