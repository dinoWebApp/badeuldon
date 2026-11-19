# 월 정산 스냅샷(SALES-5 — F-SALES·Q24). rep·연월당 1행(복합 유니크). 행이 스냅샷이므로
# "이번 달 수령 예정(=직전월 실적)" 표기가 안정된다 — 집계 재실행은 pending 행만 덮어쓰고
# paid 행은 지급 확정 금액으로 보존한다(mark_paid 이후 재집계 방어). 지급(계좌 이체) 자체는
# 오프라인이며 원천징수 3.3%도 지급 시 오프라인 처리다(Q24 — 시스템은 스냅샷+mark paid까지).
class SalesCommission < ApplicationRecord
  enum :status, { pending: 0, paid: 1 }, default: :pending

  belongs_to :sales_rep

  validates :year, :month, :base_amount, :rate, :amount, presence: true
  validates :year, numericality: { only_integer: true }
  validates :month, inclusion: { in: 1..12 }
  validates :base_amount, :amount, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :rate, numericality: { only_integer: true, greater_than_or_equal_to: 0,
                                   less_than_or_equal_to: 100 }

  scope :for_year, ->(year) { where(year:) }
  scope :for_month, ->(year, month) { where(year:, month:) }
  scope :ordered, -> { order(:year, :month) }
  scope :pending, -> { where(status: :pending) }

  def period_label
    format("%d.%02d", year, month)
  end

  def mark_paid!
    return false if paid?

    update!(status: :paid, paid_at: Time.current)
    true
  end
end
