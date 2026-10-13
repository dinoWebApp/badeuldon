# 입금(F-PAY — PAY-1·PAY-2) — 청구서 단위 입금 기록. 생성은 반드시 Payments::RecordService를
# 통한다(마감 전이까지 한 트랜잭션 — PAY-1). 금액은 정수 원이며 잔액 초과 등록은 서비스 계층에서
# 차단한다(결정 #3 — 초과 입금 기록 불가, 정확한 마감만 허용). 입금 이력은 영구 보존한다(P4).
class Payment < ApplicationRecord
  # PAY-2 — 단일 입금 상한 10억 원. 청구 총액 상한과 무관한 입력 폭주 방지선이며,
  # 잔액 초과는 서비스 계층의 재검증이 최종 기준이다(동시 등록 방어).
  MAX_AMOUNT = 1_000_000_000

  belongs_to :invoice

  validates :amount, presence: { message: "입금 금액을 입력해 주세요" },
                     numericality: { only_integer: true, greater_than: 0,
                                     less_than_or_equal_to: MAX_AMOUNT, allow_blank: true,
                                     message: "입금 금액은 1원 이상 #{MAX_AMOUNT}원 이하로 입력해 주세요" }
  validates :paid_on, presence: { message: "입금일을 입력해 주세요" }
  validate :paid_on_not_in_future

  private

  # PAY-1 — 입금일은 당일·과거만 허용(기본 오늘). 미래 입금은 기록할 수 없다(TIME-1 — KST 기준).
  def paid_on_not_in_future
    return if paid_on.nil? || paid_on <= Date.current

    errors.add(:paid_on, "입금일은 오늘 또는 그 이전 날짜로 선택해 주세요")
  end
end
