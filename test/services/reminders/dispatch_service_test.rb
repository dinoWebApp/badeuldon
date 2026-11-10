require "test_helper"
require_relative "../../test_helpers/fake_solapi_client"
require_relative "../../test_helpers/reminder_factories"
require_relative "../../test_helpers/solapi_stubbing"

module Reminders
  # 스텝 산정·발송 스캔(F-REM) — 기본/약속 트랙·D+1 열람 분기(SHARE-5)·주말 소급 창(REM-3)·
  # PAST_WINDOW 차단·final_d14/promise_overdue 종결(REM-12/13)·Free 자격 skip(REM-8)·
  # 공개 산정 진입점(steps_due_today·restartable?·manual_step_key — C-2·C-3·W-1).
  # 시나리오 기준: PRD §6.6 REM-2/3/4·PROMISE-3·§6.11 PLAN-3·SHARE-5,
  # _workspace/03_implementation.md Rule ID 매핑표, _workspace/05_review.md §Tester 중점 3·4·5.
  # 스캔은 SendService를 동기 호출하고 promise_overdue 성공 훅이 내부 NotifyUserService를
  # 생성하므로(생성자 주입 밖 경로) 발송을 동반하는 call은 with_solapi_client 방어선으로
  # 가로채 실호출 0을 보장한다(REM-10·W-7).
  # 소급 창 산술 주의 — 기준일(2026-11-10 화)에 만기 D-1 nominal이 주말이면 그 스텝은 이미
  # 창 경과라 PAST_WINDOW skip 기록이 스캔마다 먼저 남는다(예: 만기 11-09의 invoice_notice).
  class DispatchServiceTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    include ReminderFactories
    include SolapiStubbing

    fixtures :users, :clients, :invoices, :promises, :subscriptions, :payment_passes

    # 기준 시각 — 2026-11-10(화) 14:00(스캔 시각). 주말 소급 검증은 2026-11-09(월).
    TUESDAY_2PM = Time.zone.parse("2026-11-10 14:00")
    MONDAY_2PM = Time.zone.parse("2026-11-09 14:00")

    def setup
      @fake = FakeSolapiClient.new
    end

    # 발송 스캔 실행 후 해당 청구의 채무자 이력 목록(스킵 포함 — P4).
    # 스캔 경로는 SendService를 내부 생성하므로 클래스 생성 경로 방어선(with_solapi_client)으로
    # 가로챈다 — 약속 도과 훅(noti_promise_unkept)까지 함께 커버한다.
    def dispatched_logs_for(invoice)
      with_solapi_client(@fake) do
        DispatchService.new.call
      end
      MessageLog.where(invoice_id: invoice.id, recipient_role: :debtor).order(:id)
    end

    def assert_log_shapes(logs, expected)
      assert_equal expected, logs.map { |log| [ log.template_key, log.status, log.error_code ] }
    end

    test "기본 트랙 D-1 — 만기 전날이면 invoice_notice를 발송한다 (REM-2)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 11))

      travel_to(TUESDAY_2PM) do
        assert_log_shapes dispatched_logs_for(invoice),
                          [ [ "invoice_notice", "sent", nil ] ]
      end
    end

    test "기본 트랙 D+1 — 미열람 청구는 confirm_d1로 분기한다 (REM-4·SHARE-5)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      assert_empty invoice.view_events

      travel_to(TUESDAY_2PM) do
        # invoice_notice nominal(일요일)은 이미 창 경과 — PAST_WINDOW 기록 후 D+1 발송
        assert_log_shapes dispatched_logs_for(invoice),
                          [ [ "invoice_notice", "skipped", "PAST_WINDOW" ],
                            [ "confirm_d1", "sent", nil ] ]
      end
    end

    test "기본 트랙 D+1 — 열람 이력이 있으면 confirm_d1_opened로 분기한다 (REM-4·SHARE-5)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(TUESDAY_2PM) do
        record_view_event(invoice, first: true)
        assert_log_shapes dispatched_logs_for(invoice),
                          [ [ "invoice_notice", "skipped", "PAST_WINDOW" ],
                            [ "confirm_d1_opened", "sent", nil ] ]
      end
    end

    test "D+1 발송 후 분기는 고정된다 — 열림 변화로 다른 분기 템플릿이 재발송되지 않는다 (SEC-5)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(TUESDAY_2PM) do
        dispatched_logs_for(invoice)                              # 미열람 분기 발송
        record_view_event(invoice, first: true)                   # 발송 후 열람 발생
        assert_log_shapes dispatched_logs_for(invoice),           # 재스캔 — 발송 없음
                          [ [ "invoice_notice", "skipped", "PAST_WINDOW" ],
                            [ "confirm_d1", "sent", nil ] ]
      end
      assert_equal 2, MessageLog.where(invoice_id: invoice.id).count
      assert_equal 1, @fake.calls.size
    end

    test "D+7이면 requeue_d7을 발송하고 창 경과 스텝은 PAST_WINDOW로 기록한다 (REM-2·REM-3)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 3))

      travel_to(TUESDAY_2PM) do
        assert_log_shapes dispatched_logs_for(invoice),
                          [ [ "invoice_notice", "skipped", "PAST_WINDOW" ],
                            [ "confirm_d1", "skipped", "PAST_WINDOW" ],
                            [ "requeue_d7", "sent", nil ] ]       # final_d14는 미래 — 기록 없음
      end
      assert_equal 1, @fake.calls.size
      assert_equal "requeue_d7", @fake.calls.sole[:template_key]
    end

    test "소급 창 경과 스텝은 이력당 1회만 기록한다 — 재스캔 churn 0 (P4·설계 판단 3)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 3))

      travel_to(TUESDAY_2PM) do
        DispatchService.new.call
        assert_equal 2, MessageLog.where(invoice_id: invoice.id, error_code: "PAST_WINDOW").count

        DispatchService.new.call                                  # 재스캔(장애 복구 후 상정)
        assert_equal 2, MessageLog.where(invoice_id: invoice.id, error_code: "PAST_WINDOW").count
      end
    end

    test "주말 nominal 스텝은 소급 창에서 월요일로 자연 이연된다 (REM-3 — 금 만기 → 월 발송)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 6))      # 금요일 만기

      travel_to(Time.zone.parse("2026-11-09 09:00")) do                     # 같은 날 아침 산정
        assert_equal [ "confirm_d1" ], DispatchService.new.steps_due_today(invoice)
      end

      travel_to(MONDAY_2PM) do
        # D+1 nominal이 일요일(11-08) — 창 종료가 월요일(11-09)이므로 월요일에 발송된다.
        # invoice_notice nominal(11-05 목)의 창은 금요일에 닫혔다 — PAST_WINDOW.
        assert_log_shapes dispatched_logs_for(invoice),
                          [ [ "invoice_notice", "skipped", "PAST_WINDOW" ],
                            [ "confirm_d1", "sent", nil ] ]
      end
    end

    test "D+14 최종 안내 발송 성공 시 시퀀스가 종결된다 (REM-12)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 10, 27))

      travel_to(TUESDAY_2PM) do
        assert_log_shapes dispatched_logs_for(invoice),
                          [ [ "invoice_notice", "skipped", "PAST_WINDOW" ],
                            [ "confirm_d1", "skipped", "PAST_WINDOW" ],
                            [ "requeue_d7", "skipped", "PAST_WINDOW" ],
                            [ "final_d14", "sent", nil ] ]
      end
      assert invoice.reload.sequence_finished?
    end

    test "약속 트랙 — 약속 전날이면 promise_d1만 발송하고 기본 트랙은 대체된다 (PROMISE-3)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 11))

      travel_to(TUESDAY_2PM) do
        create_promise(invoice, kind: :date_selected, promised_on: Date.new(2026, 11, 11))
        assert_log_shapes dispatched_logs_for(invoice),
                          [ [ "promise_d1", "sent", nil ] ]           # invoice_notice 미발송
      end
    end

    test "약속 도과 재요청 발송 성공 시 종결과 U1 통보가 동반된다 (REM-13·NOTI-1)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      # 약속은 과거에 정상 접수됐다가 도과한 시나리오 — 접수일(월)에 today 약속을 만든다.
      travel_to(MONDAY_2PM) do
        create_promise(invoice, kind: :date_selected, promised_on: Date.new(2026, 11, 9))
      end

      travel_to(TUESDAY_2PM) do
        assert_log_shapes dispatched_logs_for(invoice),
                          [ [ "promise_d1", "skipped", "PAST_WINDOW" ],
                            [ "promise_overdue", "sent", nil ] ]
      end
      assert invoice.reload.sequence_finished?
      u1_log = MessageLog.where(invoice_id: invoice.id, recipient_role: :user).sole
      assert_equal "noti_promise_unkept", u1_log.template_key
      assert_predicate u1_log, :sent?
    end

    test "재약속하면 최신 약속 기준으로 무상태 재계산되고 발송済 스텝은 재발송되지 않는다 (PROMISE-3)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(MONDAY_2PM) do
        create_promise(invoice, kind: :date_selected, promised_on: Date.new(2026, 11, 11))
      end

      travel_to(TUESDAY_2PM) do
        assert_log_shapes dispatched_logs_for(invoice),
                          [ [ "promise_d1", "sent", nil ] ]       # 약속 전날 안내(당일 nominal)

        # 약속일 재지정(재스케줄) — 최신 약속 기준으로 스텝 맵이 재계산된다:
        # promise_d1 nominal(11-19)·promise_overdue nominal(11-21)은 미래이고, promise_d1은
        # 동일 스텝 1회 멱등(설계 판단 11)이라 재발송되지 않는다.
        create_promise(invoice, kind: :date_selected, promised_on: Date.new(2026, 11, 20))
        assert_log_shapes dispatched_logs_for(invoice),
                          [ [ "promise_d1", "sent", nil ] ]
      end
      assert_equal 1, MessageLog.where(invoice_id: invoice.id).count
      assert_equal 1, @fake.calls.size
    end

    test "부분입금 청구는 시퀀스 스텝만 발송한다 — partial_paid는 스캔 스텝에 없다 (PAY-2·Q10)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9), status: :partially_paid)

      travel_to(TUESDAY_2PM) do
        invoice.payments.create!(amount: 10_000, paid_on: Date.current)
        assert_log_shapes dispatched_logs_for(invoice),
                          [ [ "invoice_notice", "skipped", "PAST_WINDOW" ],
                            [ "confirm_d1", "sent", nil ] ]
      end
      assert_not_includes @fake.calls.map { |call| call[:template_key] }, "partial_paid"
    end

    test "Free 자격 없는 청구의 자동 스텝은 INELIGIBLE_PLAN skip으로 기록된다 (REM-8)" do
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(TUESDAY_2PM) do
        assert_log_shapes dispatched_logs_for(invoice),
                          [ [ "invoice_notice", "skipped", "PAST_WINDOW" ],
                            [ "confirm_d1", "skipped", "INELIGIBLE_PLAN" ] ]
      end
      assert_empty @fake.calls
    end

    # ── 공개 산정 진입점(C-2·C-3·W-1 — 발송 스캔과 동일 논리) ──

    test "steps_due_today는 연체·도과 단계만 산정한다 — invoice_notice·promise_d1은 제외 (REM-11·C-2)" do
      pending_notice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                               due_on: Date.new(2026, 11, 10))
      overdue = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      promise_tomorrow = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                                 due_on: Date.new(2026, 11, 9))
      promise_overdue = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                                due_on: Date.new(2026, 11, 9))

      # 도과 시나리오의 약속은 접수일 기준으로 만든다(date_selected는 과거일을 거부한다 — 결정 #3)
      travel_to(MONDAY_2PM) do
        create_promise(promise_overdue, kind: :date_selected, promised_on: Date.new(2026, 11, 9))
      end

      travel_to(TUESDAY_2PM) do
        scanner = DispatchService.new
        create_promise(promise_tomorrow, kind: :date_selected, promised_on: Date.new(2026, 11, 11))

        assert_empty scanner.steps_due_today(pending_notice)   # invoice_notice — 사전통보 밖
        assert_equal [ "confirm_d1" ], scanner.steps_due_today(overdue)
        assert_empty scanner.steps_due_today(promise_tomorrow) # promise_d1 — 사전통보 밖
        assert_equal [ "promise_overdue" ], scanner.steps_due_today(promise_overdue)
      end
    end

    test "steps_due_today는 이미 발송된 단계를 제외한다 (C-2 — 통보·발송 동일 모집단)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(TUESDAY_2PM) do
        scanner = DispatchService.new
        assert_equal [ "confirm_d1" ], scanner.steps_due_today(invoice)

        MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "confirm_d1",
                           recipient_role: :debtor, status: :sent, origin: :manual)
        assert_empty scanner.steps_due_today(invoice)          # 수동 sent분도 제외(origin 무관)
      end
    end

    test "restartable?는 종결 후 창 내 미발송 스텝 존재로 판정하고 재개 스캔이 이어 발송한다 (C-3·REM-12)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 10, 27))   # final_d14 nominal 당일
      invoice.update_column(:sequence_finished_at, Time.zone.parse("2026-11-09 14:00"))

      travel_to(TUESDAY_2PM) do
        scanner = DispatchService.new
        assert_equal true, scanner.restartable?(invoice)                  # 창 내 미발송 final_d14

        assert invoice.restart_sequence!                                  # U1 수동 재개(REM-12)
        assert_log_shapes dispatched_logs_for(invoice),
                          [ [ "invoice_notice", "skipped", "PAST_WINDOW" ],
                            [ "confirm_d1", "skipped", "PAST_WINDOW" ],
                            [ "requeue_d7", "skipped", "PAST_WINDOW" ],
                            [ "final_d14", "sent", nil ] ]
      end
      assert invoice.reload.sequence_finished?                            # 재발송 성공 → 재종결
    end

    test "남은 미발송 스텝이 없는 종결 청구는 재개 불가다 (C-3 — 마킹 유지)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 10, 27))
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "final_d14",
                         recipient_role: :debtor, status: :sent)
      invoice.update_column(:sequence_finished_at, Time.zone.parse("2026-11-09 14:00"))

      travel_to(TUESDAY_2PM) do
        # 재개 요청 판정이 false이므로(컨트롤러 restart_reminders 경로) restart_sequence!는
        # 호출되지 않는다 — 여기서는 판정과 마킹 유지만 검증한다.
        assert_equal false, DispatchService.new.restartable?(invoice)
        assert_predicate invoice.reload, :sequence_finished?
      end
    end

    test "manual_step_key는 시점 버킷·약속 트랙·열람 분기·nil 창의 단일 출처다 (W-1·REM-8·C-2)" do
      # 기준일 11-10 — "(내일)" 문구 템플릿은 전날(D-1)에만 선택하고, 그 외 만기 전 구간은
      # SHARE-6 발행 안내(issue_notice — 어느 날 보내도 내용이 참, due >= today 한정)로 대체한다.
      # 약속 트랙에서 만기 도과 + 약속 전날 이전(당일 포함) 창은 참인 템플릿이 없어 nil이다(C-2).
      far_future = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                           due_on: Date.new(2026, 11, 27))    # 만기 17일 전
      day_before = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                           due_on: Date.new(2026, 11, 11))    # 만기 전날(D-1)
      due_today = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                          due_on: Date.new(2026, 11, 10))     # 만기 당일
      opened = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                       due_on: Date.new(2026, 11, 9))
      mid = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                    due_on: Date.new(2026, 11, 3))        # D+7~D+13 구간
      late = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                     due_on: Date.new(2026, 10, 20))      # D+14 이후 구간
      promised = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                         due_on: Date.new(2026, 11, 9))
      promise_tomorrow = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                                 due_on: Date.new(2026, 11, 20))
      promise_far = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                            due_on: Date.new(2026, 11, 20))
      promise_past = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                             due_on: Date.new(2026, 11, 9))
      promise_gap = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                            due_on: Date.new(2026, 11, 9))   # 만기 도과 + 미래 약속
      promise_due_day = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                                due_on: Date.new(2026, 11, 9)) # 약속 당일 + 만기 도과

      travel_to(TUESDAY_2PM) do
        scanner = DispatchService.new
        create_promise(promised, kind: :date_selected, promised_on: Date.new(2026, 11, 11))
        create_promise(promise_tomorrow, kind: :date_selected, promised_on: Date.new(2026, 11, 11))
        create_promise(promise_far, kind: :date_selected, promised_on: Date.new(2026, 11, 20))
        create_promise(promise_gap, kind: :date_selected, promised_on: Date.new(2026, 11, 20))
        # 과거·당일 시나리오 — Promise 검증(약속일은 오늘 이후) 우회를 위해 생성 후 직접 마킹한다
        past_promise = create_promise(promise_past, kind: :date_selected,
                                      promised_on: Date.new(2026, 11, 11))
        past_promise.update_column(:promised_on, Date.new(2026, 11, 8))
        due_day_promise = create_promise(promise_due_day, kind: :date_selected,
                                         promised_on: Date.new(2026, 11, 11))
        due_day_promise.update_column(:promised_on, Date.new(2026, 11, 10))

        assert_equal "issue_notice", scanner.manual_step_key(far_future)  # 만기 17일 전 — 발행 안내
        assert_equal "invoice_notice", scanner.manual_step_key(day_before) # 만기 전날 — "(내일)" 정확
        assert_equal "issue_notice", scanner.manual_step_key(due_today)   # 만기 당일 — 예정 안내
        record_view_event(opened, first: true)
        assert_equal "confirm_d1_opened", scanner.manual_step_key(opened)
        assert_equal "requeue_d7", scanner.manual_step_key(mid)
        assert_equal "final_d14", scanner.manual_step_key(late)
        assert_equal "promise_d1", scanner.manual_step_key(promised)      # 약속일 전날
        assert_equal "promise_d1", scanner.manual_step_key(promise_tomorrow)
        assert_equal "issue_notice", scanner.manual_step_key(promise_far) # 약속일 10일 전 + 만기 전
        assert_equal "promise_overdue", scanner.manual_step_key(promise_past) # 약속일 도과
        assert_nil scanner.manual_step_key(promise_gap)   # 만기 도과 + 미래 약속 — 참인 템플릿 없음
        assert_nil scanner.manual_step_key(promise_due_day) # 약속 당일 + 만기 도과 — 동일 창(C-2)
      end
    end
  end
end
