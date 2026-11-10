# 관리자 전용 계정(AUTH-7 — U1 users와 완전 분리, 공개 가입 경로 없음 AUTH-7.2).
# 2FA(TOTP)는 AUTH-7.1 필수 — otp_confirmed_at이 없으면 콘솔 진입 불가.
class Admin < ApplicationRecord
  has_secure_password
  has_many :admin_sessions, dependent: :destroy
  has_many :audit_logs, dependent: :destroy

  # AUTH-7.1 — TOTP 시크릿은 DB 유출에 대비해 AES 암호화 저장(deterministic 아님).
  encrypts :otp_secret

  # ADMIN-1 롤 — owner(최고 관리자·기본) / staff(운영자). 롤 부여·해제 콘솔은 Run B.
  enum :role, { staff: 0, owner: 1 }, default: :owner

  normalizes :email, with: ->(email) { email.strip.downcase }
  validates :email, presence: true, uniqueness: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  # AUTH-7.2 — 운영 절차상 강도 요건은 ProvisionService/재설정 화면 안내에 위임한다(모델은 최소 검증).

  # AUTH-7.3 — 연속 5회 실패 시 잠금 + 등록 이메일 통보.
  FAILED_ATTEMPT_LIMIT = 5

  # AUTH-7.1 — TOTP 스텝 길이(초). otp_last_used_counter는 이 단위의 스텝 정수.
  OTP_STEP_SECONDS = 30

  scope :locked, -> { where.not(locked_at: nil) }

  def two_factor_enabled?
    otp_confirmed_at.present?
  end

  def locked?
    locked_at.present?
  end

  # 로그인·TOTP 실패 1건 기록. 한도 도달 시점에만 잠금으로 전환하고 true를 반환한다.
  # 감사 기록·메일 통보는 호출 계층(컨트롤러)이 담당한다(규약 §4.2 — Model→Service 금지).
  # 동시 실패에도 이중 잠금·이중 통보가 없도록 조건부 UPDATE로 원자화한다(리뷰 W-2):
  # 카운터 증가와 잠금 전환이 각각 단일 SQL — 재조회 값으로 판정한다.
  def record_failed_attempt!
    self.class.where(id: id).update_all("failed_attempts = failed_attempts + 1")
    self.failed_attempts = self.class.where(id: id).pick(:failed_attempts)
    return false if locked? || failed_attempts < FAILED_ATTEMPT_LIMIT

    self.class.where(id: id, locked_at: nil)
        .update_all(locked_at: Time.current) == 1
  end

  def reset_failed_attempts!
    update_columns(failed_attempts: 0, locked_at: nil) if failed_attempts > 0 || locked_at
  end

  # AUTH-7.3 잠금 해제(owner 콘솔이 Run B로 오기 전까지는 runner 절차 사용 — 03 문서 참조).
  # unlock 감사 기록은 호출 계층이 RecordService로 수행한다(규약 §4.2).
  def unlock!
    update!(locked_at: nil, failed_attempts: 0)
    self
  end

  # AUTH-7.1 — TOTP 검증(±1 스텝 = drift 30초). rotp의 after로 마지막 성공 스텝 이하의
  # 코드 재사용을 차단하고, 성공 시 스텝 카운터를 기록한다.
  # at 인자는 테스트용 시계 조작 허용(02 확정 해석 5).
  def verify_totp!(code, at: Time.current)
    return false if otp_secret.blank?

    last_used_at = otp_last_used_counter ? otp_last_used_counter * OTP_STEP_SECONDS : nil
    timestamp = totp.verify(code, drift_behind: OTP_STEP_SECONDS, drift_ahead: OTP_STEP_SECONDS,
                            after: last_used_at, at: at)
    return false if timestamp.nil?

    # W-1 수용 — update_column은 read-modify-write라 초 단위 동시 요청에서 동일 코드
    # 재사용이 허용될 수 있다. pending 세션 탈취+코드 가로채기 race로 현실 위험 낮음으로
    # 수용하며, 원자화는 Run B에서 재검토한다.
    update_column(:otp_last_used_counter, timestamp / OTP_STEP_SECONDS)
    true
  end

  # AUTH-7.1 — 등록 화면(QR·수동 시크릿 병기)용 프로비저닝 URI. issuer는 서비스명.
  def provisioning_uri
    totp.provisioning_uri(email)
  end

  # 최초 등록 시점에만 시크릿을 발급한다(한 번 발급되면 재발급하지 않는다).
  def generate_otp_secret!
    update!(otp_secret: ROTP::Base32.random) if otp_secret.blank?
  end

  private

  def totp
    ROTP::TOTP.new(otp_secret, issuer: "받을돈")
  end
end
