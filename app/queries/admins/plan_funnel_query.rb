module Admins
  # ADMIN-5 — 플랜 전환 퍼널(가입 → 체험 시작 → Plus 전환).
  # 퍼널 정의는 ADMIN-5·Q4 퍼널 측정용 — 존재 컬럼 기반 실용 산정:
  #   체험 시작 = subscriptions.used_trial = true(체험 만료·강등 후에도 플래그 유지 — PLAN-2)
  #   Plus 전환 = plan plus 이면서 status가 active 또는 cancelled(해지는 기간 말까지 Plus — PLAN-5)
  class PlanFunnelQuery
    Row = Struct.new(:signups, :trial_started, :plus_converted, keyword_init: true)

    def self.call
      Row.new(
        signups: User.count,
        trial_started: Subscription.where(used_trial: true).count,
        plus_converted: Subscription.where(plan: :plus, status: [ :active, :cancelled ])
                                    .distinct.count(:user_id)
      )
    end
  end
end
