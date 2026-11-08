# 거래처(CLIENT-1) — 거래처명·담당자명·알림 수신 휴대폰 번호는 필수, 이메일·사업자번호·메모는 선택.
# 연락처 표준화(국제 표기 등)는 발송 도메인(F-REM)에서 다루므로 여기선 느슨한 형식만 검증한다.
class Client < ApplicationRecord
  # PLAN-1 — Free 플랜 거래처 한도. F-PLAN 구독 체크로 판정점이 옮겨진 뒤에도 이 상수는
  # 구독 행이 없는 기존 사용자의 폴백과 UI 문구 표기의 단일 지점으로 유지한다(02_prd_update 승인 해석).
  FREE_CLIENT_LIMIT = 5

  belongs_to :user

  validates :name, :contact_name, :phone, presence: true
  validates :phone, allow_blank: true, format: { with: /\A\d{2,3}-?\d{3,4}-?\d{4}\z/ }
  validates :email, allow_blank: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # PLAN-1 — 등록 시에만 한도를 검사한다(수정은 자유). 위반 문구는 LP-12 준칙에 따라
  # 확정 보장 없이 Plus 이용 가능성만 안내한다. 판정은 구독 기준(User#client_limit_reached? —
  # Free는 아래 상수값, Plus는 무제한. 구독 행이 없는 기존 사용자는 상수 폴백).
  validate :free_plan_client_limit, on: :create

  # business_number는 F-TAX(팝빌 사업자번호 매칭) 정확도를 위해 strip한다. memo는 다중행
  # 텍스트라 제외한다.
  normalizes :name, :contact_name, :phone, :business_number, with: ->(value) { value.strip }
  normalizes :email, with: ->(email) { email.strip.downcase }

  # REM — 거래처 단위 발송 스캔 필터: 수신거부·보류가 없는 거래처. Invoice.reminders_dispatchable의
  # merge(Client.reminders_active)로 쓰인다(채무자 발송 모집합에서 한 번에 제외).
  scope :reminders_active, -> { where(refused_at: nil, reminders_suspended_at: nil) }

  # CLIENT-1(P4·REM-6) — 발행 이력이 있는 거래처의 삭제 차단. 발행 계열 청구(draft 이외 상태)가
  # 존재하면 message_logs 소실로 이어지므로 P4(모든 발신은 기록·임의 삭제 불가)에 반해 삭제를
  # 중단한다. 초안만 보유한 거래처는 발송 이력 자체가 없어 초안을 정리한 뒤 삭제를 허용한다
  # (Client에 invoices 연관이 없어 FK 연쇄가 없으므로 초안 소거를 여기서 수행한다).
  before_destroy :prevent_destroy_with_issued_invoices

  private def prevent_destroy_with_issued_invoices
    scoped_invoices = Invoice.where(client_id: id)

    if scoped_invoices.where.not(status: :draft).exists?
      errors.add(:base, "발행 이력이 있는 거래처는 삭제할 수 없습니다. 기록 보존을 위해 삭제가 차단됩니다")
      throw(:abort)
    end

    scoped_invoices.destroy_all
  end

  # VIEW-7 — 수신거부 접수 여부. refused_at 마킹은 Promises::RegisterService의 refusal 응답
  # 경로가 담당하며, 마킹 즉시 이 거래처의 모든 채무자 향 발송이 가드에서 차단된다.
  def refused?
    refused_at.present?
  end

  # REM-7 — 거래처 단위 발송 보류 여부(U1 액션 마킹 — F-REM 3-b 컨트롤러 경로)
  def reminders_suspended?
    reminders_suspended_at.present?
  end

  # REM — 보류·수신거부가 없는 발송 가능 거래처(Invoice#reminders_active?가 함께 사용)
  def reminders_active?
    !refused? && !reminders_suspended?
  end

  private

  # 한도 판정과 UI 분기(컨트롤러 @limit_reached)가 같은 구독 판정점(User#client_limit_reached?)을
  # 공유하며, FREE_CLIENT_LIMIT은 폴백·문구 표기의 단일 지점으로 유지된다(하위 호환).
  def free_plan_client_limit
    return if user.nil?

    return unless user.client_limit_reached?(user.clients.count)

    errors.add(:base, "Free 플랜은 거래처 #{FREE_CLIENT_LIMIT}개까지입니다. Plus로 무제한 이용할 수 있습니다")
  end
end
