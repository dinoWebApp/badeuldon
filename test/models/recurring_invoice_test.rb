require "test_helper"

# 반복 청구 스케줄 모델 테스트(INV-7) — day_of_month 1~28 한정·거래처 소유권 격리·품목 필수·
# next_issue_on 초기화(당월 잔여일/다음 달 경계)·advance!/hold! 커서 갱신·due_or_overdue 스코프.
# 시간 의존 검증은 travel_to로 KST를 고정한다(TIME-1). 외부 API 호출 없음.
class RecurringInvoiceTest < ActiveSupport::TestCase
  fixtures :users, :clients

  def setup
    @user = users(:gamma)
    @client = @user.clients.create!(name: "정기거래처", contact_name: "박담당", phone: "010-1234-5678")
  end

  def build_schedule(day: 10)
    RecurringInvoice.new(user: @user, client: @client, day_of_month: day).tap do |schedule|
      schedule.items.build(name: "월정액", quantity: 1, unit_price: 100_000)
    end
  end

  # 발행 완료 상태의 실제 Invoice — issue! 재사용(채번·토큰·만기 재계산 전부 실제 경로)
  def issue_invoice(user: @user, client: @client)
    invoice = Invoice.new(
      user: user, client: client, due_on: Date.current + Invoice::DEFAULT_DUE_IN_DAYS,
      issuer_display_name: user.display_name, bank_name: user.bank_name,
      account_number: user.account_number, account_holder: user.account_holder
    )
    invoice.items.build(description: "월정액", quantity: 1, unit_price: 100_000)
    assert invoice.issue!, invoice.errors.full_messages.join(", ")
    invoice
  end

  test "검증 — day_of_month는 1~28 한정(29 이상 차단)" do
    assert build_schedule(day: 1).valid?
    assert build_schedule(day: 28).valid?
    [ 0, 29, 31 ].each do |invalid|
      schedule = build_schedule(day: invalid)
      assert_not schedule.valid?
      assert schedule.errors[:day_of_month].present?
    end
  end

  test "검증 — 타인 거래처는 소유권 격리로 차단한다" do
    other_client = users(:delta).clients.first
    schedule = build_schedule
    schedule.client = other_client
    assert_not schedule.valid?
    assert schedule.errors[:client_id].present?
  end

  test "검증 — 품목 행은 1개 이상 필수" do
    schedule = RecurringInvoice.new(user: @user, client: @client, day_of_month: 10)
    assert_not schedule.valid?
    assert schedule.errors[:base].present?
  end

  test "next_issue_on 초기화 — 당월 N일이 남아 있으면 당월에 시작한다" do
    travel_to(Time.zone.parse("2026-11-05 07:00")) do
      schedule = build_schedule(day: 10)
      schedule.initialize_next_issue_on!
      assert_equal Date.new(2026, 11, 10), schedule.next_issue_on
    end
  end

  test "next_issue_on 초기화 — 당월 N일이 지났으면 다음 달 N일" do
    travel_to(Time.zone.parse("2026-11-11 07:00")) do
      schedule = build_schedule(day: 10)
      schedule.initialize_next_issue_on!
      assert_equal Date.new(2026, 12, 10), schedule.next_issue_on
    end
  end

  test "advance! — last_issued_on·last_invoice를 남기고 다음 달 N일로 이동한다(월 경계)" do
    schedule = build_schedule(day: 28)
    schedule.save!
    travel_to(Time.zone.parse("2026-11-28 07:00")) do
      schedule.advance!(issue_invoice)
      assert_equal Date.new(2026, 11, 28), schedule.last_issued_on
      assert_equal Date.new(2026, 12, 28), schedule.next_issue_on  # 월 경계 — 28일은 항상 존재
      assert_nil schedule.last_skip_reason
    end
  end

  test "hold! — 사유를 기록하고 발행일 커서만 다음 달로 이동한다" do
    schedule = build_schedule(day: 10)
    schedule.save!
    travel_to(Time.zone.parse("2026-11-10 07:00")) do
      # 커서 기준은 구값(next_issue_on) — 당일 발행 상태를 명시한 뒤 hold한다
      schedule.update!(next_issue_on: Date.current)
      schedule.hold!("직전 청구 미수금")
      assert_equal "직전 청구 미수금", schedule.last_skip_reason
      assert_equal Date.new(2026, 12, 10), schedule.next_issue_on
      assert_nil schedule.last_issued_on
    end
  end

  test "due_or_overdue — 발행일이 오늘 또는 경과한 이용 중 스케줄만 반환한다(C-2 완화)" do
    travel_to(Time.zone.parse("2026-11-10 07:00")) do
      due = build_schedule(day: 10)
      due.save!
      due.update!(next_issue_on: Date.current)  # 등록일 == 발행일이면 초기화가 다음 달로 미루므로 당일 발행 상태를 명시
      stalled = build_schedule(day: 10)
      stalled.save!
      stalled.update!(next_issue_on: Date.current - 3)  # 3일 미실행 커서 고착
      paused = build_schedule(day: 10)
      paused.save!
      paused.update!(status: :paused, next_issue_on: Date.current)
      future = build_schedule(day: 10)
      future.save!
      future.update!(next_issue_on: Date.current + 1)

      assert_includes RecurringInvoice.due_or_overdue, due
      assert_includes RecurringInvoice.due_or_overdue, stalled
      assert_not_includes RecurringInvoice.due_or_overdue, paused
      assert_not_includes RecurringInvoice.due_or_overdue, future
    end
  end
end
