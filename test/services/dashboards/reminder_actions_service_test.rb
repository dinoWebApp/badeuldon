require "test_helper"
require_relative "../../test_helpers/reminder_factories"
require_relative "../../test_helpers/fake_solapi_client"
require_relative "../../test_helpers/solapi_stubbing"

module Dashboards
  # DASH-2·Q31 — 「오늘의 액션」 안내성 세 종 산출 서비스(ReminderActionsService — W-5 층 분리).
  # 시나리오 기준: PRD §6.9 DASH-2(2026-11-26 리뷰 반영 문단)·REM-3·REM-8·REM-11,
  # _workspace/05_review.md T3 C-1·C-2·W-3(3-A 규칙).
  # 「오늘 발송 예정」의 send_at 판정:
  #   ① 그 단계의 채무자 향 pending 슬롯(재예약된 발송)의 scheduled_at — 시각이 지나기 전일 때만
  #     (지나간 슬롯은 "보류할 수 있는 예정"이 아니므로 ②로 내려보낸다 — 슬롯 실행 전 오전에만
  #     "오전 9시"로 노출된다).
  #   ② 없으면 다음 스캔 시각(평일 14시 KST)을 회원의 REM-3 허용 창에 비춘 User#next_remind_slot.
  #   → send_at이 오늘인 행만 카드에 싣는다 — 주말·비허용 요일·창 밖 미룸·당일 스캔 경과 건은 뺀다.
  # 기존 마감·답변 대기와 달리 약속일 도래·미열람 방치는 자격과 무관하다(오늘 발송 예정만 REM-8).
  # 시간은 travel_to로 2026-11-07(토)~11-10(화) KST 고정(TIME-1). 외부 API 호출 없음(스캔 실행이
  # 아닌 산정만 수행 — 솔라피 경로 없음).
  class ReminderActionsServiceTest < ActiveSupport::TestCase
    include ReminderFactories
    include SolapiStubbing

    fixtures :users, :clients, :subscriptions, :payment_passes

    SATURDAY_AM = Time.zone.parse("2026-11-07 10:00")
    SUNDAY_AM = Time.zone.parse("2026-11-08 10:00")
    MONDAY_AM = Time.zone.parse("2026-11-09 10:00")
    TUESDAY_8AM = Time.zone.parse("2026-11-10 08:00")
    TUESDAY_AM = Time.zone.parse("2026-11-10 10:00")
    TUESDAY_1PM = Time.zone.parse("2026-11-10 13:00")
    TUESDAY_3PM = Time.zone.parse("2026-11-10 15:00")

    def create_gamma_pass
      users(:gamma).payment_passes.create!(total_uses: 10, remaining_uses: 10,
                                           expires_at: Time.zone.parse("2026-12-30 23:59:59 +0900"))
    end

    # Reminders::SendService#reschedule!이 남기는 예약 슬롯과 같은 형태(채무자 향 pending).
    # scheduled_at: nil이면 14시 스캔의 창 내 즉시 발송이 이력을 점유한 상태다(new_log! —
    # 창 내 발송은 예약 시각 없이 pending을 만든다).
    def create_scheduled_slot(invoice, template_key:, scheduled_at:)
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: template_key,
                         recipient_role: :debtor, status: :pending, scheduled_at: scheduled_at)
    end

    test "오늘 나갈 자동 안내를 send_at과 함께 돌려준다 — 기본 창 회원은 다음 스캔인 오늘 14시 (DASH-2·C-1·C-2)" do
      create_gamma_pass
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 11))

      travel_to(TUESDAY_AM) do
        result = ReminderActionsService.call(user: users(:gamma))
        assert_kind_of ReminderActionsService::Result, result
        assert_equal 1, result.todays_sends.size
        row = result.todays_sends.first
        assert_kind_of ReminderActionsService::SendRow, row
        assert_equal invoice.id, row.invoice.id
        assert_equal "invoice_notice", row.template_key
        assert_equal Time.zone.parse("2026-11-10 14:00"), row.send_at
        assert_equal 1, result.todays_sends_total
        assert_empty result.promises_due_today
        assert_empty result.unviewed_idle
      end
    end

    test "재예약된 pending 슬롯의 시각이 예정 시각이다 — 창 밖 발송이 미룬 오늘 09시 슬롯 (①·REM-3·C-2)" do
      create_gamma_pass
      users(:gamma).update!(remind_end_hour: 14)   # REM-3 축소 — 09~14, 14시 스캔은 창 밖
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 11))
      create_scheduled_slot(invoice, template_key: "invoice_notice",
                            scheduled_at: Time.zone.parse("2026-11-10 09:00"))  # 전날 14시 재예약 상정

      travel_to(TUESDAY_8AM) do
        result = ReminderActionsService.call(user: users(:gamma))
        assert_equal [ Time.zone.parse("2026-11-10 09:00") ], result.todays_sends.map(&:send_at)
      end
    end

    test "재예약 슬롯이 내일 발송이면 오늘 카드에서 뺀다 (① — 날짜 판정·C-2)" do
      create_gamma_pass
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 11))
      create_scheduled_slot(invoice, template_key: "invoice_notice",
                            scheduled_at: Time.zone.parse("2026-11-11 09:00"))

      travel_to(TUESDAY_AM) do
        assert_empty ReminderActionsService.call(user: users(:gamma)).todays_sends
      end
    end

    test "지나간 pending 슬롯은 예정으로 보지 않는다 — 슬롯 실행 전 오전에만 노출된다 (① 경과·W-3)" do
      create_gamma_pass
      users(:gamma).update!(remind_end_hour: 14)
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 11))
      create_scheduled_slot(invoice, template_key: "invoice_notice",
                            scheduled_at: Time.zone.parse("2026-11-10 09:00"))

      travel_to(TUESDAY_8AM) do
        assert_equal 1, ReminderActionsService.call(user: users(:gamma)).todays_sends.size
      end
      travel_to(TUESDAY_3PM) do
        # 09시 슬롯은 시각 경과 — 실제로는 발송됐거나(step_sent?면 애초 카드 제외) 곧 실행될
        # 예정이라 "보류할 수 있는 예정"이 아니다. ②로 내려가 다음 허용 요일(목 09시)이 되어
        # 오늘 카드에서 빠진다.
        assert_empty ReminderActionsService.call(user: users(:gamma)).todays_sends
      end
    end

    test "scheduled_at 없는 pending(발송 실행 점유)도 ②로 판정해 오늘 14시 행이 나온다 (W-2 — nil 가드)" do
      create_gamma_pass
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 11))
      # 14시 스캔이 그 단계의 발송을 진행하는 동안 이력은 scheduled_at 없는 pending이다
      # (창 내 즉시 발송 — SendService new_log!·mark_execution_started!). 슬롯 판정은
      # scheduled_at이 있고 미래일 때만 ①을 쓴다 — nil이면 ②로 내려가야 한다(가드 없으면
      # nil >= Time.current로 예외).
      create_scheduled_slot(invoice, template_key: "invoice_notice", scheduled_at: nil)

      travel_to(TUESDAY_1PM) do
        result = ReminderActionsService.call(user: users(:gamma))
        assert_equal [ Time.zone.parse("2026-11-10 14:00") ], result.todays_sends.map(&:send_at)
        assert_equal 1, result.todays_sends_total
      end
      travel_to(TUESDAY_3PM) do
        # ②로 내려간 행의 예정 시각은 다음 스캔(수 14시) — 오늘 카드에서 빠진다
        assert_empty ReminderActionsService.call(user: users(:gamma)).todays_sends
      end
    end

    test "오늘 발송 예정 행은 발송 예정 시각이 이른 순으로 잘리고 같은 시각은 청구 id 순이다 (W-1·DASH-2)" do
      create_gamma_pass
      invoices = 6.times.map do
        create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                due_on: Date.new(2026, 11, 11))
      end
      # 후보 Relation(만기일·id 오름차순)의 가장 뒤 청구에 재예약된 오전 9시 슬롯(전날 14시에
      # 창이 닫혀 미뤄진 형태)을 둔다 — 정렬이 없으면 이 행이 6번째로 잘려 보류할 수 없다.
      create_scheduled_slot(invoices.last, template_key: "invoice_notice",
                            scheduled_at: Time.zone.parse("2026-11-10 09:00"))

      travel_to(TUESDAY_8AM) do
        result = ReminderActionsService.call(user: users(:gamma))
        assert_equal 6, result.todays_sends_total
        shown = result.todays_sends
        assert_equal 5, shown.size
        # 첫 행 — 재예약 오전 9시 슬롯(가장 이른 예정 시각)
        assert_equal Time.zone.parse("2026-11-10 09:00"), shown.first.send_at
        assert_equal invoices.last.id, shown.first.invoice.id
        # 나머지 4행 — ②의 오늘 14시, 같은 시각은 청구 id 오름차순
        assert shown[1..].all? { |row| row.send_at == Time.zone.parse("2026-11-10 14:00") }
        assert_equal invoices.first(4).map(&:id), shown[1..].map { |row| row.invoice.id }
        # 잘린 행 — 정렬 기준으로 가장 늦은 행(오늘 14시·남은 청구 중 가장 큰 id)
        shown_ids = shown.map { |row| row.invoice.id }
        assert_equal [ invoices[4].id ], invoices.map(&:id) - shown_ids
      end
    end

    test "REM-3 시작 15시 회원은 다음 스캔 14시가 창 밖이라 오늘 15시가 예정 시각이다 (②·C-2·W-3)" do
      create_gamma_pass
      users(:gamma).update!(remind_start_hour: 15)
      create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                              due_on: Date.new(2026, 11, 11))

      travel_to(TUESDAY_AM) do
        result = ReminderActionsService.call(user: users(:gamma))
        assert_equal [ Time.zone.parse("2026-11-10 15:00") ], result.todays_sends.map(&:send_at)
      end
    end

    test "REM-3 종료 14시 회원의 오늘 nominal 스텝은 다음 허용 요일 발송이라 카드에서 빠진다 (②·C-2·W-3)" do
      create_gamma_pass
      users(:gamma).update!(remind_end_hour: 14)
      create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                              due_on: Date.new(2026, 11, 11))

      travel_to(TUESDAY_AM) do
        assert_empty ReminderActionsService.call(user: users(:gamma)).todays_sends
      end
    end

    test "오늘이 REM-3 비허용 요일이면 카드가 없고 허용 요일 오전에는 노출된다 (②·C-2·W-3)" do
      create_gamma_pass
      users(:gamma).update!(remind_allowed_wdays: "1,3,5")   # 화·목 제외
      create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                              due_on: Date.new(2026, 11, 9))   # 월요일 만기

      travel_to(TUESDAY_AM) do
        # 화요일 비허용 — 다음 허용 요일(수) 09시가 예정이라 오늘 카드 없음
        assert_empty ReminderActionsService.call(user: users(:gamma)).todays_sends
      end
      travel_to(MONDAY_AM) do
        # 월요일 허용 — 만기 예고 nominal(일)의 소급 창이 오늘 종료
        result = ReminderActionsService.call(user: users(:gamma))
        assert_equal [ Time.zone.parse("2026-11-09 14:00") ], result.todays_sends.map(&:send_at)
      end
    end

    test "당일 스캔이 지나간 뒤에는 오늘 카드가 없고 스캔 전에는 노출된다 (②·C-1·W-3)" do
      create_gamma_pass
      create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                              due_on: Date.new(2026, 11, 11))

      travel_to(TUESDAY_1PM) do
        result = ReminderActionsService.call(user: users(:gamma))
        assert_equal [ Time.zone.parse("2026-11-10 14:00") ], result.todays_sends.map(&:send_at)
      end
      travel_to(TUESDAY_3PM) do
        # 다음 스캔은 내일(수) 14시 — 실제 발송일이 오늘이 아니다
        assert_empty ReminderActionsService.call(user: users(:gamma)).todays_sends
      end
    end

    test "주말에는 스캔이 없어 카드가 없고 월요일 오전에는 노출된다 (C-1·W-3)" do
      create_gamma_pass
      create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                              due_on: Date.new(2026, 11, 8))   # 일요일 만기

      travel_to(SATURDAY_AM) do
        # 예정 스텝(만기 예고 nominal 토)은 있지만 다음 스캔이 월요일 — 오늘 카드 없음
        assert_empty ReminderActionsService.call(user: users(:gamma)).todays_sends
      end
      travel_to(SUNDAY_AM) do
        assert_empty ReminderActionsService.call(user: users(:gamma)).todays_sends
      end
      travel_to(MONDAY_AM) do
        # 만기 예고(nominal 토)·D+1 확인 안내(nominal 월)가 같은 창에 도래 — 스캔도 둘 다 발송한다
        result = ReminderActionsService.call(user: users(:gamma))
        assert_equal %w[ invoice_notice confirm_d1 ], result.todays_sends.map(&:template_key)
        assert result.todays_sends.all? { |row| row.send_at == Time.zone.parse("2026-11-09 14:00") }
        assert_equal 2, result.todays_sends_total
      end
    end

    test "6건이면 5건으로 잘리고 총건수를 돌려주고 5건이면 잘림이 없다 (DASH-2·Q31·W-3)" do
      create_gamma_pass
      5.times do
        create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                due_on: Date.new(2026, 11, 11))
      end

      travel_to(TUESDAY_AM) do
        result = ReminderActionsService.call(user: users(:gamma))
        assert_equal 5, result.todays_sends.size
        assert_equal 5, result.todays_sends_total

        create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                due_on: Date.new(2026, 11, 11))
        result = ReminderActionsService.call(user: users(:gamma))
        assert_equal 5, result.todays_sends.size
        assert_equal 6, result.todays_sends_total
      end
    end

    test "약속일 도래·미열람 방치를 그대로 전달하고 5건으로 잘린다 (DASH-2·Q31·W-3)" do
      create_gamma_pass
      travel_to(TUESDAY_AM) do
        6.times do
          invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                            due_on: Date.new(2026, 11, 20))
          invoice.update_columns(issued_at: Time.zone.parse("2026-11-01 10:00"))  # 미열람 경과
          create_promise(invoice, kind: :date_selected, promised_on: Date.current)  # 약속일 = 오늘
        end

        result = ReminderActionsService.call(user: users(:gamma))
        assert_equal 6, result.promises_due_today_total
        assert_equal 5, result.promises_due_today.size
        assert_equal 6, result.unviewed_idle_total
        assert_equal 5, result.unviewed_idle.size
      end
    end

    test "Free 회원은 오늘 발송 예정이 비어도 약속일 도래·미열람 방치는 받는다 (REM-8·DASH-2)" do
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 11))
      invoice.update_columns(issued_at: Time.zone.parse("2026-11-01 10:00"))

      travel_to(TUESDAY_AM) do
        result = ReminderActionsService.call(user: users(:gamma))
        assert_empty result.todays_sends          # REM-8 — 자동 발송 없음(거짓 0건 카드 금지)
        assert_empty result.promises_due_today
        assert_equal 1, result.unviewed_idle.size
        assert_equal 9, result.unviewed_idle.first.idle_days
      end
    end

    test "14:00:00 정각 경계 — 13:59:59에는 오늘 14시 행이 있고 14:00:00에는 없다 (②·C-1·2차 리뷰 제안 2)" do
      create_gamma_pass
      create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                              due_on: Date.new(2026, 11, 11))

      travel_to(Time.zone.parse("2026-11-10 13:59:59")) do
        result = ReminderActionsService.call(user: users(:gamma))
        assert_equal [ Time.zone.parse("2026-11-10 14:00") ], result.todays_sends.map(&:send_at)
      end
      travel_to(Time.zone.parse("2026-11-10 14:00")) do
        # 당일 스캔 시각 경과 — 다음 스캔은 수요일 14시라 실제 발송일이 오늘이 아니다
        assert_empty ReminderActionsService.call(user: users(:gamma)).todays_sends
      end
    end

    test "실제 14시 스캔이 만든 재예약 슬롯을 14시 30분 카드가 ① 경로로 보인다 — 시작 15시 회원은 오늘 15시 (C-2·①·2차 리뷰 제안 4)" do
      create_gamma_pass
      users(:gamma).update!(remind_start_hour: 15)   # REM-3 시작 15시 — 14시 스캔은 창 밖
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 11))

      travel_to(Time.zone.parse("2026-11-10 14:00")) do
        with_solapi_client(FakeSolapiClient.new) do
          Reminders::DispatchService.new.call        # 실제 스캔 — SendService#reschedule!
        end
        slot = MessageLog.find_by(invoice_id: invoice.id, template_key: "invoice_notice",
                                  recipient_role: :debtor, status: :pending)
        assert_equal Time.zone.parse("2026-11-10 15:00"), slot.scheduled_at  # 전제 — 오늘 15시 슬롯

        travel 30.minutes                            # 14:30 — 카드는 ①의 슬롯 시각을 따른다
        result = ReminderActionsService.call(user: users(:gamma))
        assert_equal [ invoice.id ], result.todays_sends.map { |row| row.invoice.id }
        assert_equal Time.zone.parse("2026-11-10 15:00"), result.todays_sends.first.send_at
      end
    end

    test "실제 14시 스캔 뒤 종료 14시 회원의 슬롯은 다음 허용 요일이라 14시 30분 카드가 없다 (C-2·①·2차 리뷰 제안 4)" do
      create_gamma_pass
      users(:gamma).update!(remind_end_hour: 14)     # REM-3 09~14 — 14시 스캔은 창 밖
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 11))

      travel_to(Time.zone.parse("2026-11-10 14:00")) do
        with_solapi_client(FakeSolapiClient.new) do
          Reminders::DispatchService.new.call
        end
        slot = MessageLog.find_by(invoice_id: invoice.id, recipient_role: :debtor, status: :pending)
        assert_equal Time.zone.parse("2026-11-11 09:00"), slot.scheduled_at  # 수요일 09시로 재예약

        travel 30.minutes
        # ① 슬롯(수 09:00)은 미래지만 실제 발송일이 내일 — 오늘 카드에서 빠진다
        assert_empty ReminderActionsService.call(user: users(:gamma)).todays_sends
      end
    end

    test "같은 template_key의 U1 향 pending이 있어도 ①에 잡히지 않고 채무자 카드 시각은 ②를 따른다 (2차 리뷰 제안 5)" do
      create_gamma_pass
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 11))
      # U1 향 pending(예: 이벤트 알림·재예약분) — 슬롯 판정은 채무자 향만 본다(부분 유니크도
      # debtor×pending에만 건다). U1 슬롯의 16시가 카드에 새어 나가면 ②(14시) 위반.
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "invoice_notice",
                         recipient_role: :user, status: :pending,
                         scheduled_at: Time.zone.parse("2026-11-10 16:00"))

      travel_to(TUESDAY_1PM) do
        result = ReminderActionsService.call(user: users(:gamma))
        assert_equal [ Time.zone.parse("2026-11-10 14:00") ], result.todays_sends.map(&:send_at)
      end
    end

    test "마감·보류·거부·종결·상한이 섞인 회원에서 오늘 발송 예정은 자격 있는 행만 정확히 담는다 (DASH-2·리뷰 제안 7)" do
      create_gamma_pass
      due = Date.new(2026, 11, 11)                   # D-1(만기 예고)이 오늘 도래
      keep1 = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main), due_on: due)
      keep2 = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main), due_on: due)

      # 사유별 제외 대상 — 마감·보류·종결·상한은 청구 단위, 거부는 거래처 단위(전용 거래처로 분리
      # — 리뷰 W-3①: 한 거래처의 거부가 다른 사유 검증을 가리지 않게 한다)
      create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                              due_on: due, status: :paid, with_link: false)          # 마감
      suspended = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                          due_on: due)
      suspended.update_column(:reminders_suspended_at, Time.zone.parse("2026-11-10 09:00"))
      finished = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                         due_on: due)
      finished.update_column(:sequence_finished_at, Time.zone.parse("2026-11-10 09:00"))
      capped = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                       due_on: due)
      5.times do
        MessageLog.create!(invoice: capped, user: capped.user, template_key: "issue_notice",
                           recipient_role: :debtor, status: :sent, origin: :manual)
      end
      assert capped.reload.reminder_cap_reached?     # 상한 전제 확인
      refused_client = users(:gamma).clients.create!(name: "감마거부 전용", contact_name: "김거부",
                                                     phone: "010-5555-7000")
      refused_client.update_column(:refused_at, Time.zone.parse("2026-11-10 09:00"))
      create_reminder_invoice(user: users(:gamma), client: refused_client, due_on: due)  # 거부

      travel_to(TUESDAY_AM) do
        result = ReminderActionsService.call(user: users(:gamma))
        assert_equal [ keep1.id, keep2.id ].sort,
                     result.todays_sends.map { |row| row.invoice.id }.sort
        assert_equal 2, result.todays_sends_total
      end
    end

    test "같은 청구가 미열람 방치와 오늘 발송 예정에 함께 놓일 수 있다 — 모순 없음 (DASH-2·리뷰 제안 8)" do
      create_gamma_pass
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 11))   # D-1이 오늘 도래
      invoice.update_columns(issued_at: Time.zone.parse("2026-11-01 10:00"))  # 9일 경과 미열람

      travel_to(TUESDAY_AM) do
        result = ReminderActionsService.call(user: users(:gamma))
        assert_includes result.todays_sends.map { |row| row.invoice.id }, invoice.id
        assert_includes result.unviewed_idle.map { |row| row.invoice.id }, invoice.id
        assert_equal 1, result.todays_sends_total
        assert_equal 1, result.unviewed_idle_total
      end
    end

    test "recurring.yml의 발송 스캔 스케줄과 스캔 상수가 어긋나지 않는다 (설정 드리프트 방지·C-1)" do
      config = YAML.load_file(Rails.root.join("config/recurring.yml"))
      %w[production development].each do |env|
        fields = config.fetch(env).fetch("reminders_dispatch").fetch("schedule").split
        assert_equal "0", fields[0], "#{env} 스캔 분(정각)"
        assert_equal Reminders::DispatchService::SCAN_HOUR.to_s, fields[1],
                     "#{env} 스캔 시각이 스캔 상수와 어긋난다 — 카드와 실제 발송 모집합이 갈라진다"
        assert_equal Reminders::DispatchService::SCAN_WDAYS, expand_cron_wdays(fields[4]),
                     "#{env} 스캔 요일이 스캔 상수와 어긋난다"
        assert_equal "Asia/Seoul", fields[5]  # TIME-1 — KST fugit 접미사
      end
    end

    private

    # cron 요일 필드("1-5"·"1,2,3" 형태 모두)를 요일 정수 집합으로 확장한다.
    def expand_cron_wdays(field)
      field.split(",").flat_map do |part|
        part.include?("-") ? Range.new(*part.split("-").map(&:to_i)).to_a : [ part.to_i ]
      end.uniq.sort
    end
  end
end
