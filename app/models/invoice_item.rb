# 청구서 품목 행(INV-1) — 설명·수량·단가. 금액 자체는 저장하지 않고 Invoice 계산 컬럼에
# 합산된다(합계 = Σ(수량 × 단가), 산식은 Invoice.compute_amounts 단일 지점).
class InvoiceItem < ApplicationRecord
  # 수량 상한 — 단가 상한(CLIENT-2의 Item::MAX_UNIT_PRICE)과의 곱이 64bit 정수·JS 안전
  # 정수 범위를 넘어 RangeError(500)로 이어지지 않도록 Item 상한 도입과 같은 취지로 둔다.
  MAX_QUANTITY = 10_000
  # CLIENT-2 — 단가 상한은 품목 라이브러리와 동일 상수를 공유한다.
  MAX_UNIT_PRICE = Item::MAX_UNIT_PRICE

  belongs_to :invoice

  validates :description, presence: true
  # numericality의 allow_blank는 빈 값 오류를 presence 1건으로 좁히기 위함이다(Item과 동일).
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

  normalizes :description, with: ->(description) { description.strip }
end
