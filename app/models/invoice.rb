# 청구서(INV-1~6) — 초안(draft) 상태에서만 본문을 편집하고(INV-5), 발행 시 채번·토큰을
# 발급하며, 발행 계열에서만 무효 처리한다(INV-6). 상태 viewed·overdue·promised·
# partially_paid·paid는 INV-4 전이의 예약값으로 SHARE·PROMISE·REM·PAY 도메인에서 진입한다.
class Invoice < ApplicationRecord
  # PLAN-1 — Free 플랜 월 발행 한도. Client::FREE_CLIENT_LIMIT과 같은 상수 단일 지점 패턴.
  # 초안은 무제한이며 발행(draft→issued) 시점에 당월 issued_at 기준으로 검사한다(02_prd_update 승인 해석).
  FREE_MONTHLY_INVOICE_LIMIT = 3
  # INV-3 — 만기일 기본값: 발행일 + 30일
  DEFAULT_DUE_IN_DAYS = 30
  # INV-1 — 품목 행 수 상한: JS 실시간 요약의 정밀도 한계(안전 정수 2^53 ≈ 901행)와 과도한
  # 폼 페이로드를 함께 막는다. 하한(1개 이상)은 must_have_at_least_one_item이 담당한다.
  MAX_ITEMS = 100
  # SHARE-1 — 토큰 엔트로피: urlsafe_base64(32) ≈ 256bit
  TOKEN_URLSAFE_BYTES = 32
  # SHARE-2 — 링크 유효기간: 만기일 후 60일(기본)
  TOKEN_VALIDITY_DAYS_AFTER_DUE = 60
  # INV-2 — 원천징수 3.3%: 공급가액 기준, 원 단위 내림(결정 #4). 소수 연산을 피하기 위해
  # 천분율 정수(33/1000)로 산식을 표현한다.
  WITHHOLDING_RATE_PER_MILLE = 33

  # INV-6 — 무효 가능 상태 = 발행 계열(초안은 삭제, 수금완료·무효는 종결 상태).
  # 부분입금까지 포함하는 INV-4 발행 분기 전체를 발행 계열로 본다.
  VOIDABLE_STATUSES = %w[ issued viewed overdue promised partially_paid ].freeze

  # INV-5 — 발행 후 본문 불변(모델 레벨 가드). 발행 계열 갱신 시 이 컬럼들과 품목 행의
  # 변경을 차단한다. due_on 재계산은 초안→발행 전이 안에서만 일어나므로 이 가드 대상이 아니다.
  PROTECTED_CONTENT_COLUMNS = %w[
    client_id due_on tax_mode withholding_enabled issuer_display_name
    bank_name account_number account_holder subtotal tax_amount total_amount
    withholding_amount net_amount
  ].freeze

  belongs_to :user
  belongs_to :client
  has_many :items, class_name: "InvoiceItem", dependent: :destroy, inverse_of: :invoice

  # 초안 작성·수정 폼 — 품목 행 동적 편집(nested attributes). 완전 공백 행은 폼에서 폐기한다.
  accepts_nested_attributes_for :items, allow_destroy: true, reject_if: :all_blank

  # INV-4 — 상태 전이. draft→issued(issue!), 발행계열→voided(void!)만 이번 구현 범위.
  enum :status, { draft: 0, issued: 1, viewed: 2, overdue: 3, promised: 4,
                  partially_paid: 5, paid: 6, voided: 7 }, default: :draft
  # INV-1 — 부가세 별도/포함
  enum :tax_mode, { separate: 0, included: 1 }, default: :separate

  validates :due_on, :issuer_display_name, :bank_name, :account_number, :account_holder,
            presence: true
  validate :client_must_be_owned
  # INV-5 — 발행 후 본문 수정은 컨트롤러 draft 스코프와 모델 before_update 가드
  # (enforce_issued_content_immutable)로 이중 차단하고, 상태 전이는 issue!/void! 진입점에서
  # 상태를 재확인한다.
  # INV-1·SHARE-1/2 — 발행 시점에 채번·토큰·유효기간·발행 시각이 반드시 채워진다.
  validates :issue_number, :token, :token_expires_at, :issued_at, presence: true, on: :issue
  # PLAN-1 — 월 발행 한도(발행 시점)
  validate :free_plan_monthly_issue_limit, on: :issue
  validate :must_have_at_least_one_item
  # INV-1 — 품목 행 수 상한
  validate :items_count_within_limit

  normalizes :issuer_display_name, :bank_name, :account_holder, with: ->(value) { value.strip }

  before_validation :recalculate_amounts
  before_update :enforce_issued_content_immutable

  # DASH-4 — 연체일 내림차순과 동치인 정렬(연체일 = 오늘 − 만기일이므로 만기일 오름차순).
  scope :sorted_by_due, -> { order(due_on: :asc, id: :asc) }
  # 미수 = 발행 계열(초안·수금완료·무효 제외) — DASH-1 미수 총액의 모집단
  scope :unsettled, -> { where.not(status: [ :draft, :paid, :voided ]) }
  # 연체 파생 판정(결정 #2) — enum 자동 전환은 F-REM 스케줄러와 함께 한다.
  scope :overdue, -> { unsettled.where(due_on: ...Date.current) }
  scope :due_within, ->(range) { unsettled.where(due_on: range) }
  # INV-6 — 무효 처리 가능한 발행 계열
  scope :voidable, -> { where(status: VOIDABLE_STATUSES) }

  # 연체 파생 판정 — issued 계열이면서 만기일이 경과한 건(DASH-4 연체일 계산 기준)
  def overdue?
    unsettled? && due_on < Date.current
  end

  def days_overdue
    overdue? ? (Date.current - due_on).to_i : 0
  end

  def unsettled?
    !draft? && !paid? && !voided?
  end

  def voidable?
    VOIDABLE_STATUSES.include?(status)
  end

  # 발행(INV-4 draft→issued) — 채번(INV-1)·토큰(SHARE-1)·유효기간(SHARE-2)을 발급하고
  # PLAN-1 한도를 검사한다. 일별 채번 경합은 고유 인덱스 위반 시 재시도로 흡수한다.
  def issue!
    return false unless draft?

    self.status = :issued
    self.issued_at = Time.current
    reset_due_on_if_prefilled  # INV-3 — 미수정 프리필 만기일은 발행일 기준으로 재계산
    self.token = SecureRandom.urlsafe_base64(TOKEN_URLSAFE_BYTES)
    self.token_expires_at = (due_on + TOKEN_VALIDITY_DAYS_AFTER_DUE).end_of_day

    attempts = 0
    begin
      transaction do
        assign_issue_number
        save!(context: :issue)
      end
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      retry if attempts < 5
      errors.add(:base, "청구번호 발급에 실패했습니다. 잠시 후 다시 시도해 주세요")
      return false
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  # 무효(INV-6) — 발행 계열만 가능하며 링크 토큰을 즉시 폐기한다. 시퀀스 중단은
  # REM 도메인 부재로 이번 범위에서 N/A이다.
  def void!
    unless voidable?
      errors.add(:base, "발행된 청구서만 무효 처리할 수 있습니다")
      return false
    end

    self.status = :voided
    self.voided_at = Time.current
    self.token = nil
    save
  end

  # 금액 산식(정수 원) — 폼 실시간 요약(invoice_form_controller.js)과 동일 산식을 유지하고
  # 최종값은 서버 계산을 기준으로 한다.
  # - 행 합계 = Σ(수량 × 단가)
  # - 부가세 별도: 공급가액 = 행 합계, 부가세 = 공급가액의 10%(원 단위 반올림 — 사사오입)
  # - 부가세 포함: 청구 총액 = 행 합계, 공급가액 = (총액/1.1) 반올림, 부가세 = 총액 − 공급가액
  # - 원천징수(INV-2): 공급가액의 3.3% 내림(결정 #4), 실수령액 = 청구 총액 − 원천징수
  def self.compute_amounts(row_totals, tax_mode:, withholding_enabled:)
    rows_sum = row_totals.sum
    separate = tax_mode.to_s == "separate"

    subtotal = separate ? rows_sum : (rows_sum * 10 + 5) / 11
    tax_amount = separate ? (subtotal + 5) / 10 : rows_sum - subtotal
    total_amount = subtotal + tax_amount
    withholding = withholding_enabled ? subtotal * WITHHOLDING_RATE_PER_MILLE / 1000 : 0

    { subtotal: subtotal, tax_amount: tax_amount, total_amount: total_amount,
      withholding_amount: withholding, net_amount: total_amount - withholding }
  end

  private

  # 거래처는 본인 소유만 허용(소유권 격리 — Client와 동일 원칙)
  def client_must_be_owned
    return if client.nil? || user_id.nil?
    return if client.user_id == user_id

    errors.add(:client_id, "본인의 거래처만 선택할 수 있습니다")
  end

  # PLAN-1 — 당월 발행 건수 기준. 무효 처리된 건도 발행 이력이므로 포함해 산정한다.
  def free_plan_monthly_issue_limit
    return if user.nil?
    return if user.invoices.where(issued_at: Time.current.beginning_of_month..)
                   .count < FREE_MONTHLY_INVOICE_LIMIT

    errors.add(:base, "Free 플랜은 매월 #{FREE_MONTHLY_INVOICE_LIMIT}건까지 발행할 수 있습니다. Plus로 무제한 이용할 수 있습니다")
  end

  # INV-5 — 발행 계열(갱신 직전 상태가 draft가 아닌 레코드)의 본문 불변 가드. 보호 컬럼
  # 변경 또는 품목 행 변경(중첩 attributes로 함께 넘어온 경우)이 감지되면 저장을 중단한다.
  # 초안→발행(issue!)과 그 안의 due_on 재계산, void!의 상태·토큰·voided_at 기록은 통과한다.
  def enforce_issued_content_immutable
    return if status_was == "draft"
    return if (changed & PROTECTED_CONTENT_COLUMNS).empty? && !item_rows_changed?

    errors.add(:base, "발행된 청구서는 내용을 수정할 수 없습니다")
    throw(:abort)
  end

  def item_rows_changed?
    items.any? { |item| item.new_record? || item.changed? || item.marked_for_destruction? }
  end

  def must_have_at_least_one_item
    return unless items.reject(&:marked_for_destruction?).empty?

    errors.add(:base, "품목 행을 1개 이상 입력해 주세요")
  end

  # INV-1 — 품목 행 수 상한(위 MAX_ITEMS). 삭제 예정 행은 제외하고 센다.
  def items_count_within_limit
    return if items.reject(&:marked_for_destruction?).count <= MAX_ITEMS

    errors.add(:base, "품목 행은 최대 #{MAX_ITEMS}개까지 입력할 수 있습니다")
  end

  # INV-3 — 발행 시점 만기일 확정: 초안 작성일+30일 프리필을 사용자가 수정하지 않은 경우
  # (due_on이 프리필 원값 created_at+30일과 동일) PRD 원문대로 발행일+30일로 재계산한다.
  # 사용자가 명시적으로 수정한 만기일은 그대로 존중한다.
  def reset_due_on_if_prefilled
    return if created_at.nil? || due_on != created_at.to_date + DEFAULT_DUE_IN_DAYS

    self.due_on = issued_at.to_date + DEFAULT_DUE_IN_DAYS
  end

  # INV-1 — BD-YYYYMMDD-NNN 일별 순번 채번. 서비스 전역 일별 순번으로 고유 인덱스
  # 단일 기준을 만족하며, 경합 시 RecordNotUnique 재시도로 재채번한다.
  def assign_issue_number
    prefix = "BD-#{issued_at.to_date.strftime("%Y%m%d")}-"
    sequence = self.class.where("issue_number LIKE ?", "#{prefix}%").count + 1
    self.issue_number = "#{prefix}#{format("%03d", sequence)}"
  end

  # 품목 행(삭제 예정 행 제외)에서 금액 계산 컬럼을 재산정한다. nested attributes가
  # 검증 전 메모리에 적용되므로 저장 직전 최신값으로 계산된다.
  def recalculate_amounts
    rows = items.reject(&:marked_for_destruction?)
    amounts = self.class.compute_amounts(
      rows.map { |item| item.quantity.to_i * item.unit_price.to_i },
      tax_mode: tax_mode, withholding_enabled: withholding_enabled
    )
    assign_attributes(amounts)
  end
end
