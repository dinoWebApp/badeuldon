require "test_helper"
require_relative "../../test_helpers/reminder_factories"

module Dashboards
  # DASH-2·Q31 — 「미열람 방치」 카드 쿼리(UnviewedIdleQuery).
  # 시나리오 기준: PRD §6.9 DASH-2(구현 확정 — 결정 기록 Q31)·INV-4(열람 전이).
  # ① 상태 issued(한 번도 열지 않음 — mark_viewed!가 유일한 issued→viewed 경로)이고
  # issued_at이 3일 이상 지난 미수 청구 ② 경계(3일 전 발행 포함·2일 전 제외) ③ 열람·연체·
  # 마감·무효·초안 제외 ④ idle 일수 = 오늘 − 발행일(TIME-1) ⑤ 발행일 오름차순·소유권 격리.
  # 시간은 travel_to로 2026-11-10(화) KST 고정(TIME-1). 외부 API 호출 없음.
  class UnviewedIdleQueryTest < ActiveSupport::TestCase
    include ReminderFactories

    fixtures :users, :clients

    TUESDAY = Time.zone.parse("2026-11-10 10:00")

    test "발행 3일 전 청구를 idle_days 3으로 반환한다 (DASH-2·Q31)" do
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 24))
      invoice.update_columns(issued_at: Time.zone.parse("2026-11-07 10:00"))

      travel_to(TUESDAY) do
        rows = UnviewedIdleQuery.call(user: users(:gamma))
        assert_equal 1, rows.size
        assert_equal invoice.id, rows.first.invoice.id
        assert_equal 3, rows.first.idle_days
        assert_kind_of UnviewedIdleQuery::Row, rows.first
      end
    end

    test "경계 — 발행일이 3일 전 당일까지 포함하고 2일 전부터 제외한다 (DASH-2)" do
      three_days_ago = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                               due_on: Date.new(2026, 11, 24))
      three_days_ago.update_columns(issued_at: Time.zone.parse("2026-11-07 23:59"))  # 3일 전 막바지 — 포함
      two_days_ago = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                             due_on: Date.new(2026, 11, 24))
      two_days_ago.update_columns(issued_at: Time.zone.parse("2026-11-08 00:00"))    # 2일 전 시작 — 제외

      travel_to(TUESDAY) do
        rows = UnviewedIdleQuery.call(user: users(:gamma))
        assert_equal [ three_days_ago.id ], rows.map { |row| row.invoice.id }
      end
    end

    test "열람·연체 상태 청구는 제외한다 — 미열람(issued)만 (INV-4·DASH-2)" do
      viewed = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                       due_on: Date.new(2026, 11, 24), status: :viewed)
      viewed.update_columns(issued_at: Time.zone.parse("2026-11-01 10:00"))
      overdue = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 1), status: :overdue)
      overdue.update_columns(issued_at: Time.zone.parse("2026-11-01 10:00"))

      travel_to(TUESDAY) do
        assert_empty UnviewedIdleQuery.call(user: users(:gamma))
      end
    end

    test "마감·무효·초안·발행 시각 없는 청구는 제외한다 (DASH-2 — 미수·발행 계열만)" do
      paid = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                     due_on: Date.new(2026, 11, 24), status: :paid)
      paid.update_columns(issued_at: Time.zone.parse("2026-11-01 10:00"))
      voided = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                       due_on: Date.new(2026, 11, 24), status: :voided, with_link: false)
      voided.update_columns(issued_at: Time.zone.parse("2026-11-01 10:00"))
      draft = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                      due_on: Date.new(2026, 11, 24), status: :draft, with_link: false)
      create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                              due_on: Date.new(2026, 11, 24))  # 발행 경로 밖 — issued_at nil

      travel_to(TUESDAY) do
        assert_empty UnviewedIdleQuery.call(user: users(:gamma))
      end
    end

    test "여러 청구는 발행일 오름차순으로 정렬된다 (DASH-2)" do
      older = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                      due_on: Date.new(2026, 11, 24))
      older.update_columns(issued_at: Time.zone.parse("2026-11-01 10:00"))
      newer = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                      due_on: Date.new(2026, 11, 24))
      newer.update_columns(issued_at: Time.zone.parse("2026-11-07 10:00"))

      travel_to(TUESDAY) do
        rows = UnviewedIdleQuery.call(user: users(:gamma))
        assert_equal [ older.id, newer.id ], rows.map { |row| row.invoice.id }
        assert_equal [ 9, 3 ], rows.map(&:idle_days)
      end
    end

    test "다른 회원의 청구는 격리된다 (DASH-2 — Current.user 스코프)" do
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 24))
      invoice.update_columns(issued_at: Time.zone.parse("2026-11-01 10:00"))

      travel_to(TUESDAY) do
        delta_rows = UnviewedIdleQuery.call(user: users(:delta))
        assert delta_rows.any?  # delta는 fixtures의 미열람 경과 건(delta_issued 등)을 가진다
        assert_empty delta_rows.select { |row| row.invoice.id == invoice.id }  # gamma 소유 청구는 비노출
      end
    end
  end
end
