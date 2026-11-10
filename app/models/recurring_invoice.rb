# 반복 청구 스케줄(INV-7) — 월 1회(day_of_month 1~28) 자동 발행 설정. 실제 발행은
# RecurringInvoices::IssueService가 Invoice#issue! 기존 플로우(채번·토큰·PLAN-1·수금 패스)로
# 수행하며, 이 모델은 설정·다음 발행일·마지막 결과(last_issued_on·last_skip_reason)를 관리한다.
class RecurringInvoice < ApplicationRecord
  # INV-7 — 스케줄 상태. 일시중지·해지는 U1 액션(pause/resume/cancel)으로만 전이한다.
  enum :status, { active: 0, paused: 1, cancelled: 2 }, default: :active
  # Invoice.tax_mode와 동일 enum(0=separate 부가세 별도 / 1=included 포함) — 발행 시 그대로 이관
  enum :tax_mode, { separate: 0, included: 1 }, default: :separate

  # 월말(29~31) 말일 이슈 회피 — 1~28 한정(02_prd_update 확정 해석·등록 UI도 1~28 한정)
  DAY_OF_MONTH_RANGE = 1..28

  belongs_to :user
  belongs_to :client
  # 직전 발행 청구 — hold_if_unpaid 보류 판정·상세 화면 발행 이력의 기준점
  belongs_to :last_invoice, class_name: "Invoice", optional: true
  has_many :items, class_name: "RecurringInvoiceItem", dependent: :destroy, inverse_of: :recurring_invoice

  accepts_nested_attributes_for :items, reject_if: :all_blank

  validates :day_of_month, presence: true, inclusion: { in: DAY_OF_MONTH_RANGE }
  # 거래처는 본인 소유만 허용(Invoice.client_must_be_owned와 동일 소유권 격리)
  validate :client_must_be_owned
  validate :must_have_at_least_one_item

  # 발행일 미지정 저장 방지 — 컨트롤러 create에서 initialize_next_issue_on!을 먼저 부르므로
  # 이 훅은 테스트·직접 생성 경로의 폴백이다.
  before_validation :initialize_next_issue_on!,
                    if: -> { next_issue_on.blank? && RecurringInvoice::DAY_OF_MONTH_RANGE.cover?(day_of_month) }

  # 발행 대상 — 이용 중이며 발행일이 오늘 또는 이미 경과(C-2 — 잡 미실행일의 커서 고착을
  # 완화해 다음 실행에 반드시 1회 발행한다. 정확히 1회 보장은 IssueService 가드·with_lock이
  # 담당). IssueJob의 스캔 모집합.
  scope :due_or_overdue, -> { active.where(next_issue_on: ..Date.current) }
  scope :sorted_by_next_issue, -> { order(next_issue_on: :asc, id: :asc) }

  # 다음 발행일 초기화 — 등록 시점 기준 다음 달 N일(이번 달 N일이 지났으면 당연히 다음 달).
  # 같은 달이라도 오늘 이후라면 당월 N일에 즉시 시작하는 편이 자연스럽다.
  def initialize_next_issue_on!
    today = Date.current
    candidate = today.change(day: day_of_month)
    self.next_issue_on = candidate > today ? candidate : candidate.next_month
  end

  # 발행 성공 후 커서 갱신(02_prd_update 불변식 — 발행 커밋 성공 후·IssueService 트랜잭션 안에서
  # 호출). last_issued_on·last_invoice를 남기고 다음 발행일은 다음 달 N일로 미룬다(1~28 한정이라
  # 월말 클램프 불요). 커서 기준은 구값(next_issue_on)다 — 늦은 실행(C-2 완화 발행)이 다음
  # 발행일을 함께 미끄러뜨리는 드리프트를 막는다.
  def advance!(invoice)
    self.last_invoice = invoice
    self.last_issued_on = Date.current
    self.next_issue_on = next_issue_on.next_month.change(day: day_of_month)
    self.last_skip_reason = nil
    save!
  end

  # 발행 skip(INV-7 보류·PLAN-3 한도·issue! 실패) — 사유를 기록(NOTI-3 통보 데이터)하고
  # 다음 발행일을 다음 달로 미룬다. 이번 달 재시도 없음(월 1회 불변식 유지). 커서 기준은
  # advance!와 동일하게 구값(next_issue_on) — 드리프트 없음.
  def hold!(reason)
    self.last_skip_reason = reason
    self.next_issue_on = next_issue_on.next_month.change(day: day_of_month)
    save!
  end

  private

  def client_must_be_owned
    return if client.nil? || user_id.nil?
    return if client.user_id == user_id

    errors.add(:client_id, "본인의 거래처만 선택할 수 있습니다")
  end

  def must_have_at_least_one_item
    return unless items.empty?

    errors.add(:base, "품목 행을 1개 이상 입력해 주세요")
  end
end
