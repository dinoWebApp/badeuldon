require "test_helper"
require_relative "../../test_helpers/fake_solapi_client"
require_relative "../../test_helpers/reminder_factories"

module Reminders
  # 사전통보 스캔(F-REM — REM-11·NOTI-1·W-3·C-2) — 09시 평일 U1 사전통보의 모집단·범위·
  # 자격 필터·당일 재실행 멱등 검증. 발송 예정 판정(steps_due_today)은 DispatchService와
  # 단일 출처라 이 테스트에서는 통보 대상·제외 템플릿·주말 묶음에 집중한다.
  # 솔라피는 PrenoticeService(client:) 주입 체인(FakeSolapiClient)으로 차단한다 — U1 통보에
  # 성공 훅이 없어 생성자 주입으로 충분하다(W-7).
  class PrenoticeServiceTest < ActiveSupport::TestCase
    include ReminderFactories

    fixtures :users, :clients, :invoices, :promises, :subscriptions, :payment_passes

    def setup
      @fake = FakeSolapiClient.new
    end

    def run_prenotice
      PrenoticeService.new(client: @fake).call
    end

    def u1_logs_for(invoice)
      MessageLog.where(invoice_id: invoice.id, recipient_role: :user)
    end

    test "연체·도과 단계 발송 예정 청구의 U1에게만 noti_prenotice를 보낸다 (REM-11)" do
      overdue = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))          # D+1 오늘
      pending_notice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                               due_on: Date.new(2026, 11, 10))  # D-1 오늘

      travel_to(Time.zone.parse("2026-11-10 09:00")) do
        run_prenotice
      end

      assert_equal 1, u1_logs_for(overdue).count                     # 연체 단계 — 통보
      assert_equal "noti_prenotice", u1_logs_for(overdue).sole.template_key
      assert_predicate u1_logs_for(overdue).sole, :sent?
      assert_empty u1_logs_for(pending_notice)                       # 만기 예정 — 연체 단계 아님
    end

    test "promise_d1은 사전통보 대상이 아니고 promise_overdue는 대상이다 (REM-11·C-2)" do
      promise_tomorrow = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                                 due_on: Date.new(2026, 11, 9))
      promise_overdue = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                                due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-09 09:00")) do              # 월요일 — 접수일 기준 약속
        create_promise(promise_overdue, kind: :date_selected, promised_on: Date.new(2026, 11, 9))
      end

      travel_to(Time.zone.parse("2026-11-10 09:00")) do              # 화요일 09시
        create_promise(promise_tomorrow, kind: :date_selected, promised_on: Date.new(2026, 11, 11))
        run_prenotice
      end

      assert_empty u1_logs_for(promise_tomorrow)                     # promise_d1 — 제외
      assert_equal [ "noti_prenotice" ], u1_logs_for(promise_overdue).map(&:template_key)
    end

    test "자격 없는 청구는 사전통보도 없다 — 발송 예정이 없는 건이므로 (REM-8·설계 판단 10)" do
      free_invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                             due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-10 09:00")) do
        run_prenotice
      end

      assert_empty u1_logs_for(free_invoice)
    end

    test "noti_due_soon은 만기 임박만 통보하고 자격·플랜은 무관하다 (NOTI-1·설계 판단 10)" do
      eligible = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                         due_on: Date.new(2026, 11, 11))          # 내일
      free = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                     due_on: Date.new(2026, 11, 11))            # 내일 — Free
      day_after = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                          due_on: Date.new(2026, 11, 12))       # 모레 — 화요일 범위 밖

      travel_to(Time.zone.parse("2026-11-10 09:00")) do              # 화요일 — 범위 = 내일 1일
        run_prenotice
      end

      assert_equal [ "noti_due_soon" ], u1_logs_for(eligible).map(&:template_key)
      assert_equal [ "noti_due_soon" ], u1_logs_for(free).map(&:template_key)   # 플랜 무관
      assert_empty u1_logs_for(day_after)
    end

    test "금요일 아침은 토·일·월 만기를 묶어 선행 통보한다 (W-3 — 주말 잡 공백 커버)" do
      # fixtures의 만기일(2026-10월)과 D+14 nominal이 겹치지 않는 금요일을 고른다.
      saturday = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                         due_on: Date.new(2026, 11, 21))
      sunday = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                       due_on: Date.new(2026, 11, 22))
      monday = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                       due_on: Date.new(2026, 11, 23))
      tuesday = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 24))   # 다음 실행일 이후 — 제외

      travel_to(Time.zone.parse("2026-11-20 09:00")) do              # 금요일
        run_prenotice
      end

      [ saturday, sunday, monday ].each do |invoice|
        assert_equal [ "noti_due_soon" ], u1_logs_for(invoice).map(&:template_key)
      end
      assert_empty u1_logs_for(tuesday)
      assert_equal 3, @fake.calls.size                               # 청구서별 개별 발송(NOTI-1)
    end

    test "당일 재실행은 scheduled_at(당일 09시) 기준으로 멱등 흡수된다 (설계 판단 2·S9)" do
      overdue = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      due_tomorrow = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                             due_on: Date.new(2026, 11, 11))

      travel_to(Time.zone.parse("2026-11-10 09:00")) do
        run_prenotice
        run_prenotice                                                # 재실행(모호 실패 복구 상정)
      end

      assert_equal 1, u1_logs_for(overdue).count                     # noti_prenotice 1건
      assert_equal 1, u1_logs_for(due_tomorrow).count                # noti_due_soon 1건
      assert_equal Time.zone.local(2026, 11, 10, 9, 0), u1_logs_for(overdue).sole.scheduled_at
    end
  end
end
