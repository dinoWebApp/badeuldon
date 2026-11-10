require "test_helper"
require_relative "../../test_helpers/fake_solapi_client"
require_relative "../../test_helpers/reminder_factories"
require_relative "../../test_helpers/solapi_stubbing"

# 청구서 화면 F-REM 액션 통합 테스트(REM-6/7/8·REM-12/13·SHARE-6) — 보류/재개·수동 발송
# (REM-8 — 가드 저지 flash·Free 성공)·시퀀스 수동 재개(C-3)·발행 안내 선택(SHARE-6)·
# 미수 스코프 404 수렴·소유권 격리. 시나리오 기준: _workspace/03_implementation.md 3-b
# Rule ID 매핑, _workspace/05_review.md §Tester 중점 1·2·5·8.
# 수동 발송은 컨트롤러가 SendService를 생성하므로 with_solapi_client 방어선으로 가로챈다
# (실호출 0 — REM-10). 시간은 travel_to로 평일 창(2026-11-10 화)을 고정한다(TIME-1).
class App::InvoicesRemindersTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ReminderFactories
  include SolapiStubbing

  fixtures :users, :clients, :invoices, :promises, :subscriptions, :payment_passes

  def setup
    @fake = FakeSolapiClient.new
  end

  # ── REM-7 — 청구 건 단위 보류·재개 ──

  test "보류는 303으로 접수되고 reminders_suspended_at을 마킹한다 (REM-7)" do
    sign_in_as users(:delta)
    invoice = invoices(:delta_due_soon)

    patch suspend_reminders_app_invoice_path(invoice)
    assert_response :see_other
    assert_redirected_to app_invoice_path(invoice)
    assert_equal "이 청구서의 자동 안내를 보류했습니다. 예정된 발송은 취소됩니다.", flash[:notice]
    assert invoice.reload.reminders_suspended?
  end

  test "재개는 303으로 접수되고 마킹을 해소한다 (REM-7)" do
    sign_in_as users(:delta)
    invoice = invoices(:delta_due_soon)
    invoice.update_column(:reminders_suspended_at, Time.zone.parse("2026-10-12 09:00"))

    patch resume_reminders_app_invoice_path(invoice)
    assert_response :see_other
    assert_equal "이 청구서의 자동 안내를 재개했습니다. 다음 단계부터 이어집니다.", flash[:notice]
    assert_not invoice.reload.reminders_suspended?
  end

  test "보류·재개·수동 발송·재개 요청은 초안·수금완료 대상이 404로 수렴한다 (unsettled 스코프)" do
    sign_in_as users(:delta)

    [ invoices(:delta_draft), invoices(:delta_paid) ].each do |invoice|
      patch suspend_reminders_app_invoice_path(invoice)
      assert_response :not_found
      patch resume_reminders_app_invoice_path(invoice)
      assert_response :not_found
      post remind_app_invoice_path(invoice)
      assert_response :not_found
      post restart_reminders_app_invoice_path(invoice)
      assert_response :not_found
    end
  end

  # ── REM-8 — 수동 발송(지금 1통 보내기) ──

  test "Free 플랜의 수동 발송은 플랜 무관으로 발송된다 (REM-8 — origin manual)" do
    sign_in_as users(:gamma)
    invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                      due_on: Date.new(2026, 11, 9))

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      with_solapi_client(@fake) do
        post remind_app_invoice_path(invoice)
      end
    end
    assert_response :see_other
    assert_redirected_to app_invoice_path(invoice)
    assert_equal "거래처에게 안내를 발송했습니다.", flash[:notice]

    log = MessageLog.where(invoice_id: invoice.id).sole
    assert_predicate log, :sent?
    assert_predicate log, :manual?
    assert_equal "confirm_d1", log.template_key
  end

  test "수동 발송 스텝 선택 — 만기 17일 전은 issue_notice, 만기 전날은 invoice_notice다 (REM-8·운영 실측 결함)" do
    sign_in_as users(:gamma)
    far_future = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                         due_on: Date.new(2026, 11, 27))      # 만기 17일 전
    day_before = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                         due_on: Date.new(2026, 11, 11))      # 만기 전날(D-1)

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      with_solapi_client(@fake) do
        post remind_app_invoice_path(far_future)
        post remind_app_invoice_path(day_before)
      end
    end
    assert_response :see_other

    far_log = MessageLog.where(invoice_id: far_future.id).sole
    assert_equal "issue_notice", far_log.template_key             # "(내일)" 없는 발행 안내
    assert_not far_log.variables.values.join.include?("(내일)")   # "(내일)" 유입 요소 없음
    assert_equal "invoice_notice", MessageLog.where(invoice_id: day_before.id).sole.template_key
  end

  test "수동 발송 상한(5통)은 템플릿 무관으로 적용된다 — 시퀀스성·1회성 혼합 총량도 차단 (PLAN-3·C-1)" do
    sign_in_as users(:gamma)
    # 상한 도달: 순수 시퀀스성 5통
    capped = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                     due_on: Date.new(2026, 11, 27))          # 수동 선택 = issue_notice
    # 혼합 도달: 시퀀스성 3통 + 1회성 issue_notice 2통(시퀀스 집계는 3이지만 수동 집계는 5)
    mixed = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                    due_on: Date.new(2026, 11, 27))
    5.times do |i|
      MessageLog.create!(invoice: capped, user: capped.user, recipient_role: :debtor,
                         status: :sent, template_key: "confirm_d1")
    end
    3.times do |i|
      MessageLog.create!(invoice: mixed, user: mixed.user, recipient_role: :debtor,
                         status: :sent, template_key: "invoice_notice")
    end
    2.times do |i|
      MessageLog.create!(invoice: mixed, user: mixed.user, recipient_role: :debtor,
                         status: :sent, template_key: "issue_notice")
    end

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      with_solapi_client(@fake) do
        post remind_app_invoice_path(capped)
        post remind_app_invoice_path(mixed)
      end
    end
    assert_response :see_other

    [ capped, mixed ].each do |invoice|
      log = MessageLog.where(invoice_id: invoice.id, status: :skipped).sole
      assert_equal "CAP_REACHED", log.error_code                   # 6통째 — 수동 하드리밋
      assert_equal "issue_notice", log.template_key                # 수동 선택은 issue_notice
    end
    assert_empty @fake.calls
  end

  test "만기 도과 + 미래 약속의 수동 발송은 참인 문구가 없어 발송·기록 없이 안내로 수렴한다 (C-2)" do
    sign_in_as users(:gamma)
    invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                      due_on: Date.new(2026, 11, 9))          # 만기 도과
    create_promise(invoice, kind: :date_selected, promised_on: Date.new(2026, 11, 20))
    # 약속 당일 + 만기 도과 경계 — 같은 nil 창이다(C-2)
    due_day = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                      due_on: Date.new(2026, 11, 9))
    promise = create_promise(due_day, kind: :date_selected, promised_on: Date.new(2026, 11, 11))
    promise.update_column(:promised_on, Date.new(2026, 11, 10))

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      with_solapi_client(@fake) do
        post remind_app_invoice_path(invoice)
        post remind_app_invoice_path(due_day)
      end
    end
    assert_response :see_other
    assert_match(/보낼 수 있는 안내 문구가 없습니다/, flash[:notice])

    # nil 창 상태에서 show 재렌더 시 「다음 안내」 라벨 행이 아예 렌더되지 않는다(빈 표기 방지)
    get app_invoice_path(invoice)
    assert_response :ok
    assert_no_match(/다음 안내/, response.body)

    assert_empty MessageLog.where(invoice_id: invoice.id)          # 발송·기록 0건
    assert_empty MessageLog.where(invoice_id: due_day.id)
    assert_empty @fake.calls
  end

  test "수신거부 거래처의 수동 발송은 가드에 저지되고 사유가 flash로 안내된다 (VIEW-7·REM-8)" do
    sign_in_as users(:delta)
    invoice = invoices(:delta_due_soon)
    invoice.client.update_column(:refused_at, Time.zone.parse("2026-10-12 09:00"))

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      with_solapi_client(@fake) do
        post remind_app_invoice_path(invoice)
      end
    end
    assert_response :see_other
    assert_match(/거래처가 추가 안내 수신을 거부하여 발송하지 않았습니다/, flash[:notice])
    assert_empty @fake.calls                                        # 가드 — 호출 없음

    log = MessageLog.where(invoice_id: invoice.id).sole
    assert_predicate log, :skipped?
    assert_equal "REFUSED", log.error_code                          # P4 — 시도도 기록
  end

  test "발송 창 밖 수동 발송은 재예약 안내 flash로 수렴한다 (REM-3·B-2)" do
    sign_in_as users(:gamma)
    invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                      due_on: Date.new(2026, 11, 9))

    travel_to(Time.zone.parse("2026-11-10 20:00")) do               # 창 종료 후
      with_solapi_client(@fake) do
        post remind_app_invoice_path(invoice)
      end
    end
    assert_response :see_other
    assert_equal "지금은 발송 가능 시간(평일 09:00~18:00)이 아니어서 다음 평일 오전 9시에 발송됩니다.",
                 flash[:notice]
    assert_predicate MessageLog.where(invoice_id: invoice.id).sole, :pending?
    assert_empty @fake.calls
  end

  test "수동 발송 총량 경계 — 4통째·5통째는 성공하고 6통째만 CAP_REACHED로 차단된다 (Q11 삼분 경계)" do
    sign_in_as users(:gamma)
    invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                      due_on: Date.new(2026, 11, 27))          # 수동 선택 = issue_notice

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      with_solapi_client(@fake) do
        4.times { post remind_app_invoice_path(invoice) }                     # 상한 직전(4통)
        assert_response :see_other
        assert_equal "거래처에게 안내를 발송했습니다.", flash[:notice]

        post remind_app_invoice_path(invoice)                                  # 5통째 — 통과
        assert_equal "거래처에게 안내를 발송했습니다.", flash[:notice]

        post remind_app_invoice_path(invoice)                                  # 6통째 — 차단
        assert_match(/상한\(5통\)에 도달하여 발송하지 않았습니다/, flash[:notice])
      end
    end
    assert_equal 5, MessageLog.where(invoice_id: invoice.id, status: :sent).count
    log = MessageLog.where(invoice_id: invoice.id, status: :skipped).sole
    assert_equal "CAP_REACHED", log.error_code
    assert_equal 5, @fake.calls.size                                            # 차단분 호출 0
  end

  test "수동 issue_notice 발송 후에도 D-1 자동 스캔은 invoice_notice를 발송한다 (SEC-5 키 분리·무결성)" do
    sign_in_as users(:delta)                                                    # 자동 스캔 자격 필요(REM-8)
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 11, 27))

    travel_to(Time.zone.parse("2026-11-10 10:00")) do                           # 만기 17일 전
      with_solapi_client(@fake) do
        post remind_app_invoice_path(invoice)                                   # 수동 issue_notice
      end
      assert_equal "issue_notice", MessageLog.where(invoice_id: invoice.id).sole.template_key
    end

    # D-1 도래 — 수동 issue_notice(step_sent? 대상 밖)와 무관하게 자동 안내는 정상 발송된다.
    travel_to(Time.zone.parse("2026-11-26 14:00")) do                           # D-1 도래
      with_solapi_client(@fake) do
        Reminders::DispatchService.new.call
      end
    end
    logs = MessageLog.where(invoice_id: invoice.id, recipient_role: :debtor).order(:id)
    assert_equal [ %w[ issue_notice sent ], %w[ invoice_notice sent ] ],
                 logs.map { |log| [ log.template_key, log.status ] }
    assert_predicate logs.last, :auto?                                          # SEC-5 — origin 구분 기록
    assert_equal 2, @fake.calls.size
  end

  test "수동 issue_notice 발송 후 약속 전날 자동 스캔은 promise_d1을 발송한다 (PROMISE-3·SEC-5 무결성)" do
    sign_in_as users(:delta)                                                    # 자동 스캔 자격 필요(REM-8)
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 11, 11))
    create_promise(invoice, kind: :date_selected, promised_on: Date.new(2026, 11, 27))

    travel_to(Time.zone.parse("2026-11-10 10:00")) do                           # 만기 전 + 약속 원격 — issue_notice
      with_solapi_client(@fake) do
        post remind_app_invoice_path(invoice)
      end
      assert_equal "issue_notice", MessageLog.where(invoice_id: invoice.id).sole.template_key
    end

    travel_to(Time.zone.parse("2026-11-26 14:00")) do                           # 약속 전날 — 자동 스캔
      with_solapi_client(@fake) do
        Reminders::DispatchService.new.call
      end
    end
    logs = MessageLog.where(invoice_id: invoice.id, recipient_role: :debtor).order(:id)
    assert_equal [ %w[ issue_notice sent ], %w[ promise_d1 sent ] ],
                 logs.map { |log| [ log.template_key, log.status ] }
    assert_equal 2, @fake.calls.size
  end

  # ── REM-12·13 — 시퀀스 수동 재개(C-3) ──

  test "종결 청구의 재개 요청은 마킹을 해소하고 303으로 안내한다 (REM-12·C-3)" do
    sign_in_as users(:delta)
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 10, 27))  # final_d14 nominal 당일
    invoice.update_column(:sequence_finished_at, Time.zone.parse("2026-11-09 14:00"))

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      post restart_reminders_app_invoice_path(invoice)
    end
    assert_response :see_other
    assert_equal "정기 안내를 다시 진행합니다. 남은 단계부터 이어서 보냅니다.", flash[:notice]
    assert_not invoice.reload.sequence_finished?
  end

  test "남은 미발송 단계가 없는 종결 청구의 재개 요청은 안내로 거부되고 마킹이 유지된다 (C-3)" do
    sign_in_as users(:delta)
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 10, 27))
    MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "final_d14",
                       recipient_role: :debtor, status: :sent)
    invoice.update_column(:sequence_finished_at, Time.zone.parse("2026-11-09 14:00"))

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      post restart_reminders_app_invoice_path(invoice)
    end
    assert_response :see_other
    assert_equal "다시 보낼 수 있는 남은 단계가 없어 진행하지 않았습니다. 필요하면 개별 안내를 직접 확인해 주세요.",
                 flash[:alert]
    assert invoice.reload.sequence_finished?                        # 마킹 유지 — 재해소 없음
  end

  # ── SHARE-6 — 발행 안내 선택(발행 폼 옵션) ──

  test "발행 시 send_notice 체크(기본)는 issue_notice를 인큐하고 안내 flash를 보낸다 (SHARE-6)" do
    sign_in_as users(:gamma)
    draft = create_gamma_draft

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      assert_enqueued_with job: Reminders::DeliverJob,
                           args: [ draft.id, "issue_notice", "debtor" ] do
        patch issue_app_invoice_path(draft), params: { send_notice: "1" }
      end
    end
    assert_response :see_other
    assert_equal "청구서가 발행되었습니다. 거래처에게 받을돈 명의의 첫 안내를 보냅니다.", flash[:notice]
    assert draft.reload.issued?
  end

  test "발행 시 send_notice 해제는 인큐 없이 직접 전달을 안내한다 (SHARE-6 — 해제 명시 전송)" do
    sign_in_as users(:gamma)
    draft = create_gamma_draft

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      assert_no_enqueued_jobs only: Reminders::DeliverJob do
        patch issue_app_invoice_path(draft), params: { send_notice: "0" }
      end
    end
    assert_response :see_other
    assert_equal "청구서가 발행되었습니다. 링크를 복사해 거래처에 직접 전달하세요.", flash[:notice]
  end

  test "send_notice 파라미터 부재(구폼)도 기본 켬으로 해석해 인큐한다 (SHARE-6)" do
    sign_in_as users(:gamma)
    draft = create_gamma_draft

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      assert_enqueued_with job: Reminders::DeliverJob,
                           args: [ draft.id, "issue_notice", "debtor" ] do
        patch issue_app_invoice_path(draft)
      end
    end
    assert_response :see_other
  end

  # ── 소유권 격리 ──

  test "타 사용자 청구서의 F-REM 액션은 404로 격리된다 (소유권 — Current.user 스코프)" do
    sign_in_as users(:gamma)
    invoice = invoices(:delta_due_soon)

    patch suspend_reminders_app_invoice_path(invoice)
    assert_response :not_found
    patch resume_reminders_app_invoice_path(invoice)
    assert_response :not_found
    post remind_app_invoice_path(invoice)
    assert_response :not_found
    post restart_reminders_app_invoice_path(invoice)
    assert_response :not_found

    assert_not invoice.reload.reminders_suspended?
    assert_empty MessageLog.where(invoice_id: invoice.id)
  end

  private

  # gamma 초안 생성 — 발행(issue) 액션 대상(draft 스코프). PLAN-1 한도는 당월 0건이라 여유.
  def create_gamma_draft
    create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                            due_on: Date.new(2026, 12, 10), status: :draft, with_link: false)
  end
end
