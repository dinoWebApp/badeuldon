# F-REM 발송 이력(REM-6·P4·SEC-5·PLAN-3) — 모든 알림톡 발신 시도(성공·실패·스킵)의 영구 기록.
# SEC-5 멱등: 자동(origin=auto) 채무자(recipient_role=debtor) 발송은 [invoice_id, template_key]
# 부분 유니크 인덱스로 동일 청구·동일 스텝 1회가 DB에서 보장된다. 사용자 향 알림(noti_prenotice는
# 단계별 반복이 정상)과 수동 재발송(REM-8)은 인덱스 밖이다. variables는 발송 변수 기록(P4·REM-6),
# phone은 수신번호 스냅샷이다.
class CreateMessageLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :message_logs do |t|
      t.references :invoice, null: false, foreign_key: { on_delete: :cascade }
      # 소유 U1 — REM-6 이력의 소유자(조회·CSV 내보내기 단위). invoice.user와 항상 일치(모델 검증).
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      # 수신자 — debtor(채무자·거래처)·user(프리랜서 U1)
      t.integer :recipient_role, null: false, default: 0
      # 솔라피 템플릿 키 — credentials solapi.template_ids의 키(ALIMTALK_TEMPLATES.md)와 동일 문자열
      t.string :template_key, null: false
      # 발신 주체 — auto(자동·SEC-5 멱등 대상)·manual(수동 재발송 허용 — REM-8)
      t.integer :origin, null: false, default: 0
      # 발송 결과 — pending(시도 중)·sent·failed(API 실패)·skipped(가드 차단)
      t.integer :status, null: false, default: 0
      t.string :phone               # 수신번호 스냅샷(P4)
      t.text :variables             # 발송 시 조립한 #{변수명} 치환값 기록(REM-6)
      t.string :provider_message_id # 솔라피 메시지 식별자
      # 실패 코드(Solapi::ApiError#code) 또는 스킵 사유(REFUSED/SUSPENDED/FINISHED/
      # INVALID_STATUS/INELIGIBLE_PLAN/CAP_REACHED/NO_PHONE/PAST_WINDOW)
      t.string :error_code
      t.text :error_message
      t.datetime :scheduled_at      # 스텝 기준일·발송 예정 시각(사전통보류 멱등 판정에 사용)
      t.datetime :sent_at

      t.timestamps
    end

    # 솔라피 메시지 식별자 조회 경로(발송 상태 회수 — 기술 부채 항목의 전제)
    add_index :message_logs, :provider_message_id

    # SEC-5 — 자동 채무자 발송의 청구서×템플릿 1회 보장. recipient_role=0(debtor) 조건이 없으면
    # 단계별 반복이 정상인 사용자 향 알림(noti_prenotice D+1/7/14·noti_promise 재약속)까지
    # 1회로 묶이므로 인덱스 조건에 포함한다. origin=1(manual)은 재발송 허용(REM-8).
    add_index :message_logs, [ :invoice_id, :template_key ], unique: true,
              where: "origin = 0 AND recipient_role = 0",
              name: "idx_message_logs_auto_debtor_uniq"
  end
end
