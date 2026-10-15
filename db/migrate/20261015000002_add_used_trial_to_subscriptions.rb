# F-PLAN 리뷰 이슈 #2 (PLAN-2) — 체험 무한 반복 차단용 플래그. 체험 만료(expire!)가
# trial_ends_at을 소각해 기존에는 체험 이력이 남지 않았고, 만료 직후 재체험이 가능했다.
# used_trial은 한번 체험을 시작하면 영구 유지되어 1인 1회(PLAN-2 "첫 14일")를 보장한다.
class AddUsedTrialToSubscriptions < ActiveRecord::Migration[8.1]
  def up
    add_column :subscriptions, :used_trial, :boolean, null: false, default: false

    # 기존 행 보정 — 플래그 도입 전에 체험을 시작한 구독(체험 중 행은 trial_ends_at이 남는다).
    # 만료 강등으로 trial_ends_at이 소각된 과거 체험은 복원 불가하나, 테스트 키 마일스톤이라
    # 실데이터 영향이 없다(최선 보정).
    execute <<~SQL
      UPDATE subscriptions SET used_trial = TRUE WHERE trial_ends_at IS NOT NULL
    SQL
  end

  def down
    remove_column :subscriptions, :used_trial
  end
end
