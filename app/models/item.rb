# 품목 라이브러리(CLIENT-2) — 품목명·단가만 저장한다(PRD 명시 필드 외 추가 금지).
# 청구서 작성 시 선택 연동은 F-INV에서 제공된다.
class Item < ApplicationRecord
  # CLIENT-2 — 단가 상한. 상한 없이 거대 값이 검증을 통과하면 저장 단계 RangeError(500)로
  # 이어지므로 검증에서 422로 전환한다. 폼 number_field의 max도 이 상수를 공유한다.
  MAX_UNIT_PRICE = 1_000_000_000

  belongs_to :user

  validates :name, presence: true
  # numericality의 allow_blank는 빈 값 오류를 presence 1건으로 좁히기 위함이다
  # (blank+not_a_number 중복 노출 제거).
  validates :unit_price, presence: true,
                         numericality: { only_integer: true,
                                         greater_than_or_equal_to: 0,
                                         less_than_or_equal_to: MAX_UNIT_PRICE,
                                         allow_blank: true }

  normalizes :name, with: ->(name) { name.strip }
end
