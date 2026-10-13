require "test_helper"

# Promise 모델(F-PROMISE) — kind별 검증·정규화(Phase 6 #1)·「이번 주」 금요일 서버 산정
# (결정 #1)·과거 예정일 차단(결정 #3)·답변 등록(1문의 1답변 — PROMISE-6)·답변 상태 스코프.
# 시나리오 기준: _workspace/03_implementation.md §2, _workspace/05_review.md §3·§4. 시간 의존
# 검증은 travel_to로 KST 기준 주(2026-10-12~18)를 고정한다(TIME-1). 외부 API 호출 없음.
class PromiseTest < ActiveSupport::TestCase
  fixtures :invoices, :promises

  # ── 결정 #1 — this_week 약속일은 서버가 KST 접수일 기준으로 산정한다(TIME-1) ──

  test "월요일 접수 this_week는 이번 주 금요일로 산정된다 (PROMISE-1·TIME-1)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      promise = invoices(:delta_issued).promises.build(kind: :this_week)
      assert promise.valid?
      assert_equal Date.new(2026, 10, 16), promise.promised_on
    end
  end

  test "수요일 접수 this_week는 이번 주 금요일로 산정된다 (결정 #1)" do
    travel_to(Time.zone.parse("2026-10-14 09:00")) do
      promise = invoices(:delta_issued).promises.build(kind: :this_week)
      assert promise.valid?
      assert_equal Date.new(2026, 10, 16), promise.promised_on
    end
  end

  test "금요일 접수 this_week는 당일 금요일로 산정된다 (당일 경계)" do
    travel_to(Time.zone.parse("2026-10-16 09:00")) do
      promise = invoices(:delta_issued).promises.build(kind: :this_week)
      assert promise.valid?
      assert_equal Date.current, promise.promised_on
    end
  end

  test "토요일 접수 this_week는 다음 주 금요일로 산정된다 (결정 #1)" do
    travel_to(Time.zone.parse("2026-10-17 09:00")) do
      promise = invoices(:delta_issued).promises.build(kind: :this_week)
      assert promise.valid?
      assert_equal Date.new(2026, 10, 23), promise.promised_on
    end
  end

  test "일요일 접수 this_week도 다음 주 금요일로 산정된다 (결정 #1)" do
    travel_to(Time.zone.parse("2026-10-18 09:00")) do
      promise = invoices(:delta_issued).promises.build(kind: :this_week)
      assert promise.valid?
      assert_equal Date.new(2026, 10, 23), promise.promised_on
    end
  end

  test "산정된 약속일은 주말이 될 수 없다 (REM-3 평일 발송 정합)" do
    [ "2026-10-12", "2026-10-17" ].each do |day|
      travel_to(Time.zone.parse("#{day} 09:00")) do
        promise = invoices(:delta_issued).promises.build(kind: :this_week)
        assert promise.valid?
        assert_not promise.promised_on.saturday?
        assert_not promise.promised_on.sunday?
      end
    end
  end

  test "this_week에 주입된 약속일은 서버 산정값으로 덮어써진다 (PROMISE-2)" do
    travel_to(Time.zone.parse("2026-10-14 09:00")) do
      promise = invoices(:delta_issued).promises.build(kind: :this_week, promised_on: Date.new(1999, 1, 1))
      assert promise.valid?
      assert_equal Date.new(2026, 10, 16), promise.promised_on
    end
  end

  # ── date_selected — 채무자 지정 약속일(결정 #3: 당일 허용·어제 이전 차단) ──

  test "date_selected는 당일 약속일을 허용한다 (결정 #3 경계)" do
    travel_to(Time.zone.parse("2026-10-16 09:00")) do
      promise = invoices(:delta_issued).promises.build(kind: :date_selected, promised_on: Date.current)
      assert promise.valid?
    end
  end

  test "date_selected는 어제 이전 약속일을 차단한다 (서버 재검증 — min 속성 우회 대비)" do
    travel_to(Time.zone.parse("2026-10-16 09:00")) do
      promise = invoices(:delta_issued).promises.build(kind: :date_selected, promised_on: Date.current - 1)
      assert_not promise.valid?
      assert_includes promise.errors[:promised_on], "입금 예정일은 오늘 또는 그 이후 날짜로 선택해 주세요"
    end
  end

  test "date_selected는 약속일 없이 접수될 수 없다" do
    promise = invoices(:delta_issued).promises.build(kind: :date_selected)
    assert_not promise.valid?
    assert_includes promise.errors[:promised_on], "입금 예정일을 선택해 주세요"
  end

  # ── inquiry — 자유 메모(플랜 결정 #3 상한) ──

  test "inquiry는 메모 없이 접수될 수 없다" do
    promise = invoices(:delta_issued).promises.build(kind: :inquiry, memo: "   ")
    assert_not promise.valid?
    assert_includes promise.errors[:memo], "문의 내용을 입력해 주세요"
  end

  test "메모는 2,000자까지 허용된다 (MEMO_MAX_LENGTH 경계)" do
    promise = invoices(:delta_issued).promises.build(kind: :inquiry, memo: "가" * Promise::MEMO_MAX_LENGTH)
    assert promise.valid?
  end

  test "메모는 2,000자를 초과할 수 없다 (MEMO_MAX_LENGTH 초과)" do
    promise = invoices(:delta_issued).promises.build(kind: :inquiry, memo: "가" * (Promise::MEMO_MAX_LENGTH + 1))
    assert_not promise.valid?
    assert promise.errors.key?(:memo)
  end

  # ── kind별 필드 정규화(Phase 6 리뷰 #1) — kind에 맞지 않는 클라이언트 입력 무시 ──

  test "paid_report에 주입된 약속일·메모는 모두 무시된다 (PROMISE-2 보조)" do
    promise = invoices(:delta_issued).promises.build(
      kind: :paid_report, promised_on: Date.new(2026, 12, 1), memo: "위조 메모"
    )
    assert promise.valid?
    assert_nil promise.promised_on
    assert_nil promise.memo
  end

  test "inquiry에 주입된 약속일은 무시되고 메모는 보존된다 (Phase 6 #1)" do
    promise = invoices(:delta_issued).promises.build(
      kind: :inquiry, promised_on: Date.new(2026, 12, 1), memo: "진짜 문의"
    )
    assert promise.valid?
    assert_nil promise.promised_on
    assert_equal "진짜 문의", promise.memo
  end

  test "this_week에 주입된 메모는 무시되고 약속일은 서버 산정으로 유지된다 (Phase 6 #1)" do
    travel_to(Time.zone.parse("2026-10-14 09:00")) do
      promise = invoices(:delta_issued).promises.build(
        kind: :this_week, promised_on: Date.new(1999, 1, 1), memo: "위조 메모"
      )
      assert promise.valid?
      assert_equal Date.new(2026, 10, 16), promise.promised_on
      assert_nil promise.memo
    end
  end

  test "date_selected에 주입된 메모는 무시되고 지정 약속일은 보존된다 (Phase 6 #1)" do
    travel_to(Time.zone.parse("2026-10-16 09:00")) do
      promise = invoices(:delta_issued).promises.build(
        kind: :date_selected, promised_on: Date.current, memo: "위조 메모"
      )
      assert promise.valid?
      assert_equal Date.current, promise.promised_on
      assert_nil promise.memo
    end
  end

  # ── answer! — 1문의 1답변(PROMISE-6), answered_at의 유일 기록 경로 ──

  test "무답변 문의에 답변하면 내용과 answered_at이 기록된다 (PROMISE-6)" do
    inquiry = promises(:delta_unanswered_inquiry)
    travel_to(Time.zone.parse("2026-10-15 11:00")) do
      assert inquiry.answer!("변경된 계좌로 입금해 주셔도 됩니다.")
    end

    assert_not_nil inquiry.reload.answered_at
    assert_equal "변경된 계좌로 입금해 주셔도 됩니다.", inquiry.reload.answer
    assert_equal Time.zone.parse("2026-10-15 11:00"), inquiry.answered_at
  end

  test "답변한 문의에는 다시 답변할 수 없다 (1문의 1답변 — PROMISE-6)" do
    inquiry = promises(:delta_answered_inquiry)
    answered_at = inquiry.answered_at

    assert_not inquiry.answer!("두 번째 답변")
    assert_includes inquiry.errors[:base], "문의에는 한 번만 답변할 수 있습니다"
    assert_equal "청구 총액에 부가세가 포함된 금액입니다.", inquiry.reload.answer  # 기존 답변 불변
    assert_equal answered_at, inquiry.reload.answered_at
  end

  test "문의가 아닌 응답은 답변 대상이 아니다 (PROMISE-6)" do
    paid_report = promises(:delta_paid_report_promise)

    assert_not paid_report.answer!("입금 확인했습니다")
    assert_includes paid_report.errors[:base], "문의에는 한 번만 답변할 수 있습니다"
    assert_nil paid_report.reload.answer
  end

  test "빈 답변은 기록되지 않는다 (PROMISE-6)" do
    inquiry = promises(:delta_unanswered_inquiry)

    assert_not inquiry.answer!("")
    assert_includes inquiry.errors[:answer], "답변 내용을 입력해 주세요"
    assert_nil inquiry.reload.answered_at
  end

  # ── 답변 상태 스코프(PROMISE-6 — 뷰어 표시·DASH-2 답변 대기) ──

  test "answered·unanswered 스코프는 답변 상태로 정확히 분류한다 (PROMISE-6)" do
    answered_ids = Promise.answered.map(&:id)
    assert_includes answered_ids, promises(:delta_answered_inquiry).id
    assert_not_includes answered_ids, promises(:delta_unanswered_inquiry).id

    unanswered_ids = Promise.unanswered.map(&:id)
    assert_includes unanswered_ids, promises(:delta_unanswered_inquiry).id
    assert_not_includes unanswered_ids, promises(:delta_answered_inquiry).id
  end
end
