require "test_helper"
require_relative "../../test_helpers/fake_solapi_client"
require_relative "../../test_helpers/solapi_stubbing"

# PAY-2 부분입금 정책 확정(Q22·Q23 — 2026-11-16) + B-1 회귀(재리뷰 최우선 지시) 통합 테스트.
# 4케이스(정상 부분입금·과다입금·마감 후 재입금·반복 부분입금) 전부 303(500 없음 — B-1 회귀),
# 과다입금은 잔액 0·paid·초과분 감사 기록(AuditLog payment_over_recorded)·플래시 오프라인 환불
# 안내, 마감 후 재입금은 기록만 추가(상태 불변·알림 0), partial_paid는 건마다 재발송(Q23 —
# 상한 집계 밖). PRD 근거: PAY-2·Q22·Q23 문언(02_prd_update.md).
# 플래시 검증은 follow_redirect! 대신 flash 접근을 쓴다 — paid 청구서 상세 렌더는
# tax_invoice_context 버그(07_test_report BUG-1)로 현재 500이라 회귀 격리를 위해 본문 미렌더.
class App::PaymentsOverPolicyTest < ActionDispatch::IntegrationTest
  fixtures :users, :clients, :invoices, :promises

  def record(invoice, amount:, paid_on: "2026-10-12", send_thanks: nil)
    params = { payment: { amount:, paid_on: } }
    params[:payment][:send_thanks] = send_thanks unless send_thanks.nil?
    post app_invoice_payments_path(invoice), params: params
  end

  # ── B-1 회귀 — 모든 입금 성공 경로 303 ──

  test "정상 부분입금은 303으로 접수되고 잔액을 재계산해 안내한다 (B-1 회귀·PAY-2)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      invoice = invoices(:delta_viewed)                   # 총액 55,000

      record invoice, amount: "20000"
      assert_response :see_other
      assert_redirected_to app_invoice_path(invoice)
      assert_match(/부분입금을 기록했습니다\. 남은 잔액은 35,000원입니다\./, flash[:notice])
      assert invoice.reload.partially_paid?
      assert_equal 35_000, invoice.remaining_amount
    end
  end

  test "정확한 잔액 마감은 기존 경로를 유지하고 초과분 비고를 남기지 않는다 (PAY-1·Q22 경계)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      invoice = invoices(:delta_viewed)

      record invoice, amount: "55000"
      assert_response :see_other                          # B-1 — 303(500 아님)
      assert invoice.reload.paid?
      assert_equal 0, invoice.remaining_amount
      assert_match(/수금을 마감했습니다/, flash[:notice])
      assert_no_match(/초과/, flash[:notice])
      assert_empty AuditLog.where(action: "payment_over_recorded", target_id: invoice.id)
    end
  end

  # ── Q22 — 과다입금 ──

  test "과다입금은 실입금액을 기록하고 잔액 0·paid 마감·초과분 감사 기록·오프라인 환불 안내를 남긴다 (Q22)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      invoice = invoices(:delta_issued)                   # 총액 220,000

      record invoice, amount: "250000"
      assert_response :see_other                          # B-1 회귀 — 차단 폐기로 303
      assert invoice.reload.paid?
      assert_equal 250_000, invoice.payments.sole.amount  # 실제 입력 금액 기록
      assert_equal 0, invoice.remaining_amount            # 0 하한 클램프 — 음수 노출 금지

      assert_match(/남은 잔액을 30,000원 초과/, flash[:notice])   # W-5 정정 문언 — 잔액 기준
      assert_match(/환불은 거래처와 직접 조율/, flash[:notice])   # 오프라인 안내

      audit = AuditLog.find_by(action: "payment_over_recorded", target_id: invoice.id)
      assert_not_nil audit
      assert_equal "Invoice", audit.target_type
      assert_equal invoice.id, audit.target_id
      assert_match(/30,000원/, audit.detail)
    end
  end

  test "부분입금 누적 후의 과다입금도 초과분은 잔액 기준으로 산정된다 (Q22·W-5 경계)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      invoice = invoices(:delta_issued)

      record invoice, amount: "100000"                    # 잔액 120,000
      assert_response :see_other

      record invoice, amount: "140000"                    # 잔액 초과 20,000 — 총액 초과 아님
      assert_response :see_other
      assert invoice.reload.paid?
      assert_equal 240_000, invoice.payments.sum(:amount)
      assert_equal 0, invoice.remaining_amount
      assert_match(/남은 잔액을 20,000원 초과/, flash[:notice])
    end
  end

  # ── Q22 — 마감 후 재입금(기록만·상태 불변·알림 없음) ──

  test "마감(paid) 후 재입금은 payments 기록만 추가하고 상태·알림이 불변이다 (Q22)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      invoice = invoices(:delta_paid)                     # 이미 paid — payments 0건

      assert_no_enqueued_jobs only: Reminders::DeliverJob do
        record invoice, amount: "10000"
      end
      assert_response :see_other                          # B-1 회귀 — 422 폐기로 303
      assert invoice.reload.paid?                         # 상태 불변
      assert_equal 1, invoice.payments.count              # 기록만 추가(P4)
      assert_equal 10_000, invoice.payments.sole.amount
      assert_match(/수금 상태는 수금완료로 유지됩니다/, flash[:notice])
      assert_empty AuditLog.where(action: "payment_over_recorded", target_id: invoice.id)  # 초과분 개념 부적용
    end
  end

  test "마감 후 재입금의 amount 미전송(원클릭 — 잔액 0 상태)은 422로 흡수되고 미기록이다 (Q22 경계)" do
    # T8 경계 정의: 마감 후 재입금 amount nil → remain 0 → Payment 금액 검증("입금 금액 미입력") 422.
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      invoice = invoices(:delta_paid)
      # delta_paid fixture는 payments 0건(paid 상태만 세팅) — 잔액 0 상태를 만든다
      invoice.payments.create!(amount: invoice.total_amount, paid_on: Date.current)

      assert_no_difference -> { invoice.reload.payments.count } do
        post app_invoice_payments_path(invoice), params: { payment: { paid_on: "2026-10-12" } }
      end
      assert_response :unprocessable_entity               # remain 0 → amount 0 → 검증 실패
    end
  end

  # ── Q23 — partial_paid 건마다 재발송 ──

  test "반복 부분입금마다 partial_paid가 재발송된다 (Q23 — 1회성 차단 폐기)" do
    travel_to(Time.zone.parse("2026-10-12 10:00")) do     # 평일 발송 창 내(REM-3)
      sign_in_as users(:delta)
      invoice = invoices(:delta_issued)

      assert_enqueued_with job: Reminders::DeliverJob,
                           args: [ invoice.id, "partial_paid", "debtor" ] do
        record invoice, amount: "100000"
      end
      assert_response :see_other

      # 두 번째 부분입금 — 1회성 차단 없이 건마다 재발송(Q23)
      assert_enqueued_with job: Reminders::DeliverJob,
                           args: [ invoice.id, "partial_paid", "debtor" ] do
        record invoice, amount: "10000"
      end
      assert_response :see_other
      assert invoice.reload.partially_paid?
    end
  end

  test "partial_paid 반복 재발송은 수동 포함 총량 5통 하한 집계에 포함되지 않는다 (Q23·Q10/PLAN-3)" do
    invoice = invoices(:delta_issued)
    assert_not_includes MessageLog::SEQUENCE_TEMPLATE_KEYS, "partial_paid"  # 시퀀스 상한 집계 밖
  end

  # ── 금액 무결성 회귀 ──

  test "0·음수·미래 입금일은 422로 거부된다 (금액·날짜 무결성)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      invoice = invoices(:delta_issued)

      record invoice, amount: "0"
      assert_response :unprocessable_entity
      record invoice, amount: "-1000"
      assert_response :unprocessable_entity
      record invoice, amount: "1000", paid_on: "2026-10-13"
      assert_response :unprocessable_entity

      assert_equal 0, invoice.reload.payments.count
      assert invoice.reload.issued?
    end
  end
end
