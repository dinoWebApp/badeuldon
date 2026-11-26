require "test_helper"
require_relative "../../test_helpers/fake_solapi_client"
require_relative "../../test_helpers/solapi_stubbing"
require_relative "../../test_helpers/reminder_factories"

module Promises
  # 응답 접수 단일 진입점(F-PROMISE) — 4종 접수·INV-4 issued|viewed→promised 원자 전이·
  # PROMISE-7 상태 불변·종결 상태에서의 시도 처리(설계 의도 확인)·서버 재검증(결정 #3)·
  # 위조 kind 거부. 시나리오 기준: _workspace/03_implementation.md §2,
  # _workspace/05_review.md §검증표 5·7·8. 시간 의존 검증은 travel_to로 KST 고정(TIME-1).
  # F-REM 훅 검증(발송 중단 마킹·U1 알림 인큐·스캔 전무)은 Phase 7에서 확장했다 — 스캔 경로는
  # DispatchService(client: 주입)으로 실호출을 차단한다(REM-10).
  class RegisterServiceTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    include SolapiStubbing
    include ReminderFactories

    fixtures :invoices, :promises, :users, :clients, :subscriptions, :payment_passes

    # ── 약속 2종 — INV-4 전이를 동반한다 ──

    test "this_week 접수는 issued 청구서를 promised로 전이하고 기록한다 (INV-4)" do
      invoice = invoices(:delta_issued)

      travel_to(Time.zone.parse("2026-10-14 10:00")) do
        promise = RegisterService.new(invoice: invoice, kind: :this_week).call
        assert promise.persisted?
        assert_equal Date.new(2026, 10, 16), promise.promised_on  # 수요일 접수 → 이번 주 금
      end

      assert invoice.reload.promised?
      assert_equal 1, invoice.promises.count
    end

    test "date_selected 접수는 viewed 청구서를 promised로 전이하고 기록한다 (INV-4)" do
      invoice = invoices(:delta_viewed)
      assert_equal 1, invoice.promises.count  # fixture — 답변 완료 문의 1건

      travel_to(Time.zone.parse("2026-10-14 10:00")) do
        promise = RegisterService.new(invoice: invoice, kind: :date_selected,
                                      promised_on: Date.new(2026, 10, 30)).call
        assert promise.persisted?
        assert_equal Date.new(2026, 10, 30), promise.promised_on  # 지정값 보존
      end

      assert invoice.reload.promised?
      assert_equal 2, invoice.promises.count
    end

    # ── 회신 2종 — 상태 불변(PROMISE-7: 수금 마감은 U1 확인으로만) ──

    test "paid_report 접수는 청구서 상태를 바꾸지 않는다 (PROMISE-7)" do
      invoice = invoices(:delta_issued)

      promise = RegisterService.new(invoice: invoice, kind: :paid_report).call

      assert promise.persisted?
      assert_nil promise.promised_on
      assert invoice.reload.issued?
    end

    test "inquiry 접수는 청구서 상태를 바꾸지 않는다 (PROMISE-7)" do
      invoice = invoices(:delta_issued)

      promise = RegisterService.new(invoice: invoice, kind: :inquiry, memo: "입금 계좌 문의드립니다").call

      assert promise.persisted?
      assert_equal "입금 계좌 문의드립니다", promise.memo
      assert invoice.reload.issued?
    end

    # ── 종결·비대상 상태에서의 약속 시도 — 전이 불가·기록 여부 확인(설계 의도) ──

    test "paid 청구서 약속 시도는 전이 없이 이력만 추가된다 (설계 의도 — 이력 추가형)" do
      invoice = invoices(:delta_paid)

      travel_to(Time.zone.parse("2026-10-14 10:00")) do
        promise = RegisterService.new(invoice: invoice, kind: :this_week).call
        assert promise.persisted?
      end

      assert invoice.reload.paid?
      assert_equal 1, invoice.promises.count
    end

    test "voided 청구서 약속 시도도 전이 없이 이력만 추가된다 (설계 의도 — 진입 차단은 뷰어 토큰 가드)" do
      invoice = invoices(:delta_voided)

      travel_to(Time.zone.parse("2026-10-14 10:00")) do
        promise = RegisterService.new(invoice: invoice, kind: :this_week).call
        assert promise.persisted?
      end

      assert invoice.reload.voided?
      assert_equal 1, invoice.promises.count
    end

    test "연체(저장 상태) 약속 시도는 promised 전이가 불가하다 (리뷰 이슈 #4 — F-REM 백로그)" do
      invoice = invoices(:delta_overdue)

      travel_to(Time.zone.parse("2026-10-14 10:00")) do
        promise = RegisterService.new(invoice: invoice, kind: :this_week).call
        assert promise.persisted?
      end

      assert invoice.reload.overdue?
      assert_equal 1, invoice.promises.count
    end

    # ── 재응답·멱등성(결정 #4 — 이력 보존) ──

    test "promised 재응답은 전이 없이 이력만 추가된다 (결정 #4)" do
      invoice = invoices(:delta_promised)
      assert_equal 2, invoice.promises.count  # fixture — 약속 이력 2건

      travel_to(Time.zone.parse("2026-10-15 10:00")) do
        RegisterService.new(invoice: invoice, kind: :date_selected,
                            promised_on: Date.new(2026, 11, 6)).call
      end

      assert invoice.reload.promised?
      assert_equal 3, invoice.promises.count
    end

    test "mark_promised!는 조건 불일치 시 갱신 없이 거짓을 반환한다 (원자 조건부 UPDATE)" do
      invoice = invoices(:delta_issued)

      assert invoice.mark_promised!                 # issued → promised (1행)
      assert invoice.reload.promised?
      assert_not invoice.mark_promised!             # 이미 promised — 0행(전이 1회 보장)
      assert invoice.reload.promised?
    end

    test "전이 단계 실패 시 기록도 함께 롤백된다 (1트랜잭션 원자성)" do
      invoice = invoices(:delta_issued)
      invoice.define_singleton_method(:mark_promised!) do
        raise ActiveRecord::ActiveRecordError, "전이 강제 실패"
      end

      assert_raises(ActiveRecord::ActiveRecordError) do
        RegisterService.new(invoice: invoice, kind: :this_week).call
      end

      assert invoice.reload.issued?
      assert_empty invoice.reload.promises          # 기록까지 함께 확정·폐기
    end

    # ── 서버 재검증(결정 #3)·위조 차단 ──

    test "과거 예정일 date_selected는 거부되고 상태·이력에 잔재가 없다 (결정 #3)" do
      invoice = invoices(:delta_issued)

      travel_to(Time.zone.parse("2026-10-16 09:00")) do
        error = assert_raises(RegisterService::InvalidResponse) do
          RegisterService.new(invoice: invoice, kind: :date_selected,
                              promised_on: Date.current - 1).call
        end
        assert_match(/입금 예정일은 오늘 또는 그 이후/, error.message)
      end

      assert invoice.reload.issued?
      assert_empty invoice.reload.promises
    end

    test "위조 kind는 일반 문구의 InvalidResponse로 거부된다 (enum 정보 누출 없음)" do
      invoice = invoices(:delta_issued)

      [ "hacker", "0", "", nil ].each do |kind|
        error = assert_raises(RegisterService::InvalidResponse) do
          RegisterService.new(invoice: invoice, kind: kind).call
        end
        assert_match(/응답을 처리할 수 없습니다\. 다시 시도해 주세요\z/, error.message)
      end

      assert invoice.reload.issued?
      assert_empty invoice.reload.promises
    end

    # ── F-REM — 발송 중단 계열 응답의 상태 마킹(PROMISE-7·VIEW-7·REM-7) ──

    test "paid_report 접수는 청구를 즉시 일시정지하고 U1 입금 회신 알림을 인큐한다 (PROMISE-7·REM-7)" do
      invoice = invoices(:delta_issued)

      travel_to(Time.zone.parse("2026-10-14 10:00")) do
        assert_enqueued_with job: Reminders::DeliverJob,
                             args: [ invoice.id, "noti_deposit_reply", "user" ] do
          RegisterService.new(invoice: invoice, kind: :paid_report).call
        end
      end

      assert invoice.reload.reminders_suspended?          # 마감은 U1 확인으로만(PROMISE-7)
      assert invoice.reload.issued?                       # 상태는 불변 — 정지일 뿐
      assert invoice.reminders_suspended_at.present?
    end

    test "paid_report 접수 후 자동 스캔은 채무자 발송을 하지 않는다 (PROMISE-7 — 오발송 차단)" do
      fake = FakeSolapiClient.new
      invoice = invoices(:delta_issued)

      travel_to(Time.zone.parse("2026-10-14 10:00")) do
        RegisterService.new(invoice: invoice, kind: :paid_report).call
        Reminders::DispatchService.new(client: fake).call
      end

      # 일시정지 청구는 스캔 모집합(reminders_dispatchable)에서 제외된다 — 다른 청구의
      # 정상 발송(fixture delta_due_soon의 만기 예정 안내)은 스캔이 계속 수행된다.
      assert_empty MessageLog.where(invoice_id: invoice.id, recipient_role: :debtor)
      assert_equal "BD-20260901-001", invoice.issue_number
      assert fake.calls.none? { |call| call[:variables]["청구서명"] == invoice.issue_number }
    end

    test "this_week에 주입된 약속일은 서버 산정값으로 저장된다 (PROMISE-2)" do
      invoice = invoices(:delta_issued)

      travel_to(Time.zone.parse("2026-10-14 09:00")) do
        promise = RegisterService.new(invoice: invoice, kind: :this_week,
                                      promised_on: Date.new(1999, 1, 1)).call
        assert_equal Date.new(2026, 10, 16), promise.reload.promised_on
      end
    end

    # ── F-REM — 수신 거부 전파(VIEW-7·Q30 — 같은 회원 안에서 번호 단위) ──

    test "refusal 접수는 같은 회원·같은 번호 거래처 전부에 거부를 전파한다 (VIEW-7·Q30)" do
      invoice = invoices(:delta_issued)                          # delta_main — 010-3333-7777
      sibling = users(:delta).clients.create!(name: "델타지점", contact_name: "덜지점",
                                              phone: "01033337777")            # 하이픈 없는 같은 번호
      other_number = users(:delta).clients.create!(name: "델타다른번호", contact_name: "덜다름",
                                                   phone: "010-8888-9999")

      travel_to(Time.zone.parse("2026-10-14 10:00")) do
        assert_enqueued_with job: Reminders::DeliverJob,
                             args: [ invoice.id, "noti_refusal", "user" ] do
          RegisterService.new(invoice: invoice, kind: :refusal).call
        end
      end

      assert invoice.client.reload.refused?                      # 접수 거래처 마킹(기존)
      assert_equal "01033337777", invoice.client.reload.refused_phone # 거부 시점 번호 저장
      assert sibling.reload.refused?                             # 하이픈 형식이 달라도 전파
      assert_equal invoice.client.reload.refused_at, sibling.reload.refused_at
      assert_equal "01033337777", sibling.reload.refused_phone   # 전파 행에도 거부 시점 번호 명시
      assert_not other_number.reload.refused?                    # 다른 번호는 무영향
      assert_nil other_number.reload.refused_phone
    end

    test "refusal 전파는 다른 회원의 같은 번호 거래처에는 영향을 주지 않는다 (VIEW-7·Q30)" do
      invoice = invoices(:delta_issued)                          # delta — 010-3333-7777
      stranger = users(:gamma).clients.create!(name: "감마동일번호", contact_name: "감동일",
                                               phone: "010-3333-7777")

      travel_to(Time.zone.parse("2026-10-14 10:00")) do
        RegisterService.new(invoice: invoice, kind: :refusal).call
      end

      assert invoice.client.reload.refused?
      assert_not stranger.reload.refused?                        # 회원 간 결합 금지
    end

    test "refusal 전파는 같은 회원의 다른 번호 거래처에는 영향을 주지 않는다 (VIEW-7·Q30)" do
      invoice = invoices(:delta_issued)
      same_user_other_number = users(:delta).clients.create!(name: "델타다른번호", contact_name: "덜다름",
                                                             phone: "010-8888-9999")

      travel_to(Time.zone.parse("2026-10-14 10:00")) do
        RegisterService.new(invoice: invoice, kind: :refusal).call
      end

      assert invoice.client.reload.refused?
      assert_not same_user_other_number.reload.refused?
    end

    test "refusal 전파는 같은 회원·같은 번호의 여러 건을 전부 마킹한다 (VIEW-7·Q30 — 리뷰 W-5·Tester 제안 2)" do
      invoice = invoices(:delta_issued)                          # delta_main — 010-3333-7777
      siblings = 3.times.map do |index|
        users(:delta).clients.create!(name: "델타형제#{index}", contact_name: "덜형제",
                                      phone: index.even? ? "01033337777" : "010-3333-7777")
      end

      travel_to(Time.zone.parse("2026-10-14 10:00")) do
        RegisterService.new(invoice: invoice, kind: :refusal).call
      end

      siblings.each do |sibling|
        assert sibling.reload.refused?, "#{sibling.name}이(가) 전파 누락됐다"
        assert_equal invoice.client.reload.refused_at, sibling.reload.refused_at
        assert_equal "01033337777", sibling.reload.refused_phone # 전파 행 전수 refused_phone 보장
      end
    end

    test "refusal 전파는 이미 거부된 형제의 접수 시각을 덮지 않는다 (VIEW-7·Q30 — 리뷰 W-5①)" do
      invoice = invoices(:delta_issued)
      earlier = users(:delta).clients.create!(name: "먼저거부 형제", contact_name: "덜먼저",
                                              phone: "010-3333-7777")
      earlier_at = Time.zone.parse("2026-10-01 09:00")
      earlier.update_column(:refused_at, earlier_at)

      travel_to(Time.zone.parse("2026-10-14 10:00")) do
        RegisterService.new(invoice: invoice, kind: :refusal).call
      end

      assert_equal earlier_at, earlier.reload.refused_at         # 선(先) 접수 시각 유지
      assert_equal Time.zone.parse("2026-10-14 10:00"), invoice.client.reload.refused_at
    end

    test "refusal 재접수는 멱등이다 — refused_at이 갱신되지 않는다 (VIEW-7·Q30 — 리뷰 제안 2)" do
      invoice = invoices(:delta_issued)

      travel_to(Time.zone.parse("2026-10-14 10:00")) do
        RegisterService.new(invoice: invoice, kind: :refusal).call
      end
      first_refused_at = invoice.client.reload.refused_at

      travel_to(Time.zone.parse("2026-10-15 10:00")) do
        RegisterService.new(invoice: invoice, kind: :refusal).call  # 같은 번호 재접수(의사 재확인)
      end

      assert_equal first_refused_at, invoice.client.reload.refused_at  # 접수 시각 불변
      assert invoice.reload.sequence_finished?                       # 종결 마킹도 유지
    end

    test "번호를 바꾼 거부 행의 재접수는 현재 번호만 전파하고 거부 시점 번호는 불변이다 (VIEW-7·Q30 — 리뷰 Tester 1·5-d)" do
      invoice = invoices(:delta_issued)                              # delta_main — 010-3333-7777(A)
      refused_at = Time.zone.parse("2026-10-14 10:00")
      # 형제를 먼저 만든다(거부 마킹 전 — 상속 콜백에 걸리지 않게)
      sibling_a = users(:delta).clients.create!(name: "옛번호 형제", contact_name: "덜옛번호",
                                                phone: "010-3333-7777")          # 번호 A
      sibling_b = users(:delta).clients.create!(name: "새번호 형제", contact_name: "덜새번호",
                                                phone: "010-8888-9999")          # 번호 B
      invoice.client.update_columns(refused_at: refused_at, refused_phone: "01033337777")
      invoice.client.update_column(:phone, "010-8888-9999")        # 거부 상태로 번호 이동(A→B)

      travel_to(Time.zone.parse("2026-10-20 10:00")) do
        assert_enqueued_with job: Reminders::DeliverJob,
                             args: [ invoice.id, "noti_refusal", "user" ] do
          RegisterService.new(invoice: invoice, kind: :refusal).call  # B 링크에서의 재접수
        end
      end

      assert_equal refused_at, invoice.client.reload.refused_at      # 접수 마킹 스킵 — 불변
      assert_equal "01033337777", invoice.client.reload.refused_phone # 거부 시점 번호(A)도 불변
      assert sibling_b.reload.refused?                               # 현재 번호(B)만 전파 대상
      assert_equal Time.zone.parse("2026-10-20 10:00"), sibling_b.reload.refused_at
      assert_equal "01088889999", sibling_b.reload.refused_phone     # 전파 행의 거부 시점 번호 = B
      assert_not sibling_a.reload.refused?                           # 번호 A 행은 무영향
      assert_nil sibling_a.reload.refused_phone
    end

    test "refusal 전파로 거부된 거래처의 다른 청구 발송은 REFUSED skip으로 기록된다 (VIEW-7·Q30·P4)" do
      fake = FakeSolapiClient.new
      invoice = invoices(:delta_issued)                              # delta_main — 010-3333-7777
      sibling = users(:delta).clients.create!(name: "델타전파 형제", contact_name: "덜전파",
                                              phone: "010-3333-7777")
      sibling_invoice = create_reminder_invoice(user: users(:delta), client: sibling,
                                                due_on: Date.new(2026, 11, 9))

      travel_to(Time.zone.parse("2026-10-14 10:00")) do
        RegisterService.new(invoice: invoice, kind: :refusal).call
      end

      assert sibling.reload.refused?                                 # 전파 마킹
      travel_to(Time.zone.parse("2026-10-15 10:00")) do              # 평일 창 내 — 가드만 판정한다
        result = Reminders::SendService.new(invoice: sibling_invoice, template_key: "confirm_d1",
                                            recipient_role: :debtor, client: fake).call
        assert_equal :skipped, result
      end

      skip_log = MessageLog.where(invoice_id: sibling_invoice.id, recipient_role: :debtor).sole
      assert_predicate skip_log, :skipped?
      assert_equal "REFUSED", skip_log.error_code                    # P4 — 스킵도 발송 이력이다
      assert_empty fake.calls                                        # 실발송 0건
    end

    test "전파 뒤 트랜잭션이 실패하면 접수·전파 마킹이 함께 롤백된다 (VIEW-7·Q30 — 같은 트랜잭션·리뷰 제안 2)" do
      invoice = invoices(:delta_issued)
      sibling = users(:delta).clients.create!(name: "델타롤백", contact_name: "덜롤백",
                                              phone: "010-3333-7777")
      invoice.define_singleton_method(:finish_sequence!) do
        raise ActiveRecord::ActiveRecordError, "종결 강제 실패"
      end

      assert_raises(ActiveRecord::ActiveRecordError) do
        RegisterService.new(invoice: invoice, kind: :refusal).call
      end

      assert_not invoice.client.reload.refused?                  # 접수 마킹까지 원점 복귀
      assert_not sibling.reload.refused?                         # 전파분도 함께 폐기
      assert_empty invoice.reload.promises                       # promise 기록도 함께
    end
  end
end
