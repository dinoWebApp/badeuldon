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

    # W-5(a) — 수신 거부하지 않은 보류 청구에 「안내 재개하기」가 보인다는 양성 단언
    # (버튼 분기 조건이 잘못 바뀌어 보류 재개 진입점이 사라져도 잡아낸다)
    get app_invoice_path(invoice)
    assert_select "button", text: "안내 재개하기"

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
    # 약속 당일 + 만기 도과 경계 — 같은 nil 창이다(C-2)
    due_day = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                      due_on: Date.new(2026, 11, 9))

    # 약속 생성도 시나리오 시점(11-10) 안에서 수행한다 — 약속 모델은 "오늘 이후" 검증이라
    # 블록 밖(실제 오늘)에서 고정 약속일로 만들면 그 날짜가 지나는 순간 생성이 깨진다
    # (2026-11-23 실측 — 11-20 고정일이 11-21부터 RecordInvalid). 시점 안에서는 미래일(11-20)과
    # 당일(11-10) 모두 검증을 통과하므로 우회 기록(update_column)이 필요 없다(시나리오 의도 불변).
    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      create_promise(invoice, kind: :date_selected, promised_on: Date.new(2026, 11, 20))
      create_promise(due_day, kind: :date_selected, promised_on: Date.new(2026, 11, 10))

      with_solapi_client(@fake) do
        post remind_app_invoice_path(invoice)
        post remind_app_invoice_path(due_day)
      end
      assert_response :see_other
      assert_match(/보낼 수 있는 안내 문구가 없습니다/, flash[:notice])

      # nil 창 상태에서 show 재렌더 시 「다음 안내」 라벨 행이 아예 렌더되지 않는다(빈 표기 방지).
      # [2026-11-19 Tester] GET도 시나리오 시점(11-10) 안에서 수행한다 — 블록 밖이면 실제
      # 오늘 기준으로 판정해 약속일(11-20)이 내일이 되는 구간에 이 테스트가 실패했다.
      get app_invoice_path(invoice)
      assert_response :ok
      assert_no_match(/다음 안내/, response.body)
    end

    assert_empty MessageLog.where(invoice_id: invoice.id)          # 발송·기록 0건
    assert_empty MessageLog.where(invoice_id: due_day.id)
    assert_empty @fake.calls
  end

  test "수신거부 거래처의 수동 발송은 가드에 저지되고 사유가 flash로 안내된다 (VIEW-7·REM-8)" do
    sign_in_as users(:delta)
    invoice = invoices(:delta_due_soon)
    mark_refused(invoice.client, at: Time.zone.parse("2026-10-12 09:00"))

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      # 버튼은 reminders_active?(수신 거부 배제)로 숨겨진다 — 직접 URL 우회도 아래 가드가 막는다.
      get app_invoice_path(invoice)
      assert_response :ok
      assert_no_match(/지금 1통 보내기/, response.body)
      assert_no_match(/안내 보류하기/, response.body)

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

  # 수신 거부 상태에서의 보류 요청(직접 URL — 버튼은 reminders_active?로 숨겨져 있다).
  # 현재 동작 기록: 보류 마킹은 그대로 남고(재개 경로가 막혀 영구 잔존 — 리뷰 §5 관찰 3),
  # 발송에는 영향이 없다(REFUSED 가드가 SUSPENDED보다 앞선다). 종결·거부 상태는 불변.
  test "수신 거부한 거래처의 청구 보류 요청은 보류 마킹을 남기고 거부·종결 상태를 바꾸지 않는다 (VIEW-7·REM-7 — 현재 동작 기록)" do
    sign_in_as users(:delta)
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 10, 27))
    finished_at = Time.zone.parse("2026-11-09 14:00")
    refused_at = Time.zone.parse("2026-11-09 15:00")
    invoice.update_column(:sequence_finished_at, finished_at)
    mark_refused(invoice.client, at: refused_at)

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      patch suspend_reminders_app_invoice_path(invoice)
      assert_response :see_other
      assert_redirected_to app_invoice_path(invoice)
      assert_equal "이 청구서의 자동 안내를 보류했습니다. 예정된 발송은 취소됩니다.", flash[:notice]

      # 보류 마킹 뒤의 수동 발송 요청도 REFUSED가 우선이다 — 사유가 SUSPENDED로 바뀌지 않는다.
      with_solapi_client(@fake) do
        post remind_app_invoice_path(invoice)
      end
      assert_response :see_other
    end

    invoice.reload
    assert invoice.reminders_suspended?                             # 현재 동작 — 보류 마킹은 남는다
    assert_equal finished_at, invoice.sequence_finished_at          # 종결 상태 불변
    assert_equal refused_at, invoice.client.reload.refused_at       # 거부 상태 불변

    log = MessageLog.where(invoice_id: invoice.id).sole
    assert_equal "REFUSED", log.error_code                          # 발송 영향 없음 — 거부 가드 우선
    assert_empty @fake.calls
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

    # 약속은 시나리오 시점(11-10) 안에서 만든다 — 약속 모델의 "오늘 이후" 검증 때문에 블록 밖
    # 실제 오늘 기준 고정 약속일(11-27)은 그 날짜가 지난 뒤 생성이 깨진다(같은 파일 C-2 선례).
    travel_to(Time.zone.parse("2026-11-10 10:00")) do                           # 만기 전 + 약속 원격 — issue_notice
      create_promise(invoice, kind: :date_selected, promised_on: Date.new(2026, 11, 27))
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
      # W-5(a) — 수신 거부하지 않은 종결 청구에 「안내 다시 보내기」가 보인다는 양성 단언
      # (플랜 시나리오 3의 「버튼 노출」 — 분기 조건이 잘못 바뀌어도 잡아낸다)
      get app_invoice_path(invoice)
      assert_select "button", text: "안내 다시 보내기"

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

  # ── VIEW-7 — 수신 거부한 거래처의 청구는 재개할 수 없다(채무자 의사 — 되돌리는 경로 없음) ──

  test "수신 거부한 거래처의 종결 청구 화면에는 재개 버튼이 없고 거부 안내 배너가 있다 (VIEW-7)" do
    sign_in_as users(:delta)
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 10, 27))
    invoice.update_column(:sequence_finished_at, Time.zone.parse("2026-11-09 14:00"))
    mark_refused(invoice.client, at: Time.zone.parse("2026-11-09 15:00"))

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      get app_invoice_path(invoice)
    end
    assert_response :ok
    assert_no_match(/안내 다시 보내기/, response.body)              # 버튼·보조 문구 모두 미노출
    assert_match(/이 거래처가 추가 안내 수신을 거부했습니다/, response.body)  # 거부 배너가 사유 설명
  end

  test "수신 거부한 거래처의 종결 청구 재개 요청은 상태 변경 없이 사유 안내로 거부된다 (VIEW-7·REM-12)" do
    sign_in_as users(:delta)
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 10, 27))
    invoice.update_columns(
      reminders_suspended_at: Time.zone.parse("2026-11-09 13:00"),
      sequence_finished_at: Time.zone.parse("2026-11-09 14:00")
    )
    mark_refused(invoice.client, at: Time.zone.parse("2026-11-09 15:00"))

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      post restart_reminders_app_invoice_path(invoice)
    end
    assert_response :see_other
    assert_redirected_to app_invoice_path(invoice)
    assert_equal "이 거래처가 추가 안내 수신을 거부하여 자동 안내를 다시 진행할 수 없습니다.",
                 flash[:alert]
    # W-5(b) — 세 마킹의 보존을 직접 본다(가드가 쓰기보다 앞서 상태 변경이 없음).
    invoice.reload
    assert_equal Time.zone.parse("2026-11-09 13:00"), invoice.reminders_suspended_at
    assert_equal Time.zone.parse("2026-11-09 14:00"), invoice.sequence_finished_at
    assert_equal Time.zone.parse("2026-11-09 15:00"), invoice.client.reload.refused_at
  end

  # 보류·수신 거부 겹침 — 거래처가 거부한 뒤 청구에 보류·종결 마킹이 남은 상태(구멍 A).
  # 재개 버튼도 다시 보내기 버튼도 노출하지 않는다(거부 배너가 사유를 설명).
  test "수신 거부한 거래처의 보류 중 청구 화면에는 재개·다시 보내기 버튼이 없다 (VIEW-7 — 겹침)" do
    sign_in_as users(:delta)
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 10, 27))
    invoice.update_columns(
      reminders_suspended_at: Time.zone.parse("2026-11-09 14:00"),
      sequence_finished_at: Time.zone.parse("2026-11-09 14:30")
    )
    mark_refused(invoice.client, at: Time.zone.parse("2026-11-09 15:00"))

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      get app_invoice_path(invoice)
    end
    assert_response :ok
    assert_no_match(/안내 재개하기/, response.body)                  # 보류 재개 버튼 미노출
    assert_no_match(/안내 다시 보내기/, response.body)               # 종결 재시도 버튼도 미노출
    assert_match(/이 거래처가 추가 안내 수신을 거부했습니다/, response.body)  # 거부 배너가 사유 설명
  end

  test "수신 거부한 거래처의 보류 중 청구 재개 요청은 상태 변경 없이 사유 안내로 거부된다 (VIEW-7·REM-7)" do
    sign_in_as users(:delta)
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 10, 27))
    invoice.update_columns(
      reminders_suspended_at: Time.zone.parse("2026-11-09 14:00"),
      sequence_finished_at: Time.zone.parse("2026-11-09 14:30")
    )
    mark_refused(invoice.client, at: Time.zone.parse("2026-11-09 15:00"))

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      patch resume_reminders_app_invoice_path(invoice)
    end
    assert_response :see_other
    assert_redirected_to app_invoice_path(invoice)
    assert_equal "이 거래처가 추가 안내 수신을 거부하여 자동 안내를 재개할 수 없습니다.",
                 flash[:alert]
    invoice.reload
    assert invoice.reminders_suspended?                             # 보류 마킹 유지 — 상태 변경 없음
    assert invoice.sequence_finished?                               # 종결 마킹도 유지
  end

  # ── VIEW-7(Q30) — 상속 거래처의 청구도 직접 거부와 같은 화면·가드를 탄다(리뷰 Tester 중점 4) ──

  test "상속 거래처의 청구 화면에는 발송·재개 버튼이 없고 재개·재시작 요청은 사유 안내로 거부된다 (VIEW-7·Q30)" do
    sign_in_as users(:delta)
    users(:delta).clients.create!(name: "델타거부 원본", contact_name: "덜원본", phone: "010-3131-3131")
    mark_refused(users(:delta).clients.last, at: Time.zone.parse("2026-11-09 15:00"))
    inherited = users(:delta).clients.create!(name: "델타상속", contact_name: "덜상속",
                                              phone: "01031313131")            # 같은 번호 재등록 — 상속
    assert inherited.reload.refused?
    invoice = create_reminder_invoice(user: users(:delta), client: inherited,
                                      due_on: Date.new(2026, 10, 27))
    invoice.update_columns(
      reminders_suspended_at: Time.zone.parse("2026-11-09 14:00"),
      sequence_finished_at: Time.zone.parse("2026-11-09 14:30")
    )

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      get app_invoice_path(invoice)
    end
    assert_response :ok
    assert_match(/수신 거부/, response.body)                    # 자동 안내 현황 배지 — 상속 마킹도
    assert_match(/이 거래처가 추가 안내 수신을 거부했습니다/, response.body)
    assert_no_match(/지금 1통 보내기/, response.body)
    assert_no_match(/안내 재개하기/, response.body)
    assert_no_match(/안내 다시 보내기/, response.body)

    patch resume_reminders_app_invoice_path(invoice)
    assert_response :see_other
    assert_equal "이 거래처가 추가 안내 수신을 거부하여 자동 안내를 재개할 수 없습니다.", flash[:alert]
    invoice.reload
    assert_equal Time.zone.parse("2026-11-09 14:00"), invoice.reminders_suspended_at  # 상태 변경 없음
    assert_equal Time.zone.parse("2026-11-09 15:00"), invoice.client.reload.refused_at

    post restart_reminders_app_invoice_path(invoice)
    assert_response :see_other
    assert_equal "이 거래처가 추가 안내 수신을 거부하여 자동 안내를 다시 진행할 수 없습니다.",
                 flash[:alert]
    assert_equal Time.zone.parse("2026-11-09 14:30"), invoice.reload.sequence_finished_at
  end

  # ── PLAN-3·Q28·W-4 — 상한 도달 청구의 화면(종결 마킹은 없다 — 배지·안내 상자로 표시하고
  #    버튼 행은 숨긴다. 상한 판정은 컨트롤러 컨텍스트(@reminder_cap_reached) 경유) ──

  test "상한 도달 청구 화면은 상한 안내 상자·배지를 보이고 발송 버튼 행을 숨긴다 (PLAN-3·Q28·W-4)" do
    sign_in_as users(:gamma)                                        # Free — 무료 플랜 문구 숨김도 함께 검증
    invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                      due_on: Date.new(2026, 11, 27))
    5.times do
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "issue_notice",
                         recipient_role: :debtor, status: :sent, origin: :manual)
    end

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      get app_invoice_path(invoice)
    end
    assert_response :ok
    assert_match(/발송 상한에 도달했습니다/, response.body)          # 상한 안내 상자
    assert_match(/입금을 기록하면 나가는 안내/, response.body)
    assert_match(/상한 도달/, response.body)                        # 상태 배지 — 「자동 안내 중」 대체
    assert_no_match(/지금 1통 보내기/, response.body)
    assert_no_match(/안내 보류하기/, response.body)
    assert_no_match(/다음 안내:/, response.body)
    assert_no_match(/무료 플랜은 자동 발송이 없습니다/, response.body) # 막힌 버튼 권유 방지
  end

  test "상한 전 청구 화면은 기존대로 발송 버튼 행을 보인다 (W-4 회귀)" do
    sign_in_as users(:gamma)
    invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                      due_on: Date.new(2026, 11, 27))

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      get app_invoice_path(invoice)
    end
    assert_response :ok
    assert_match(/지금 1통 보내기/, response.body)
    assert_match(/안내 보류하기/, response.body)
    assert_no_match(/상한 도달/, response.body)
  end

  # 마감 리뷰 W-3(2026-11-26) — 자동 1회성(partial_paid 등·Q10 집계 밖)만으로 수동 상한
  # (채무자 향 sent 전체 5통)에만 걸린 청구는 「상한 도달」 표시가 없는데 「지금 1통 보내기」가
  # 보이고 누르면 CAP_REACHED로 막혔다(죽은 버튼). 직접 발송 버튼·「다음 안내」 표기·무료
  # 플랜 문구를 숨기고 한 줄 안내로 대체한다(「안내 보류하기」는 유지 — 발송 조작이 아니다).
  test "수동 상한만 도달한 청구 화면은 직접 발송 버튼·다음 안내를 숨기고 한 줄 안내를 보인다 (PLAN-3·W-3)" do
    sign_in_as users(:gamma)                                        # Free — 무료 플랜 문구 숨김도 함께 검증
    invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                      due_on: Date.new(2026, 11, 27))
    5.times do
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "partial_paid",
                         recipient_role: :debtor, status: :sent)    # 자동 1회성 5통 — 수동 상한만 도달
    end
    assert invoice.manual_reminder_cap_reached?
    assert_not invoice.reminder_cap_reached?                        # 자동 상한 집계는 미도달(Q10)

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      get app_invoice_path(invoice)
    end
    assert_response :ok
    assert_no_match(/지금 1통 보내기/, response.body)               # 막힌 버튼 숨김
    assert_no_match(/다음 안내:/, response.body)                    # 라벨 숨김
    assert_match(/직접 안내는 청구 건당 5통을 모두 보내 더 보낼 수 없습니다/, response.body)
    assert_no_match(/발송 상한에 도달했습니다/, response.body)      # 자동 상한 표시는 아니다
    assert_no_match(/상한 도달/, response.body)                     # 배지도 미노출
    assert_no_match(/무료 플랜은 자동 발송이 없습니다/, response.body) # 막힌 버튼 권유 방지
    assert_match(/안내 보류하기/, response.body)                    # 보류하기는 유지
  end

  test "상한 도달한 수금 완료 청구 화면에는 상한 안내 상자·배지가 없다 (미수 청구 한정)" do
    sign_in_as users(:gamma)
    invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                      due_on: Date.new(2026, 11, 27))
    invoice.mark_paid!                                               # INV-4 — 상한 도달 뒤 마감된 청구
    5.times do
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "issue_notice",
                         recipient_role: :debtor, status: :sent, origin: :manual)
    end

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      get app_invoice_path(invoice)
    end
    assert_response :ok
    assert_no_match(/발송 상한에 도달했습니다/, response.body)       # 완납 청구는 발송 대상이 아니다
    assert_no_match(/상한 도달/, response.body)                      # 배지도 미노출
  end

  # 마지막 수정 반례(Tester 2026-11-26) — 배너 우선순위(거부 → 상한 → 보류 → 종결)의 조합
  # 검증. 상한 도달 분기는 보류·종결 분기보다 앞서고, 상한 도달 시 버튼 행 자체가
  # 렌더되지 않아 재개·보류·직접 발송·다시 보내기 조작이 모두 사라진다.
  test "상한 도달 + 청구 건 보류가 겹친 청구 화면은 상한 상자만 보이고 발송·재개·보류 버튼이 없다 (PLAN-3·Q28·REM-7)" do
    sign_in_as users(:gamma)
    invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                      due_on: Date.new(2026, 11, 27))
    invoice.update_column(:reminders_suspended_at, Time.zone.parse("2026-11-09 14:00"))
    5.times do
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "issue_notice",
                         recipient_role: :debtor, status: :sent, origin: :manual)
    end
    assert invoice.reminder_cap_reached?
    assert invoice.reminders_suspended?

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      get app_invoice_path(invoice)
    end
    assert_response :ok
    assert_match(/발송 상한에 도달했습니다/, response.body)          # 상한 상자 — 보류 배너보다 우선
    assert_no_match(/자동 안내가 보류 중입니다/, response.body)
    assert_no_match(/안내 재개하기/, response.body)
    assert_no_match(/안내 보류하기/, response.body)
    assert_no_match(/지금 1통 보내기/, response.body)
    assert_no_match(/다음 안내:/, response.body)
  end

  test "상한 도달 + 수신 거부가 겹친 청구 화면은 거부 안내가 먼저이고 상한 상자·버튼이 없다 (VIEW-7·PLAN-3)" do
    sign_in_as users(:delta)
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 11, 27))
    mark_refused(invoice.client, at: Time.zone.parse("2026-11-09 15:00"))
    5.times do
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "issue_notice",
                         recipient_role: :debtor, status: :sent, origin: :manual)
    end
    assert invoice.reminder_cap_reached?

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      get app_invoice_path(invoice)
    end
    assert_response :ok
    assert_match(/이 거래처가 추가 안내 수신을 거부했습니다/, response.body)  # 배너 1순위 — 거부 안내
    assert_no_match(/발송 상한에 도달했습니다/, response.body)       # 상한 상자는 렌더되지 않는다
    assert_no_match(/안내 재개하기/, response.body)
    assert_no_match(/안내 보류하기/, response.body)
    assert_no_match(/지금 1통 보내기/, response.body)
    assert_no_match(/다음 안내:/, response.body)
  end

  test "상한 도달 + 종결(수신 거부 아님)이 겹친 청구 화면은 상한 상자를 보이고 다시 보내기 버튼이 없다 (PLAN-3·REM-12)" do
    sign_in_as users(:delta)
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 10, 27))
    invoice.update_column(:sequence_finished_at, Time.zone.parse("2026-11-09 14:00"))
    5.times do
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "issue_notice",
                         recipient_role: :debtor, status: :sent, origin: :manual)
    end
    assert invoice.reminder_cap_reached?
    assert invoice.sequence_finished?

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      get app_invoice_path(invoice)
    end
    assert_response :ok
    assert_match(/발송 상한에 도달했습니다/, response.body)          # 상한 상자 — 종결 상자보다 우선
    assert_no_match(/정기 안내를 마무리했습니다/, response.body)
    assert_no_match(/안내 다시 보내기/, response.body)
    assert_no_match(/지금 1통 보내기/, response.body)
    assert_no_match(/다음 안내:/, response.body)
  end

  # ── 리뷰 §5-3 — 거래처 단위 보류 + 청구 종결 겹침. 「안내 다시 보내기」가 보였지만
  #    거래처 보류가 남아 발송이 없었다(「다시 진행합니다」 안내가 거짓). 버튼을 숨기고,
  #    거래처를 재개하면 실제 발송이 가능해지므로 다시 보인다. ──

  test "거래처 단위 보류가 겹친 종결 청구 화면에는 다시 보내기 버튼이 없고 보류 안내가 보인다 (리뷰 §5-3)" do
    sign_in_as users(:delta)
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 10, 27))
    invoice.update_column(:sequence_finished_at, Time.zone.parse("2026-11-09 14:00"))
    invoice.client.update_column(:reminders_suspended_at, Time.zone.parse("2026-11-09 15:00"))

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      get app_invoice_path(invoice)
      assert_response :ok
      assert_no_match(/안내 다시 보내기/, response.body)            # 거래처 보류가 남아 발송이 없다
      assert_match(/거래처 단위로 보류 중입니다/, response.body)     # 배너가 사유·재개 경로를 설명

      # 거래처를 재개하면 버튼이 다시 보인다(재개 뒤 종결 해소 시 실제 발송이 일어난다)
      patch resume_reminders_app_client_path(invoice.client)
      assert_response :see_other
      get app_invoice_path(invoice)
      assert_response :ok
      assert_select "button", text: "안내 다시 보내기"
    end
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
