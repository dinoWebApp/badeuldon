# 영업 직원·감투 임원 계정(SALES-1 — F-SALES·Q24). U1 users·Admins와 완전 분리된 별도
# 계정 테이블(AUTH-7 준용 격리 — 공개 가입 경로 없음, 생성은 관리자 콘솔뿐).
# role 이원화: sales(영업 직원) = 수수료 20%·12개월 캡 / officer(감투 임원) = 15%·무기한.
# commission_rate가 있으면 역할 기본값을 덮어쓴다(per-rep 오버라이드 — effective_rate).
class SalesRep < ApplicationRecord
  has_secure_password

  # W-8 — 파괴 방어선(거래처 삭제 가드 선례)을 연관 콜백보다 먼저 선언해 의도한 안내 문구로
  # 차단한다(파괴가 시작되기 전 abort — dependent 콜백이 실행될 여지를 남기지 않는다).
  before_destroy :prevent_destroy_with_history

  has_many :sales_rep_sessions, dependent: :destroy
  has_many :sales_referral_codes, dependent: :destroy # W-8 가드 통과분(이력 없는 계정)만 연쇄 삭제
  # W-8 — 정산 스냅샷은 P4 지급 이력이라 파괴로 소실돼서는 안 된다. 가드(위)가 1차 방어선이며
  # restrict_with_error는 우회 경로 방어선이다.
  has_many :sales_commissions, dependent: :restrict_with_error
  # SALES-3 어트리뷰션 역참조. 영업 계정 삭제는 P4(어트리뷰션·정산 이력 보존)상 허용하지
  # 않는다(콘솔에도 삭제 액션이 없다) — 방어선으로 restrict_with_error를 명시한다.
  has_many :referred_users, class_name: "User", foreign_key: :referred_by_sales_rep_id,
                            inverse_of: :referred_by_sales_rep, dependent: :restrict_with_error

  enum :role, { sales: 0, officer: 1 }, default: :sales
  enum :status, { active: 0, suspended: 1 }, default: :active

  # Q24 — 역할별 기본 수수료율(%). commission_rate 오버라이드가 없을 때 적용된다.
  ROLE_DEFAULT_RATES = { "sales" => 20, "officer" => 15 }.freeze

  # AUTH-7.3 준용 — 연속 5회 실패 시 잠금(로그인 경로 Sales::SessionsController가 기록).
  FAILED_ATTEMPT_LIMIT = 5

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :name, with: ->(name) { name.strip }
  normalizes :title, with: ->(title) { title.strip }

  validates :email, presence: true, uniqueness: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  # W-2 — 개별 요율 오버라이드의 서버 측 범위 보장(1~50% 정수). 폼 min/max만으로는 조작
  # 요청을 막지 못하고, 100 초과값은 정산 스냅샷(SalesCommission rate 0..100 검증)에서
  # RecordInvalid → rep 정산이 조용히 누락된다(SALES-5). nil은 역할 기본값 사용.
  validates :commission_rate, numericality: { only_integer: true,
                                              greater_than_or_equal_to: 1,
                                              less_than_or_equal_to: 50 },
                              allow_nil: true

  scope :locked, -> { where.not(locked_at: nil) }

  # Q24 — 적용 수수료율(%)의 단일 판정점: 개별 오버라이드 우선, 없으면 역할 기본값.
  def effective_rate
    commission_rate.presence || ROLE_DEFAULT_RATES.fetch(role)
  end

  def locked?
    locked_at.present?
  end

  # SALES-2 — 현재 유효한 추천 코드(가입 폼·대시보드 공용 단일 판정점).
  def current_referral_code
    sales_referral_codes.current_valid.order(:valid_from, :id).last
  end

  # 로그인 실패 1건 기록(Admin 동일 패턴) — 카운터 증가·잠금 전환을 원자 UPDATE로 처리해
  # 동시 실패에도 이중 잠금이 없다. 감사 기록은 호출 계층(컨트롤러)이 담당한다(규약 §4.2).
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

  def unlock!
    update!(locked_at: nil, failed_attempts: 0)
    self
  end

  # W-8 — 파괴 방어(P4 기록 보존). 유치 사용자 또는 정산 스냅샷이 하나라도 있으면 파괴를
  # 차단해 어트리뷰션·지급 이력을 보존한다. 이력이 전혀 없는 오생성 계정(코드 미공유·정산
  # 없음)만 파괴를 허용하며, 허용분의 감사 기록은 Model→Service 금지(규약 §4.2)에 따라
  # 실행 계층(콘솔·runner 절차)이 담당한다 — 03 문서 운영 노트 참조.
  private def prevent_destroy_with_history
    return if referred_users.none? && sales_commissions.none?

    errors.add(:base, "유치 사용자 또는 정산 이력이 있는 영업 계정은 삭제할 수 없습니다. 정지로만 운영합니다(기록 보존)")
    throw(:abort)
  end
end
