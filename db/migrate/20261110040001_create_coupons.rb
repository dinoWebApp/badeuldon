# ADMIN-4 쿠폰·프로모션(Q12) — 쿠폰 1테이블 + 구독 첫 결제 할인 예약 컬럼 + 감사 로그
# 사용자 행위 기록을 위한 admin_id null 허용(파생 최소 변경 — 03 문서 파일별 사유 참조).
# 쿠폰은 Plus 첫 결제 1회 할인 한정: percent(1~100)·amount(1~9,900 — 0원 방지)·
# max_redemptions/used_count(결제 성공 시점 1회 증가 — SEC-5 멱등)·expires_at(date)·active.
class CreateCoupons < ActiveRecord::Migration[8.1]
  def change
    create_table :coupons do |t|
      t.string :code, null: false                        # 대문자 영숫자 8~16자 — 모델 형식 검증
      t.string :name, null: false                        # 관리자 식별용 표시명
      t.integer :discount_type, null: false, default: 0  # percent: 0 / amount: 1
      t.integer :discount_value, null: false             # percent는 1~100, amount는 1~9,900
      t.integer :max_redemptions, null: false            # 총 사용 한도(건)
      t.integer :used_count, null: false, default: 0     # 결제 성공 건수 — 성공 시점에만 증가
      t.date :expires_at                                 # nil = 만료 없음
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :coupons, :code, unique: true

    # U1 쿠폰 적용 예약 — 구독에 걸린 쿠폰이 첫 Plus 차감(renew 경유)에 1회 소비된다.
    # 첫 차감 성공 트랜잭션에서 nil로 환원되므로 "적용 1회·재과금 정상가"가 상태로 보장된다.
    add_reference :subscriptions, :coupon, foreign_key: true

    # coupon_redeemed 감사(U1 행위 — 관리 행위 아님, ADMIN-4 추적 목적)를 위해 admin_id를
    # null 허용으로 완화한다. 기존 admin 행위 로그는 전부 admin_id를 유지한다.
    change_column_null :audit_logs, :admin_id, true
  end
end
