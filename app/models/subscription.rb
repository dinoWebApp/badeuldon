# 구독(F-PLAN — PLAN-1/2) — 사용자당 1행(user_id 고유 인덱스). plan이 현재 요금제(free/plus),
# status가 Plus 생명주기(체험→이용→해지→만료)를 표현한다. Free 가입 직후 행이 존재하며
# (User 생성 콜백), 한도 판정(Client·Invoice 검증)은 이 모델의 limit 메서드가 단일 판정점이다.
# 구독 레코드가 없는 기존 사용자(기능 도입 이전 가입)는 User의 폴백이 Free 상수를 적용한다.
class Subscription < ApplicationRecord
  # PLAN-2 — Plus 월 9,900원(부가세 포함). 자동 갱신 차감 금액의 단일 지점.
  PLUS_MONTHLY_PRICE = 9_900
  # PLAN-2 — 첫 14일 무료 체험
  TRIAL_DAYS = 14
  # 자동 갱신 주기 — 1개월
  PERIOD_MONTHS = 1

  belongs_to :user

  enum :plan, { free: 0, plus: 1 }, default: :free
  # status — trialing: 체험 중, active: 이용 중(Free 가입 기본값 포함 — 현재 요금제가 효력 중),
  # cancelled: 해지(기간 종료까지 Plus 유지 — PLAN-5), expired: 만료(Free 강등 완료)
  enum :status, { trialing: 0, active: 1, cancelled: 2, expired: 3 }, default: :active

  # 토스 고객 식별자 고유(값 있을 시) — DB 부분 고유 인덱스와 이중 방어
  validates :toss_customer_key, uniqueness: true, allow_nil: true

  # 새 구독에는 즉시 토스 고객 식별자를 부여한다 — 카드(빌링) 인증 위젯의 customerKey로
  # 쓰이며 사용자당 안정적으로 재사용된다(재등록마다 새 키를 만들지 않는다).
  before_create { self.toss_customer_key ||= SecureRandom.uuid }

  # ── PLAN-1 한도 판정(단일 판정점) ──────────────────────────────────────────
  # Free는 상수값(Client·Invoice의 기존 상수를 단일 소스로 재사용), Plus는 무제한.
  # count는 호출부에서 산정한 현재 건수(거래처 수·당월 발행 수)다.

  def client_limit_reached?(current_count)
    return false if plus?

    current_count >= Client::FREE_CLIENT_LIMIT
  end

  def monthly_invoice_limit_reached?(current_count)
    return false if plus?

    # PLAN-4 — 사용 가능한 수금 패스가 있으면 한도 초과분을 패스로 발행한다(이슈 #7).
    # 발행 시점에 Invoice#issue!가 패스를 1건 소비한다.
    return false if user.payment_passes.usable.exists?

    current_count >= Invoice::FREE_MONTHLY_INVOICE_LIMIT
  end

  # ── 생명주기 ──────────────────────────────────────────────────────────────

  # PLAN-2 — 무료 체험은 계정당 1회다. used_trial 플래그는 체험 만료·강등 후에도 유지되므로
  # 만료 직후 재체험(무한 14일 Plus)이 불가능하다(이슈 #2).
  class TrialAlreadyUsedError < StandardError; end

  # 체험 시작(PLAN-2) — Plus 전환 + 14일 후 체험 종료. 이미 Plus면 호출하지 않는다
  # (UpgradeService가 가드), 체험 이력이 있으면 1회 가드로 거부한다.
  def start_trial!
    raise TrialAlreadyUsedError, "무료 체험은 이미 사용되었습니다" if used_trial?

    update!(plan: :plus, status: :trialing, trial_ends_at: TRIAL_DAYS.days.from_now,
            used_trial: true)
  end

  # 카드 등록 완료(빌링키 발급 성공) — 이용 중 전환 + 과금 주기 시작. 주기 종료 시점에
  # SubscriptionRenewalJob이 첫 차감을 수행한다.
  #
  # 주기 기준은 현재·체험 종료·기존 주기 종료 중 가장 미래 시점이다(이슈 #3):
  # ① 체험 중 조기 등록 — 체험 종료 후부터 유료 주기(체험 잔여일의 유료 편입 방지)
  # ② 해지 잔여 기간 중 재등록 — 기존 주기 종료 후부터 새 주기(이중 이용 구간 방지)
  def activate!(billing_key:, period: PERIOD_MONTHS)
    base = [ Time.current, trial_ends_at, current_period_end ].compact.max
    update!(plan: :plus, status: :active, toss_billing_key: billing_key,
            current_period_start: base, current_period_end: base + period.months)
  end

  # 해지(PLAN-5) — 기간 종료까지 Plus 유지. 실제 강등은 주기 종료 시 SubscriptionRenewalJob이
  # expire!로 수행한다.
  def cancel!
    update!(status: :cancelled)
  end

  # 만료 — Free로 강등하고 카드·주기 정보를 폐기한다. used_trial 플래그는 유지된다
  # (재체험 차단 — 이슈 #2). 재가입(카드 재등록) 시 activate!가 새 빌링키·주기로 덮어쓴다.
  def expire!
    update!(plan: :free, status: :expired, trial_ends_at: nil, toss_billing_key: nil,
            current_period_start: nil, current_period_end: nil)
  end
end
