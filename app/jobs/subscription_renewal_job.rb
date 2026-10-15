# 자동 갱신(F-PLAN — PLAN-2/5) — 매일 실행. 과금 주기가 끝난 구독을 처리한다.
# - 이용 중(active) + 빌링키 보유 → 포트원 빌링키 차감 → 주문(paid) 기록 + 1개월 주기 연장
# - 차감 실패 → 실패 주문 기록 + 즉시 만료 강등(dunning 미실시 — 이번 마일스톤 확정 사항)
# - 해지(cancelled) 후 주기 종료 → 만료 강등(PLAN-5 — 해지 시 기간 말까지 이용)
# 멱등 — 주기 연장 후 current_period_end가 미래가 되어 재실행 대상에서 제외된다.
class SubscriptionRenewalJob < ApplicationJob
  queue_as :default

  def perform
    due_subscriptions.find_each do |subscription|
      Subscriptions::UpgradeService.new(user: subscription.user, action: :renew).call
    rescue Subscriptions::UpgradeService::UpgradeError => e
      # 갱신 실패는 이미 주문(failed)·강등으로 기록됐다 — 나머지 대상 처리를 계속한다.
      Rails.logger.warn("[SubscriptionRenewalJob] user=#{subscription.user_id} #{e.message}")
    end
  end

  private

  # 주기 종료 대상 — 이용 중(차감 대상) 또는 해지(강등 대상). 주기가 설정된 구독만이다.
  def due_subscriptions
    Subscription.where(status: [ :active, :cancelled ])
                .where.not(current_period_end: nil)
                .where(current_period_end: ...Time.current)
  end
end
