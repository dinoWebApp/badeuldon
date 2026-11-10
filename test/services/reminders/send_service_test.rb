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
        assert_equal 5, MessageLog.sequence_sent_count(invoice.id)
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
        assert_equal 5, MessageLog.sequence_sent_count(capped.id)
      end
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
      assert_equal 5, MessageLog.sequence_sent_count(invoice.id)   # paid_thanks 미가산
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
      assert_equal 2, MessageLog.sequence_sent_count(invoice.id)     # 상한은 auto+manual 합산
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
