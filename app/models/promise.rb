# 채무자 응답(F-PROMISE) — 뷰어(③) 액션 4종(PROMISE-1)의 접수 기록. 어떤 가입·개인정보
# 입력 없이 링크 세션에서만 기록된다(PROMISE-2). created_at이 곧 접수시각이며 이력은
# 영구 보존한다(P4 — 재응답도 기존 레코드를 유지하고 청구서 약속 표시는 최신 응답 기준).
# kind별 의미:
#   this_week     「이번 주 내에 입금할게요」 — 약속일은 서버가 접수일 기준 산정(결정 #1)
#   date_selected 「입금 예정일 지정」     — 채무자 지정일(당일 허용, 어제 이전 차단 — 결정 #3)
#   paid_report   「이미 입금했어요」      — 시퀀스 정지·DASH-2 마감 대기. 마감은 U1 확인으로만
#                                            확정된다(허위 회신 방지 — PROMISE-7)
#   inquiry       「문의·이의 있어요」     — U1 답변 → 뷰어에서 채무자 확인(PROMISE-6)
# 약속(this_week·date_selected) 접수는 INV-4 issued|viewed→promised 전이의 원인이 되며
# 상태 전이는 Invoice#mark_promised!(Promises::RegisterService가 호출)가 담당한다.
class Promise < ApplicationRecord
  # memo 상한 — inquiry 자유 메모 남용 방지(플랜 결정 #3)
  MEMO_MAX_LENGTH = 2_000

  belongs_to :invoice

  # INV-4 — 응답 종류. 약속대기(promised) 진입 원인은 this_week·date_selected뿐이다.
  enum :kind, { this_week: 0, date_selected: 1, paid_report: 2, inquiry: 3 }

  # PROMISE-6 — 답변 상태 조회(뷰어 발행인 답변 표시·DASH-2 답변 대기)
  scope :answered, -> { where.not(answered_at: nil) }
  scope :unanswered, -> { where(answered_at: nil) }

  validates :kind, presence: true
  # memo — inquiry 전용 자유 메모(상한 2,000자). answer는 U1만 기록하며(App::PromisesController#answer),
  # 채무자 요청 경로의 허용 파라미터에는 절대 포함하지 않는다(PROMISE-2·P3).
  validates :memo, length: { maximum: MEMO_MAX_LENGTH }
  validates :memo, presence: { message: "문의 내용을 입력해 주세요" }, if: :inquiry?
  # date_selected — 채무자 지정 약속일. 당일 허용, 어제 이전 차단(결정 #3).
  validates :promised_on, presence: { message: "입금 예정일을 선택해 주세요" }, if: :date_selected?
  validate :promised_on_not_in_past, if: :date_selected?
  validates :answer, presence: { message: "답변 내용을 입력해 주세요" }, if: :answered_at?

  # kind별 필드 일관성(Phase 6 리뷰 #1) — kind에 맞지 않는 클라이언트 입력은 서버가 무시한다.
  # 약속일은 date_selected만 채무자 값을 받고(this_week는 아래 콜백이 서버 산정), memo는
  # inquiry만 받는다. 나머지 조합은 nil로 강제해 위조 요청이 U1 타임라인의 약속일 표시를
  # 오염하지 않게 한다(PROMISE-2 보조). 산정 콜백보다 먼저 선언해 this_week 산정값을 보존한다.
  before_validation :normalize_kind_fields

  # 결정 #1 — this_week는 채무자 입력 없이 서버가 KST 접수일 기준으로 약속일을 산정한다(TIME-1).
  before_validation :compute_this_week_promised_on, if: :this_week?

  # PROMISE-6 — U1 답변 등록(1문의 1답변 — 무답변 inquiry에 1회 한정). answered_at은
  # 이 메서드가 유일한 기록 경로다. 성공 true / 실패 false(errors로 P1 톤 안내).
  def answer!(text)
    unless inquiry? && answered_at.blank?
      errors.add(:base, "문의에는 한 번만 답변할 수 있습니다")
      return false
    end

    self.answer = text
    self.answered_at = Time.current
    save
  end

  private

  # 리뷰 #1 — kind별 허용 필드 외 입력의 강제 무시. paid_report·inquiry에 주입된 약속일,
  # 비-inquiry memo는 저장되지 않는다(P4 이력 무결성 보조).
  def normalize_kind_fields
    self.promised_on = nil unless date_selected?
    self.memo = nil unless inquiry?
  end

  # 결정 #1 — 「이번 주 금요일」: 접수일이 월~금이면 이번 주 금요일, 토·일이면 다음 주
  # 금요일(주 시작은 월요일). REM-3 평일 발송 기준과 정합되도록 주말을 약속일로 만들지 않는다.
  def compute_this_week_promised_on
    friday_offset = Date.current.saturday? || Date.current.sunday? ? 11 : 4
    self.promised_on = Date.current.beginning_of_week + friday_offset
  end

  def promised_on_not_in_past
    return if promised_on.nil? || promised_on >= Date.current

    errors.add(:promised_on, "입금 예정일은 오늘 또는 그 이후 날짜로 선택해 주세요")
  end
end
