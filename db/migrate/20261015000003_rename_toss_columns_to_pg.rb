# 토스 → 포트원(KG이니시스) 전환(PLAN-5) — 결제 식별자 컬럼의 범용화(rename).
# 데이터는 그대로 유지하고 이름만 바꾼다: 토스 전용 접두어(toss_*)를 PG 무관 접두어(pg_*)로,
# payment_key는 포트원 규격 용어(payment_id — 우리가 채번한 paymentId)로 정렬한다.
# 고유 인덱스도 함께 갱신해 멱등성 제약(pg_order_id 고유)을 그대로 유지한다.
class RenameTossColumnsToPg < ActiveRecord::Migration[8.1]
  def up
    change_table :orders, bulk: true do |t|
      t.rename :toss_order_id, :pg_order_id      # 서버 채번 UUID — 포트원 paymentId로 사용
      t.rename :toss_payment_key, :pg_payment_id # 포트원 결제 ID(paymentId) 스냅샷
      t.rename :toss_billing_key, :pg_billing_key
    end
    rename_index :orders, "index_orders_on_toss_order_id", "index_orders_on_pg_order_id"
    rename_index :orders, "index_orders_on_toss_payment_key", "index_orders_on_pg_payment_id"

    # 부분 고유 인덱스 — SQLite는 인덱스 정의(WHERE 절 포함)를 원문으로 보관한다. 구컬럼명을
    # 참조하는 WHERE 절이 남은 채로 테이블 재구축(column rename)이 일어나면 실패하므로,
    # rename 전에 삭제하고 뒤에서 새 정의(pg_customer_key)로 다시 만든다.
    remove_index :subscriptions, name: "idx_subscriptions_on_toss_customer_key_uniq"
    change_table :subscriptions, bulk: true do |t|
      t.rename :toss_customer_key, :pg_customer_key # 포트원 customer.id — 빌링키 발급용
      t.rename :toss_billing_key, :pg_billing_key
    end
    add_index :subscriptions, :pg_customer_key, unique: true,
              where: "pg_customer_key IS NOT NULL", name: "idx_subscriptions_on_pg_customer_key_uniq"
  end

  def down
    # up과 대칭 — 부분 고유 인덱스를 먼저 지우고 컬럼을 되돌린 뒤 구정의로 다시 만든다.
    remove_index :subscriptions, name: "idx_subscriptions_on_pg_customer_key_uniq"
    change_table :subscriptions, bulk: true do |t|
      t.rename :pg_customer_key, :toss_customer_key
      t.rename :pg_billing_key, :toss_billing_key
    end
    add_index :subscriptions, :toss_customer_key, unique: true,
              where: "toss_customer_key IS NOT NULL", name: "idx_subscriptions_on_toss_customer_key_uniq"

    rename_index :orders, "index_orders_on_pg_order_id", "index_orders_on_toss_order_id"
    rename_index :orders, "index_orders_on_pg_payment_id", "index_orders_on_toss_payment_key"
    change_table :orders, bulk: true do |t|
      t.rename :pg_order_id, :toss_order_id
      t.rename :pg_payment_id, :toss_payment_key
      t.rename :pg_billing_key, :toss_billing_key
    end
  end
end
