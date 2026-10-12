# 거래처(CLIENT-1) — U1이 입력·관리하는 청구 상대 정보. 소유권은 user_id로 격리하며
# 사용자 탈퇴 시 함께 삭제된다(AUTH-1.5 — dependent 삭제는 User 모델 연관에서 명시).
class CreateClients < ActiveRecord::Migration[8.1]
  def change
    create_table :clients do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false          # 거래처명
      t.string :contact_name, null: false  # 담당자명
      t.string :phone, null: false         # 알림 수신 휴대폰 번호
      t.string :email                      # 선택
      t.string :business_number            # 선택 — 사업자번호
      t.text :memo                         # 선택
      t.timestamps
    end
  end
end
