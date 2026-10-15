# 수금 패스(F-PLAN — PLAN-4) — 구독 없이 자동 시퀀스·응답 수집을 건별로 이용하는 이용권.
# 10건 4,000원, 발급일로부터 90일 유효. 사용 차감(use!)은 with_lock으로 직렬화해 동시 사용에도
# 잔여 횟수가 음수가 되지 않는다(DB 체크 제약 이중 방어).
class PaymentPass < ApplicationRecord
  # PLAN-4 — 발급 수량(10건)·유효일(90일)
  TOTAL_USES = 10
  VALIDITY_DAYS = 90

  class UsesExhausted < StandardError; end

  belongs_to :user

  validates :total_uses, :remaining_uses, presence: true
  validates :total_uses, :remaining_uses,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # 사용 가능한 패스 — 잔여 횟수 1 이상 && 유효기간 내. 목록 필터용 스코프와 같은 기준.
  scope :usable, -> { where(remaining_uses: 1..).where(expires_at: Time.current...) }

  def usable?
    remaining_uses.positive? && expires_at > Time.current
  end

  # 1건 사용 — 행 잠금 하에서 재판정 후 차감한다(두 탭 동시 클릭 흡수). 더 사용할 수 없으면
  # UsesExhausted(0이면 이후 사용 불가 — PLAN-4).
  def use!
    with_lock do
      raise UsesExhausted, "이미 모두 사용되었거나 만료된 수금 패스입니다" unless usable?

      update!(remaining_uses: remaining_uses - 1)
    end
    self
  end
end
