# 자동 갱신(F-PLAN — PLAN-2/5) — 매일 실행. 과금 주기가 끝난 구독을 처리한다.
# - 이용 중(active) + 빌링키 보유 → 포트원 빌링키 차감 → 주문(paid) 기록 + 1개월 주기 연장
# - 차감 실패 → 실패 주문 기록 + dunning 스케줄 진입(PLAN-5 — D+1·D+3·D+7 재차감,
#   3회 소진 시 cancelled — 기간 말 만료는 본 Job의 해지 경로가 담당)
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
    rescue PortOne::ClientService::MissingChannelKey => e
      # 채널 키 미등록(설정 오류 — PLAN-5)은 이 구독만 건너뛰고 나머지 대상(해지 후 만료
      # 강등 포함) 처리를 계속한다. 전용 예외만 잡는다 — 코드 오류는 잡 밖으로 나간다.
      Rails.logger.error("[SubscriptionRenewalJob] user=#{subscription.user_id} #{e.message}")
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
