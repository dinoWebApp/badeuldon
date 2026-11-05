# F-REM(Phase 6 — 리뷰 C-1) — SEC-5 멱등 인덱스 재정의.
# 기존 인덱스(origin=auto 한정)는 수동(manual) 발송이 보낸 스텝을 자동 스캔이 별도 auto
# 로그로 재발송하는 경로(SEC-5 위반 — 동일 청구·동일 단계 2통)를 막지 못했다.
# - "동일 단계 정확히 1회" 판정 자체는 SendService의 origin 무관 sent 조회가 담당한다.
# - 이 인덱스는 "동시 진행 슬롯은 (청구서×템플릿)당 정확히 1개"(경합 선점)를 DB에서 보장한다.
# - recipient_role=debtor 조건은 유지 — U1 향(noti_*)은 단계별 반복이 정상이다.
# - status=pending 조건으로 수동 재발송(REM-8 — sent·failed·skipped는 인덱스 밖)의
#   이력 누적을 보장한다.
class ChangeMessageLogsIdempotencyIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :message_logs, name: "idx_message_logs_auto_debtor_uniq"
    add_index :message_logs, [ :invoice_id, :template_key ], unique: true,
              where: "recipient_role = 0 AND status = 0",
              name: "idx_message_logs_debtor_pending_uniq"
  end
end
