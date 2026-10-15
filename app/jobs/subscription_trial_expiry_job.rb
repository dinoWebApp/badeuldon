# 체험 종료 강등(F-PLAN — PLAN-2) — 매일 실행. 체험 기간이 끝났는데 빌링키(카드)가 없는
# 구독을 Free로 강등한다. 카드가 있으면 App::SubscriptionsController#update(카드 등록)에서
# 이미 active로 전환된 뒤라 이 잡 대상이 아니다. 멱등 — expire 처리는 이미 만료된 구독을
# 무변경으로 흡수한다(Subscriptions::UpgradeService#expire).
# 해지(cancelled)도 체험 종료를 무효화하지 않는다 — 체험 중 해지한 구독(이슈 #6 가드의
# trialing 해지 허용)은 종료 시점에 같은 방식으로 강등되지 않으면 Plus 무기한 방치가 된다.
class SubscriptionTrialExpiryJob < ApplicationJob
  queue_as :default

  def perform
    due_trials.find_each do |subscription|
      Subscriptions::UpgradeService.new(user: subscription.user, action: :expire).call
    end
  end

  private

  # 체험 종료 대상 — 체험 중(trialing) 또는 체험 중 해지(cancelled) 상태로 체험 종료가
  # 지났고 카드가 없는 구독. 체험 종료일 기준 판정이므로 status가 무엇이든 이력상 체험이다.
  def due_trials
    Subscription.where(status: [ :trialing, :cancelled ])
                .where.not(trial_ends_at: nil)
                .where(trial_ends_at: ...Time.current, pg_billing_key: nil)
  end
end
