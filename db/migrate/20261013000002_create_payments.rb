# 입금(F-PAY — PAY-1 원클릭 마감·PAY-2 부분입금) — 청구서별 입금 이력. 금액은 정수 원이며
# 0·음수는 서비스·모델 검증과 무관하게 DB에서도 저장 불가하다(데이터 무결성 이중 방어).
# 입금일(paid_on)은 KST 기준일(기본 오늘)로 과거·당일만 허용하며 미래 차단은 모델 검증 담당.
class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :invoice, null: false, foreign_key: true
      t.integer :amount, null: false
      t.date :paid_on, null: false

      t.timestamps
    end

    add_check_constraint :payments, "amount > 0", name: "payments_amount_positive"
  end
end
