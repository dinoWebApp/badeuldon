# 품목 라이브러리(CLIENT-2) — 자주 쓰는 품목명·단가 저장. 단가는 정수(원)만 허용하며
# 0원(무상)도 유효하다. 소유권은 user_id로 격리, 탈퇴 시 함께 삭제된다(AUTH-1.5).
class CreateItems < ActiveRecord::Migration[8.1]
  def change
    create_table :items do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false                     # 품목명
      t.integer :unit_price, null: false, default: 0  # 단가(원) — 0 이상 정수
      t.timestamps
    end
  end
end
