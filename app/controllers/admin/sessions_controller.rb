# 관리자 로그인 — 2단계 플로우(AUTH-7.1~7.4).
# ① 이메일+비밀번호(pending 단계 — 인증 전 임시, 5분 TTL) ② 2FA:
#    미등록 → totp_setup(QR+수동 시크릿, 최초 1회) → totp_confirm → 세션 발급
#    등록됨 → totp_setup(코드 입력) → totp_verify → 세션 발급
# 오류 문구는 존재 여부 노출 금지 원칙으로 통일한다.
class Admin::SessionsController < Admin::BaseController
  skip_before_action :require_admin_session, only: %i[ new create totp_setup totp_confirm totp_verify ]
  # AUTH-7.3 — 자동화 시도 완화(로그인·2FA 코드 제출 공통)
  rate_limit to: 10, within: 3.minutes, only: %i[ create totp_confirm totp_verify ],
             with: -> { redirect_to new_admin_session_path, alert: "너무 많은 시도가 있었습니다. 잠시 후 다시 시도해 주세요." }

  PENDING_TTL = 5.minutes

  def new
  end

  # 1단계 — 이메일+비밀번호. 실패는 잠금·미존재·오비밀번호 모두 동일 문구(열거 방지).
  def create
    email, password = session_params
    admin = Admin.find_by(email: email)
    authenticated = admin&.authenticate(password)
    if authenticated && !admin.locked?
      start_pending(admin)
      redirect_to totp_setup_admin_session_path, status: :see_other
    else
      handle_failed_login(admin)
    end
  end

  # 2단계 화면 — 미등록이면 QR+시크릿(최초 1회 노출), 등록 상태면 코드 입력 폼.
  def totp_setup
    @admin = require_pending_admin or return
    load_totp_view(@admin)
  end

  # 2FA 최초 등록 완료 — 코드 검증 → otp_confirmed_at 기록(AUTH-7.1) → 세션 발급.
  def totp_confirm
    admin = require_pending_admin or return
    redirect_if_registered(admin) and return
    if Admins::TotpService.verify(admin, params[:code])
      admin.update!(otp_confirmed_at: Time.current)
      issue_session(admin)
    else
      render_totp_failure(admin)
    end
  end

  # 등록 계정 2FA 코드 검증 → 세션 발급.
  # W-6 — 미등록(otp_confirmed_at nil) 계정은 등록 플로우(totp_confirm)로 유도한다.
  def totp_verify
    admin = require_pending_admin or return
    redirect_if_unregistered(admin) and return
    if Admins::TotpService.verify(admin, params[:code])
      issue_session(admin)
    else
      render_totp_failure(admin)
    end
  end

  def destroy
    terminate_admin_session
    redirect_to new_admin_session_path, status: :see_other, notice: "로그아웃되었습니다."
  end

  private

  # Rails 8.1 expect 스칼라 키는 값 Array 반환 — U1 패턴 준용으로 분해(B-1).
  def session_params
    params.expect(:email, :password)
  end

  # 1단계 실패 공통 처리 — 실패 카운터 기록 후 통일 문구로 422 재렌더(W-5).
  def handle_failed_login(admin)
    if admin
      newly_locked = admin.record_failed_attempt!
      AuditLogs::RecordService.call(admin:, action: "login_failed", ip: request.remote_ip)
      notify_lockout(admin) if newly_locked
    end
    flash.now[:alert] = "이메일 또는 비밀번호가 올바르지 않습니다."
    render :new, status: :unprocessable_entity
  end

  # AUTH-7.3 — 신규 잠금 시점에만 통보 메일 + lockout 감사(1회 보장 — 모델은 상태 전환만).
  def notify_lockout(admin)
    AuditLogs::RecordService.call(admin:, action: "lockout", ip: request.remote_ip)
    AdminMailer.locked_out(admin).deliver_later
  end

  # pending 단계(1단계 통과, 인증 전) 검증 — 만료·없음·잠금이면 로그인부터 다시.
  # C-1 — pending 유지 중 잠긴 계정(예: 2FA 시도 중 5회 도달)은 2단계를 통과시키지 않는다.
  def require_pending_admin
    expires_at = session[:pending_admin_expires_at].to_i
    admin = Admin.find_by(id: session[:pending_admin_id])
    if expires_at < Time.current.to_i || admin.nil?
      clear_pending
      redirect_to new_admin_session_path, alert: "로그인 세션이 만료되었습니다. 다시 로그인해 주세요."
      return nil
    end
    if admin.locked?
      clear_pending
      redirect_to new_admin_session_path, alert: "이메일 또는 비밀번호가 올바르지 않습니다."
      return nil
    end
    admin
  end

  def start_pending(admin)
    session[:pending_admin_id] = admin.id
    session[:pending_admin_expires_at] = PENDING_TTL.from_now.to_i
  end

  def clear_pending
    session.delete(:pending_admin_id)
    session.delete(:pending_admin_expires_at)
  end

  def redirect_if_registered(admin)
    return false unless admin.two_factor_enabled?

    redirect_to totp_setup_admin_session_path, status: :see_other
    true
  end

  # W-6 — 2FA 미완료 계정이 totp_verify로 세션 발급받는 것을 차단(등록 플로우로 303 유도).
  def redirect_if_unregistered(admin)
    return false if admin.two_factor_enabled?

    redirect_to totp_setup_admin_session_path, status: :see_other
    true
  end

  # 코드 실패 — 실패 카운터 기록 후 422 재렌더(미등록이면 동일 시크릿의 QR 재표시).
  def render_totp_failure(admin)
    newly_locked = admin.record_failed_attempt!
    notify_lockout(admin) if newly_locked
    @admin = admin
    load_totp_view(admin)
    flash.now[:alert] = "인증 코드가 올바르지 않습니다."
    render :totp_setup, status: :unprocessable_entity
  end

  # 2단계 화면 공통 표시값 — 미등록 계정의 시크릿은 이 시점(최초 등록)에 발급하고
  # 등록 완료 전까지만 뷰로 노출한다(AUTH-7.1 · 리뷰 B-3).
  # 동시 다중 GET 시 재발급 race는 단일 운영자·5분 pending TTL로 수용(리뷰 B-3 권고).
  def load_totp_view(admin)
    admin.generate_otp_secret! unless admin.two_factor_enabled?
    @otp_secret = admin.otp_secret
    @qr_data_url = Admins::TotpService.qr_data_url(admin) unless admin.two_factor_enabled?
  end

  # 세션 발급(AUTH-7.4) — 실패 카운터 리셋·신규 IP 통보·감사 기록·마지막 로그인 기록.
  # 순서 고정(리뷰 C-2): notify_new_ip는 last_login_ip 기록 전에 판정해야 한다.
  def issue_session(admin)
    admin.reset_failed_attempts!
    admin_session = AdminSession.issue_for!(admin, ip: request.remote_ip)
    notify_new_ip(admin)
    admin.update_columns(last_login_at: Time.current, last_login_ip: request.remote_ip)
    AuditLogs::RecordService.call(admin:, action: "login_success", ip: request.remote_ip)
    clear_pending
    session[:admin_session_token] = admin_session.token
    redirect_to admin_root_path, status: :see_other, notice: "관리자로 로그인되었습니다."
  end

  # AUTH-7.4 — 직전 로그인 IP와 다르면 신규 IP 로그인 통보 + 감사 기록(최소 구현).
  # 첫 로그인(직전 IP 없음)은 통보하지 않는다.
  def notify_new_ip(admin)
    return if admin.last_login_ip.blank? || admin.last_login_ip == request.remote_ip

    AdminMailer.new_login(admin, request.remote_ip).deliver_later
    AuditLogs::RecordService.call(admin:, action: "new_ip_login", ip: request.remote_ip)
  end
end
