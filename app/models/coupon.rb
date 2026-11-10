# 쿠폰·프로모션(ADMIN-4 — Q12). Plus 첫 결제 1회 할인 한정이다: 자동 갱신(재과금)과
# 수금 패스에는 절대 적용되지 않는다(PLAN-2 정상가 유지). 코드 검증(존재·활성·만료·한도)은
# 모두 서버가 단일 판정점(redeemable?)으로 수행하고, used_count는 결제 성공 트랜잭션에서만
# 1회 증가한다(SEC-5 멱등 — charge 실패 시 증가 없음).
class Coupon < ApplicationRecord
  enum :discount_type, { percent: 0, amount: 1 }

  # amount 할인의 상한 — Plus 정가(PLAN-2). 정가 전액 할인(0원 차감)은 포트원 차감이
  # 성립하지 않으므로 redeemable?이 배제한다(0원 방지).
  MAX_AMOUNT_DISCOUNT = Subscription::PLUS_MONTHLY_PRICE

  # W-2 — 예약(coupon_id 참조)이 걸린 쿠폰 삭제는 조용한 nullify(예약 소멸 → 첫 차감 정가
  # 청구 불일치·P4 기록 부재) 대신 차단하고 사유를 errors로 남긴다(컨트롤러 alert 경유).
  # 주의: dependent: :nullify의 before_destroy가 연결 선언 시점에 먼저 등록되므로, 이 가드는
  # 반드시 has_many보다 "앞"에 선언해야 nullify보다 먼저 실행된다.
  before_destroy :reject_destroy_with_reservations

  # nullify는 도달하지 않는다(가드가 예약 보유 삭제를 차단 — 방어선으로 유지).
  has_many :subscriptions, dependent: :nullify

  normalizes :code, with: ->(code) { code.strip.upcase }

  validates :code, presence: true,
                   uniqueness: { case_sensitive: false },
                   format: { with: /\A[A-Z0-9]{8,16}\z/,
                             message: "은 대문자 영숫자 8~16자여야 합니다" }
  validates :name, presence: true
  validates :discount_value, presence: true, numericality: { only_integer: true }
  validates :max_redemptions, presence: true,
                              numericality: { only_integer: true, greater_than: 0 }
  validates :used_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  validate :discount_value_range_by_type

  def reject_destroy_with_reservations
    return unless subscriptions.exists?

    errors.add(:base, "사용 예정인 쿠폰은 삭제할 수 없습니다. 비활성화로 중지해 주세요.")
    throw :abort
  end

  # 적용 가능 판정(단일 판정점) — 활성·미만료·한도 잔여·차감 금액 성립(0원 이상 할인 금지).
  def redeemable?
    active? && !expired? && remaining_count.positive? && final_price_for(Subscription::PLUS_MONTHLY_PRICE).positive?
  end

  def expired?
    expires_at.present? && expires_at < Date.current
  end

  def remaining_count
    max_redemptions - used_count
  end

  # Plus 정가에 대한 첫 차감 금액(원). percent는 절사(floor) — 원 단위 미만 절삭.
  def final_price_for(price)
    discount = percent? ? (price * discount_value / 100) : discount_value
    price - discount
  end

  # 사용 가능 사유 안내(컨트롤러 flash용) — redeemable?이 false일 때의 구체 사유.
  def unavailability_reason
    return "비활성화된 쿠폰입니다" unless active?
    return "만료된 쿠폰입니다 (만료일: #{expires_at.strftime('%Y-%m-%d')})" if expired?
    return "사용 한도가 모두 소진된 쿠폰입니다" if remaining_count <= 0 # W-4 — 음수 잔여도 한도 초과로 안내

    "이 쿠폰은 할인 적용 후 결제 금액이 0원이 되어 사용할 수 없습니다"
  end

  # 결제 성공 시점 1회 증가(SEC-5) — 한도 가드(`used_count < max_redemptions`)를 포함한
  # 단일 조건부 UPDATE로 TOCTOU 경합을 원자 차단한다(W-1). 가드 미적용(잔여 0)이면
  # 영향 행 0 — false 반환으로 호출자(UpgradeService)가 결제를 중단할 수 있다.
  # 호출은 UpgradeService의 첫 차감 성공 트랜잭션 내부로 한정한다.
  def consume!
    affected = self.class.where(id: id)
                       .where("used_count < max_redemptions")
                       .update_all("used_count = used_count + 1") # rubocop:disable Rails/SkipsModelValidations
    return false if affected.zero?

    self.used_count += 1
    true
  end

  private

  def discount_value_range_by_type
    return if discount_value.blank? || !discount_value.is_a?(Integer)

    if percent?
      errors.add(:discount_value, "은(는) 1~100 사이여야 합니다") unless discount_value.between?(1, 100)
    elsif amount?
      errors.add(:discount_value, "은(는) 1~#{MAX_AMOUNT_DISCOUNT} 사이여야 합니다") unless discount_value.between?(1, MAX_AMOUNT_DISCOUNT)
    end
  end
end
