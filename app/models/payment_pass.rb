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

  # PLAN-9(Q27) — 회원 단위 수량 차감(관리자 환불 실행). 주문↔패스 연결 컬럼이 없어
  # "그 주문의 패스"만 무효화할 수 없으므로, 결제 수량만큼 회원의 유효한 패스(잔여 1 이상·
  # 만료 전)를 만료 임박순(expires_at 오래된 것 먼저)으로 차감한다. 잔여가 모자라면 그 패스를
  # 0으로 만들고 다음 패스로, 그래도 모자라면 0에서 끝내고 나머지는 무시한다(음수 방지 —
  # DB 체크 제약 remaining_uses >= 0 위반 없음). 차감은 건별 with_lock + 잠금 후 usable?
  # 재판정으로 직렬화한다(use!와 같은 이중 방어).
  # 반환: [실제 차감 건수, 무시된(미차감) 수량]
  def self.revoke_uses!(user:, count:)
    raise ArgumentError, "차감 수량은 1 이상이어야 합니다" unless count.to_i.positive?

    revoked = 0
    user.payment_passes.usable.order(:expires_at, :id).each do |pass|
      break if revoked >= count

      pass.with_lock do
        next unless pass.usable? # 잠금 시점 재판정 — 스코프 조회 시점과의 차이 흡수

        take = [ pass.remaining_uses, count - revoked ].min
        pass.update!(remaining_uses: pass.remaining_uses - take)
        revoked += take
      end
    end
    [ revoked, count - revoked ]
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
