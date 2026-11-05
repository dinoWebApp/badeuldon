require "test_helper"
require_relative "../../test_helpers/fake_solapi_client"
require_relative "../../test_helpers/reminder_factories"

module Reminders
  # U1 향 알림 진입점(F-REM — NOTI-1) — 8종 경로·phone 미등록 skip(NO_PHONE)·REM-3 창
  # 미적용(즉시 발송 — 확정 해석 3). 시나리오 기준: _workspace/03_implementation.md
  # NOTI-1 매핑·설계 판단 2, _workspace/05_review.md §Tester 8.
  # 솔라피는 생성자 client: 주입(FakeSolapiClient)으로 차단한다 — 실호출 0(REM-10).
  class NotifyUserServiceTest < ActiveSupport::TestCase
    include ReminderFactories

    fixtures :users, :clients, :invoices

    def setup
      @fake = FakeSolapiClient.new
    end

    def notify(invoice, template_key)
      NotifyUserService.new(invoice: invoice, template_key: template_key, client: @fake).call
    end

    test "NOTI-1 8종 전 경로가 U1 향 sent 이력과 함께 발송된다" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      %w[noti_opened noti_promise noti_deposit_reply noti_inquiry noti_refusal
         noti_prenotice noti_promise_unkept noti_due_soon].each do |template_key|
        assert_equal :sent, notify(invoice, template_key), "#{template_key} 발송 실패"
      end

      logs = MessageLog.where(invoice_id: invoice.id, recipient_role: :user)
      assert_equal 8, logs.count
      assert logs.all(&:sent?)
      assert logs.all? { |log| log.phone == users(:delta).phone }   # 수신자는 U1 프로필 번호
    end

    test "phone 미등록 사용자의 알림은 skipped NO_PHONE으로 기록된다 (에러 아님 — 01_plan 리스크)" do
      invoice = create_reminder_invoice(user: users(:alpha), client: clients(:alpha_client_1),
                                        due_on: Date.new(2026, 11, 9))

      assert_equal :skipped, notify(invoice, "noti_opened")

      log = MessageLog.where(invoice_id: invoice.id, recipient_role: :user).sole
      assert_predicate log, :skipped?
      assert_equal "NO_PHONE", log.error_code
      assert_empty @fake.calls
    end

    test "U1 알림은 발송 창 밖(주말·야간)에도 즉시 발송된다 (REM-3 — 채무자 향만 적용)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-15 22:00")) do              # 일요일 밤
        assert_equal :sent, notify(invoice, "noti_due_soon")
      end
      assert_equal 1, @fake.calls.size
    end
  end
end
