class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    # 청구서(INV-1 필수 구성) — 발행 시점 스냅샷(표시명·계좌)과 계산 금액(원 단위 정수)을 함께 저장한다.
    # issue_number·token은 발행(issue!) 시점에 생성되므로 초안 단계 NULL을 허용하고 고유 인덱스로
    # 무결성을 보장한다(SQLite·Postgres 모두 NULL 다중 허용).
    create_table :invoices do |t|
      t.references :user, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true

      # INV-1 — 청구번호 BD-YYYYMMDD-NNN(일별 순번, 발행 시 채번)
      t.string :issue_number
      # INV-4 — 초안/발행/미열람/열람/연체/약속대기/부분입금/수금완료/무효
      t.integer :status, null: false, default: 0
      # INV-3 — 만기일(기본 발행일 + 30일)
      t.date :due_on, null: false
      # INV-1 — 부가세 별도(separate)/포함(included)
      t.integer :tax_mode, null: false, default: 0
      # INV-2 — 원천징수 3.3% 표기(프리랜서 프로필 기본값 반영)
      t.boolean :withholding_enabled, null: false, default: false

      # INV-1 — 발행자 표시명·입금 계좌 스냅샷(프로필 기본 프리필, 건별 변경)
      t.string :issuer_display_name, null: false
      t.string :bank_name, null: false
      t.string :account_number, null: false
      t.string :account_holder, null: false

      # 금액 계산 컬럼(정수 원) — subtotal 공급가액, tax 부가세, total 청구 총액,
      # withholding 원천징수액, net 실수령액. limit: 8 = bigint — PostgreSQL 이식 시에도
      # 단가 상한 조합(행당 1e13, 총액 1.1e13+)을 안전 저장한다(int4는 ±21.4억 한계).
      t.integer :subtotal, null: false, default: 0, limit: 8
      t.integer :tax_amount, null: false, default: 0, limit: 8
      t.integer :withholding_amount, null: false, default: 0, limit: 8
      t.integer :total_amount, null: false, default: 0, limit: 8
      t.integer :net_amount, null: false, default: 0, limit: 8

      # SHARE-1 — 추측 불가 고유 토큰(발행 시 생성, 무효 시 폐기)
      t.string :token
      # SHARE-2 — 링크 유효기간(만기일 + 60일)
      t.datetime :token_expires_at
      t.datetime :issued_at
      t.datetime :voided_at

      t.timestamps
    end
    add_index :invoices, :issue_number, unique: true
    add_index :invoices, :token, unique: true
    # DASH-4 — 연체일 내림차순(= 만기일 오름차순) 목록 조회
    add_index :invoices, [ :user_id, :due_on ]

    create_table :invoice_items do |t|
      t.references :invoice, null: false, foreign_key: true
      t.string :description, null: false
      t.integer :quantity, null: false
      t.integer :unit_price, null: false

      t.timestamps
    end
  end
end
