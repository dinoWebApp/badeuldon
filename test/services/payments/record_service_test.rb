require "test_helper"

# Payments::RecordService — Q22 구조화(2026-11-20 T3): 과다입금 초과분을 마감 기록 자체
# (payments.note)에 남기는 행위를 서비스 계층에서 고정한다. with_lock 트랜잭션 안에서
# 기록·전이·비고가 함께 확정되고(P4), 감사 로그(payment_over_recorded)는 병행 유지된다.
# 정확한 마감·부분입금·마감 후 재입금은 note가 없음(초과분 마감 개념이 성립하지 않는 경로)
# — 리뷰 05_review.md §검증관찰 7의 반증 방어.
class Payments::RecordServiceTest < ActiveSupport::TestCase
  fixtures :users, :clients, :invoices

  test "과다입금은 초과분을 note에 구조화 기록하고 감사 로그를 병행한다 (Q22·P4)" do
    invoice = invoices(:delta_issued) # 총액 220,000
    service = Payments::RecordService.new(invoice:, amount: 250_000, paid_on: Date.current)

    payment = service.call

    assert invoice.reload.paid?
    assert_equal 250_000, payment.amount                     # 실제 입력 금액 원값 기록
    assert_not_nil payment.note, "초과분은 마감 기록 비고에 남는다(Q22 구조화)"
    assert_match(/남은 잔액을 30,000원 초과하여 마감 처리/, payment.note)
    assert_match(/초과분 환불은 거래처와 직접 협의/, payment.note)

    audit = AuditLog.find_by(action: "payment_over_recorded", target_type: "Invoice", target_id: invoice.id)
    assert_not_nil audit, "감사 로그 병행 유지(P4)"
    assert_match(/30,000원/, audit.detail)
  end

  test "정확한 잔액 마감은 note와 감사를 남기지 않는다 (Q22 경계·PAY-1)" do
    invoice = invoices(:delta_issued)
    payment = Payments::RecordService.new(invoice:, amount: 220_000, paid_on: Date.current).call

    assert invoice.reload.paid?
    assert_nil payment.note
    assert_empty AuditLog.where(action: "payment_over_recorded", target_type: "Invoice", target_id: invoice.id)
  end

  test "부분입금은 note를 남기지 않는다 (PAY-2)" do
    invoice = invoices(:delta_issued)
    payment = Payments::RecordService.new(invoice:, amount: 20_000, paid_on: Date.current).call

    assert invoice.reload.partially_paid?
    assert_nil payment.note
  end

  test "마감(paid) 후 재입금은 기록만 추가하고 note·감사가 없다 (Q22 상태 불변 경로)" do
    invoice = invoices(:delta_issued)
    Payments::RecordService.new(invoice:, amount: 250_000, paid_on: Date.current).call
    late = Payments::RecordService.new(invoice:, amount: 10_000, paid_on: Date.current).call

    assert_equal 2, invoice.payments.count
    assert invoice.reload.paid?                              # 상태 불변
    assert_nil late.note, "마감 후 재입금에는 초과분 마감 개념이 없다"
    assert_equal 1, AuditLog.where(action: "payment_over_recorded", target_type: "Invoice", target_id: invoice.id).count,
                 "감사는 첫 과다입금 마감 1회뿐"
  end
end
