require "test_helper"

# 반복 청구 자동 발행 서비스 테스트(INV-7) — 정상 발행(품목 스냅샷·issue! 재사용·issue_notice
# 인큐 SHARE-6)·보류(hold_if_unpaid — 직전 미수/완납 분기)·PLAN-1 한도 skip(Q16)·오늘 외 호출
# 무시(멱등)·IssueJob 스캔(paused/cancelled 제외). 외부 API는 실호출 없이 enqueue만 검증한다.
class RecurringInvoices::IssueServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :users, :clients

  def setup
    @user = users(:gamma) # 프로필 완료·구독·수금 패스 없음 — PLAN-1 Free 폴백 경로
    @client = @user.clients.create!(name: "정기거래처", contact_name: "박담당", phone: "010-1234-5678")
  end

  def create_schedule(day: 10, hold_if_unpaid: false, last_invoice: nil, status: :active)
    RecurringInvoice.new(
      user: @user, client: @client, day_of_month: day,
      tax_mode: :separate, withholding_enabled: true, hold_if_unpaid: hold_if_unpaid
    ).tap do |schedule|
      schedule.items.build(name: "월정액", quantity: 1, unit_price: 100_000)
      schedule.save!
      # 초기화 훅은 테스트 외부의 실제 오늘 기준이라, 시나리오 발행일(2026-11-10)로 고정한다
      schedule.update!(next_issue_on: Date.new(2026, 11, 10))
      schedule.update!(last_invoice: last_invoice) if last_invoice
      schedule.update!(status: status) if status != :active
    end
  end

  def issue_invoice(client: @client)
    invoice = Invoice.new(
      user: @user, client: client, due_on: Date.current + Invoice::DEFAULT_DUE_IN_DAYS,
      issuer_display_name: @user.display_name, bank_name: @user.bank_name,
      account_number: @user.account_number, account_holder: @user.account_holder
    )
    invoice.items.build(description: "선행 작업", quantity: 1, unit_price: 50_000)
    assert invoice.issue!, invoice.errors.full_messages.join(", ")
    invoice
  end

  # ── 정상 발행 ──

  test "정상 발행 — Invoice·품목 스냅샷·issue_notice 인큐·advance!가 전부 적용된다" do
    schedule = create_schedule
    travel_to(Time.zone.parse("2026-11-10 06:30")) do
      assert_enqueued_with(job: Reminders::DeliverJob) do
        @result = RecurringInvoices::IssueService.new.call(schedule)
      end
      assert_equal :issued, @result[:result]

      # SHARE-6 — 컨트롤러 issue 플로우와 동일 인자(invoice id·issue_notice·debtor)
      # NOTI-3(Q15·W-2) — U1 통보(noti_recurring_issued)도 커밋 후 인큐된다
      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs
                .select { |j| j[:job] == Reminders::DeliverJob }
      assert_equal 2, enqueued.count
      invoice_id = @result[:invoice].id
      assert enqueued.any? { |j| j[:args] == [ invoice_id, "issue_notice", "debtor" ] }
      assert enqueued.any? { |j| j[:args] == [ invoice_id, "noti_recurring_issued", "user" ] }
      invoice = @result[:invoice]
      assert invoice.issued?
      assert_equal @client.id, invoice.client_id
      assert_equal Date.current + 30, invoice.due_on                    # INV-3 발행일+30일 준용
      assert invoice.issue_number.start_with?("BD-20261110-")           # INV-1 채번 재사용
      assert invoice.token.present?                                     # SHARE-1 토큰 재사용
      assert_equal "월정액", invoice.items.first.description             # 품목 스냅샷
      assert_equal 1, invoice.items.first.quantity
      assert_equal 100_000, invoice.items.first.unit_price
      assert invoice.withholding_enabled
      assert_equal Date.current, schedule.reload.last_issued_on
      assert_equal Date.new(2026, 12, 10), schedule.reload.next_issue_on
      assert_equal invoice.id, schedule.reload.last_invoice_id
      assert_nil schedule.reload.last_skip_reason
    end
  end

  test "정상 발행 — 재실행은 멱등하게 무시된다(발행일이 다음 달로 이동)" do
    schedule = create_schedule
    travel_to(Time.zone.parse("2026-11-10 06:30")) do
      RecurringInvoices::IssueService.new.call(schedule)
      before = Invoice.count

      result = RecurringInvoices::IssueService.new.call(schedule.reload)
      assert_equal :skipped, result[:result]
      assert_equal before, Invoice.count
    end
  end

  # ── INV-7 보류(hold_if_unpaid) ──

  test "보류 — 직전 청구가 미수(unsettled)면 skip·사유 기록·다음 달 이동" do
    last = issue_invoice
    schedule = create_schedule(hold_if_unpaid: true, last_invoice: last)
    travel_to(Time.zone.parse("2026-11-10 06:30")) do
      before = Invoice.count
      result = RecurringInvoices::IssueService.new.call(schedule)

      assert_equal :held, result[:result]
      assert_equal before, Invoice.count
      assert schedule.reload.last_skip_reason.to_s.include?("직전 청구")
      assert_equal Date.new(2026, 12, 10), schedule.reload.next_issue_on
      assert_equal last.id, schedule.reload.last_invoice_id
    end
  end

  test "보류 — 직전 청구가 수금 완료(paid)면 정상 발행한다" do
    last = issue_invoice
    assert last.mark_paid!
    schedule = create_schedule(hold_if_unpaid: true, last_invoice: last)
    travel_to(Time.zone.parse("2026-11-10 06:30")) do
      result = RecurringInvoices::IssueService.new.call(schedule)
            assert_equal :issued, result[:result]
      assert_nil schedule.reload.last_skip_reason
    end
  end

  test "보류 — hold_if_unpaid 미설정이면 직전 미수와 무관하게 발행한다" do
    last = issue_invoice
    schedule = create_schedule(hold_if_unpaid: false, last_invoice: last)
    travel_to(Time.zone.parse("2026-11-10 06:30")) do
      assert_equal :issued, RecurringInvoices::IssueService.new.call(schedule)[:result]
    end
  end

  # ── PLAN-1 한도 skip(Q16) ──

  test "한도 skip — 당월 발행이 Free 3건 한도에 도달하면 skip·사유 기록" do
    3.times { issue_invoice }
    schedule = create_schedule
    travel_to(Time.zone.parse("2026-11-10 06:30")) do
      before = Invoice.count
      result = RecurringInvoices::IssueService.new.call(schedule)

      assert_equal :held, result[:result]
      assert_equal before, Invoice.count
      assert schedule.reload.last_skip_reason.to_s.include?("한도")
      assert_equal Date.new(2026, 12, 10), schedule.reload.next_issue_on
    end
  end

  # ── 오늘 외 호출·Job 스캔 ──

  test "오늘이 발행일이 아니면 기록 없이 무시한다(멱등)" do
    schedule = create_schedule(day: 10)
    travel_to(Time.zone.parse("2026-11-09 06:30")) do
      before = Invoice.count
      result = RecurringInvoices::IssueService.new.call(schedule)
      assert_equal :skipped, result[:result]
      assert_equal before, Invoice.count
      assert_nil schedule.reload.last_skip_reason
    end
  end

  test "IssueJob — due_or_overdue 스케줄만 발행하고 개별 실패는 계속 진행한다" do
    due = create_schedule(day: 10)
    paused = create_schedule(day: 10, status: :paused)
    travel_to(Time.zone.parse("2026-11-10 06:30")) do
      # paused 스케줄은 스캔 대상이 아니며, due만 발행(채무자 issue_notice+U1 통보 = 인큐 2건)
      assert_enqueued_jobs 2, only: Reminders::DeliverJob do
        RecurringInvoices::IssueJob.perform_now
      end
      assert_equal Date.current, due.reload.last_issued_on
      assert_equal Date.new(2026, 12, 10), due.reload.next_issue_on
      assert_nil paused.reload.last_issued_on
    end
  end

  # ── SEC-5 발송 멱등 준용 — 같은 날 IssueJob 2회 실행 시 2번째는 무영향 ──

  test "IssueJob — 같은 날 2회 perform해도 2번째 실행은 발행·인큐에 무영향이다" do
    schedule = create_schedule(day: 10)
    travel_to(Time.zone.parse("2026-11-10 06:30")) do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      RecurringInvoices::IssueJob.perform_now
      first_invoice_count = Invoice.count
      first_enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.count
      assert_equal Date.current, schedule.reload.last_issued_on

      RecurringInvoices::IssueJob.perform_now

      assert_equal first_invoice_count, Invoice.count           # 재발행 없음
      assert_equal first_enqueued, ActiveJob::Base.queue_adapter.enqueued_jobs.count # 재인큐 없음
      assert_equal Date.new(2026, 12, 10), schedule.reload.next_issue_on # 커서 이중 이동 없음
      assert_equal Date.current, schedule.reload.last_issued_on
    end
  end

  # ── C-1 이중 발행 창 방지 ──

  test "C-1 — advance! 실패 시 발행까지 롤백되고 재실행 시 이중 발행이 없다" do
    schedule = create_schedule
    travel_to(Time.zone.parse("2026-11-10 06:30")) do
      before = Invoice.count
      schedule.define_singleton_method(:advance!) do |*_|
        raise ActiveRecord::RecordInvalid, self
      end

      assert_raises(ActiveRecord::RecordInvalid) do
        RecurringInvoices::IssueService.new.call(schedule)
      end
      # 실패 주입 해제 — 같은 인스턴스(reload는 자기 자신)의 싱글턴이 재실행까지 물지 않게 한다
      schedule.singleton_class.remove_method(:advance!)
      # 롤백 — 청구 0건·커서 유지·알림 인큐 0건(커밋 후 전용)
      assert_equal before, Invoice.count
      assert_equal Date.new(2026, 11, 10), schedule.reload.next_issue_on
      assert_equal 0, ActiveJob::Base.queue_adapter.enqueued_jobs.count

      # 재실행 — 커서가 오늘에 남아 있어도(비원자 창 재현 상태) 정확히 1회 발행
      result = RecurringInvoices::IssueService.new.call(schedule.reload)
      assert_equal :issued, result[:result]
      assert_equal before + 1, Invoice.count
      assert_equal Date.new(2026, 12, 10), schedule.reload.next_issue_on
    end
  end

  # ── C-2 잡 미실행 만회 ──

  test "C-2 — 3일 미실행(커서 고착) 스케줄도 다음 실행에 1회 발행하고 드리프트 없이 갱신된다" do
    schedule = create_schedule
    travel_to(Time.zone.parse("2026-11-10 06:30")) do
      schedule.update!(next_issue_on: Date.current - 3)  # 11-07 발행 예정이 3일 미실행

      before = Invoice.count
      result = RecurringInvoices::IssueService.new.call(schedule.reload)

      assert_equal :issued, result[:result]
      assert_equal before + 1, Invoice.count
      # 커서는 구값(11-07) 기준 다음 달 10일 — 실행이 늦어도 발행일이 밀리지 않는다
      assert_equal Date.new(2026, 12, 10), schedule.reload.next_issue_on
    end
  end

  # ── W-2(NOTI-3 Q15) — held 통보 인큐·등록 전 템플릿 NO_TEMPLATE skip ──

  test "W-2 — 보류 시 직전 청구가 있으면 U1 통보(noti_recurring_held)를 인큐한다" do
    last = issue_invoice
    schedule = create_schedule(hold_if_unpaid: true, last_invoice: last)
    travel_to(Time.zone.parse("2026-11-10 06:30")) do
      assert_enqueued_jobs 1, only: Reminders::DeliverJob do
        RecurringInvoices::IssueService.new.call(schedule)
      end
      held = ActiveJob::Base.queue_adapter.enqueued_jobs
              .select { |j| j[:job] == Reminders::DeliverJob }.last
      assert_equal [ last.id, "noti_recurring_held", "user" ], held[:args]
    end
  end
end
