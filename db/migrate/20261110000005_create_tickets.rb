# F-ADMIN Run C 3-b — 1:1 문의 티켓(ADMIN-8). tickets(헤더: 사용자·분류·제목·상태) +
# ticket_messages(스레드 본문). message_logs는 티켓 알림 기록을 위해 invoice_id NOT NULL을
# 완화하고 ticket_id(nullable)를 추가한다(REM-6/P4 확장 — 티켓 알림톡도 발신 기록에 남긴다).
# 기존 부분 유니크 인덱스(debtor×pending)와 청구 집계 쿼리는 invoice_id가 계속 채워지는
# 행만 대상이므로 무영향(티켓 알림은 invoice_id nil·recipient_role=user로 인덱스 밖).
class CreateTickets < ActiveRecord::Migration[8.1]
  def change
    create_table :tickets do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      # 분류 5종 — PRD ADMIN-8(결제/이용 문의/버그 제보/기능 제안/기타). default는 etc.
      t.integer :category, null: false, default: 4
      t.string :title, null: false # 100자 상한은 모델 검증(뷰 maxlength 병행)
      # 접수(open) → 답변(answered) → 종료(closed). 사용자 추가 질문 시 open 복귀.
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :tickets, :status

    create_table :ticket_messages do |t|
      t.references :ticket, null: false, foreign_key: { on_delete: :cascade }
      # user:0(문의자) / admin:1(운영자 답변)
      t.integer :sender, null: false
      t.text :body, null: false # 2,000자 상한은 모델 검증
      t.timestamps
    end

    # REM-6/P4 확장 — 티켓 알림 발송 기록. nullability 완화 + nullable FK 추가만으로
    # 기존 쿼리·부분 유니크 인덱스는 무영향(위 모듈 주석 참조).
    change_column_null :message_logs, :invoice_id, true
    add_reference :message_logs, :ticket, foreign_key: { on_delete: :cascade }
  end
end
