# dunning 재차감(PLAN-5 — 2026-11-16 확정) — 자동 갱신 차감 실패 구독을 D+1·D+3·D+7에
# 동일 빌링키로 다시 차감한다. 실제 차감은 Subscriptions::UpgradeService(action: :retry_charge)
# 가 담당하며, 이 Job은 진입점(스칼라 id)과 멱등 가드만 소유한다.
#
# 멱등 설계 — Job이 여러 번 예약·실행돼도 안전하다:
# - 이미 차감 성공(reset_dunning!로 next_retry_at nil)·cancelled·expired면 no-op
# - next_retry_at이 미래로 이동했다(중간 실패로 재스케줄)면 그 시각으로 Job을 다시 건 뒤 종료
# - 차감 실패는 UpgradeError로 귀결되지만 이미 record_charge_failure!가 다음 단계를
#   스케줄했으므로 재시도 대열에 넣지 않는다(dunning 스케줄 자체가 재시도 계획이다).
module Subscriptions
  class DunningRetryJob < ApplicationJob
    queue_as :default

    # 구독 행이 삭제된 경우(계정 파기 등) — 재시도 무의미. dunning 스케줄이 재시도를
    # 통제하므로 일시적 오류의 retry_on은 두지 않는다(중복 차감 시도 방지).
    discard_on ActiveJob::DeserializationError

    def perform(subscription_id)
      subscription = Subscription.find_by(id: subscription_id)
      return if subscription.blank? || !subscription.dunning_active?

      if subscription.next_retry_at.present? && subscription.next_retry_at > Time.current
        Subscriptions::DunningRetryJob
          .set(wait: (subscription.next_retry_at - Time.current).seconds)
          .perform_later(subscription.id)
        return
      end

      Subscriptions::UpgradeService.new(user: subscription.user,
                                        action: :retry_charge).call
    rescue Subscriptions::UpgradeService::UpgradeError => e
      # 실패는 이미 주문(failed)·dunning 단계 진행(또는 cancelled)으로 기록됐다.
      Rails.logger.warn("[Subscriptions::DunningRetryJob] subscription=#{subscription_id} #{e.message}")
    rescue PortOne::ClientService::MissingChannelKey => e
      # 채널 키 미등록(설정 오류 — PLAN-5)은 카드 거절이 아니므로 실패 주문·dunning 단계
      # 진행 없이 그대로 둔다(설정 복구 후 재실행 대상 — 상태 변경 없음).
      Rails.logger.error("[Subscriptions::DunningRetryJob] subscription=#{subscription_id} #{e.message}")
    end
  end
end
