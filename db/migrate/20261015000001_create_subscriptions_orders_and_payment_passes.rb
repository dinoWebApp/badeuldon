# F-PLAN 구독·과금(PLAN-1~5) — 구독(Subscription)·주문(Order)·수금 패스(PaymentPass).
# 1인 1구독은 user_id 고유 인덱스로 DB에서 강제하며, 토스 식별자(toss_order_id·toss_customer_key)
# 는 고유 인덱스로 멱등성·중복 발급을 막는다. 금액은 정수 원(PAY 도메인과 동일 원칙)이며
# 수금 패스의 잔여 횟수는 음수 불가 체크 제약으로 이중 방어한다.
class CreateSubscriptionsOrdersAndPaymentPasses < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      # 1인 1구독 — 고유 인덱스(PLAN 구조 상 user:subscription = 1:1). on_delete: :cascade는
      # dependent: :destroy를 우회한 원시 삭제(테스트 teardown delete_all 등)에서도 자식 행이
      # 사용자 삭제를 막지 않게 하는 DB 방어선이다. model destroy 경로와 이중이지만 무해하다.
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      # plan — Free(0)·Plus(1, 월 9,900원 — PLAN-2)
      t.integer :plan, null: false, default: 0
      # status — trialing(체험)·active(이용 중)·cancelled(해지, 기간 종료까지 유지)·expired(만료·Free 강등)
      t.integer :status, null: false, default: 1
      t.datetime :trial_ends_at   # 체험 종료 시각(14일 — PLAN-2)
      t.datetime :current_period_start
      t.datetime :current_period_end
      # 토스 고객 식별자 — 빌링키 발급용으로 사용자당 안정적으로 재사용한다
      t.string :toss_customer_key
      # 토스 빌링키 — 자동결제 차감에 쓰인다(테스트 키 마일스톤은 평문 저장, 전환 시 암호화 검토)
      t.string :toss_billing_key

      t.timestamps
    end

    # 값이 있을 때만 고유 — NULL은 중복 허용(빌링키 미발급 구독이 다수)
    add_index :subscriptions, :toss_customer_key, unique: true,
              where: "toss_customer_key IS NOT NULL", name: "idx_subscriptions_on_toss_customer_key_uniq"

    create_table :orders do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      # product — plus_monthly(Plus 월 구독 결제)·collection_pass(수금 패스 단건 — PLAN-4)
      t.integer :product, null: false
      # amount — 정수 원. 부가세 포함 표시가(PLAN-2·4)의 원값을 그대로 저장한다
      t.integer :amount, null: false
      # status — pending(결제 대기)·paid(승인)·failed(실패)·cancelled(취소·환불 반영)
      t.integer :status, null: false, default: 0
      # 서버 생성 UUID — 위젯 요청·승인 confirm·웹훅이 이 값으로 정합을 맞춘다
      t.string :toss_order_id, null: false
      t.string :toss_payment_key
      t.string :toss_billing_key
      t.datetime :paid_at
      # 토스 응답 스냅샷 — 승인·실패 응답 원문 보관(웹훅 무결성 재검증 근거)
      t.json :metadata

      t.timestamps
    end

    add_index :orders, :toss_order_id, unique: true
    # 웹훅(paymentStatusChanged)이 toss_payment_key로 주문을 찾는 조회 경로
    add_index :orders, :toss_payment_key

    create_table :payment_passes do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      # PLAN-4 — 10건 4,000원, 90일 유효
      t.integer :total_uses, null: false, default: 10
      t.integer :remaining_uses, null: false, default: 10
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_check_constraint :payment_passes, "remaining_uses >= 0", name: "payment_passes_remaining_uses_non_negative"
  end
end
