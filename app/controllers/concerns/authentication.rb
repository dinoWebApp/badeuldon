module Authentication
  extend ActiveSupport::Concern

  # AUTH-1.6 — 세션 유지 기본 30일(재인증 = 비밀번호 재로그인)
  SESSION_COOKIE_MAX_AGE = 30.days

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    # AUTH-1.3 — 로그인 직후 표시명(display_name)이 미설정이면 최초 프로필 설정 화면으로 안내한다.
    # 최초 프로필 완료가 원래 가려던 페이지(return_to)보다 우선하며, 그 외에는 /app 대시보드로 보낸다.
    def after_authentication_url
      return_to = session.delete(:return_to_after_authenticating)
      return edit_app_profile_url if Current.user&.display_name.blank?

      return_to || app_root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed[:session_id] = {
          value: session.id, expires: SESSION_COOKIE_MAX_AGE, httponly: true, same_site: :lax
        }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
