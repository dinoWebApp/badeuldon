# 채무자 응답(F-PROMISE) — 뷰어(③) 액션 4종의 접수 기록. invoice FK로 청구서와 묶으며,
# invoice_id 인덱스가 청구서 상세 타임라인·DASH-2 오늘의 액션 집계를 지원한다. created_at이
# 곧 접수시각이며 응답 이력은 영구 보존한다(P4 — 재응답도 기존 레코드를 유지한다).
class CreatePromises < ActiveRecord::Migration[8.1]
  def change
    create_table :promises do |t|
      t.references :invoice, null: false, foreign_key: true
      # kind — PROMISE-1 액션 4종(this_week/date_selected/paid_report/inquiry)
      t.integer :kind, null: false
      # promised_on — 약속일. this_week(접수 서버 산정)·date_selected(채무자 지정)만 존재하고
      # paid_report·inquiry는 null이다(kind별 의미 — Promise 모델 주석).
      t.date :promised_on
      # memo — 문의 자유 메모(inquiry 전용, 상한 2,000자 — 모델 검증)
      t.text :memo
      # answer — U1 답변(PROMISE-6 — 1문의 1답변). 채무자 요청 경로에는 절대 기록되지 않는다.
      t.text :answer
      # answered_at — 답변 등록 시각(KST 고정 — TIME-1). null이면 무답변(DASH-2 답변 대기).
      t.datetime :answered_at

      t.timestamps
    end
  end
end
