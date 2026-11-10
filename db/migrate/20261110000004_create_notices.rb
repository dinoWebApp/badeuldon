# F-ADMIN Run C — 운영 공지(ADMIN-6 관리·ADMIN-7 노출) 2테이블.
# notices(중요도 enum·게시 기간 published_at~expires_at, expires_at nil=무기한) ·
# notice_reads(사용자별 읽음 — 복합 유니크 [user_id, notice_id]로 재시도 멱등 보장, SEC-5 성격).
class CreateNotices < ActiveRecord::Migration[8.1]
  def change
    create_table :notices do |t|
      t.string :title, null: false
      t.text :body, null: false
      # ADMIN-6 중요도 — general:0(일반·배너) / important:1(중요·팝업). 열거 안정성용 기본값 0.
      t.integer :importance, null: false, default: 0
      t.datetime :published_at               # nil = 미발행 초안(관리자 publish로 기록)
      t.datetime :expires_at                 # nil = 무기한 게시
      t.timestamps
    end
    add_index :notices, :published_at
    add_index :notices, :importance

    create_table :notice_reads do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :notice, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    # 같은 사용자가 같은 공지를 두 번 읽을 수 없다 — 중복 POST에도 1건(SEC-5 멱등).
    add_index :notice_reads, [ :user_id, :notice_id ], unique: true
  end
end
