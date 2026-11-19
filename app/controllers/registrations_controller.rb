# 회원가입 — AUTH-1(이메일/비밀번호), AUTH-9(휴대폰 SMS 인증 필수), 가입 즉시 활성화.
# SALES-3 — 추천 코드(선택) 유효 검증 후 어트리뷰션 기록·첫결제 할인 쿠폰 자동 예약(SALES-4).
# 휴대폰 인증은 폼 내 2단계 비동기(send_phone_code → verify_phone_code)이며, 가입 create에서
# 최종 권위 판정을 이중 수행한다. C-1 — 검증 통과 주체와 가입 주체를 같은 브라우저로 결합한다:
# verify 성공 시 세션에 정규화 번호를 저장하고, create는 세션값과 제출번호 대조 + consumed 행의
# 최근 존재로 판정한다(번호만 아는 제3자의 코드 없는 가입 차단).
class RegistrationsController < ApplicationController
  # VIEW-1 — 인증 진입 화면도 공개 표면: 구형·인앱 브라우저 허용(AllowAllBrowsers).
  include AllowAllBrowsers
  allow_unauthenticated_access only: %i[ new create send_phone_code verify_phone_code ]
  before_action :redirect_if_authenticated, only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_registration_path, alert: "너무 많은 요청이 있었습니다. 잠시 후 다시 시도해 주세요." }
  # AUTH-9 — 인증번호 발송·확인은 공개 엔드포인트라 IP 기준 가드를 추가로 둔다(번호당
  # 1분 1회·1시간 3회는 PhoneVerifications::SendService가 DB 이력 기준으로 판정).
  # W-5 — 국내 이동통신은 CGNAT로 다수 사용자가 출발 IP를 공유하므로 IP당 한도는 20회/1시간으로
  # 완화한다(번호당 DB 이력 한도가 1차 방어선).
  rate_limit to: 20, within: 1.hour, by: -> { request.remote_ip }, only: %i[ send_phone_code verify_phone_code ],
             with: -> { render_rate_limited }

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)
    @referral_code = resolve_referral_code
    return render_signup_failure unless signup_ready?

    if @user.save
      complete_signup!
      redirect_to edit_app_profile_path, status: :see_other,
                  notice: "회원가입이 완료되었습니다. 받을돈에 오신 것을 환영합니다!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  # AUTH-9 1단계 — 인증번호 SMS 발송(비동기 fetch). 응답은 마스킹 번호만(뒷자리 4).
  def send_phone_code
    phone, = params.expect(:phone) # expect 스칼라는 Array 반환 — 분해(admin 세션 B-1 패턴)
    result = PhoneVerifications::SendService.new(phone:).call
    if result.success?
      render json: { ok: true, phone: result.masked_phone }
    else
      render json: { ok: false, error: result.error }, status: :unprocessable_entity
    end
  end

  # AUTH-9 2단계 — 인증번호 확인(1회용 consumed). 성공 시 정규화 번호를 세션에 저장해(C-1)
  # 가입 create가 같은 브라우저만 인증 통과로 판정한다 — 최종 권위 판정은 create가 재수행.
  def verify_phone_code
    phone, code = params.expect(:phone, :code) # 분해(B-1 패턴)
    result = PhoneVerifications::VerifyService.new(phone:, code:).call
    if result.verified?
      session[:verified_phone] = normalize_phone(phone)
      render json: { ok: true }
    else
      render json: { ok: false, error: result.error }, status: :unprocessable_entity
    end
  end

  private

  # 로그인 사용자의 가입 화면 재진입을 /app 대시보드로 되돌린다(원클릭 복귀).
  def redirect_if_authenticated
    redirect_to app_root_url, status: :see_other if authenticated?
  end

  def registration_params
    params.expect(user: [ :email, :password, :password_confirmation, :phone ])
  end

  # SALES-3 — 추천 코드 유효 검증(공백 무시·현재 유효 창만 수용). 코드를 입력했는데 유효하지
  # 않으면 nil을 돌려 가입을 중단시킨다(지시서 확정 — 오류 시 422 안내, 조용한 무시 금지).
  def resolve_referral_code
    input = params[:referred_code].to_s.strip.upcase
    return nil if input.blank?

    SalesReferralCode.current_valid.find_by(code: input)
  end

  # 가입 직전 이중 검증 — ① 휴대폰 인증: 검증을 통과한 "이 브라우저 세션"만 가입할 수 있도록
  # 세션값(verify_phone_code 성공 시 저장)과 정규화 제출번호 대조 + consumed 행의 최근 존재
  # (PhoneVerification 정규화가 번호를 맞춰주므로 정규화 문자열 비교로 충분) ② 추천 코드 오류.
  def signup_ready?
    phone_verified? && (@referral_code || params[:referred_code].to_s.strip.blank?)
  end

  # AUTH-9(C-1) — 세션값 == 정규화(제출번호) 대조로 검증 주체와 가입 주체를 동일 브라우저로
  # 결합한다. consumed_recently만으로는 번호를 아는 제3자가 코드 없이 가입할 수 있었다.
  def phone_verified?
    normalized = normalize_phone(registration_params[:phone])
    session[:verified_phone].present? &&
      session[:verified_phone] == normalized &&
      PhoneVerification.consumed_recently.exists?(phone: normalized)
  end

  # 번호 정규화 단일 지점(숫자만 — PhoneVerification·VerifyService와 동일 규칙).
  def normalize_phone(value)
    value.to_s.gsub(/\D/, "")
  end

  # 가입 성공 후처리 — C-1(검증 세션값 소멸)·SALES-3/4 어트리뷰션·쿠폰 부착·U1 세션 발급.
  def complete_signup!
    attach_referral!(@referral_code)
    session.delete(:verified_phone)
    start_new_session_for @user
  end

  # SALES-3/4 — 어트리뷰션 기록(P4 스냅샷)·첫결제 할인 쿠폰 자동 예약. 쿠폰 부착 실패는
  # 가입을 막지 않는다(정가 첫 결제 폴백). W-6 — 실패는 Rails 로그에 더해 감사 로그로 기록해
  # 콘솔에서 관측 가능하게 한다(admin nil — coupon_redeemed U1 행위 선례). 사후 복구는 admin
  # 콘솔 또는 runner(어트리뷰션 누락분 수동 update + 첫 결제 전 쿠폰 재예약).
  def attach_referral!(referral_code)
    @user.update!(referred_by_sales_rep_id: referral_code.sales_rep_id,
                  referral_code_snapshot: referral_code.code)
    Sales::AttachFirstChargeCouponService.new(user: @user).call
  rescue StandardError => e
    Rails.logger.error("[RegistrationsController] referral attach failed user=#{@user.id} #{e.class}: #{e.message}")
    AuditLogs::RecordService.call(admin: nil, action: attach_failure_action,
                                  target: @user, detail: "#{e.class}: #{e.message}",
                                  ip: request.remote_ip)
  end

  # 어트리뷰션 실패(누락 시 수수료 영구 소실 위험)와 쿠폰 부착 실패(정가 폴백)를 감사 action으로 구분.
  def attach_failure_action
    @user.referred_by_sales_rep_id.present? ? "coupon_attach_failed" : "referral_attribution_failed"
  end

  # 422 재렌더 — 인증 미통과·코드 오류 안내를 폼 상단 alert로 표시한다.
  def render_signup_failure
    flash.now[:alert] = if @referral_code || params[:referred_code].to_s.strip.blank?
      "휴대폰 인증이 필요합니다. 인증번호를 확인해 주세요."
    else
      "추천 코드가 유효하지 않거나 만료되었습니다. 코드를 확인해 주세요."
    end
    render :new, status: :unprocessable_entity
  end

  # 인증번호 엔드포인트의 IP rate limit 응답(JSON — fetch 호출 대응).
  def render_rate_limited
    render json: { ok: false, error: "인증 요청이 너무 많습니다. 잠시 후 다시 시도해 주세요." },
           status: :too_many_requests
  end
end
