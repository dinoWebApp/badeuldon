# 거래처(CLIENT-1) — 거래처명·담당자명·알림 수신 휴대폰 번호는 필수, 이메일·사업자번호·메모는 선택.
# 연락처 표준화(국제 표기 등)는 발송 도메인(F-REM)에서 다루므로 여기선 느슨한 형식만 검증한다.
class Client < ApplicationRecord
  # PLAN-1 — Free 플랜 거래처 한도. F-PLAN에서 구독 상태 체크로 교체할 때까지 전 사용자에게
  # 적용하며, 한도 수치는 이 상수 단일 지점으로 관리한다(02_prd_update 승인 해석).
  FREE_CLIENT_LIMIT = 5

  belongs_to :user

  validates :name, :contact_name, :phone, presence: true
  validates :phone, allow_blank: true, format: { with: /\A\d{2,3}-?\d{3,4}-?\d{4}\z/ }
  validates :email, allow_blank: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # PLAN-1 — 등록 시에만 한도를 검사한다(수정은 자유). 위반 문구는 LP-12 준칙에 따라
  # 확정 보장 없이 Plus 이용 가능성만 안내한다.
  validate :free_plan_client_limit, on: :create

  # business_number는 F-TAX(팝빌 사업자번호 매칭) 정확도를 위해 strip한다. memo는 다중행
  # 텍스트라 제외한다.
  normalizes :name, :contact_name, :phone, :business_number, with: ->(value) { value.strip }
  normalizes :email, with: ->(email) { email.strip.downcase }

  private

  # 한도 판정과 UI 분기(컨트롤러 @limit_reached)가 같은 FREE_CLIENT_LIMIT을 공유한다.
  def free_plan_client_limit
    return if user.nil?
    return if user.clients.count < FREE_CLIENT_LIMIT

    errors.add(:base, "Free 플랜은 거래처 #{FREE_CLIENT_LIMIT}개까지입니다. Plus로 무제한 이용할 수 있습니다")
  end
end
