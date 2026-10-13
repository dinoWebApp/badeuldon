require "test_helper"

module Promises
  # 응답 접수 단일 진입점(F-PROMISE) — 4종 접수·INV-4 issued|viewed→promised 원자 전이·
  # PROMISE-7 상태 불변·종결 상태에서의 시도 처리(설계 의도 확인)·서버 재검증(결정 #3)·
  # 위조 kind 거부. 시나리오 기준: _workspace/03_implementation.md §2,
  # _workspace/05_review.md §검증표 5·7·8. 시간 의존 검증은 travel_to로 KST 고정(TIME-1).
  # 외부 API 호출 없음.
  class RegisterServiceTest < ActiveSupport::TestCase
    fixtures :invoices, :promises

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

    test "this_week에 주입된 약속일은 서버 산정값으로 저장된다 (PROMISE-2)" do
      invoice = invoices(:delta_issued)

      travel_to(Time.zone.parse("2026-10-14 09:00")) do
        promise = RegisterService.new(invoice: invoice, kind: :this_week,
                                      promised_on: Date.new(1999, 1, 1)).call
        assert_equal Date.new(2026, 10, 16), promise.reload.promised_on
      end
    end
  end
end
