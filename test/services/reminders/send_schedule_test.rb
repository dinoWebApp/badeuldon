require "test_helper"
require_relative "../../test_helpers/reminder_factories"

module Reminders
  # 실제 발송 예정 시각 산정(Reminders::SendSchedule — REM-11·DASH-2·REM-3·TIME-1) 단위 검증.
  # ① 채무자 향 pending 슬롯(scheduled_at이 미래일 때만) / ② user.next_remind_slot(다음 스캔
  # 시각) 규칙과 next_scan_time 경계를 검증한다. 시간은 travel_to로 2026-11-10(화) KST 고정.
  # 외부 API 호출 없음(산정만 — 솔라피 경로 없음).
  class SendScheduleTest < ActiveSupport::TestCase
    include ReminderFactories

    fixtures :users, :clients, :subscriptions, :payment_passes

    TUESDAY_1PM = Time.zone.parse("2026-11-10 13:00")
    TUESDAY_8AM = Time.zone.parse("2026-11-10 08:00")

    def create_gamma_pass
      users(:gamma).payment_passes.create!(total_uses: 10, remaining_uses: 10,
                                           expires_at: Time.zone.parse("2026-12-30 23:59:59 +0900"))
    end

    def create_scheduled_slot(invoice, template_key:, scheduled_at:)
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: template_key,
                         recipient_role: :debtor, status: :pending, scheduled_at: scheduled_at)
    end

    def invoice_for(user)
      create_reminder_invoice(user: user, client: user.clients.first, due_on: Date.new(2026, 11, 11))
    end

    test "기본 창 평일 회원 — 다음 스캔인 오늘 14시를 돌려준다 (②)" do
      create_gamma_pass
      invoice = invoice_for(users(:gamma))

      travel_to(TUESDAY_1PM) do
        assert_equal Time.zone.parse("2026-11-10 14:00"),
                     SendSchedule.send_at_for(user: users(:gamma), invoice: invoice,
                                              template_key: "invoice_notice")
      end
    end

    test "시작 15시 회원 — 14시 스캔은 창 밖이라 오늘 15시를 돌려준다 (②)" do
      create_gamma_pass
      users(:gamma).update!(remind_start_hour: 15)
      invoice = invoice_for(users(:gamma))

      travel_to(TUESDAY_1PM) do
        assert_equal Time.zone.parse("2026-11-10 15:00"),
                     SendSchedule.send_at_for(user: users(:gamma), invoice: invoice,
                                              template_key: "invoice_notice")
      end
    end

    test "종료 14시 회원 — 14시 스캔은 창 밖이라 다음 허용 요일(수) 시작 시각을 돌려준다 (②)" do
      create_gamma_pass
      users(:gamma).update!(remind_end_hour: 14)   # 09~14 — 14시 스캔(14시 정각)은 창 밖
      invoice = invoice_for(users(:gamma))

      travel_to(TUESDAY_1PM) do
        assert_equal Time.zone.parse("2026-11-11 09:00"),  # 수요일 09시
                     SendSchedule.send_at_for(user: users(:gamma), invoice: invoice,
                                              template_key: "invoice_notice")
      end
    end

    test "비허용 요일·주말·당일 스캔 경과 — 오늘이 아닌 다음 스캔 시각을 돌려준다 (②)" do
      create_gamma_pass
      invoice = invoice_for(users(:gamma))

      travel_to(TUESDAY_1PM) do
        users(:gamma).update!(remind_allowed_wdays: "1,3,5")   # 화요일 비허용
        assert_equal Time.zone.parse("2026-11-11 09:00"),      # 수요일 시작 시각
                     SendSchedule.send_at_for(user: users(:gamma), invoice: invoice,
                                              template_key: "invoice_notice")
      end

      travel_to(Time.zone.parse("2026-11-07 10:00")) do        # 토요일 — 스캔 요일 아님
        assert_equal Time.zone.parse("2026-11-09 14:00"),      # 월요일 스캔
                     SendSchedule.send_at_for(user: users(:gamma), invoice: invoice,
                                              template_key: "invoice_notice")
      end

      travel_to(Time.zone.parse("2026-11-10 14:00")) do        # 당일 스캔 정각 경과
        assert_equal Time.zone.parse("2026-11-11 14:00"),
                     SendSchedule.send_at_for(user: users(:gamma), invoice: invoice,
                                              template_key: "invoice_notice")
      end
    end

    test "오늘 오전 9시 pending 슬롯은 ①로 그 시각을 돌려준다 (지나기 전)" do
      create_gamma_pass
      users(:gamma).update!(remind_end_hour: 14)
      invoice = invoice_for(users(:gamma))
      create_scheduled_slot(invoice, template_key: "invoice_notice",
                            scheduled_at: Time.zone.parse("2026-11-10 09:00"))

      travel_to(TUESDAY_8AM) do
        assert_equal Time.zone.parse("2026-11-10 09:00"),
                     SendSchedule.send_at_for(user: users(:gamma), invoice: invoice,
                                              template_key: "invoice_notice")
      end
    end

    test "지나간 pending 슬롯과 scheduled_at nil pending은 ②로 내려간다 (① 경과)" do
      create_gamma_pass
      users(:gamma).update!(remind_end_hour: 14)
      invoice = invoice_for(users(:gamma))
      create_scheduled_slot(invoice, template_key: "invoice_notice",
                            scheduled_at: Time.zone.parse("2026-11-10 09:00"))

      travel_to(TUESDAY_1PM) do
        assert_equal Time.zone.parse("2026-11-11 09:00"),   # ② 폴백 — 수요일 09시
                     SendSchedule.send_at_for(user: users(:gamma), invoice: invoice,
                                              template_key: "invoice_notice")
      end

      stale = invoice_for(users(:gamma))
      create_scheduled_slot(stale, template_key: "invoice_notice", scheduled_at: nil)
      travel_to(TUESDAY_1PM) do
        assert_equal Time.zone.parse("2026-11-11 09:00"),
                     SendSchedule.send_at_for(user: users(:gamma), invoice: stale,
                                              template_key: "invoice_notice")
      end
    end

    test "U1 향 pending 슬롯은 ①에 잡히지 않는다 — 채무자 향만 본다" do
      create_gamma_pass
      invoice = invoice_for(users(:gamma))
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "invoice_notice",
                         recipient_role: :user, status: :pending,
                         scheduled_at: Time.zone.parse("2026-11-10 16:00"))

      travel_to(TUESDAY_1PM) do
        assert_equal Time.zone.parse("2026-11-10 14:00"),
                     SendSchedule.send_at_for(user: users(:gamma), invoice: invoice,
                                              template_key: "invoice_notice")
      end
    end

    test "next_scan_time — 13:59:59는 오늘 14시, 14:00:00은 다음 평일 14시다" do
      travel_to(Time.zone.parse("2026-11-10 13:59:59")) do
        assert_equal Time.zone.parse("2026-11-10 14:00"), SendSchedule.next_scan_time
      end
      travel_to(Time.zone.parse("2026-11-10 14:00")) do
        assert_equal Time.zone.parse("2026-11-11 14:00"), SendSchedule.next_scan_time
      end
      travel_to(Time.zone.parse("2026-11-06 18:00")) do       # 금요일 저녁 — 다음은 월요일
        assert_equal Time.zone.parse("2026-11-09 14:00"), SendSchedule.next_scan_time
      end
    end
  end
end
