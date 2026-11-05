# F-REM 테스트용 레코드 팩토리 — 발송 시나리오는 만기일·상태·열람 이력·약속을 자유 조합해야
# 해서(REM-3 주말 창·REM-12 경계·PROMISE-3 재스케줄) fixtures의 고정 날짜만으로는 부족하다.
# 생성 경로는 실제 모델 검증(금액 재산정·품목 필수·소유권)을 통과한다 — 우회 기록 아님.
# 토큰·유효기간은 SHARE-1/2 규격(발급 상태)으로 채워 reminders_dispatchable 모집합에 들어가게
# 한다(링크 없는 청구는 with_link: false로 만든다 — 스캔 제외 검증용).
module ReminderFactories
  # 발행 계열 청구서 생성 — status는 INV-4 enum 심볼(:issued·:overdue·:promised 등).
  # due_on은 Date·문자열 모두 허용(TIME-1 — KST 기준 날짜).
  def create_reminder_invoice(user:, client:, due_on:, status: :issued, with_link: true)
    invoice = Invoice.create!(
      user: user, client: client, status: status, due_on: due_on,
      issuer_display_name: "테스트발행자", bank_name: "신한은행",
      account_number: "110-234-567890", account_holder: "김델타",
      tax_mode: :separate,
      items_attributes: [ { description: "리마인더 테스트 품목", quantity: 1, unit_price: 100_000 } ]
    )
    if with_link
      invoice.update_columns(
        token: SecureRandom.urlsafe_base64(32),
        token_expires_at: (invoice.due_on + 60).end_of_day
      )
    end
    invoice
  end

  # 열람 이력 기록(SHARE-3) — D+1 열람 분기(confirm_d1_opened) 시나리오용.
  def record_view_event(invoice, first: false)
    invoice.view_events.create!(first: first, device: "mobile", ip: "203.0.113.10",
                                viewed_at: Time.current)
  end

  # 약속 기록(F-PROMISE) — 약속 트랙·재스케줄(PROMISE-3) 시나리오용. 청구서 상태 전이는
  # 하지 않는다(발송 스캔은 unsettled이면 약속 보유 여부로만 트랙을 판정한다).
  def create_promise(invoice, kind:, promised_on: nil)
    invoice.promises.create!(kind: kind, promised_on: promised_on)
  end
end
