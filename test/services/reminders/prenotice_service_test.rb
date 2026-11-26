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

    test "상한 도달 청구는 사전통보 대상이 아니다 — 14시 발송이 막히는 건을 예정이라 알리지 않는다 (PLAN-3·Q28·REM-11·W-3)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))          # D+1 = 11-10 오늘
      # 수동 발행 안내(issue_notice) 5통 — Q11 집계로 상한 도달(자동 단계는 CAP_REACHED로 막힌다)
      5.times do
        MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "issue_notice",
                           recipient_role: :debtor, status: :sent, origin: :manual)
      end

      travel_to(Time.zone.parse("2026-11-10 09:00")) do
        run_prenotice
      end

      assert_empty u1_logs_for(invoice)                                # noti_prenotice 0건
      assert_empty @fake.calls                                         # U1 통보 발송 호출 0
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

    # ── 실제 발송 시각 정합(REM-11 확정 2026-11-26 — SendSchedule 단일 출처) ──────────
    # steps_due_today가 비어 있지 않아도 실제 발송 예정 시각(Reminders::SendSchedule.send_at_for)
    # 이 오늘이 아니면 통보하지 않는다 — 14시 스캔이 REM-3 창 밖이면 reschedule!로 다른 날·시각에
    # 나가므로 "오늘 발송 예정" 통보(REM-11 사실 아님)를 막는다. 각 케이스는 스텝이 존재함을 먼저
    # 단언한다(공허 단언 금지).

    def overdue_invoice_for(user)
      create_reminder_invoice(user: user, client: user.clients.first,
                              due_on: Date.new(2026, 11, 9))         # D+1 = 화요일 오늘
    end

    def assert_prenotice_step_present(invoice)
      assert Reminders::DispatchService.new.steps_due_today(invoice).present?,
             "전제 — 사전통보 대상 스텝이 오늘 도래해야 한다"
    end

    test "REM-3 종료 14시 회원은 오늘 nominal 스텝이 있어도 통보하지 않는다 — 실제 발송은 내일 09시 (REM-11 정합)" do
      users(:delta).update!(remind_end_hour: 14)                     # 09~14 — 14시 스캔 창 밖
      invoice = overdue_invoice_for(users(:delta))

      travel_to(Time.zone.parse("2026-11-10 09:00")) do
        assert_prenotice_step_present(invoice)
        run_prenotice
      end

      assert_empty u1_logs_for(invoice)                              # 통보 없음 — 발송일이 내일
    end

    test "REM-3 시작 15시 회원은 통보한다 — 실제 발송 예정이 오늘 15시 (REM-11 정합)" do
      users(:delta).update!(remind_start_hour: 15)                   # 15~18 — 14시 스캔 창 밖·당일 15시 허용
      invoice = overdue_invoice_for(users(:delta))

      travel_to(Time.zone.parse("2026-11-10 09:00")) do
        assert_prenotice_step_present(invoice)
        run_prenotice
      end

      assert_equal 1, u1_logs_for(invoice).where(template_key: "noti_prenotice").count
    end

    test "오늘이 REM-3 비허용 요일이면 통보하지 않는다 — 발송도 오늘 없다 (REM-11·REM-3)" do
      users(:delta).update!(remind_allowed_wdays: "1,3,5")           # 화·목 제외
      invoice = overdue_invoice_for(users(:delta))

      travel_to(Time.zone.parse("2026-11-10 09:00")) do              # 화요일 — 비허용
        assert_prenotice_step_present(invoice)
        run_prenotice
      end

      assert_empty u1_logs_for(invoice)
    end

    test "전날 14시에 재예약된 오늘 09시 슬롯은 통보한다 — ① 경로의 슬롯 시각이 오늘 (REM-11·REM-3)" do
      users(:delta).update!(remind_end_hour: 14)                     # 창 밖 재예약 상정
      invoice = overdue_invoice_for(users(:delta))
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "confirm_d1",
                         recipient_role: :debtor, status: :pending,
                         scheduled_at: Time.zone.parse("2026-11-10 09:00"))

      travel_to(Time.zone.parse("2026-11-10 09:00")) do
        assert_prenotice_step_present(invoice)
        run_prenotice
      end

      assert_equal 1, u1_logs_for(invoice).where(template_key: "noti_prenotice").count
    end

    test "주말 소급분 — 창 밖 회원은 월요일에 통보하지 않고 기본 창 회원은 통보한다 (REM-11·REM-3 소급)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 7))  # 토 만기 — confirm_d1 nominal 일, 소급 창 종료 월

      travel_to(Time.zone.parse("2026-11-09 09:00")) do              # 월요일 — 주말 nominal 소급분
        assert_prenotice_step_present(invoice)
        users(:delta).update!(remind_end_hour: 14)
        run_prenotice
        assert_empty u1_logs_for(invoice)                            # 실제 발송은 화요일 09시 — 오늘 아님

        MessageLog.delete_all                                        # 상태 초기화 후 대조
        users(:delta).update!(remind_end_hour: 18)                   # 기본 창 복원
        run_prenotice
        assert_equal 1, u1_logs_for(invoice).where(template_key: "noti_prenotice").count
      end
    end

    # ── Tester 보강(2026-11-26 리뷰 W-1·중점 제안 1~6) ──────────────────────────

    test "09:05 실행에서 오늘 09시 pending 슬롯은 경과로 보아 통보하지 않는다 — 운영 지배 분기 (REM-11·리뷰 W-1)" do
      users(:delta).update!(remind_end_hour: 14)                     # 09~14 — ② 폴백이 내일이 되는 창
      invoice = overdue_invoice_for(users(:delta))
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "confirm_d1",
                         recipient_role: :debtor, status: :pending,
                         scheduled_at: Time.zone.parse("2026-11-10 09:00"))

      travel_to(Time.zone.parse("2026-11-10 09:05")) do              # 운영 잡은 09:00+ε에 실행된다
        assert_prenotice_step_present(invoice)                       # 슬롯 미발송이면 스텝은 여전히 오늘 도래
        assert_equal Time.zone.parse("2026-11-11 09:00"),            # ① 경과 → ② 폴백(수요일 시작 시각)
                     Reminders::SendSchedule.send_at_for(user: invoice.user, invoice: invoice,
                                                         template_key: "confirm_d1")
        run_prenotice
      end

      assert_empty u1_logs_for(invoice)                              # 통보 0건 — "오늘 예정" 통보 금지
    end

    test "오늘 09시 슬롯이 이미 sent면 예정이 소멸해 통보하지 않는다 — 정각 경합 삼태계 ① (REM-11·B6)" do
      users(:delta).update!(remind_end_hour: 14)
      invoice = overdue_invoice_for(users(:delta))
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "confirm_d1",
                         recipient_role: :debtor, status: :sent,
                         scheduled_at: Time.zone.parse("2026-11-10 09:00"))

      travel_to(Time.zone.parse("2026-11-10 09:05")) do
        assert_empty Reminders::DispatchService.new.steps_due_today(invoice)  # step_sent? — 예정 소멸
        run_prenotice
      end

      assert_empty u1_logs_for(invoice)
      # 삼태계 ②(09:05 pending → 0건)는 바로 위 테스트, ③(09:00:00 동률 → 1건)은
      # 「전날 14시에 재예약된 오늘 09시 슬롯은 통보한다」 테스트가 각각 고정한다.
    end

    test "due 키가 내일 슬롯에 미뤄져 있으면 통보하지 않는다 — 슬롯 시각이 우선한다 (REM-11·리뷰 3)" do
      users(:delta).update!(remind_end_hour: 14)
      invoice = overdue_invoice_for(users(:delta))
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "confirm_d1",
                         recipient_role: :debtor, status: :pending,
                         scheduled_at: Time.zone.parse("2026-11-11 09:00"))   # 내일 재예약 슬롯

      travel_to(Time.zone.parse("2026-11-10 09:00")) do
        assert_prenotice_step_present(invoice)                       # 기본 창이었다면 오늘 14시였을 스텝
        run_prenotice
      end

      assert_empty u1_logs_for(invoice)                              # 실제 발송일이 내일 — 통보 없음
    end

    test "다른 키의 pending 슬롯은 사전통보 판정에 흘러들지 않는다 — due 키만 산정한다 (REM-11·리뷰 3)" do
      invoice = overdue_invoice_for(users(:delta))                   # 기본 창 — due 키 confirm_d1은 오늘 14시
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "invoice_notice",
                         recipient_role: :debtor, status: :pending,
                         scheduled_at: Time.zone.parse("2026-11-10 09:00"))   # due_keys 밖 키의 슬롯

      travel_to(Time.zone.parse("2026-11-10 09:00")) do
        assert_equal [ "confirm_d1" ], Reminders::DispatchService.new.steps_due_today(invoice)
        run_prenotice
      end

      assert_equal 1, u1_logs_for(invoice).where(template_key: "noti_prenotice").count
    end

    test "시작 10시·종료 14시 회원은 오늘 10시 슬롯을 ①로 통보한다 — 09시 겹침은 시작 09시 회원 특유 (REM-11·리뷰 W-2 경계)" do
      users(:delta).update!(remind_start_hour: 10, remind_end_hour: 14)  # 재예약 슬롯이 10:00에 찍힌다
      invoice = overdue_invoice_for(users(:delta))
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "confirm_d1",
                         recipient_role: :debtor, status: :pending,
                         scheduled_at: Time.zone.parse("2026-11-10 10:00"))

      travel_to(Time.zone.parse("2026-11-10 09:00")) do              # 사전통보 시점에 슬롯은 미래
        assert_prenotice_step_present(invoice)
        assert_equal Time.zone.parse("2026-11-10 10:00"),            # ① — 슬롯 그대로
                     Reminders::SendSchedule.send_at_for(user: invoice.user, invoice: invoice,
                                                         template_key: "confirm_d1")
        run_prenotice
      end

      assert_equal 1, u1_logs_for(invoice).where(template_key: "noti_prenotice").count
    end

    test "기본 창 회원의 noti_prenotice와 noti_due_soon은 병행한다 — 새 필터는 due_soon 경로를 건드리지 않는다 (NOTI-1·REM-11)" do
      overdue = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))          # D+1 — 오늘 도래
      due_tomorrow = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                             due_on: Date.new(2026, 11, 11))    # 내일 — due_soon

      travel_to(Time.zone.parse("2026-11-10 09:00")) do
        run_prenotice
      end

      assert_equal [ "noti_prenotice" ], u1_logs_for(overdue).map(&:template_key)
      assert_equal [ "noti_due_soon" ], u1_logs_for(due_tomorrow).map(&:template_key)
    end

    test "종료 14시 회원은 prenotice는 생략돼도 noti_due_soon은 나간다 (NOTI-1 — due_soon은 발송 시각 무관)" do
      users(:delta).update!(remind_end_hour: 14)
      overdue = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      due_tomorrow = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                             due_on: Date.new(2026, 11, 11))

      travel_to(Time.zone.parse("2026-11-10 09:00")) do
        run_prenotice
      end

      assert_empty u1_logs_for(overdue)                              # 실제 발송일 내일 — prenotice 생략
      assert_equal [ "noti_due_soon" ], u1_logs_for(due_tomorrow).map(&:template_key)
    end

    test "대시보드 오늘 발송 예정 카드와 사전통보는 같은 상태에서 함께 갈린다 — 기본 창·종료 14시·시작 15시 (DASH-2·REM-11 동치)" do
      windows = {
        "기본 창" => { remind_start_hour: 9, remind_end_hour: 18 },
        "종료 14시" => { remind_start_hour: 9, remind_end_hour: 14 },
        "시작 15시" => { remind_start_hour: 15, remind_end_hour: 18 }
      }
      windows.each do |label, attrs|
        users(:delta).update!(attrs)
        invoice = overdue_invoice_for(users(:delta))

        travel_to(Time.zone.parse("2026-11-10 09:00")) do
          assert_prenotice_step_present(invoice)                     # 스텝은 세 창 모두 오늘 도래
          result = Dashboards::ReminderActionsService.call(user: users(:delta))
          card_row = result.todays_sends.find { |row| row.invoice == invoice }
          run_prenotice
          notified = u1_logs_for(invoice).where(template_key: "noti_prenotice").exists?

          assert_equal card_row.present?, notified,
                       "#{label} — 카드 노출과 사전통보가 동치여야 한다(카드=#{card_row.present?} 통보=#{notified})"
          expected = attrs[:remind_start_hour] == 15 ? "15:00" : "14:00"
          if attrs[:remind_end_hour] == 14
            assert_nil card_row                                      # 종료 14시 — 내일 09시로 미뤄 카드에서도 뺀다
          else
            assert_equal Time.zone.parse("2026-11-10 #{expected}"), card_row.send_at
          end
        end
        MessageLog.where(invoice_id: invoice.id).delete_all          # 다음 창 대조를 위한 상태 초기화
      end
    end
  end
end
