# 거래처(CLIENT-1) — 거래처명·담당자명·알림 수신 휴대폰 번호는 필수, 이메일·사업자번호·메모는 선택.
# 연락처 표준화(국제 표기 등)는 발송 도메인(F-REM)에서 다루므로 여기선 느슨한 형식만 검증한다.
class Client < ApplicationRecord
  # PLAN-1 — Free 플랜 거래처 한도. F-PLAN 구독 체크로 판정점이 옮겨진 뒤에도 이 상수는
  # 구독 행이 없는 기존 사용자의 폴백과 UI 문구 표기의 단일 지점으로 유지한다(02_prd_update 승인 해석).
  FREE_CLIENT_LIMIT = 5

  belongs_to :user

  has_many :recurring_invoices, dependent: :destroy # INV-7 — 거래처 삭제 시 반복 청구 스케줄 연쇄 정리

  validates :name, :contact_name, :phone, presence: true
  validates :phone, allow_blank: true, format: { with: /\A\d{2,3}-?\d{3,4}-?\d{4}\z/ }
  validates :email, allow_blank: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # PLAN-1 — 등록 시에만 한도를 검사한다(수정은 자유). 위반 문구는 LP-12 준칙에 따라
  # 확정 보장 없이 Plus 이용 가능성만 안내한다. 판정은 구독 기준(User#client_limit_reached? —
  # Free는 아래 상수값, Plus는 무제한. 구독 행이 없는 기존 사용자는 상수 폴백).
  validate :free_plan_client_limit, on: :create

  # business_number는 F-TAX(팝빌 사업자번호 매칭) 정확도를 위해 strip한다. memo는 다중행
  # 텍스트라 제외한다. ceo_name·corp_addr는 TAX-1 공급받는자 정보(2026-11-16 추가 — strip만).
  normalizes :name, :contact_name, :phone, :business_number, :ceo_name, :corp_addr,
             with: ->(value) { value.strip }

  # TAX-1 — 공급받는자 사업자번호(하이픈 제외 정규화). business_number 컬럼을 재사용한다
  # (마이그레이션 불요). 사업자번호 없는(개인) 거래처는 전자세금계산서 발행 비대상이다.
  def corp_num
    business_number.to_s.gsub(/\D/, "").presence
  end

  # VIEW-7(Q30) — 하이픈 유무 차이를 흡수한 번호 비교 키. 형식 검증이 숫자·하이픈만 허용하므로
  # delete("-") 결과와 same_phone_digits 스코프의 SQL replace(phone, '-', '')가 같은 함수다
  # (전파·상속의 번호 정규화는 이 키와 스코프로 단일화 — 리뷰 W-4).
  def phone_digits
    phone.to_s.delete("-")
  end

  # VIEW-7(Q30 — 2026-11-26) — 수신 거부는 거래처 행이 아니라 번호에 고정된다(refused_phone —
  # 거부 접수·전파 시점의 번호). 같은 회원의 다른 거래처가 같은 번호로 수신 거부된 이력이 있으면
  # 모든 저장에서 그 거부 시각을 물려받는다 — 거부 후 같은 번호를 새 거래처로 등록해 발송을 다시
  # 받는 우회를 막는다(P1). 행의 번호를 바꿔도 그 행은 거부 상태로 남지만(채무자 의사) 새 번호로
  # 상속을 퍼뜨리지 않는다 — 상속 원천 판정은 행의 현재 번호가 아닌 refused_phone 기준이다. 등록 자체는 막지 않는다(청구서 발행·링크 직접 전달 가능 — 발송
  # 차단은 SendService의 REFUSED 가드가 client.refused?로 처리). 되돌림 없음: 이미 기록된
  # refused_at은 지우지 않는다(채무자 의사 표현).
  before_save :inherit_refusal_from_same_phone

  # 이번 저장에서 수신 거부를 상속했는지(App::ClientsController의 고지 문구 분기에 사용).
  attr_reader :refusal_inherited
  normalizes :email, with: ->(email) { email.strip.downcase }

  # REM — 거래처 단위 발송 스캔 필터: 수신거부·보류가 없는 거래처. Invoice.reminders_dispatchable의
  # merge(Client.reminders_active)로 쓰인다(채무자 발송 모집합에서 한 번에 제외).
  scope :reminders_active, -> { where(refused_at: nil, reminders_suspended_at: nil) }

  # VIEW-7(Q30·리뷰 W-4) — 하이픈을 제외한 번호 일치(전파의 단일 비교 기준 — 전파 대상은
  # 현재 그 번호를 가진 미거부 행). digits는 Client#phone_digits 산출값을 받는다. 형식 검증이
  # 숫자·하이픈만 허용하므로 SQL replace와 Ruby delete("-")가 항상 같은 키를 만든다.
  # 상속(inherit_refusal_from_same_phone)은 refused_phone 기준으로 판정한다(이 스코프 미사용).
  scope :same_phone_digits, ->(digits) { where("replace(phone, '-', '') = ?", digits) }

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

  # before_save — 검증을 통과한 모든 저장에서 동작한다(형식 검증 뒤라 번호는 숫자·하이픈만).
  # 이미 refused_at이 있으면 유지한다. 상속 원천 판정은 형제 행의 현재 번호가 아니라
  # refused_phone(거부 시점 번호) 기준 — 거부된 행이 번호를 바꿔도 새 번호로 상속을
  # 퍼뜨리지 않는다(VIEW-7·Q30 — 2026-11-26 refused_phone 도입).
  private def inherit_refusal_from_same_phone
    @refusal_inherited = false
    return if refused_at.present? || user.nil?

    siblings = user.clients.where.not(refused_at: nil)
                             .where.not(id: id) # 신규(id nil)는 전체가 후보 — IS NOT NULL로 전수 매칭
    # 상속 원천은 refused_phone(거부 시점 번호) 일치뿐이다 — 행의 번호 변경을 따라가지 않는
    # 단일 기준(레거시 nil 폴백 제거 — VIEW-7 2026-11-26). 거부 시점 번호가 기록되지 않은
    # 거부 행은 상속의 원천이 되지 않는다(운영 데이터에 그런 행은 없다 — 마이그레이션 소급
    # 20261126050721·접수·전파 쓰기(RegisterService)가 refused_phone을 전부 채운다). 그런 행
    # 자체는 여전히 거부 상태로 발송이 막힌다(refused?는 행 단위) — 상속만 하지 않는, 더 적게
    # 차단하는 안전한 방향이다.
    source = siblings.where(refused_phone: phone_digits).first
    return if source.nil?

    self.refused_at = source.refused_at
    self.refused_phone = phone_digits # source.refused_phone과 같은 값 — 거부 시점 번호 기록
    @refusal_inherited = true
  end

  # 한도 판정과 UI 분기(컨트롤러 @limit_reached)가 같은 구독 판정점(User#client_limit_reached?)을
  # 공유하며, FREE_CLIENT_LIMIT은 폴백·문구 표기의 단일 지점으로 유지된다(하위 호환).
  def free_plan_client_limit
    return if user.nil?

    return unless user.client_limit_reached?(user.clients.count)

    errors.add(:base, "Free 플랜은 거래처 #{FREE_CLIENT_LIMIT}개까지입니다. Plus로 무제한 이용할 수 있습니다")
  end
end
