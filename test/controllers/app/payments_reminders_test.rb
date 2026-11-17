require "test_helper"

# 입금 기록 F-REM 연동 통합 테스트(PAY-4·PAY-2·REM-6) — 감사 알림 옵션(send_thanks)의
# 기본 켬 해석(파라미터 부재)·해제·부분입금 안내는 옵션 무관 발송, 422 재렌더의 발송 이력
# 컨텍스트(RemindersContext) 적재. 시나리오 기준: _workspace/03_implementation.md 3-b
# PAY-4 매핑, _workspace/05_review.md §Tester 중점 1(B-1 회귀 — 인큐 경로).
# 잡 인큐만 검증하고 perform은 하지 않는다(발송 경로는 서비스·잡 테스트가 stub으로 담당).
class App::PaymentsRemindersTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  fixtures :users, :clients, :invoices, :promises

  test "원클릭 마감은 send_thanks 미전송(구폼)도 감사 알림을 인큐한다 (PAY-4 — 기본 켬 해석)" do
    sign_in_as users(:delta)
    invoice = invoices(:delta_issued)

    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      assert_enqueued_with job: Reminders::DeliverJob,
                           args: [ invoice.id, "paid_thanks", "debtor" ] do
        post app_invoice_payments_path(invoice), params: { payment: { paid_on: "2026-10-12" } }
        assert_response :see_other
      end
    end
    assert invoice.reload.paid?
  end

  test "send_thanks 해제는 감사 알림을 인큐하지 않는다 (PAY-4 — 선택 옵션)" do
    sign_in_as users(:delta)
    invoice = invoices(:delta_viewed)

    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      post app_invoice_payments_path(invoice),
           params: { payment: { amount: "55000", paid_on: "2026-10-12", send_thanks: "0" } }
      assert_response :see_other
    end

    assert invoice.reload.paid?
    # 부분입금이 아닌 전액 마감이므로 어떤 발송 잡도 인큐되지 않았다
    assert_no_enqueued_jobs only: Reminders::DeliverJob
  end

  test "부분입금은 send_thanks와 무관하게 잔액 안내를 인큐한다 (REM-4·PAY-2)" do
    sign_in_as users(:delta)
    invoice = invoices(:delta_viewed)

    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      assert_enqueued_with job: Reminders::DeliverJob,
                           args: [ invoice.id, "partial_paid", "debtor" ] do
        post app_invoice_payments_path(invoice),
             params: { payment: { amount: "20000", paid_on: "2026-10-12", send_thanks: "0" } }
        assert_response :see_other
      end
    end
    assert invoice.reload.partially_paid?
  end

  test "마감 본 재등록(Q22 — 기록만 추가)은 어떤 발송 잡도 인큐하지 않는다 (Q22·P4)" do
    # Q22(2026-11-16): 마감(paid) 후 재입금은 상태 불변·알림 발화 없음 — 기록만 추가된다.
    sign_in_as users(:delta)
    invoice = invoices(:delta_paid)

    assert_no_enqueued_jobs only: Reminders::DeliverJob do
      post app_invoice_payments_path(invoice),
           params: { payment: { amount: "10000", paid_on: "2026-10-12" } }
    end
    assert_response :see_other
    assert invoice.reload.paid?
    assert_equal 1, invoice.payments.count
  end
end
