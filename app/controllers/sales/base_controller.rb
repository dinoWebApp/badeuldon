# 영업 직원 표면 공통 베이스(표면 ⑤ /sales — SALES-6·7). U1 Authentication 가드를 해제하고
# 별도 sales_rep_sessions 토큰으로 가드한다(U1·관리자 세션과 절대 공유하지 않는다 —
# session[:sales_session_token]). noindex는 표면 경로 접두어(/sales — SURF-3)로 적용된다.
class Sales::BaseController < ApplicationController
  layout "sales"
  skip_before_action :require_authentication
  before_action :require_sales_session
  helper_method :current_sales_rep

  private

  # SALES-7 — 쿠키 토큰 → sales_rep_session 조회 후 만료 재검증(Admin::BaseController 동일
  # 패턴). 유효하면 활동 시각을 갱신하고 Current.sales_rep_session에 적재한다.
  def require_sales_session
    sales_rep_session = find_sales_rep_session
    if sales_rep_session
      sales_rep_session.touch_activity!
      Current.sales_rep_session = sales_rep_session
    else
      terminate_sales_session
      redirect_to new_sales_session_path, status: :see_other,
                  alert: "세션이 만료되었습니다. 다시 로그인해 주세요."
    end
  end

  def find_sales_rep_session
    return @find_sales_rep_session if defined?(@find_sales_rep_session)

    token = session[:sales_session_token]
    candidate = token && SalesRepSession.find_by(token:)
    @find_sales_rep_session = candidate if candidate && !candidate.expired?
  end

  def terminate_sales_session
    find_sales_rep_session&.destroy
    Current.sales_rep_session = nil
    session.delete(:sales_session_token)
  end

  def current_sales_rep
    Current.sales_rep
  end
end
