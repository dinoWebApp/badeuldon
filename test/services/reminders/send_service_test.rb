require "test_helper"
require_relative "../../test_helpers/fake_solapi_client"
require_relative "../../test_helpers/reminder_factories"
require_relative "../../test_helpers/solapi_stubbing"

module Reminders
  # 단일 발송 실행기(F-REM) — 가드 매트릭스 7종·REM-3 발송 창·멱등(SEC-5·C-1)·재예약
  # (B-2·W-4)·발송 후속 훅(REM-12/13)·실패 기록·변수 조립의 전 경로.
  # 시나리오 기준: PRD §6.6 REM-3/8/12/13·§6.11 PLAN-3·SEC-5·PROMISE-3/7·PAY-2/4·VIEW-7,
  # _workspace/03_implementation.md Rule ID 매핑표·설계 판단 1~12, _workspace/05_review.md
  # §Tester 중점 1·2·6·7·9(B-1·B-2·C-1 회귀 포함).
  # 솔라피는 FakeSolapiClient를 client:로 주입한다 — 실호출 0(REM-10·AGENTS.md 테스트 전략).
  # promise_overdue 성공 훅의 U1 통보는 SendService 내부에서 NotifyUserService를 생성해
  # 생성자 주입이 닿지 않으므로(SolapiStubbing 주석 참조) with_solapi_client 방어선을 함께 쓴다.
  # 시간은 travel_to로 평일 창(2026-11-10 화)·주말(11-14 토)을 KST 고정한다(TIME-1).
  class SendServiceTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    include ReminderFactories
    include SolapiStubbing

    fixtures :users, :clients, :invoices, :promises, :subscriptions, :payment_passes

    # 고정 시각 — 2026-11-10(화)은 평일 창 내 기준일, 11-14(토)·11-15(일)·11-16(월)은 창 경계 검증용
    TUESDAY_10AM = Time.zone.parse("2026-11-10 10:00")

    def setup
      @fake = FakeSolapiClient.new
    end

    def send_debtor(invoice, template_key, origin: :auto, client: @fake)
      SendService.new(invoice: invoice, template_key: template_key,
                      recipient_role: :debtor, origin: origin, client: client).call
    end

    def send_user(invoice, template_key, scheduled_at: nil, client: @fake)
      SendService.new(invoice: invoice, template_key: template_key,
                      recipient_role: :user, scheduled_at: scheduled_at, client: client).call
    end

    def sequence_sent_log(invoice, template_key)
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: template_key,
                         recipient_role: :debtor, status: :sent)
    end

    def debtor_logs(invoice)
      MessageLog.where(invoice_id: invoice.id, recipient_role: :debtor)
    end

    # ── 정상 발송 ──

    test "창 내 평일 채무자 발송은 솔라피를 호출하고 sent 이력을 남긴다 (REM-1·REM-6·SEC-5)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(TUESDAY_10AM) do
        assert_equal :sent, send_debtor(invoice, "confirm_d1")
      end

      log = debtor_logs(invoice).sole
      assert_predicate log, :sent?
      assert_predicate log, :auto?
      assert_equal "010-3333-7777", log.phone                     # 거래처 번호 — U1 번호 비노출(P2)
      assert_equal Time.zone.parse("2026-11-10 10:00"), log.sent_at
      assert_equal "msg_fake_1", log.provider_message_id          # 응답 식별자 기록(REM-6)

      call = @fake.calls.sole
      assert_equal "confirm_d1", call[:template_key]
      assert_equal "010-3333-7777", call[:to]
      assert_equal "테스트발행자", call[:variables]["발행인명"]     # 표시명만(P2·REM-1)
      assert_equal "델타파트너스", call[:variables]["거래처명"]
      assert_equal "110,000", call[:variables]["금액"]             # 100,000+10% 별도
      assert_equal "110,000", call[:variables]["잔액"]
      assert_equal "11월 9일(월)", call[:variables]["만기일"]       # KST 한국어 포맷(TIME-1)
    end

    # ── REM-3 발송 창(평일 09~18 KST — 해제 불가) ──

    test "창 시작 09:00은 발송하고 08:59는 당일 09시로 재예약한다 (REM-3 경계)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-10 08:59")) do
        assert_equal :rescheduled, send_debtor(invoice, "confirm_d1")
        assert_equal Time.zone.local(2026, 11, 10, 9, 0),
                     debtor_logs(invoice).sole.reload.scheduled_at
      end

      travel_to(Time.zone.parse("2026-11-10 09:00")) do
        assert_equal :sent, send_debtor(invoice, "confirm_d1")
      end
    end

    # C-1(마감 리뷰 2026-11-26) — 창 시작 직전 1분 이내 접수분. 예약 슬롯은 접수 시각에
    # 생성되므로(updated_at < scheduled_at) 그 1분을 "다른 실행 진행 중"의 근거로 삼으면
    # 다음 실행이 :duplicate로 흡수되고 슬롯이 영구 pending으로 남는다. 예약 슬롯은 실행
    # 시작 표시(mark_execution_started!의 touch)가 있을 때만 진행 중으로 본다.
    test "창 시작 직전 1분 이내 접수분의 예약 슬롯은 다음 실행에서 발송된다 (REM-3 재예약분·C-1)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-10 08:59:30")) do            # 창 시작 30초 전 접수
        assert_equal :rescheduled, send_debtor(invoice, "confirm_d1", origin: :manual)
        slot = debtor_logs(invoice).pending.sole
        assert_equal Time.zone.local(2026, 11, 10, 9, 0), slot.scheduled_at
        assert slot.updated_at < slot.scheduled_at                    # 접수 시각 생성 — 표시 전
      end

      travel_to(Time.zone.parse("2026-11-10 09:00:02")) do            # 창 시작 직후 실행
        with_solapi_client(@fake) do
          assert_equal :sent,
                       Reminders::DeliverJob.new.perform(invoice.id, "confirm_d1", "debtor", "manual")
        end
      end
      assert_equal 1, debtor_logs(invoice).where(status: :sent).count
      assert_empty debtor_logs(invoice).pending                       # 유령 슬롯 없음
      assert_equal 1, @fake.calls.size
    end

    test "창 시작 직전 접수분의 자동 실행(DeliverJob 재시도)도 예약 슬롯을 발송한다 (REM-3·C-1)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-10 08:59:45")) do
        assert_equal :rescheduled, send_debtor(invoice, "requeue_d7")
      end

      travel_to(Time.zone.parse("2026-11-10 09:00:10")) do
        with_solapi_client(@fake) do
          assert_equal :sent,
                       Reminders::DeliverJob.new.perform(invoice.id, "requeue_d7", "debtor", "auto")
        end
      end
      assert_equal 1, debtor_logs(invoice).where(status: :sent).count
      assert_empty debtor_logs(invoice).pending
      assert_equal 1, @fake.calls.size
    end

    # 동시 실행 회귀(SEC-5) — 실행 시작 표시 뒤에는 예약 슬롯의 1분 창이 다시 유효해진다.
    # 첫 실행이 발송을 마친 뒤 30초 안의 중복 실행은 sent 판정으로, 첫 실행이 claim 뒤 발송
    # 중인 상태(표시만 있고 미발송)의 병렬 실행은 진행 중 판정으로 각각 흡수된다.
    test "예약 슬롯 실행 뒤 30초 안의 중복 실행은 duplicate로 흡수되고 stub 호출은 1회다 (SEC-5·C-1)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-10 08:59:30")) do
        assert_equal :rescheduled, send_debtor(invoice, "confirm_d1")
      end

      travel_to(Time.zone.parse("2026-11-10 09:00:02")) do            # 첫 실행 — 발송
        with_solapi_client(@fake) do
          assert_equal :sent,
                       Reminders::DeliverJob.new.perform(invoice.id, "confirm_d1", "debtor", "auto")
        end
      end

      travel_to(Time.zone.parse("2026-11-10 09:00:32")) do            # 30초 뒤 중복 실행
        assert_equal :duplicate,
                     Reminders::DeliverJob.new.perform(invoice.id, "confirm_d1", "debtor", "auto")
      end
      assert_equal 1, debtor_logs(invoice).where(status: :sent).count
      assert_equal 1, @fake.calls.size
    end

    test "실행 시작 표시만 있고 미발송인 예약 슬롯의 병렬 실행은 duplicate로 흡수된다 (SEC-5·C-1)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-10 08:59:30")) do
        assert_equal :rescheduled, send_debtor(invoice, "confirm_d1", origin: :manual)
      end

      travel_to(Time.zone.parse("2026-11-10 09:00:05")) do
        debtor_logs(invoice).pending.sole.touch                       # 첫 실행의 claim 표시 시뮬레이션
        assert_equal :duplicate, send_debtor(invoice, "confirm_d1", origin: :manual)
      end
      assert_empty @fake.calls
      assert_predicate debtor_logs(invoice).pending.sole.reload, :pending?
    end

    # 실행 시작 표시(touch)의 시간 경계 — 첫 실행이 발송을 마친 뒤 같은 예약 슬롯에 대한
    # 재실행은 origin이 갈린다. 자동은 step_sent?로 duplicate(이미 sent인 자동 단계는
    # 재발송하지 않는다 — W-1과 같은 방향), 수동은 멱등 판정 밖이라 새 이력으로 재발송된다(REM-8).
    test "예약 슬롯 발송 뒤의 재실행은 자동은 duplicate로 흡수하고 수동은 재발송을 누적한다 (SEC-5·REM-8)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-10 08:59:30")) do
        assert_equal :rescheduled, send_debtor(invoice, "confirm_d1")
      end

      travel_to(Time.zone.parse("2026-11-10 09:00:02")) do            # 첫 실행 — 예약 슬롯 발송
        with_solapi_client(@fake) do
          assert_equal :sent,
                       Reminders::DeliverJob.new.perform(invoice.id, "confirm_d1", "debtor", "auto")
        end
        # 자동 재실행 — sent 판정으로 흡수되고 stub 호출에 변화가 없다.
        assert_equal :duplicate,
                     Reminders::DeliverJob.new.perform(invoice.id, "confirm_d1", "debtor", "auto")
        assert_equal 1, @fake.calls.size
      end

      travel_to(Time.zone.parse("2026-11-10 09:05")) do               # 수동 재실행 — 재발송 허용(REM-8)
        assert_equal :sent, send_debtor(invoice, "confirm_d1", origin: :manual)
      end
      assert_equal 2, debtor_logs(invoice).where(status: :sent).count # 예약분 1 + 수동 재발송 1
      assert_empty debtor_logs(invoice).pending
      assert_equal 2, @fake.calls.size
    end

    # W-1(마감 리뷰 2026-11-26) — 창 판정이 멱등 판정보다 앞이면, 스캔 시각이 회원 허용
    # 시간 밖일 때(REM-3 세부 설정으로 종료 시각을 당긴 회원) 이미 sent인 자동 단계에도
    # 예약 슬롯이 생기고, 다음 날 실행은 step_sent?로 duplicate가 되어 슬롯이 영구 pending으로
    # 남았다(유령 「예정」 행). 이미 발송된 자동 단계는 재예약하지 않는다.
    test "이미 sent인 자동 단계는 스캔이 허용 창 밖이어도 재예약하지 않는다 (REM-3·W-1)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      sequence_sent_log(invoice, "confirm_d1")
      users(:delta).update_column(:remind_end_hour, 13)               # 허용 종료 13시로 축소(REM-3 세부 설정)

      travel_to(Time.zone.parse("2026-11-10 14:00")) do               # 허용 창 밖 스캔
        assert_equal :duplicate, send_debtor(invoice, "confirm_d1")
      end
      assert_empty debtor_logs(invoice).pending                       # 유령 「예정」 행 없음
      assert_equal 1, debtor_logs(invoice).count                      # sent 이력만
      assert_empty @fake.calls
    end

    test "창 종료 17:59는 발송하고 18:00은 다음 평일 09시로 재예약한다 (REM-3 경계)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-10 17:59")) do
        assert_equal :sent, send_debtor(invoice, "confirm_d1")
      end

      travel_to(Time.zone.parse("2026-11-10 18:00")) do
        assert_equal :rescheduled, send_debtor(invoice, "requeue_d7")
        assert_equal Time.zone.local(2026, 11, 11, 9, 0),
                     debtor_logs(invoice).where(template_key: "requeue_d7").sole.reload.scheduled_at
      end
    end

    test "주말 접수분은 다음 평일 09시로 재예약하고 DeliverJob에 origin을 전달한다 (REM-3·B-2)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-14 12:00")) do            # 토요일
        assert_enqueued_with job: DeliverJob,
                             args: [ invoice.id, "confirm_d1", "debtor", "manual" ] do
          assert_equal :rescheduled, send_debtor(invoice, "confirm_d1", origin: :manual)
        end

        log = debtor_logs(invoice).sole
        assert_predicate log, :pending?
        assert_predicate log, :manual?                             # 접수 시점 origin 유지(B-2)
        assert_equal Time.zone.local(2026, 11, 16, 9, 0), log.scheduled_at  # 월요일 09시
      end
    end

    test "창 밖 재예약은 pending 이력을 선기록하고 2회 재예약은 1개로 흡수된다 (W-4)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-14 12:00")) do            # 토요일
        assert_equal :rescheduled, send_debtor(invoice, "confirm_d1")
        assert_equal 1, debtor_logs(invoice).count                 # 예약 흔적 1개(REM-6 가시성)

        assert_equal :rescheduled, send_debtor(invoice, "confirm_d1")
        assert_equal 1, debtor_logs(invoice).count                 # 유니크 인덱스 — 첫 예약 유효
      end
      assert_empty @fake.calls                                     # 재예약은 발송이 아니다
    end

    # 마지막 수정 반례(Tester 2026-11-26) — 같은 단계 수동 발송을 창 밖에서 2회 접수하면
    # 예약 슬롯은 부분 유니크 인덱스로 1개만 남지만(첫 예약 유효 — 위 W-4), DeliverJob은
    # reschedule! 호출 수만큼(2회) 큐에 쌓인다. 다음 날 잡이 연속 실행되면 ① 1회차가 슬롯을
    # claim해 발송(sent로 갱신)하고 ② 2회차는 남은 pending 슬롯이 없어 new_log!가 새 이력을
    # 만들어 한 번 더 발송한다(수동 재발송 허용 — REM-8·멱등 판정 밖).
    # 현재 동작 기록: 회원에게는 "다음 평일 오전 9시에 발송됩니다" 안내가 2회 보이고,
    # 실제로도 다음 날 같은 안내가 2통 발송된다 — 안내와 결과가 수렴한다.
    test "같은 단계 수동 발송 2회 재예약의 잡 2회 연속 실행은 슬롯 발송 + 새 이력 재발송으로 수렴한다 (REM-3·REM-8 — 현재 동작 기록)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-10 20:00")) do               # 창 밖 — 같은 단계 2회 접수
        assert_equal :rescheduled, send_debtor(invoice, "confirm_d1", origin: :manual)
        assert_equal :rescheduled, send_debtor(invoice, "confirm_d1", origin: :manual)
        assert_equal 1, debtor_logs(invoice).count                    # 슬롯은 1개(유니크 인덱스)
        assert_enqueued_jobs 2, only: Reminders::DeliverJob           # 잡은 접수 수만큼 쌓인다
      end

      travel_to(Time.zone.parse("2026-11-11 09:00")) do               # 다음 날 — 잡 2회 연속 실행
        with_solapi_client(@fake) do
          assert_equal :sent,
                       Reminders::DeliverJob.new.perform(invoice.id, "confirm_d1", "debtor", "manual")
          assert_equal :sent,
                       Reminders::DeliverJob.new.perform(invoice.id, "confirm_d1", "debtor", "manual")
        end
      end
      assert_equal 2, debtor_logs(invoice).where(status: :sent).count # 슬롯 1 + 재발송 신규 이력 1
      assert_empty debtor_logs(invoice).pending                       # 유령 슬롯 없음
      assert_equal 2, @fake.calls.size                                # 실제 발송도 2통
    end

    test "U1 향은 창 밖(일요일)에도 즉시 발송한다 (REM-3 — 채무자 향만 적용)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-15 20:00")) do            # 일요일 밤
        assert_equal :sent, send_user(invoice, "noti_opened")
      end
      assert_predicate debtor_logs(invoice).none?, :present?       # 채무자 이력 없음
      log = MessageLog.where(invoice_id: invoice.id, recipient_role: :user).sole
      assert_predicate log, :sent?
    end

    test "Free 플랜의 수동 창 밖 재예약은 origin=manual pending으로 기록된다 (B-2 회귀)" do
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-14 20:00")) do            # 토요일 밤
        assert_equal :rescheduled, send_debtor(invoice, "confirm_d1", origin: :manual)

        log = debtor_logs(invoice).sole
        assert_predicate log, :manual?
        assert_predicate log, :pending?
        assert_equal Time.zone.local(2026, 11, 16, 9, 0), log.scheduled_at
      end
    end

    # ── 가드 매트릭스(스킵 사유의 단일 출처) ──

    test "수신거부 거래처의 채무자 발송은 1회성도 REFUSED로 차단한다 (VIEW-7)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9), status: :paid)
      invoice.client.update_column(:refused_at, Time.current)

      travel_to(TUESDAY_10AM) do
        assert_equal :skipped, send_debtor(invoice, "confirm_d1")
        assert_equal :skipped, send_debtor(invoice, "paid_thanks") # 1회성에도 유지(전 발송 차단)
      end
      assert debtor_logs(invoice).all? { |log| log.error_code == "REFUSED" }
      assert_empty @fake.calls
    end

    test "청구·거래처 보류는 채무자 발송에 SUSPENDED로 차단한다 (REM-7·1회성 유지)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      invoice.update_column(:reminders_suspended_at, Time.current)

      travel_to(TUESDAY_10AM) do
        assert_equal :skipped, send_debtor(invoice, "confirm_d1")
        assert_equal :skipped, send_debtor(invoice, "partial_paid") # 1회성에도 유지
      end

      invoice.update_column(:reminders_suspended_at, nil)
      invoice.client.update_column(:reminders_suspended_at, Time.current)
      travel_to(TUESDAY_10AM) do
        assert_equal :skipped, send_debtor(invoice, "confirm_d1")
      end
      assert debtor_logs(invoice).all? { |log| log.error_code == "SUSPENDED" }
      assert_empty @fake.calls
    end

    test "종결 가드는 시퀀스성에만 적용되고 paid_thanks는 종결 상태에서도 발송된다 (B-1 회귀)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9), status: :paid)
      invoice.update_column(:sequence_finished_at, Time.current)

      travel_to(TUESDAY_10AM) do
        assert_equal :skipped, send_debtor(invoice, "confirm_d1")
        assert_equal "FINISHED", debtor_logs(invoice).sole.reload.error_code

        assert_equal :sent, send_debtor(invoice, "paid_thanks")    # 1회성 — 가드 제외(B-1)
      end
      assert_equal 1, @fake.calls.size
      assert_equal "paid_thanks", @fake.calls.last[:template_key]
    end

    test "상태 가드는 시퀀스성에만 적용되고 paid 청구의 paid_thanks는 발송된다 (B-1 회귀)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9), status: :paid)

      travel_to(TUESDAY_10AM) do
        assert_equal :skipped, send_debtor(invoice, "confirm_d1")
        assert_equal "INVALID_STATUS", debtor_logs(invoice).sole.reload.error_code

        assert_equal :sent, send_debtor(invoice, "paid_thanks")
      end
    end

    test "자격 가드는 자동 시퀀스성에만 적용된다 — Free 수동·1회성은 플랜 무관 (REM-8·B-1)" do
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.new(2026, 11, 9))
      assert_not users(:gamma).reminder_eligible?

      travel_to(TUESDAY_10AM) do
        assert_equal :skipped, send_debtor(invoice, "confirm_d1")  # auto 시퀀스성 — 차단
        assert_equal "INELIGIBLE_PLAN", debtor_logs(invoice).sole.reload.error_code

        assert_equal :sent, send_debtor(invoice, "confirm_d1", origin: :manual)  # 수동 허용
      end

      paid = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                     due_on: Date.new(2026, 11, 9), status: :paid)
      travel_to(TUESDAY_10AM) do
        assert_equal :sent, send_debtor(paid, "paid_thanks")       # 1회성 — 자격 가드 제외
      end
      assert_equal 2, @fake.calls.size
    end

    test "상한은 4통에서 5통째를 통과시키고 6통째를 CAP_REACHED로 차단한다 (PLAN-3·REM-12)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      %w[invoice_notice confirm_d1 requeue_d7 promise_d1].each do |key|
        sequence_sent_log(invoice, key)
      end

      travel_to(TUESDAY_10AM) do
        assert_equal :sent, send_debtor(invoice, "final_d14")      # 5통째 — 통과
        assert_equal 5, MessageLog.cap_sent_count(invoice.id)
      end

      # 6통째 차단 검증은 직접 기록한 5건 기준으로 한다 — 서비스 발송 final_d14는 종결 훅
      # (REM-12)이 동반되어 FINISHED 가드가 상한보다 먼저 적용되기 때문이다.
      capped = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                       due_on: Date.new(2026, 11, 9))
      %w[invoice_notice confirm_d1 requeue_d7 final_d14 promise_d1].each do |key|
        sequence_sent_log(capped, key)
      end
      travel_to(TUESDAY_10AM) do
        assert_equal :skipped, send_debtor(capped, "promise_overdue")  # 6통째 — 차단
        log = debtor_logs(capped).where(template_key: "promise_overdue").sole
        assert_equal "CAP_REACHED", log.error_code
        assert_equal 5, MessageLog.cap_sent_count(capped.id)
      end
    end

    test "수동 issue_notice 5통 뒤 자동 시퀀스 단계는 CAP_REACHED로 차단된다 (PLAN-3·Q11·Q28)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      5.times do
        MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "issue_notice",
                           recipient_role: :debtor, status: :sent, origin: :manual)
      end

      travel_to(TUESDAY_10AM) do
        # 수동 1회성(issue_notice)도 상한 산정 대상(Q11)이라 자동 단계가 이어지지 않는다(Q28).
        assert_equal :skipped, send_debtor(invoice, "confirm_d1")
      end
      log = debtor_logs(invoice).where(status: :skipped).sole
      assert_equal "CAP_REACHED", log.error_code
      assert_empty @fake.calls                                         # 차단분 — API 호출 0
    end

    test "수동 4통과 자동 시퀀스 1통의 합계 5통에서 다음 자동 단계는 차단된다 (PLAN-3·Q28)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      4.times do
        MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "issue_notice",
                           recipient_role: :debtor, status: :sent, origin: :manual)
      end

      travel_to(TUESDAY_10AM) do
        assert_equal :sent, send_debtor(invoice, "confirm_d1")         # 5통째 — 합산 통과
        assert_equal 5, MessageLog.cap_sent_count(invoice.id)

        assert_equal :skipped, send_debtor(invoice, "requeue_d7")      # 6통째 — 합산 차단
      end
      log = debtor_logs(invoice).where(template_key: "requeue_d7").sole
      assert_equal "CAP_REACHED", log.error_code
      assert_equal 1, @fake.calls.size                                 # 5통째 성공분만 호출
    end

    # ── Q28 상한 합산 경계(정상·경계·예외 — Tester 2026-11-26) ──

    test "수동 시퀀스성·수동 1회성·자동의 혼합 4통에서 자동 5통째는 통과하고 6통째는 CAP_REACHED다 (PLAN-3·Q28 경계)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      sequence_sent_log(invoice, "invoice_notice")                                  # 자동 시퀀스성 — 1
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "confirm_d1",
                         recipient_role: :debtor, status: :sent, origin: :manual)   # 수동 시퀀스성 — 2
      2.times do
        MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "issue_notice",
                           recipient_role: :debtor, status: :sent, origin: :manual) # 수동 1회성 — 3·4
      end
      assert_equal 4, MessageLog.cap_sent_count(invoice.id)                         # 3출처 혼합 합산(Q28)

      travel_to(TUESDAY_10AM) do
        assert_equal :sent, send_debtor(invoice, "requeue_d7")       # 5통째 — 혼합 4 + 자동 1 통과
        assert_equal 5, MessageLog.cap_sent_count(invoice.id)

        assert_equal :skipped, send_debtor(invoice, "final_d14")     # 6통째 — 혼합 집계로 차단
      end
      log = debtor_logs(invoice).where(template_key: "final_d14").sole
      assert_equal "CAP_REACHED", log.error_code
      assert_equal 1, @fake.calls.size                               # 5통째 성공분만 — 차단분 호출 0
    end

    test "수동 포함 5통의 약속 트랙에서 promise_overdue 자동 발송은 CAP_REACHED로 막히고 종결 마킹·U1 통보도 없다 (PLAN-3·Q28·REM-13 — 현재 동작 기록)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      # 약속은 접수일(11-09 월)에 만든다 — 약속일 다음 날(11-10)에 promise_overdue가 도래한다.
      travel_to(Time.zone.parse("2026-11-09 14:00")) do
        create_promise(invoice, kind: :date_selected, promised_on: Date.new(2026, 11, 9))
      end

      # 수동 발송 포함 5통 — 시퀀스성 auto 3통 + 수동 시퀀스성 1통 + 수동 1회성 1통(Q28 합산).
      %w[invoice_notice confirm_d1 promise_d1].each { |key| sequence_sent_log(invoice, key) }
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "requeue_d7",
                         recipient_role: :debtor, status: :sent, origin: :manual)
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "issue_notice",
                         recipient_role: :debtor, status: :sent, origin: :manual)
      assert_equal 5, MessageLog.cap_sent_count(invoice.id)

      travel_to(TUESDAY_10AM) do
        # 성공 훅(noti_promise_unkept — NotifyUserService를 내부 생성)이 실호출로 새지 않게
        # 클래스 생성 경로 방어선으로도 감싼다(가드가 깨져 sent가 나더라도 흡수).
        with_solapi_client(@fake) do
          assert_equal :skipped, send_debtor(invoice, "promise_overdue")
        end
      end

      log = debtor_logs(invoice).where(template_key: "promise_overdue").sole
      assert_equal "CAP_REACHED", log.error_code
      # 현재 동작 기록(Q28) — 상한으로 막힌 promise_overdue는 종결 마킹(REM-13)을 하지 않는다.
      assert_not invoice.reload.sequence_finished?
      # 현재 동작 기록(NOTI-1) — 약속 미이행 U1 통보는 발송 성공 훅에 묶여 있어 이 경로에서도 나가지 않는다.
      assert_empty MessageLog.where(invoice_id: invoice.id, recipient_role: :user)
      assert_empty @fake.calls                                        # 차단분 — API 호출 0
    end

    test "상한 도달(수동 합산) 청구에서도 자동 1회성 partial_paid·paid_thanks는 발송되고 상한 집계는 늘지 않는다 (PLAN-3·Q10)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "confirm_d1",
                         recipient_role: :debtor, status: :sent, origin: :manual)   # 수동 시퀀스성
      4.times do
        MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "issue_notice",
                           recipient_role: :debtor, status: :sent, origin: :manual) # 수동 1회성
      end
      assert_equal 5, MessageLog.cap_sent_count(invoice.id)                         # 수동 합산 도달

      travel_to(TUESDAY_10AM) do
        assert_equal :sent, send_debtor(invoice, "partial_paid")
        assert_equal :sent, send_debtor(invoice, "paid_thanks")
      end

      assert_equal 5, MessageLog.cap_sent_count(invoice.id)           # 1회성 2통 미가산(Q10)
      assert_equal 7, debtor_logs(invoice).where(status: :sent).count # 발송 자체는 7통
    end

    test "창 밖 수동 5번째는 다음 평일 09시로 예약되고 실행된 뒤 그날 14시 자동 단계는 CAP_REACHED다 (PLAN-3·Q28·REM-3)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(TUESDAY_10AM) do                                      # 창 내 — 수동 4통
        4.times do
          assert_equal :sent, send_debtor(invoice, "issue_notice", origin: :manual)
        end
        assert_equal 4, MessageLog.cap_sent_count(invoice.id)
        assert_equal 4, @fake.calls.size                              # 창 내 4통은 즉시 발송
      end

      # 5번째 — sent 이력이 없는 시퀀스성 템플릿(requeue_d7). 창 밖이라 즉시 발송되지 않고
      # 다음 평일 09시로 예약된다(예약 슬롯 재사용 — 아래 흡수 테스트 참고).
      travel_to(Time.zone.parse("2026-11-10 20:00")) do               # 창 밖 — 5번째 접수
        assert_equal :rescheduled, send_debtor(invoice, "requeue_d7", origin: :manual)
        scheduled = debtor_logs(invoice).where(template_key: "requeue_d7").sole
        assert_predicate scheduled, :pending?
        assert_equal Time.zone.local(2026, 11, 11, 9, 0), scheduled.scheduled_at
        assert_equal 4, @fake.calls.size                              # 예약은 발송이 아니다
      end

      travel_to(Time.zone.parse("2026-11-11 09:05")) do               # 수요일 — 예약분 실행(잡과 동일 경로)
        with_solapi_client(@fake) do
          assert_equal :sent,
                       Reminders::DeliverJob.new.perform(invoice.id, "requeue_d7", "debtor", "manual")
        end
      end
      assert_equal 5, MessageLog.cap_sent_count(invoice.id)           # 예약분이 5통째로 집계된다(Q11)
      executed = debtor_logs(invoice).where(template_key: "requeue_d7").sole
      assert_predicate executed.reload, :sent?                        # 예약 슬롯이 그대로 sent로 갱신
      assert_equal Time.zone.local(2026, 11, 11, 9, 0), executed.scheduled_at

      travel_to(Time.zone.parse("2026-11-11 14:00")) do               # 같은 날 14시 자동 스캔
        calls_before_scan = @fake.calls.size                          # 창 내 4통 + 예약분 1통
        with_solapi_client(@fake) do
          DispatchService.new.call
        end
        assert_equal calls_before_scan, @fake.calls.size              # CAP_REACHED·PAST_WINDOW는 호출 0
        log = debtor_logs(invoice).where(template_key: "confirm_d1").sole
        assert_predicate log, :skipped?
        assert_equal "CAP_REACHED", log.error_code
      end
    end

    # REM-3 재예약분 실행 정합(2026-11-26) — 창 밖 재예약의 실행은 동일 템플릿의 sent 이력이
    # 이미 있어도 예약 슬롯을 재사용해 발송한다. 과거에는 new_log!의 유니크 복구가 가장 오래된
    # 이력(.order(:id).first)을 돌려 sent 이력에 흡수되고 예약 슬롯이 영구 pending으로 남았다.
    test "창 밖 재예약분의 실행은 동일 템플릿 sent 이력이 있어도 예약 슬롯을 재사용해 발송한다 (REM-3·SEC-5)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(TUESDAY_10AM) do
        assert_equal :sent, send_debtor(invoice, "confirm_d1", origin: :manual)
      end
      travel_to(Time.zone.parse("2026-11-10 20:00")) do               # 창 밖 — 같은 단계 재요청
        assert_equal :rescheduled, send_debtor(invoice, "confirm_d1", origin: :manual)
      end

      travel_to(Time.zone.parse("2026-11-11 09:05")) do
        with_solapi_client(@fake) do
          assert_equal :sent,
                       Reminders::DeliverJob.new.perform(invoice.id, "confirm_d1", "debtor", "manual")
        end
      end
      assert_equal 2, debtor_logs(invoice).where(status: :sent).count # 창 내 1통 + 예약분 발송
      assert_empty debtor_logs(invoice).pending                       # 예약 슬롯 잔존 없음
      assert_equal 2, MessageLog.cap_sent_count(invoice.id)           # 예약분도 상한 집계(Q11)
      assert_equal 2, @fake.calls.size                                # 창 내 1통 + 예약분
    end

    # W-4(마감 리뷰 2026-11-26) — 1회성(partial_paid·Q23 이벤트성)도 창 밖 접수는 재예약되고
    # 다음 날 예약 슬롯으로 발송된다. new_log!의 유니크 복구가 슬롯을 돌려주므로 과거 sent
    # 이력에 흡수되지 않는다(재예약분 실행 정합 — 1회성 경로의 커버).
    test "창 밖 재예약된 1회성(partial_paid)은 다음 날 예약 슬롯으로 발송된다 (Q23·REM-3·W-4)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(TUESDAY_10AM) do
        MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "partial_paid",
                           recipient_role: :debtor, status: :sent)    # 과거 부분입금 안내 1통
      end
      travel_to(Time.zone.parse("2026-11-10 20:00")) do               # 추가 부분입금 — 창 밖 접수
        assert_equal :rescheduled, send_debtor(invoice, "partial_paid")
        assert_predicate debtor_logs(invoice).pending.sole, :pending?
      end

      travel_to(Time.zone.parse("2026-11-11 09:05")) do               # 다음 날 예약분 실행
        with_solapi_client(@fake) do
          assert_equal :sent,
                       Reminders::DeliverJob.new.perform(invoice.id, "partial_paid", "debtor", "auto")
        end
      end
      assert_equal 2, debtor_logs(invoice).where(status: :sent).count
      assert_empty debtor_logs(invoice).pending                       # 예약 슬롯 잔존 없음
    end

    # 마지막 수정 반례(Tester 2026-11-26) — 1회성(partial_paid·Q23 이벤트성)의 재예약분과
    # 동시(이중) 잡 실행의 결합. 이벤트성은 멱등 판정 밖이라: ① 1회차 — 유니크 위반 복구가
    # 예약 슬롯을 돌려 발송(슬롯이 sent로 갱신). ② 2회차 — 남은 슬롯이 없어 new_log!가 새
    # 이력을 만들어 한 번 더 발송한다. 현재 동작 기록: 같은 이벤트의 잡이 2회 실행되면 같은
    # 부분입금 안내가 2통 간다(건마다 새 이력 — Q23 설계·PLAN-3 상한 집계 밖 유지).
    test "창 밖 재예약된 partial_paid의 잡 2회 연속 실행은 슬롯 발송 + 새 이력 발송으로 2통이 된다 (Q23·REM-3 — 현재 동작 기록)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(TUESDAY_10AM) do
        MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "partial_paid",
                           recipient_role: :debtor, status: :sent)  # 과거 부분입금 안내 1통
      end
      travel_to(Time.zone.parse("2026-11-10 20:00")) do               # 추가 부분입금 — 창 밖 접수
        assert_equal :rescheduled, send_debtor(invoice, "partial_paid")
        assert_equal 1, debtor_logs(invoice).pending.count
      end

      travel_to(Time.zone.parse("2026-11-11 09:00")) do               # 잡 2회 연속 실행(이중 인큐 가정)
        with_solapi_client(@fake) do
          assert_equal :sent,
                       Reminders::DeliverJob.new.perform(invoice.id, "partial_paid", "debtor", "auto")
          assert_equal :sent,
                       Reminders::DeliverJob.new.perform(invoice.id, "partial_paid", "debtor", "auto")
        end
      end
      assert_equal 3, debtor_logs(invoice).where(status: :sent).count # 과거 1 + 슬롯 1 + 신규 1
      assert_empty debtor_logs(invoice).pending                       # 유령 슬롯 없음
      assert_equal 2, @fake.calls.size
    end

    # 같은 원칙의 자동 경로 — claim_log가 갱신 경로로 더 오래된 failed 이력을 돌려주는 동안
    # 예약 슬롯이 남아 있으면 슬롯이 영구 pending으로 남았다(발송은 failed 이력 갱신으로
    # 일어나지만 발송 이력의 「발송 예정」 유령 행이 되고 이후 reschedule! 예약을 흡수한다).
    # 예약 슬롯 우선으로 슬롯을 실행하고 failed 이력은 P4 기록으로 보존한다.
    test "자동 재시도는 오래된 failed 이력보다 예약 슬롯을 우선 실행하고 유령 슬롯을 남기지 않는다 (REM-3·SEC-5·P4)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      failing = FakeSolapiClient.new(
        raise_on: { "confirm_d1" => Solapi::ApiError.new(status: 400, code: "HTTP_400",
                                                         message: "템플릿 불일치") }
      )

      travel_to(TUESDAY_10AM) do                                      # 창 내 — 자동 발송 실패
        assert_equal :failed, send_debtor(invoice, "confirm_d1", client: failing)
      end
      travel_to(Time.zone.parse("2026-11-10 20:00")) do               # 창 밖 — 지연 실행분 재예약
        assert_equal :rescheduled, send_debtor(invoice, "confirm_d1")
        assert_predicate debtor_logs(invoice).pending.sole, :pending?
      end

      travel_to(Time.zone.parse("2026-11-11 09:05")) do               # 예약분 실행(자동)
        with_solapi_client(@fake) do
          assert_equal :sent,
                       Reminders::DeliverJob.new.perform(invoice.id, "confirm_d1", "debtor", "auto")
        end
      end
      sent = debtor_logs(invoice).where(status: :sent).sole
      assert_equal Time.zone.local(2026, 11, 11, 9, 0), sent.scheduled_at  # 예약 슬롯이 실행된 것
      assert_equal 1, debtor_logs(invoice).where(status: :failed).count    # failed 이력 보존(P4)
      assert_empty debtor_logs(invoice).pending                            # 유령 슬롯 없음
      assert_equal 1, @fake.calls.size
    end

    # 마지막 수정 반례(Tester 2026-11-26) — 모호 실패(재상승 → failed 이력 보존)와 창 밖
    # 재예약의 결합. 실패 뒤 같은 단계의 재시도가 창 밖(20시)에 들어와 재예약되면 다음 날
    # 예약 슬롯으로 발송되고, failed 이력은 P4 기록으로 그대로 보존된다(5차 슬롯 우선의
    # "failed + 슬롯" 경로 — 실패·성공 기록이 각각 1건씩 남는다).
    test "모호 실패 뒤 창 밖 재예약된 재시도는 다음 날 슬롯으로 발송하고 failed 이력은 보존된다 (REM-3·P4)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      failing = FakeSolapiClient.new(
        raise_on: { "confirm_d1" => Solapi::ApiError.new(status: nil, code: "TIMEOUT",
                                                         message: "read timeout") }
      )

      travel_to(TUESDAY_10AM) do                                      # 창 내 — 모호 실패
        assert_raises(Solapi::ApiError) do
          send_debtor(invoice, "confirm_d1", client: failing)
        end
      end
      assert_equal 1, debtor_logs(invoice).where(status: :failed).count
      assert_equal 1, failing.calls.size

      travel_to(Time.zone.parse("2026-11-10 20:00")) do               # 같은 단계 재시도 — 창 밖 재예약
        assert_equal :rescheduled, send_debtor(invoice, "confirm_d1")
        assert_predicate debtor_logs(invoice).pending.sole, :pending?
      end

      travel_to(Time.zone.parse("2026-11-11 09:00")) do               # 다음 날 예약분 실행
        with_solapi_client(@fake) do
          assert_equal :sent,
                       Reminders::DeliverJob.new.perform(invoice.id, "confirm_d1", "debtor", "auto")
        end
      end
      sent = debtor_logs(invoice).where(status: :sent).sole
      assert_equal Time.zone.local(2026, 11, 11, 9, 0), sent.scheduled_at  # 예약 슬롯이 실행된 것
      assert_equal 1, debtor_logs(invoice).where(status: :failed).count    # failed 이력 보존(P4)
      assert_empty debtor_logs(invoice).pending                            # 유령 슬롯 없음
      assert_equal 1, @fake.calls.size                                     # 실패 1(failing) + 성공 1(fake)
    end

    # 가드 순서 불변 — 예약 접수(창 밖)는 가드 전에 예약되지만, 예약 슬롯을 claim한 실행은
    # 여전히 가드를 통과한 뒤에 발송한다. 상한 도달 청구의 예약 실행은 슬롯을 CAP_REACHED
    # skip으로 마킹한다(슬롯이 sent가 되거나 pending에 남지 않는다 — PLAN-3·Q28).
    test "상한 도달 청구의 예약 실행은 슬롯을 CAP_REACHED skip으로 마킹하고 발송하지 않는다 (PLAN-3·Q28·REM-3)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      5.times do
        MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "issue_notice",
                           recipient_role: :debtor, status: :sent, origin: :manual)
      end

      travel_to(Time.zone.parse("2026-11-10 20:00")) do               # 창 밖 접수 — 가드 전 예약
        assert_equal :rescheduled, send_debtor(invoice, "requeue_d7", origin: :manual)
      end

      travel_to(Time.zone.parse("2026-11-11 09:05")) do               # 예약분 실행 — 가드 재평가
        with_solapi_client(@fake) do
          assert_equal :skipped,
                       Reminders::DeliverJob.new.perform(invoice.id, "requeue_d7", "debtor", "manual")
        end
      end
      log = debtor_logs(invoice).where(template_key: "requeue_d7").sole
      assert_predicate log, :skipped?
      assert_equal "CAP_REACHED", log.error_code
      assert_empty debtor_logs(invoice).pending                       # 슬롯 잔존 없음
      assert_equal 5, MessageLog.cap_sent_count(invoice.id)           # 상한 집계 불변
      assert_empty @fake.calls                                        # 발송 0
    end

    test "수동 상한은 시퀀스성·1회성 혼합 총량 5통에서 발동하고 6통째 manual 발송을 차단한다 (PLAN-3·Q11·C-1)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 27))

      travel_to(TUESDAY_10AM) do
        # 다른 템플릿 조합으로 5통 도달 — 수동은 템플릿 무관 총량 집계(Q11)다.
        %w[ issue_notice confirm_d1 requeue_d7 final_d14 promise_d1 ].each do |key|
          assert_equal :sent, send_debtor(invoice, key, origin: :manual), key
        end

        # 6통째 — 시퀀스 집계(3통)로는 미도달이어도 수동 총량 5통에 걸린다.
        assert_equal :skipped, send_debtor(invoice, "issue_notice", origin: :manual)
        log = debtor_logs(invoice).where(status: :skipped).sole
        assert_equal "CAP_REACHED", log.error_code
        assert_equal "issue_notice", log.template_key

        # 자동 경로의 1회성 3종은 여전히 무영향(Q10) — 수동 가드만의 차단이다.
        # (issue_notice 자동 재발송은 수동 sent분을 step_sent?가 흡수해 duplicate가 정상이다.)
        assert_equal :sent, send_debtor(invoice, "partial_paid", origin: :auto)
        assert_equal 5, MessageLog.where(invoice_id: invoice.id, recipient_role: :debtor,
                                         status: :sent, origin: :manual).count
      end
      assert_equal 6, @fake.calls.size                              # 차단분은 호출 0
    end

    test "상한 도달에도 1회성 발송과 수동 재발송 외 상한 집계는 영향이 없다 (PLAN-3·Q10)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9), status: :paid)
      %w[invoice_notice confirm_d1 requeue_d7 final_d14 promise_d1].each do |key|
        sequence_sent_log(invoice, key)
      end

      travel_to(TUESDAY_10AM) do
        assert_equal :sent, send_debtor(invoice, "paid_thanks")    # 1회성 — 집계 밖(Q10)
      end
      assert_equal 5, MessageLog.cap_sent_count(invoice.id)        # paid_thanks 미가산(Q10)
    end

    test "전화번호 없는 사용자의 U1 알림은 NO_PHONE으로 기록된다 (NOTI-1 — 에러 아님)" do
      invoice = create_reminder_invoice(user: users(:alpha), client: clients(:alpha_client_1),
                                        due_on: Date.new(2026, 11, 9))
      assert users(:alpha).phone.blank?

      travel_to(TUESDAY_10AM) do
        assert_equal :skipped, send_user(invoice, "noti_opened")
      end

      log = MessageLog.where(invoice_id: invoice.id, recipient_role: :user).sole
      assert_predicate log, :skipped?
      assert_equal "NO_PHONE", log.error_code
      assert_empty @fake.calls                                     # 번호가 없어 호출 자체가 없다
    end

    # ── 멱등(SEC-5·C-1·S8·S9) ──

    test "자동 동일 스텝 2회는 sent 1건으로 수렴하고 2회차는 duplicate이다 (SEC-5)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(TUESDAY_10AM) do
        assert_equal :sent, send_debtor(invoice, "confirm_d1")
        assert_equal :duplicate, send_debtor(invoice, "confirm_d1")
      end

      assert_equal 1, debtor_logs(invoice).where(status: :sent).count
      assert_equal 1, @fake.calls.size
    end

    test "수동 sent 스텝의 자동 재발송은 origin 무관 판정으로 차단된다 (C-1 회귀)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(TUESDAY_10AM) do
        assert_equal :sent, send_debtor(invoice, "confirm_d1", origin: :manual)
        assert_equal :duplicate, send_debtor(invoice, "confirm_d1")  # 자동 — 차단
      end

      assert_equal 1, debtor_logs(invoice).count                     # 신규 로그 0
      assert_equal 1, @fake.calls.size
    end

    test "수동 재발송은 멱등 판정 밖으로 이력을 누적한다 (REM-8·PLAN-3 합산)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(TUESDAY_10AM) do
        assert_equal :sent, send_debtor(invoice, "confirm_d1", origin: :manual)
        assert_equal :sent, send_debtor(invoice, "confirm_d1", origin: :manual)
      end

      logs = debtor_logs(invoice).where(status: :sent)
      assert_equal 2, logs.count                                     # 이력 누적 허용
      assert_equal 2, MessageLog.cap_sent_count(invoice.id)          # 상한은 시퀀스성 auto+manual 합산
      assert_equal 2, @fake.calls.size
    end

    test "수동 진행 중(pending) 슬롯의 자동 충돌은 duplicate로 흡수된다 (SEC-5·S8)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(TUESDAY_10AM) do
        MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "confirm_d1",
                           recipient_role: :debtor, origin: :manual, status: :pending)
        assert_equal :duplicate, send_debtor(invoice, "confirm_d1")  # 진행 중 1분 이내
      end

      assert_equal 1, debtor_logs(invoice).count
      assert_empty @fake.calls
    end

    test "U1 사전통보는 같은 예정시각 재실행을 흡수하고 다른 날은 새 이력이다 (S9)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-09 09:00")) do              # 월요일
        monday_9 = Time.zone.local(2026, 11, 9, 9, 0)
        assert_equal :sent, send_user(invoice, "noti_prenotice", scheduled_at: monday_9)
        assert_equal :duplicate, send_user(invoice, "noti_prenotice", scheduled_at: monday_9)
      end
      travel_to(Time.zone.parse("2026-11-10 09:00")) do              # 다른 날 — 반복 정상
        assert_equal :sent, send_user(invoice, "noti_prenotice",
                                      scheduled_at: Time.zone.local(2026, 11, 10, 9, 0))
      end

      assert_equal 2, MessageLog.where(invoice_id: invoice.id, recipient_role: :user).count
    end

    # 5차의 "pending 슬롯 우선"은 채무자 향 부분 유니크 인덱스(debtor×pending) 전제다 — U1
    # 예정 알림에는 인덱스가 없어 다른 예정 시각의 pending 이력이 공존할 수 있다(예: 전날
    # 실행 크래시 잔여). 오늘 실행이 그 행을 재사용하면 오늘 scheduled_at의 이력이 남지 않아
    # 잡 재시도 시 같은 알림이 재발송된다(SEC-5·P4) — 슬롯 우선을 채무자 향으로 한정(6차,
    # 2026-11-26). 같은 예정 시각의 sent 이력 흡수는 위 S9 테스트가 커버한다.
    test "U1 예정 알림은 다른 예정시각의 stale pending이 있어도 자기 예정시각의 새 이력으로 발송한다 (SEC-5·S9)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-11-09 09:00")) do              # 전날 실행 크래시 잔여(가정)
        MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "noti_prenotice",
                           recipient_role: :user, status: :pending,
                           scheduled_at: Time.zone.local(2026, 11, 9, 9, 0))
      end

      travel_to(Time.zone.parse("2026-11-10 09:00")) do              # 오늘 실행 — 다른 예정 시각
        assert_equal :sent, send_user(invoice, "noti_prenotice",
                                      scheduled_at: Time.zone.local(2026, 11, 10, 9, 0))
      end

      logs = MessageLog.where(invoice_id: invoice.id, recipient_role: :user,
                              template_key: "noti_prenotice").order(:id)
      assert_equal 2, logs.count                                     # stale 행 재사용 아님 — 새 이력
      sent = logs.last
      assert_predicate sent, :sent?
      assert_equal Time.zone.local(2026, 11, 10, 9, 0), sent.scheduled_at
      assert_predicate logs.first.reload, :pending?                  # stale 이력은 기록으로 보존(P4)
    end

    test "U1 이벤트 알림(scheduled_at 없음)은 이벤트마다 새 이력이다 (설계 판단 2)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(TUESDAY_10AM) do
        assert_equal :sent, send_user(invoice, "noti_promise")
        assert_equal :sent, send_user(invoice, "noti_promise")
      end

      assert_equal 2, MessageLog.where(invoice_id: invoice.id, recipient_role: :user,
                                       template_key: "noti_promise").count
    end

    # ── 발송 후속 훅(REM-12·13 — 발송 성공 시점에만 종결) ──

    test "auto final_d14 성공 시에만 시퀀스가 종결된다 (REM-12)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 10, 27))

      travel_to(TUESDAY_10AM) do
        assert_equal :sent, send_debtor(invoice, "final_d14")
      end
      assert invoice.reload.sequence_finished?

      other = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 10, 27))
      travel_to(TUESDAY_10AM) do
        assert_equal :sent, send_debtor(other, "final_d14", origin: :manual)
      end
      assert_not other.reload.sequence_finished?                     # 수동은 훅 대상 아님
    end

    test "auto promise_overdue 성공은 종결과 약속 미이행 U1 통보를 동반한다 (REM-13·NOTI-1)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      # 성공 훅의 U1 통보는 서비스 내부에서 NotifyUserService를 생성해 client: 주입이 닿지
      # 않으므로(W-7 잔여 gap — 보고서 참조) 클래스 생성 경로 방어선으로 가로챈다.
      travel_to(TUESDAY_10AM) do
        with_solapi_client(@fake) do
          assert_equal :sent, send_debtor(invoice, "promise_overdue")
        end
      end

      assert invoice.reload.sequence_finished?
      u1_log = MessageLog.where(invoice_id: invoice.id, recipient_role: :user).sole
      assert_equal "noti_promise_unkept", u1_log.template_key
      assert_predicate u1_log, :sent?
    end

    # ── 실패 기록(P4 — 모든 시도는 기록) ──

    test "확정 실패(HTTP_400)는 failed 기록 후 종료하고 재상승하지 않는다 (REM-6·잡 불변식)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      failing = FakeSolapiClient.new(
        raise_on: { "confirm_d1" => Solapi::ApiError.new(status: 400, code: "HTTP_400",
                                                         message: "템플릿 불일치") }
      )

      travel_to(TUESDAY_10AM) do
        assert_equal :failed, send_debtor(invoice, "confirm_d1", client: failing)
      end

      log = debtor_logs(invoice).sole
      assert_predicate log, :failed?
      assert_equal "HTTP_400", log.error_code
      assert_predicate log.reload, :failed?                          # 재상승 없음 — 반환으로 종료
    end

    test "모호 실패(TIMEOUT)는 failed 기록 후 재상승해 잡 재시도로 넘긴다 (§11.2)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      failing = FakeSolapiClient.new(
        raise_on: { "confirm_d1" => Solapi::ApiError.new(status: nil, code: "TIMEOUT",
                                                         message: "read timeout") }
      )

      travel_to(TUESDAY_10AM) do
        error = assert_raises(Solapi::ApiError) do
          send_debtor(invoice, "confirm_d1", client: failing)
        end
        assert_predicate error, :retryable?
      end

      log = debtor_logs(invoice).sole
      assert_predicate log, :failed?
      assert_equal "TIMEOUT", log.error_code
    end

    test "failed 슬롯의 자동 재시도는 origin을 실행 주체로 덮어쓴다 (W-6 회귀)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      failing = FakeSolapiClient.new(
        raise_on: { "confirm_d1" => Solapi::ApiError.new(status: 400, code: "HTTP_400",
                                                         message: "템플릿 불일치") }
      )

      travel_to(Time.zone.parse("2026-11-10 10:00")) do
        assert_equal :failed, send_debtor(invoice, "confirm_d1", origin: :manual, client: failing)
      end

      travel_to(Time.zone.parse("2026-11-10 10:05")) do              # 진행 중 창 경과 후 자동 재시도
        assert_equal :sent, send_debtor(invoice, "confirm_d1")
      end

      log = debtor_logs(invoice).sole
      assert_predicate log.reload, :sent?
      assert_predicate log, :auto?                                   # 「직접 발송」 왜곡 해소(W-6)
      assert_equal 1, @fake.calls.size                               # 자동 재시도 1회(실패분은 failing)
    end

    # ── 변수 조립(REM-4·PAY-2·PROMISE-4) ──

    test "부분입금 안내는 잔액·입금금액 변수를 조립한다 (REM-4·PAY-2)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(TUESDAY_10AM) do
        invoice.payments.create!(amount: 40_000, paid_on: Date.current)
        assert_equal :sent, send_debtor(invoice, "partial_paid")
      end

      variables = @fake.calls.sole[:variables]
      assert_equal "40,000", variables["입금금액"]
      assert_equal "70,000", variables["잔액"]
    end

    test "noti_promise의 this_week 약속은 이번 주 내로 치환하고 약속 트랙은 실제 날짜다 (PROMISE-4)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))

      travel_to(TUESDAY_10AM) do                                     # 화요일 접수 → 금요일 산정
        create_promise(invoice, kind: :this_week)
        send_user(invoice, "noti_promise")
        send_debtor(invoice, "promise_d1")
      end

      assert_equal "이번 주 내", @fake.calls.first[:variables]["약속일"]   # U1 향 치환
      assert_equal "11월 13일(금)", @fake.calls.last[:variables]["약속일"] # 채무자 향 실제 날짜
    end

    # ── I18n 무영향 스냅샷(REM-2·T2 회귀 방어 — 05_review Tester 제안 4) ──
    # 변수 조립(build_variables·format_date)은 수동 포맷이라 I18n locale 의존이 없다 —
    # locale 전환(ko→en)과 무관히 동일 포맷이 유지됨을 스냅샷으로 고정해 솔라피 템플릿
    # 치환(REG-2 검수본)을 보호한다. available_locales에 :en이 있어 회귀 여지가 실재한다.
    test "변수 조립은 I18n locale 전환과 무관히 동일 포맷을 유지한다 (REM-2·TIME-1)" do
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.new(2026, 11, 9))
      service = SendService.new(invoice: invoice, template_key: "confirm_d1",
                                recipient_role: :debtor, client: @fake)

      travel_to(TUESDAY_10AM) do
        ko_variables = service.send(:build_variables)
        assert_equal "11월 9일(월)", ko_variables["만기일"]
        assert_equal "110,000", ko_variables["금액"]

        I18n.with_locale(:en) do
          assert_equal ko_variables, service.send(:build_variables)  # 스냅샷 — 무변동
        end
      end
    end
  end
end
