# 휴대폰 SMS 인증(AUTH-9 — F-SALES 가입 플로우). 발송 이력 행 자체가 rate limit 판정
# 근거다(번호당 최근 1분 1회·1시간 3회 — SendService). 코드는 6자리 숫자·5분 만료·
# 검증 시도 5회 제한·성공 시 consumed 마킹(1회용). 코드 평문 저장은 인증 용도상 단기
# 수명(5분)과 1회용 소비로 위험이 통제된다 — 가입 컨트롤러의 이중 검증은 consumed 행의
# 최근 존재로 판정한다.
class PhoneVerification < ApplicationRecord
  # AUTH-9 — 코드 유효 시간(5분)·검증 시도 한도(5회)·코드 자릿수(6자리 숫자).
  CODE_TTL = 5.minutes
  MAX_ATTEMPTS = 5
  CODE_DIGITS = 6

  # 가입 컨트롤러 이중 검증 — consumed 행을 "최근"으로 인정하는 창. 인증 직후 가입 제출까지의
  # 여유 시간이며, 행 자체는 5분 만료라 consumed_at 기준으로 별도 창을 둔다.
  VERIFICATION_VALID_WINDOW = 30.minutes

  normalizes :phone, with: ->(phone) { phone.to_s.gsub(/\D/, "") }

  validates :phone, :code, :expires_at, presence: true

  # rate limit 조회용([phone, created_at] 인덱스 — AUTH-9).
  scope :sent_within, ->(period) { where(created_at: period.ago..) }

  # 가입 이중 검증용 — 해당 번호의 최근 소비된(검증 성공) 행.
  scope :consumed_recently, -> {
    where.not(consumed_at: nil).where(consumed_at: VERIFICATION_VALID_WINDOW.ago..)
  }

  def expired?
    expires_at <= Time.current
  end

  def consumed?
    consumed_at.present?
  end

  def attempts_exceeded?
    attempts >= MAX_ATTEMPTS
  end

  # 실패 1건 기록 — 5회 도달 시 이 코드로는 더 이상 검증할 수 없다(서비스가 판정).
  def record_attempt!
    increment!(:attempts) # rubocop:disable Rails/SkipsModelValidations
  end

  # 검증 성공 — consumed 마킹(1회용 보장). 이미 소비됐으면 false(재사용 차단).
  def consume!
    return false if consumed?

    update!(consumed_at: Time.current)
    true
  end
end
