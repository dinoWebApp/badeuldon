require "test_helper"
require_relative "../../test_helpers/reminder_factories"

module Dashboards
  # DASH-2·Q31 — 「약속일 도래」 카드 쿼리(PromisesDueTodayQuery).
  # 시나리오 기준: PRD §6.9 DASH-2(구현 확정 — 결정 기록 Q31)·PROMISE-3.
  # ① 최신 약속(this_week·date_selected — 청구별 created_at·id 마지막 행)의 약속일이 오늘인
  # 미수 청구 ② 재응답(재스케줄)으로 최신 약속일이 미래로 바뀐 건은 제외 ③ paid_report·inquiry는
  # 약속이 아니다 ④ 마감·초안 제외(미수 unsetsolved만) ⑤ 만기일 오름차순·소유권 격리.
  # 시간은 travel_to로 2026-11-10(화) KST 고정(TIME-1). 외부 API 호출 없음.
  class PromisesDueTodayQueryTest < ActiveSupport::TestCase
    include ReminderFactories

    fixtures :users, :clients

    TUESDAY = Time.zone.parse("2026-11-10 10:00")

    test "약속일이 오늘인 미수 청구를 반환한다 (DASH-2·Q31)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 15))
      travel_to(TUESDAY) do
        create_promise(invoice, kind: :date_selected, promised_on: Date.current)

        rows = PromisesDueTodayQuery.call(user: users(:delta))
        assert_equal 1, rows.size
        assert_equal invoice.id, rows.first.invoice.id
        assert_equal Date.current, rows.first.promise.promised_on
        assert_kind_of PromisesDueTodayQuery::Row, rows.first
      end
    end

    test "여러 청구는 만기일 오름차순으로 정렬된다 (DASH-2)" do
      travel_to(TUESDAY) do
        later = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 20))
        earlier = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                          due_on: Date.new(2026, 11, 12))
        create_promise(later, kind: :date_selected, promised_on: Date.current)
        create_promise(earlier, kind: :date_selected, promised_on: Date.current)

        rows = PromisesDueTodayQuery.call(user: users(:delta))
        assert_equal [ earlier.id, later.id ], rows.map { |row| row.invoice.id }
      end
    end

    test "재응답으로 최신 약속일이 미래로 바뀐 청구는 제외한다 — 최신 약속 기준 (PROMISE-3·Q31)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 15))
      travel_to(TUESDAY) do
        create_promise(invoice, kind: :date_selected, promised_on: Date.current)      # 이전 약속 — 오늘
        create_promise(invoice, kind: :date_selected, promised_on: Date.current + 3)  # 최신 약속 — 미래

        assert_empty PromisesDueTodayQuery.call(user: users(:delta))
      end
    end

    test "this_week 약속도 약속일(금요일)이 오늘이면 대상이고 paid_report·inquiry는 약속이 아니다 (DASH-2)" do
      this_week = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                          due_on: Date.new(2026, 11, 15))
      paid_report = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                            due_on: Date.new(2026, 11, 16))
      inquiry = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 17))

      # this_week의 약속일은 서버가 접수일 기준 산정(결정 #1 — 평일 접수 = 그 주 금요일)이므로
      # 금요일에 접수해 "약속일 = 오늘"을 만든다.
      travel_to(Time.zone.parse("2026-11-13 10:00")) do  # 금요일
        create_promise(this_week, kind: :this_week)
        create_promise(paid_report, kind: :paid_report)
        inquiry.promises.create!(kind: :inquiry, memo: "입금 계좌가 변경되었는지 확인 부탁드립니다.")

        rows = PromisesDueTodayQuery.call(user: users(:delta))
        assert_equal 1, rows.size
        assert_equal this_week.id, rows.sole.invoice.id
        assert_equal Date.new(2026, 11, 13), rows.sole.promise.promised_on
      end
    end

    test "약속일이 내일이면 제외한다 (경계 — 오늘만)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 15))
      travel_to(TUESDAY) do
        create_promise(invoice, kind: :date_selected, promised_on: Date.current + 1)

        assert_empty PromisesDueTodayQuery.call(user: users(:delta))
      end
    end

    test "마감·초안 청구는 제외한다 (DASH-2 — 미수 청구만)" do
      travel_to(TUESDAY) do
        paid = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                       due_on: Date.new(2026, 11, 15), status: :paid)
        draft = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 15), status: :draft, with_link: false)
        create_promise(paid, kind: :date_selected, promised_on: Date.current)
        create_promise(draft, kind: :date_selected, promised_on: Date.current)

        assert_empty PromisesDueTodayQuery.call(user: users(:delta))
      end
    end

    test "다른 회원의 약속은 격리된다 (DASH-2 — Current.user 스코프)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 15))
      travel_to(TUESDAY) do
        create_promise(invoice, kind: :date_selected, promised_on: Date.current)

        assert_empty PromisesDueTodayQuery.call(user: users(:gamma))
      end
    end
  end
end
