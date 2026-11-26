require "test_helper"
require_relative "../../test_helpers/reminder_factories"

module Dashboards
  # DASH-2·Q31 — 「오늘 발송 예정」 카드의 후보 청구 조회(TodaysSendsQuery).
  # 시나리오 기준: PRD §6.9 DASH-2(2026-11-26 리뷰 W-5 층 분리 반영)·REM-3·REM-8·VIEW-7.
  # Query는 자격·모집합·후보 범위까지만 판정한다(최종 스텝 선별은 ReminderActionsService).
  # ① REM-8 자격(Plus 또는 사용 가능한 수금 패스)이 없으면 빈 집합 ② 기본 트랙 후보는
  # due_on ∈ 오늘−17..오늘+1(주말 창 경계 — 금요일 만기 D+14의 월요일 창 종료) ③ 약속 트랙은
  # 최신 this_week·date_selected 약속의 promised_on ∈ 오늘−4..오늘+1 ④ 발송 모집합
  # (reminders_dispatchable) 밖 — 수신 거부·보류·마감·링크 만료 — 제외 ⑤ 만기일 오름차순.
  # 시간은 travel_to로 2026-11-10(화) KST 고정(TIME-1). 외부 API 호출 없음.
  class TodaysSendsQueryTest < ActiveSupport::TestCase
    include ReminderFactories

    fixtures :users, :clients

    TUESDAY = Time.zone.parse("2026-11-10 10:00")

    def create_gamma_pass
      users(:gamma).payment_passes.create!(total_uses: 10, remaining_uses: 10,
                                           expires_at: Time.zone.parse("2026-12-30 23:59:59 +0900"))
    end

    test "오늘 도래 스텝이 있는 미수 청구를 후보로 반환한다 (DASH-2·Q31)" do
      create_gamma_pass
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 11))       # 내일 만기 — D-1

      travel_to(TUESDAY) do
        rows = TodaysSendsQuery.call(user: users(:gamma))
        assert_equal [ invoice.id ], rows.map(&:id)
        assert_kind_of ActiveRecord::Relation, rows
      end
    end

    test "기본 트랙 후보 범위 밖 만기 청구는 제외한다 (DASH-2·Q31)" do
      create_gamma_pass
      create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                              due_on: Date.new(2026, 11, 12))                       # 오늘+2 — 밖
      create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                              due_on: Date.new(2026, 10, 23), status: :overdue)     # 오늘−18 — 밖

      travel_to(TUESDAY) do
        assert_empty TodaysSendsQuery.call(user: users(:gamma))
      end
    end

    test "범위 경계 — 오늘+1과 오늘−17까지 포함한다 (DASH-2·Q31 — 주말 창 종료)" do
      create_gamma_pass
      tomorrow = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                         due_on: Date.new(2026, 11, 11))                       # 오늘+1
      window_end = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                           due_on: Date.new(2026, 10, 24), status: :overdue)   # 오늘−17

      travel_to(TUESDAY) do
        assert_equal [ window_end.id, tomorrow.id ].sort,
                     TodaysSendsQuery.call(user: users(:gamma)).map(&:id).sort
      end
    end

    test "약속 트랙 — 최신 약속일이 오늘이면 후보에 들어간다 (DASH-2·Q31·PROMISE-3)" do
      create_gamma_pass
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 25))   # 기본 트랙 밖 만기
      travel_to(TUESDAY) do
        invoice.promises.create!(kind: :date_selected, promised_on: Date.current)

        assert_equal [ invoice.id ], TodaysSendsQuery.call(user: users(:gamma)).map(&:id)
      end
    end

    test "약속 트랙 범위 밖 약속일은 후보로 만들지 않는다 (DASH-2·Q31)" do
      create_gamma_pass
      travel_to(TUESDAY) do
        invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                          due_on: Date.new(2026, 11, 25))
        promise = invoice.promises.create!(kind: :date_selected, promised_on: Date.current)
        promise.update_column(:promised_on, Date.current - 5)  # 오늘−5 — 과거 약속(재응답 전 상정)

        assert_empty TodaysSendsQuery.call(user: users(:gamma))
      end
    end

    test "약속 트랙 포함 경계 — 약속일 오늘−4(promise_overdue nominal+1+소급 창 끝)도 후보다 (DASH-2·Q31·REM-3)" do
      create_gamma_pass
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 25))   # 기본 트랙 밖 만기
      travel_to(TUESDAY) do
        promise = invoice.promises.create!(kind: :date_selected, promised_on: Date.current)
        promise.update_column(:promised_on, Date.current - 4)  # 검증이 과거 약속일을 막아 직접 마킹(기존 −5 테스트 선례)

        assert_equal [ invoice.id ], TodaysSendsQuery.call(user: users(:gamma)).map(&:id)
      end
    end

    test "약속 트랙 포함 경계 — 약속일 오늘+1(promise_d1 nominal이 내일 도래 전일)도 후보다 (DASH-2·Q31·PROMISE-3)" do
      create_gamma_pass
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 25))
      travel_to(TUESDAY) do
        invoice.promises.create!(kind: :date_selected, promised_on: Date.current + 1)

        assert_equal [ invoice.id ], TodaysSendsQuery.call(user: users(:gamma)).map(&:id)
      end
    end

    test "this_week kind 약속도 약속 트랙 후보가 된다 (DASH-2·Q31 — this_week·date_selected)" do
      create_gamma_pass
      # this_week의 약속일은 서버 산정(접수일 기준 금요일) — 금요일에 접수하면 약속일=오늘이 되어
      # 약속 트랙 창(오늘−4..오늘+1)에 들어간다(PROMISE-2·TIME-1).
      travel_to(Time.zone.parse("2026-11-13 10:00")) do   # 금요일
        invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                          due_on: Date.new(2026, 11, 27))   # 기본 트랙 창(오늘−17..오늘+1) 밖
        invoice.promises.create!(kind: :this_week)

        assert_equal Date.current, invoice.promises.this_week.sole.promised_on
        assert_equal [ invoice.id ], TodaysSendsQuery.call(user: users(:gamma)).map(&:id)
      end
    end

    test "후보 범위 안 청구라도 링크 유효기간이 지났으면 후보에서 제외된다 (DASH-2·Q31 — link_valid)" do
      create_gamma_pass
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 11))
      invoice.update_column(:token_expires_at, Time.zone.parse("2026-11-09 23:59:59 +0900"))  # 오늘(11-10) 전 만료

      travel_to(TUESDAY) do
        assert_empty TodaysSendsQuery.call(user: users(:gamma))
      end
    end

    test "시퀀스가 종결된 청구는 후보 범위 안이어도 제외된다 (DASH-2·Q31 — sequence_finished)" do
      create_gamma_pass
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 11))
      invoice.update_column(:sequence_finished_at, Time.zone.parse("2026-11-09 09:00 +0900"))

      travel_to(TUESDAY) do
        assert_empty TodaysSendsQuery.call(user: users(:gamma))
      end
    end

    test "수신 거부된 거래처의 청구는 후보에서 제외된다 — 다른 거래처 청구는 유지된다 (VIEW-7·W-3)" do
      create_gamma_pass
      refused = create_reminder_invoice(user: users(:gamma), client: create_gamma_client("거부거래처"),
                                        due_on: Date.new(2026, 11, 11))
      mark_refused(refused.client, at: Time.zone.parse("2026-11-10 09:00"))
      normal = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                       due_on: Date.new(2026, 11, 11))

      travel_to(TUESDAY) do
        assert_equal [ normal.id ], TodaysSendsQuery.call(user: users(:gamma)).map(&:id)
      end
    end

    test "마감·보류 청구는 발송 모집합 밖이라 후보가 아니다 (DASH-2)" do
      create_gamma_pass
      create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                              due_on: Date.new(2026, 11, 11), status: :paid)
      suspended = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                          due_on: Date.new(2026, 11, 11))
      suspended.update_columns(reminders_suspended_at: Time.zone.parse("2026-11-10 09:00"))

      travel_to(TUESDAY) do
        assert_empty TodaysSendsQuery.call(user: users(:gamma))
      end
    end

    test "자격이 없는 회원(Free·패스 없음)은 후보가 있어도 빈 집합이다 (REM-8)" do
      create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                              due_on: Date.new(2026, 11, 11))       # 패스를 만들지 않는다

      travel_to(TUESDAY) do
        assert_empty TodaysSendsQuery.call(user: users(:gamma))
      end
    end

    test "여러 청구는 만기일 오름차순으로 정렬된다 (DASH-2)" do
      create_gamma_pass
      later = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                      due_on: Date.new(2026, 11, 11))                      # 오늘+1
      earlier = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 10, 30), status: :overdue)  # 오늘−11

      travel_to(TUESDAY) do
        assert_equal [ earlier.id, later.id ], TodaysSendsQuery.call(user: users(:gamma)).map(&:id)
      end
    end

    test "다른 회원의 청구는 격리된다 (DASH-2)" do
      create_gamma_pass
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 11))

      travel_to(TUESDAY) do
        delta_rows = TodaysSendsQuery.call(user: users(:delta))
        assert delta_rows.any?  # delta는 fixtures의 후보 범위 건(delta_due_soon 등)을 가진다
        assert_empty delta_rows.select { |row| row.id == invoice.id }  # gamma 소유 청구는 비노출
      end
    end

    private

    def create_gamma_client(name)
      users(:gamma).clients.create!(name: name, contact_name: "김거부", phone: "010-5555-7000")
    end
  end
end
