# TAX-1/2(2026-11-16) — 전자세금계산서 발행 기록. 1청구 1발행(invoice_id unique — P4 발행
# 기록 영구 보존·중복 발행 차단의 DB 담보), 취소(canceled)도 레코드를 유지해 이력을 남긴다.
# 재발행은 이번 런 스코프 밖(PRD 후속 — canceled 후 발행 버튼 비활성·안내).
class CreateTaxInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :tax_invoices do |t|
      t.references :invoice, null: false, foreign_key: true, index: { unique: true }
      t.references :user, null: false, foreign_key: true
      # 바로빌 관리번호(24자 이내·회원사 단위 유니크 — "TI{user_id}I{invoice_id}" 채번)
      t.string :mgt_num, null: false
      # status — pending(발행 요청 후 바로빌 처리 확인 중) / issued(발급완료) /
      # canceled(발급 취소) / failed(전송 실패 등). barobill_state는 바로빌 원값(3014 등)을
      # 그대로 기록해 P4 진단 정보를 보존한다.
      t.integer :status, default: 0, null: false
      t.integer :barobill_state
      t.integer :nts_send_state
      # TAX-2 — 국세청 승인번호(NTSSendKey)
      t.string :nts_send_key
      t.date :write_date
      t.integer :supply_total, null: false
      t.integer :tax_total, null: false
      t.integer :grand_total, null: false
      # Q21 — 발행 수수료 결제 주문(건당 300원·포트원 단건). 결제 완료 후에만 발행된다.
      t.references :order, foreign_key: true
      t.timestamps
    end
    add_index :tax_invoices, :mgt_num, unique: true
    add_index :tax_invoices, :status
  end
end
