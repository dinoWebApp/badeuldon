# 3-S 통합 결선 마이그레이션 — 병렬 배치(T3·T5·T6·T7) 스키마 선언 통합 반영
# T6: users 리마인더 발송 창(REM-3) / T7: users 다이제스트 토글 + message_logs.digest(NOTI-2)
# T5: subscriptions dunning 컬럼(PLAN-5) / T3: view_events 복합 인덱스(열람 중복 억제 조회)
# payments.note는 생성하지 않음 — T8이 감사 로그 기록으로 해소(후속 스키마 과제)
class ParallelBatch3sIntegration < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.string  :remind_allowed_wdays, null: false, default: "1,2,3,4,5"
      t.integer :remind_start_hour,   null: false, default: 9
      t.integer :remind_end_hour,     null: false, default: 18
      t.boolean :noti2_digest_enabled, null: false, default: true
    end

    change_table :subscriptions, bulk: true do |t|
      t.integer :dunning_stage, null: false, default: 0
      t.datetime :next_retry_at
      t.datetime :last_payment_failed_at
    end

    add_column :message_logs, :digest, :boolean, null: false, default: false

    add_index :view_events, [ :invoice_id, :ip, :viewed_at ],
              name: "index_view_events_on_invoice_ip_viewed_at"
  end
end
