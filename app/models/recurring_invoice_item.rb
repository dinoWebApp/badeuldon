# 반복 청구 스케줄 품목(INV-7) — 매월 동일 발행의 스냅샷 소스. 발행 시
# RecurringInvoices::IssueService가 이 행을 InvoiceItem(description·quantity·unit_price)로
# 복제하며, 금액 계산은 Invoice.recalculate_amounts가 단일 담당한다.
class RecurringInvoiceItem < ApplicationRecord
  # 상한은 InvoiceItem과 동일 기준(수량·단가 곱이 정수 범위를 넘지 않도록)
  MAX_QUANTITY = InvoiceItem::MAX_QUANTITY
  MAX_UNIT_PRICE = InvoiceItem::MAX_UNIT_PRICE

  belongs_to :recurring_invoice

  validates :name, presence: true
  validates :quantity, presence: true,
                       numericality: { only_integer: true,
                                       greater_than_or_equal_to: 1,
                                       less_than_or_equal_to: MAX_QUANTITY,
                                       allow_blank: true }
  validates :unit_price, presence: true,
                         numericality: { only_integer: true,
                                         greater_than_or_equal_to: 0,
                                         less_than_or_equal_to: MAX_UNIT_PRICE,
                                         allow_blank: true }

  normalizes :name, with: ->(name) { name.strip }
end
