require "test_helper"

# 입금 모델(F-PAY — PAY-1·2) 단위 테스트 — 금액·입금일 검증과 DB CHECK 이중 방어.
# 기록·전이·잔액 재검증 같은 서비스 규칙은 컨트롤러 통합(test/controllers/app/payments_controller_test.rb)과
# 실스레드 동시성(test/integration/payments_concurrency_test.rb)이 HTTP 계층에서 담당한다.
# 시나리오 기준: _workspace/03_implementation.md §3, _workspace/05_review.md 금액 무결성 검증표.
class PaymentTest < ActiveSupport::TestCase
  fixtures :users, :clients, :invoices

  AMOUNT_MESSAGE = "입금 금액은 1원 이상 #{Payment::MAX_AMOUNT}원 이하로 입력해 주세요"

  test "금액은 양의 정수면 유효하다 (PAY-2)" do
    payment = invoices(:delta_issued).payments.build(amount: 10_000, paid_on: Date.current)
    assert payment.valid?
  end

  test "금액이 빈 값이면 입력 안내로 거부된다 (전액 승격 금지 — Phase 6)" do
    payment = invoices(:delta_issued).payments.build(amount: "", paid_on: Date.current)
    assert_not payment.valid?
    assert_includes payment.errors[:amount], "입금 금액을 입력해 주세요"
  end

  test "0·음수·소수·쉼표 금액은 수치 안내로 거부된다" do
    %w[0 -1 1.5 10,000].each do |amount|
      payment = invoices(:delta_issued).payments.build(amount: amount, paid_on: Date.current)
      assert_not payment.valid?, "금액 #{amount.inspect}는 거부되어야 한다"
      assert_includes payment.errors[:amount], AMOUNT_MESSAGE
    end
  end

  test "상한 10억 초과 금액은 거부된다 (입력 폭주 방지선)" do
    payment = invoices(:delta_issued).payments.build(amount: Payment::MAX_AMOUNT + 1, paid_on: Date.current)
    assert_not payment.valid?
    assert_includes payment.errors[:amount], AMOUNT_MESSAGE
  end

  test "입금일은 당일·과거는 유효하고 미래는 거부된다 (TIME-1 — KST 기준)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      assert invoices(:delta_issued).payments.build(amount: 10_000, paid_on: Date.current).valid?
      assert invoices(:delta_issued).payments.build(amount: 10_000, paid_on: Date.current - 1).valid?

      payment = invoices(:delta_issued).payments.build(amount: 10_000, paid_on: Date.current + 1)
      assert_not payment.valid?
      assert_includes payment.errors[:paid_on], "입금일은 오늘 또는 그 이전 날짜로 선택해 주세요"
    end
  end

  test "입금일이 빈 값이면 입력 안내로 거부된다" do
    payment = invoices(:delta_issued).payments.build(amount: 10_000, paid_on: "")
    assert_not payment.valid?
    assert_includes payment.errors[:paid_on], "입금일을 입력해 주세요"
  end

  test "모델 검증 우회 원시 INSERT는 DB CHECK로 차단된다 (payments_amount_positive)" do
    error = assert_raises(ActiveRecord::StatementInvalid) do
      Payment.insert({ invoice_id: invoices(:delta_issued).id, amount: 0, paid_on: Date.current })
    end
    assert_match(/payments_amount_positive/, error.message)
  end
end
