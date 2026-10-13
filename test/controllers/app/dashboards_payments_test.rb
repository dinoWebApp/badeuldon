require "test_helper"

# DASH-1·2 잔액 재계산(F-PAY) — 부분입금·마감이 대시보드 카드 수치·액션·목록에 그대로 반영되는지
# HTTP 마감 경로(POST payments)로 검증한다. 집계 산식 = Σ총액 − Σ입금액(모집단 서브쿼리 한정).
# 시나리오 기준: _workspace/03_implementation.md §3, _workspace/05_review.md 잔액 계산 검증표·
# Tester 중점 5. 기준일 2026-10-12(KST) 고정 — fixtures 미수 총액 기준값 946,000원·연체 2건
# 385,000원·7일 내 만기 1건(TIME-1). 외부 API 호출 없음.
class App::DashboardsPaymentsTest < ActionDispatch::IntegrationTest
  fixtures :users, :clients, :invoices, :promises

  test "부분입금 후 미수 총액·연체 금액은 잔액 기준으로 반영된다 (DASH-1·PAY-2)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      # 파생 연체 청구서(delta_issued — 총액 220,000원)에 100,000원 부분입금
      post app_invoice_payments_path(invoices(:delta_issued)),
           params: { payment: { amount: "100000", paid_on: "2026-10-10" } }
      assert_response :see_other

      get app_root_path
      assert_response :success

      assert_select "article", text: /미수 총액/ do
        assert_select "p", text: "846,000원", count: 1              # 946,000 − 100,000
      end
      assert_select "article", text: /연체 건수·금액/ do
        assert_select "p", text: "2건", count: 1                    # 건수 불변 — 잔액만 감소
        assert_select "span", text: "285,000원", count: 1           # 385,000 − 100,000
      end
    end
  end

  test "원클릭 마감(paid) 청구서는 미수·7일 내 만기·목록에서 제외된다 (DASH-1·DASH-4)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      # 7일 내 만기(delta_due_soon — 총액 66,000원, 만기 2026-10-15)를 원클릭 마감
      post app_invoice_payments_path(invoices(:delta_due_soon)),
           params: { payment: { paid_on: "2026-10-12" } }
      assert_response :see_other

      get app_root_path
      assert_response :success

      assert_select "article", text: /미수 총액/ do
        assert_select "p", text: "880,000원", count: 1              # 946,000 − 66,000
      end
      assert_select "article", text: /7일 내 만기/ do
        assert_select "p", text: "0건", count: 1                    # 마감으로 소멸
      end
      assert_no_match(/BD-20261001-001/, response.body)             # DASH-4 목록 제외
      assert_match(/BD-20260915-001/, response.body)                # 상위 5건 재편입(부분입금 건)
    end
  end

  test "마감 대기 청구서를 원클릭 마감하면 DASH-2 카드가 소멸한다 (DASH-2·PROMISE-7)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      get app_root_path
      assert_select "article", text: /마감 대기/, count: 1           # 사전 조건 — paid_report 회신

      # 실제 마감 경로(POST payments)로 paid 전이 — 직접 상태 세팅이 아닌 U1 확인 플로우
      post app_invoice_payments_path(invoices(:delta_partially_paid)),
           params: { payment: { paid_on: "2026-10-12" } }
      assert_response :see_other

      get app_root_path
      assert_select "article", text: /마감 대기/, count: 0           # unsettled 제외 — 소멸
      assert_select "article", text: /미수 총액/ do
        assert_select "p", text: "616,000원", count: 1              # 946,000 − 330,000
      end
    end
  end

  test "무효 처리된 청구서의 입금 이력은 집계에서 차감하지 않는다 (DASH-1 — 차감 비대칭 없음)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      invoice = invoices(:delta_viewed)                              # 총액 55,000원

      post app_invoice_payments_path(invoice),
           params: { payment: { amount: "20000", paid_on: "2026-10-10" } }
      assert_response :see_other

      patch void_app_invoice_path(invoice)
      assert_response :see_other
      assert invoice.reload.voided?
      assert_equal 1, invoice.payments.count                        # 이력은 보존(P4)

      get app_root_path
      assert_response :success
      # 무효 본은 모집단 제외 — 잔액(35,000원)도 입금(20,000원)도 미수 집계에 불포함
      assert_select "article", text: /미수 총액/ do
        assert_select "p", text: "891,000원", count: 1              # 946,000 − 55,000
      end
      assert_select "article", text: /연체 건수·금액/ do
        assert_select "span", text: "385,000원", count: 1           # 연체 금액 무영향
      end
    end
  end
end
