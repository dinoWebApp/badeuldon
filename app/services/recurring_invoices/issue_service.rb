# 반복 청구 자동 발행(INV-7) — 스케줄 1건의 당일 발행 플로우. 실제 발행은 Invoice#issue!
# 기존 플로우(채번 INV-1·토큰 SHARE-1·PLAN-1 한도·수금 패스 PLAN-4)를 재사용하며, 이 서비스는
# ① 보류 판정(hold_if_unpaid — 직전 청구 미수금) ② PLAN-1 사전 skip(Q16) ③ 발행·품목 스냅샷
# ④ 커서 갱신(advance!)·skip 기록(hold! — NOTI-3) ⑤ 커밋 후 알림 인큐(①채무자 issue_notice —
# SHARE-6 REM-1 서비스 명의·②U1 recurring 통보 — NOTI-3 Q15)를 담당한다.
#
# 원자성(C-1) — call 본문 전체를 schedule.with_lock 트랜잭션으로 감싼다. 행 잠금으로 동시
# 실행이 직렬화되고(잠금 후 next_issue_on 재판정 — 2번째 실행은 skipped), issue!와 advance!가
# 같은 트랜잭션 안에 있어 advance! 실패 시 발행까지 롤백된다(고아 청구·무통지·보류 판정 상실
# 동시 방지). 알림 인큐는 트랜잭션 커밋 "후"에만 수행한다 — 롤백된 발행의 안내 잔존 방지.
#
# 발행일 완화(C-2) — 판정은 `next_issue_on <= Date.current`다. 잡 미실행일(배포·다운타임)에
# 커서가 고착돼도 다음 실행에 반드시 1회 발행하고, 커서는 구값(next_issue_on) 기준 다음 달
# N일로 이동해 발행일이 늦은 실행만큼 밀리는 드리프트가 없다.
#
# Q15(W-2 방침 (b)) — U1 통보(noti_recurring_issued/held)를 커밋 후 항상 인큐한다. 템플릿이
# credentials에 없으면 SendService가 MISSING_TEMPLATE을 skipped(NO_TEMPLATE) MessageLog로
# 기록하고 정상 종료한다(발행 무영향) — 솔라피 등록 후 별도 코드 변경 없이 자동 활성화.
# held 통보는 MessageLog·변수의 invoice 문맥이 필요해 직전 발행 청구(last_invoice_id)가 있을
# 때만 인큐한다 — 없으면 스케줄 last_skip_reason·show 배너가 기록을 대신한다.
module RecurringInvoices
  class IssueService
    # INV-3 — 반복 청구 만기도 기존 기본값 준용(발행일+30일).
    DEFAULT_DUE_IN_DAYS = Invoice::DEFAULT_DUE_IN_DAYS

    def call(schedule)
      result = nil
      schedule.with_lock do
        result = run(schedule)
      end
      enqueue_notifications(schedule, result)
      result
    end

    private

    # 발행 판정·실행 — with_lock 트랜잭션 안에서만 호출된다(행 잠금 하 재판정·원자 갱신).
    def run(schedule)
      return skipped(schedule, "스케줄이 아직 발행일이 아닙니다") unless schedule.next_issue_on <= Date.current

      # INV-7 보류 — hold_if_unpaid이고 직전 발행 청구가 미수(unsettled)면 이번 달은 skip.
      # 판정은 메모리 캐시가 아닌 DB 최신 상태(마감 전이는 update_all이라 메모리 상태가 늦는다).
      if schedule.hold_if_unpaid && Invoice.unsettled.exists?(id: schedule.last_invoice_id)
        return hold!(schedule, "직전 청구가 아직 입금되지 않아 이번 달 발행을 보류했습니다")
      end

      # Q16 — PLAN-1 월 발행 한도 사전 skip. issue!가 최종 게이트지만 한도 초과가 예상되는
      # 발행까지 만들고 되돌리는 낭비·오차 없이 사유를 기록한다(NOTI-3 통보 데이터).
      issued_this_month = schedule.user.invoices.where(issued_at: Time.current.beginning_of_month..).count
      if schedule.user.monthly_invoice_limit_reached?(issued_this_month)
        return hold!(schedule, "이번 달 발행 한도를 초과해 이번 달 발행을 보류했습니다")
      end

      issue(schedule)
    end

    # 발행 — 초안 생성(품목 스냅샷·금액 프리필) → issue!(한도 최종 게이트·채번·토큰·수금 패스
    # 소비) → 성공 시 advance!(같은 트랜잭션 — 실패 시 전체 롤백).
    def issue(schedule)
      invoice = build_invoice(schedule)

      unless invoice.issue!
        return hold!(schedule, invoice_issue_failure_reason(invoice))
      end

      schedule.advance!(invoice)
      { result: :issued, invoice: invoice }
    end

    def build_invoice(schedule)
      user = schedule.user
      invoice = Invoice.new(
        user: user,
        client: schedule.client,
        due_on: Date.current + DEFAULT_DUE_IN_DAYS,             # INV-3 발행일+30일 준용
        tax_mode: schedule.tax_mode,
        withholding_enabled: schedule.withholding_enabled,
        issuer_display_name: user.display_name,                  # INV-1 발행자 표시명 스냅샷
        bank_name: user.bank_name,                               # 계좌 프로필 스냅샷
        account_number: user.account_number,
        account_holder: user.account_holder
      )
      schedule.items.each do |item|
        invoice.items.build(description: item.name, quantity: item.quantity, unit_price: item.unit_price)
      end
      invoice
    end

    # skip 기록 — 사유만 남기고 발행일 커서를 이동(월 1회 불변식). 상태는 active 유지.
    def hold!(schedule, reason)
      schedule.hold!(reason)
      { result: :held, reason: reason }
    end

    # 오늘(또는 이전)이 발행일이 아닌 중복 호출 — 기록 없이 무시(멱등). with_lock 재판정이
    # 동시 실행의 2번째 호출을 여기로 수렴시킨다(C-1).
    def skipped(schedule, reason)
      { result: :skipped, reason: reason }
    end

    def invoice_issue_failure_reason(invoice)
      invoice.errors.full_messages_for(:base).first ||
        invoice.errors.full_messages.first ||
        "청구서 발행에 실패해 이번 달 발행을 보류했습니다"
    end

    # ── 알림 인큐(커밋 후 전용 — 트랜잭션 안에서 인큐하지 않는다) ─────────────
    # SHARE-6 — 발행 안내 알림톡(채무자 향 1회성 — PLAN-3 상한 집계 밖). App::InvoicesController#issue와
    # 동일 경로이며 예약 판정(창 밖 다음 평일 이연)은 Reminders::SendService가 담당한다.
    # NOTI-3(Q15·W-2) — U1 통보 2종. 템플릿 미등록은 SendService가 skipped(NO_TEMPLATE)로
    # 기록·정상 종료한다 — 등록 후 자동 활성화.
    def enqueue_notifications(schedule, result)
      case result[:result]
      when :issued
        Reminders::DeliverJob.perform_later(result[:invoice].id, "issue_notice", "debtor")
        Reminders::DeliverJob.perform_later(result[:invoice].id, "noti_recurring_issued", "user")
      when :held
        if schedule.last_invoice_id
          Reminders::DeliverJob.perform_later(schedule.last_invoice_id, "noti_recurring_held", "user")
        end
      end
    end
  end
end
