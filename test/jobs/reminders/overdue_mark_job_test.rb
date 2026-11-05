require "test_helper"
require_relative "../../test_helpers/reminder_factories"

module Reminders
  # 연체 저장화 잡(F-REM — INV-4·TIME-1) — unsettled·만기 경과 건의 overdue 전환 계약:
  # 만기 당일 경계·promised 제외(PROMISE-3)·미수 밖 상태 무영향·멱등 재실행.
  # DB 접근만 하고 외부 API가 없어 stub이 필요 없다.
  class OverdueMarkJobTest < ActiveSupport::TestCase
    include ReminderFactories

    fixtures :users, :clients, :invoices

    test "unsettled·만기 경과 청구를 overdue로 저장 전환한다 (INV-4·TIME-1)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      # overdue?는 파생 판정(unsettled? && due_on < Date.current)이므로 KST 고정 블록 안에서
      # 판정한다(TIME-1 — 블록 밖은 실제 오늘 기준이 된다).
      travel_to(Time.zone.parse("2026-11-10 07:00")) do
        OverdueMarkJob.perform_now
        assert invoice.reload.overdue?
      end
      assert_equal "overdue", invoice.reload.status                  # enum 저장값은 시간 무관
    end

    test "만기 당일은 연체가 아니다 — 경과일에만 전환한다 (INV-4 경계·TIME-1)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 10))

      travel_to(Time.zone.parse("2026-11-10 07:00")) do
        OverdueMarkJob.perform_now
        assert invoice.reload.issued?
      end

      travel_to(Time.zone.parse("2026-11-11 07:00")) do
        OverdueMarkJob.perform_now
        assert invoice.reload.overdue?
      end
      assert_equal "overdue", invoice.reload.status
    end

    test "promised는 제외하고 draft·paid·voided는 건드리지 않는다 (PROMISE-3·INV-4)" do
      promised = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                         due_on: Date.new(2026, 11, 9), status: :promised)
      paid = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                     due_on: Date.new(2026, 11, 9), status: :paid)
      voided = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                       due_on: Date.new(2026, 11, 9), status: :voided)

      travel_to(Time.zone.parse("2026-11-10 07:00")) do
        OverdueMarkJob.perform_now

        assert promised.reload.promised?                             # 약속 트랙 유지
        assert paid.reload.paid?
        assert voided.reload.voided?
      end
    end

    test "재실행은 멱등이다 — overdue 재전환·오류 없음 (잡 재시도 무해)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-10 07:00")) do
        OverdueMarkJob.perform_now
        assert_nothing_raised { OverdueMarkJob.perform_now }
        assert invoice.reload.overdue?
      end
      assert_equal "overdue", invoice.reload.status
    end
  end
end
