# 반복 청구(INV-7) — 스케줄(recurring_invoices) + 스냅샷 소스 품목(recurring_invoice_items).
# 발행 자체는 기존 invoices(Invoice#issue!)로 이뤄지며 이 테이블은 월 1회 자동 발행의 설정과
# 마지막 결과(last_issued_on·last_invoice_id·last_skip_reason)만 기록한다.
# client_id — client 삭제는 발행 이력 보유 시 모델 가드로 차단되고, 가드를 통과한 삭제는
# has_many dependent: :destroy + FK on_delete: :cascade로 스케줄을 함께 정리한다(고아 방지).
class CreateRecurringInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :recurring_invoices do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :client, null: false, foreign_key: { on_delete: :cascade }
      # 직전 발행 청구(보류 판정 hold_if_unpaid·상세 화면 발행 이력 링크용) — 미발행 스케줄은 null.
      # 청구서는 발행 계열에서 삭제 경로가 없어(P4) FK는 기록 보존 원칙상 restrict로 둔다.
      t.references :last_invoice, foreign_key: { to_table: :invoices, on_delete: :restrict }
      # 매월 발행일 — 월말(29~31) 말일 이슈 회피로 1~28 한정(모델 검증)
      t.integer :day_of_month, null: false
      t.integer :tax_mode, default: 0, null: false        # Invoice.tax_mode와 동일 enum
      t.boolean :withholding_enabled, default: false, null: false
      t.boolean :hold_if_unpaid, default: false, null: false  # 직전 청구 미수금 시 보류(INV-7)
      t.integer :status, default: 0, null: false          # active:0 / paused:1 / cancelled:2
      t.date :last_issued_on
      t.date :next_issue_on, null: false
      t.string :last_skip_reason                          # NOTI-3 — 보류·한도 skip 사유 기록
      t.timestamps
    end

    add_index :recurring_invoices, [ :user_id, :next_issue_on ]

    create_table :recurring_invoice_items do |t|
      t.references :recurring_invoice, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false                         # 발행 시 InvoiceItem.description로 스냅샷
      t.integer :quantity, null: false, default: 1
      t.integer :unit_price, null: false, default: 0
      t.timestamps
    end
  end
end
