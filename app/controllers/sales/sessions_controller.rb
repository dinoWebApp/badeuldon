# 영업 직원 로그인(SALES-1·7 — 이메일/비밀번호 단일 단계. 2FA 불요 — 본인 실적 열람만 하는
# 민감도, AUTH-7과 구분). Admin::SessionsController 패턴을 따르되 2단계(TOTP) 없이 즉시
# 세션을 발급한다. 정지(suspended)·잠금(5회 실패) 계정은 차단하며, 오류 문구는 존재 여부
# 노출 금지 원칙으로 통일한다.
class Sales::SessionsController < Sales::BaseController
  skip_before_action :require_sales_session, only: %i[ new create ]
  # AUTH-7.3 준용 — 자동화 시도 완화.
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_sales_session_path, alert: "너무 많은 시도가 있었습니다. 잠시 후 다시 시도해 주세요." }

  def new
  end

  def create
    email, password = session_params
    rep = SalesRep.find_by(email: email)
    authenticated = rep&.authenticate(password)
    if authenticated && !rep.locked? && rep.active?
      issue_session(rep)
    else
      handle_failed_login(rep)
    end
  end

  def destroy
    terminate_sales_session
    redirect_to new_sales_session_path, status: :see_other, notice: "로그아웃되었습니다."
  end

  private

  # Rails 8.1 expect 스칼라 키는 값 Array 반환 — admin 세션 패턴 준용으로 분해(B-1).
  def session_params
    params.expect(:email, :password)
  end

  # 실패 공통 처리 — 실패 카운터 기록 후 통일 문구로 422 재렌더(열거 방지). 잠금 도달 시
  # 감사 로그를 남긴다(ADMIN-2 — 영업 계정 행위도 감사 대상. sales_rep_session 토큰 전파 방지).
  def handle_failed_login(rep)
    if rep
      newly_locked = rep.record_failed_attempt!
      AuditLogs::RecordService.call(action: "sales_rep_login_failed", target: rep,
                                    detail: rep.email, ip: ClientIp.of(request))
      AuditLogs::RecordService.call(action: "sales_rep_lockout", target: rep,
                                    detail: rep.email, ip: ClientIp.of(request)) if newly_locked
    end
    flash.now[:alert] = "이메일 또는 비밀번호가 올바르지 않습니다."
    render :new, status: :unprocessable_entity
  end

  # 세션 발급 — 실패 카운터 리셋·감사 기록 후 전용 쿠키 키(sales_session_token)로 발급.
  def issue_session(rep)
    rep.reset_failed_attempts!
    sales_rep_session = SalesRepSession.issue_for!(rep, ip: ClientIp.of(request))
    AuditLogs::RecordService.call(action: "sales_rep_login_success", target: rep,
                                  detail: rep.email, ip: ClientIp.of(request))
    session[:sales_session_token] = sales_rep_session.token
    redirect_to sales_root_path, status: :see_other, notice: "영업 직원으로 로그인되었습니다."
  end
end
