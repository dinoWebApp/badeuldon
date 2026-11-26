# AUTH-1.5·ADMIN-3(결정 기록 Q33 — 2026-11-26) — 회원 삭제 시 결제 기록 비식별 보관 5년.
# 식별 불가능한 사본 — user_id·이름·이메일·전화번호·빌링키·metadata·refund_reason은 담지 않는다.
# 원본 주문은 기존대로 연쇄 삭제(개인정보 즉시 파기)되며, 이 테이블은 전자상거래법·
# 개인정보처리방침 §3의 계약·결제 기록 5년 보존 의무만 충족한다. 보존 기준은 withdrawn_at(탈퇴 시각).
class CreateWithdrawnPaymentRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :withdrawn_payment_records do |t|
      # Order의 enum 값을 담는다 — 보관 시 enum 라벨을 복사하며 insert_all이 위 모델의
      # enum 매핑으로 Order와 같은 정수로 직렬화한다(값 의미는 Order 모델 단일 출처).
      t.integer :product, null: false
      t.integer :item_type, null: false
      t.integer :amount, null: false
      t.integer :status, null: false
      # 보관 멱등 키 — 원본 주문의 PG 주문번호(식별자가 아닌 주문번호).
      t.string :pg_order_id, null: false
      t.string :pg_payment_id
      t.datetime :order_created_at
      t.datetime :paid_at
      t.datetime :refunded_at
      # 보존 기준일(탈퇴 시각) — 5년 경과분 파기 범위 조회 인덱스.
      t.datetime :withdrawn_at, null: false

      t.timestamps null: false
    end

    add_index :withdrawn_payment_records, :pg_order_id, unique: true
    add_index :withdrawn_payment_records, :withdrawn_at
  end
end
