# 기술 부채-DB 통합 마이그레이션(병렬 배치 T3) — 2건:
# ① payments.note(Q22 구조화) — 과다입금(잔액 초과) 마감 건의 초과분 비고를 감사 로그에서
#    마감 기록 자체로 승격한다. P4("모든 발신은 기록"의 기록 무결성 준용) — 비고는
#    Payments::RecordService가 감사 로그와 병행해서만 쓴다(사용자 입력 경로 없음 → null 허용).
# ② message_logs digest 주 단위 멱등 부분 유니크 인덱스(W-1 DB 방어선) — WeeklyDigestService의
#    멱등 판정 쿼리 MessageLog.exists?(user_id:, template_key:, scheduled_at:)와 정확히 같은
#    3컬럼 키에, digest=true(digest=1) 행 한정 유니크 제약을 건다. 경합(동시 실행)에서도
#    주 1행이 DB에서 보장된다(SEC-5 — debtor pending 슬롯 인덱스 선례와 같은 부분 유니크
#    방식). where 절은 기존 선례(idx_message_logs_debtor_pending_uniq)와 같은 SQLite 정수
#    표현을 쓴다. 애플리케이션 멱등 판정(exists? → create!)은 유지한다 — 인덱스는 최후
#    방어선이며 친절한 :duplicate 반환은 서비스가 담당한다.
class TechDebtPaymentsNoteAndDigestIndex < ActiveRecord::Migration[8.1]
  def up
    add_column :payments, :note, :string
    dedup_digest_logs!
    add_index :message_logs, [ :user_id, :template_key, :scheduled_at ],
              name: "idx_message_logs_digest_period_uniq",
              unique: true, where: "digest = 1"
  end

  def down
    remove_index :message_logs, name: "idx_message_logs_digest_period_uniq"
    remove_column :payments, :note
  end

  private

  # 인덱스 생성 실패 방어 — 운영 digest 행 중복(경합 유래)이 있으면 유니크 인덱스 생성이
  # 실패하므로 같은 (user_id·template_key·scheduled_at) 묶음에서 최신 1행만 남기고 오래된
  # 행을 삭제한다. digest 행은 주 단위 1회 기록이 의도라 동일 주기 중복은 내용상 동치이며,
  # 최신 행이 실제 발송 상태(sent/failed)를 가장 잘 대표한다. 삭제는 비가역 — down에서
  # 되돌리지 않는다(P4 영구 기록 중 "중복 사본"만 제거, 유효 기록은 1행 보존).
  def dedup_digest_logs!
    execute <<~SQL.squish
      DELETE FROM message_logs
      WHERE digest = 1
        AND id NOT IN (
          SELECT MAX(id) FROM message_logs WHERE digest = 1
          GROUP BY user_id, template_key, scheduled_at
        )
    SQL
  end
end
