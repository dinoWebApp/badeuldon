# F-REM 발송 제어 상태(REM-7·REM-12/13·VIEW-7) — 청구·거래처 단위 발송 보류, 시퀀스 자동
# 종결, 수신거부 접수 시각. 값 존재가 곧 상태다(마킹 방식 — 해제는 컬럼 비움). promises의
# refusal kind(VIEW-7 회신 이력)는 integer 컬럼이라 enum 확장만으로 충분해 마이그레이션 없음.
class AddReminderColumnsToInvoicesAndClients < ActiveRecord::Migration[8.1]
  def change
    # REM-7 — 청구 건 단위 발송 보류(PROMISE-7 입금 완료 회신 접수·U1 액션에서 마킹)
    add_column :invoices, :reminders_suspended_at, :datetime
    # REM-12·REM-13 — 시퀀스 자동 종결(final_d14·promise_overdue 발송 성공·무효·수신거부)
    add_column :invoices, :sequence_finished_at, :datetime
    # REM-7 — 거래처 단위 발송 보류(U1 액션에서 마킹 — F-REM 3-b)
    add_column :clients, :reminders_suspended_at, :datetime
    # VIEW-7 — 수신거부 접수(거래처 번호 단위 즉시 중단. Promises::RegisterService refusal 경로)
    add_column :clients, :refused_at, :datetime
  end
end
