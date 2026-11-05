require "test_helper"
require_relative "../../test_helpers/fake_solapi_client"
require_relative "../../test_helpers/reminder_factories"
require_relative "../../test_helpers/solapi_stubbing"

module Reminders
  # 즉시·단건 발송 잡(F-REM) — 이벤트성 발송·모호 실패 재시도의 잡 진입점 계약 검증.
  # 잡은 SendService를 감싸기만 한다(§11.2 잡 인자 스칼라 규약). 잡 계층엔 주입점이 없으므로
  # with_solapi_client 방어선으로 래퍼 생성 경로를 가로챈다 — stub 없이 perform_now를 실행하면
  # test 환경에서도 credentials의 유효 키로 실제 솔라피 API를 호출한다(리뷰 W-7 실측·
  # deliver_job.rb 헤더 주석 참조 — 절대 준수).
  # 검증 항목: origin 기본 auto(기존 3인자 호출점 호환)·4번째 origin 전달(B-2)·창 밖 재예약
  # 재인큐·재예약 pending의 실행 마킹(W-4)·존재하지 않는 청구 흡수(discard_on)·자동 Free skip.
  class DeliverJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    include ReminderFactories
    include SolapiStubbing

    fixtures :users, :clients, :invoices, :subscriptions, :payment_passes

    def setup
      @fake = FakeSolapiClient.new
    end

    def create_target(status: :issued)
      create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                              due_on: Date.new(2026, 11, 9), status: status)
    end

    test "perform_now는 stub 래퍼로 발송하고 origin 기본값은 auto다 (W-7·기존 호출점 호환)" do
      invoice = create_target

      travel_to(Time.zone.parse("2026-11-10 10:00")) do
        with_solapi_client(@fake) do
          DeliverJob.perform_now(invoice.id, "confirm_d1", "debtor")
        end
      end

      log = MessageLog.where(invoice_id: invoice.id).sole
      assert_predicate log, :sent?
      assert_predicate log, :auto?                                   # 3인자 호출 → auto
      assert_equal "confirm_d1", @fake.calls.sole[:template_key]
    end

    test "4번째 origin 인자가 전달되면 수동 발송으로 기록된다 (B-2 — Free 재예약 origin 유지)" do
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-10 10:00")) do
        with_solapi_client(@fake) do
          DeliverJob.perform_now(invoice.id, "confirm_d1", "debtor", "manual")
        end
      end

      log = MessageLog.where(invoice_id: invoice.id).sole
      assert_predicate log, :sent?
      assert_predicate log, :manual?                                 # Free 수동 — 자격 가드 우회(REM-8)
      assert_equal 1, @fake.calls.size
    end

    test "창 밖 접수분 전체 여정 — 재예약 pending(manual)이 다음 평일 실행에 sent로 마킹된다 (B-2·W-4)" do
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-14 20:00")) do              # 토요일 밤 수동 접수
        with_solapi_client(@fake) do
          assert_equal :rescheduled,
                       SendService.new(invoice: invoice, template_key: "confirm_d1",
                                       recipient_role: :debtor, origin: :manual,
                                       client: @fake).call
        end
        pending = MessageLog.where(invoice_id: invoice.id).sole
        assert_predicate pending, :pending?
        assert_predicate pending, :manual?
        assert_equal Time.zone.local(2026, 11, 16, 9, 0), pending.scheduled_at
      end

      travel_to(Time.zone.parse("2026-11-16 09:00")) do              # 월요일 09시 예약 실행
        with_solapi_client(@fake) do
          DeliverJob.perform_now(invoice.id, "confirm_d1", "debtor", "manual")
        end
      end

      logs = MessageLog.where(invoice_id: invoice.id)
      assert_equal 1, logs.count                                     # pending이 sent로 갱신(신규 아님)
      assert_predicate logs.sole.reload, :sent?
      assert_predicate logs.sole, :manual?
      assert_equal 1, @fake.calls.size
    end

    test "창 밖 접수는 재예약 DeliverJob을 인큐하고 origin을 유지한다 (B-2)" do
      invoice = create_target

      travel_to(Time.zone.parse("2026-11-14 12:00")) do              # 토요일
        assert_enqueued_with job: DeliverJob,
                             args: [ invoice.id, "confirm_d1", "debtor", "auto" ] do
          with_solapi_client(@fake) do
            DeliverJob.perform_now(invoice.id, "confirm_d1", "debtor")
          end
        end
      end
    end

    test "존재하지 않는 청구는 discard_on으로 흡수된다 (RecordNotFound)" do
      assert_nothing_raised do
        with_solapi_client(@fake) do
          DeliverJob.perform_now(999_999_999, "confirm_d1", "debtor")
        end
      end
      assert_empty @fake.calls
    end

    test "자동 기본 origin의 Free 대상은 INELIGIBLE_PLAN skip으로 기록된다 (REM-8 — 가드 범위 유지)" do
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-10 10:00")) do
        with_solapi_client(@fake) do
          DeliverJob.perform_now(invoice.id, "confirm_d1", "debtor")
        end
      end

      log = MessageLog.where(invoice_id: invoice.id).sole
      assert_predicate log, :skipped?
      assert_equal "INELIGIBLE_PLAN", log.error_code                 # 자동은 자격 가드 대상 유지
      assert_empty @fake.calls
    end
  end
end
