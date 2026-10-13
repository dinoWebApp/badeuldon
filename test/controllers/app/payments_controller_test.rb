require "test_helper"

# 입금 기록·마감(F-PAY) 통합 테스트 — PAY-1 원클릭 마감(금액 필드 없는 제출)·이중 클릭 멱등(SEC),
# PAY-2 부분입금·잔액 재계산·누적 마감, 금액 무결성(0·음수·쉼표·빈 문자열·잔액 초과·미래 날짜),
# INV-4 상태 매트릭스(PAYABLE_STATUSES 전 전이 + draft·paid·voided 차단), Phase 6 수정 2건
# (0원 발행 차단·부분입금 폼 paid_on 오류 표시), §4 회귀 2건(issue!/void! 자동 저장·answer 재렌더),
# 소유권 격리. 시나리오 기준: _workspace/03_implementation.md §2·§4·Phase 6 수정 이력,
# _workspace/05_review.md 멱등·동시성 검증표·Tester 중점 7건.
# 날짜 파생 어설션은 travel_to 2026-10-12(KST) 기준일 고정(TIME-1). 실스레드 동시성 시나리오는
# test/integration/payments_concurrency_test.rb가 담당한다.
class App::PaymentsControllerTest < ActionDispatch::IntegrationTest
  fixtures :users, :clients, :invoices, :promises

  # ── 인증·소유권 ──

  test "비인증 입금 기록은 로그인 화면으로 리다이렉트되고 기록되지 않는다 (AUTH-1)" do
    assert_no_difference -> { Payment.count } do
      post app_invoice_payments_path(invoices(:delta_issued)),
           params: { payment: { paid_on: "2026-10-12" } }
    end
    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "타 사용자 청구서 입금 기록은 404로 격리된다 (소유권 — Current.user 스코프)" do
    sign_in_as users(:gamma)
    invoice = invoices(:delta_issued)

    assert_no_difference -> { Payment.count } do
      post app_invoice_payments_path(invoice),
           params: { payment: { amount: "100000", paid_on: "2026-10-10" } }
    end
    assert_response :not_found
    assert invoice.reload.issued?
    assert_equal 220_000, invoice.remaining_amount
  end

  # ── 원클릭 마감(PAY-1) ──

  test "원클릭 마감은 금액 필드 없이 제출해도 잔액 전액 1건으로 마감된다 (PAY-1)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      invoice = invoices(:delta_issued)

      # 폼에 금액 필드가 없어 amount 키 자체가 전송되지 않는다 — 서버가 잔액 기준값을 계산한다
      post app_invoice_payments_path(invoice), params: { payment: { paid_on: "2026-10-12" } }
      assert_response :see_other
      assert_redirected_to app_invoice_path(invoice)

      assert invoice.reload.paid?
      assert_equal 1, invoice.payments.count
      assert_equal 220_000, invoice.payments.sum(:amount)          # 잔액 전액 — 서버 계산
      assert_equal 0, invoice.remaining_amount
      assert_equal Date.new(2026, 10, 12), invoice.payments.sole.paid_on  # 입금일 기록(PAY-1)

      follow_redirect!
      assert_select "#notice", text: "수금을 마감했습니다. 수고하셨습니다!"
      assert_select "span", text: "수금 완료", count: 1             # 헤더 녹색 뱃지
      assert_select "p", text: "수금이 완료되었습니다", count: 1     # 확정 배너
      assert_select "p", text: "2026-10-12 입금 분까지 확인되어 마감했습니다.", count: 1
      assert_select "button", text: "입금 확인하고 마감", count: 0   # 폼 미노출
      assert_select "p", text: "부분입금 기록", count: 0
    end
  end

  test "이중 클릭 재현 — 두 번째 동일 요청은 422로 흡수되고 입금은 1건이다 (SEC 멱등)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      invoice = invoices(:delta_issued)

      post app_invoice_payments_path(invoice), params: { payment: { paid_on: "2026-10-12" } }
      assert_response :see_other

      # 동일 요청 2회 — 이중 클릭 두 번째
      post app_invoice_payments_path(invoice), params: { payment: { paid_on: "2026-10-12" } }
      assert_response :unprocessable_entity
      assert_select "#alert", text: "이미 수금이 마감된 청구서입니다"
    end

    invoice = invoices(:delta_issued)
    assert invoice.reload.paid?
    assert_equal 1, invoice.payments.count                          # 정확히 1건
    assert_equal 220_000, invoice.payments.sum(:amount)             # 이중 기록 0원
  end

  test "마감 본(paid) 재등록은 422이고 폼 대신 확정 배너를 렌더한다 (INV-4)" do
    sign_in_as users(:delta)
    invoice = invoices(:delta_paid)

    post app_invoice_payments_path(invoice),
         params: { payment: { amount: "10000", paid_on: "2026-10-12" } }
    assert_response :unprocessable_entity
    assert_select "#alert", text: "이미 수금이 마감된 청구서입니다"
    assert_equal 0, invoice.reload.payments.count

    get app_invoice_path(invoice)
    assert_response :success
    assert_select "p", text: "수금이 완료되었습니다", count: 1
    assert_select "button", text: "입금 확인하고 마감", count: 0
    assert_select "p", text: "부분입금 기록", count: 0
  end

  # ── 부분입금(PAY-2) ──

  test "부분입금은 303으로 접수되고 잔액을 재계산해 안내한다 (PAY-2)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      # delta_viewed(총액 55,000원, 만기 2026-10-20) — 만기 미경과로 파생 연체 분기가 없어
      # 부분입금 뱃지를 그대로 검증할 수 있다(delta_issued는 기준일에 파생 연체 표기가 우선한다).
      invoice = invoices(:delta_viewed)

      post app_invoice_payments_path(invoice),
           params: { payment: { amount: "20000", paid_on: "2026-10-10" } }
      assert_response :see_other
      assert_redirected_to app_invoice_path(invoice)

      assert invoice.reload.partially_paid?
      assert_equal 1, invoice.payments.count
      assert_equal 20_000, invoice.payments.sum(:amount)
      assert_equal 35_000, invoice.remaining_amount

      follow_redirect!
      assert_select "#notice", text: "부분입금을 기록했습니다. 남은 잔액은 35,000원입니다."
      assert_select "span", text: "부분입금", count: 1              # 상태 뱃지
      assert_select "dd", text: "35,000원", count: 1                # 잔액 표시
      assert_select "h3", text: "입금 이력"
      assert_select "li", text: /2026-10-10/                        # 입금 이력 기록
      assert_select "li", text: /20,000원/
    end
  end

  test "부분입금 누적 후 잔액 도달 시 마감된다 (PAY-2·INV-4)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      invoice = invoices(:delta_issued)

      post app_invoice_payments_path(invoice),
           params: { payment: { amount: "100000", paid_on: "2026-10-10" } }
      assert_response :see_other
      assert invoice.reload.partially_paid?

      post app_invoice_payments_path(invoice),
           params: { payment: { amount: "120000", paid_on: "2026-10-11" } }
      assert_response :see_other

      assert invoice.reload.paid?
      assert_equal 2, invoice.payments.count                        # 2회 부분입금 누적
      assert_equal 220_000, invoice.payments.sum(:amount)
      assert_equal 0, invoice.remaining_amount

      follow_redirect!
      assert_select "#notice", text: "수금을 마감했습니다. 수고하셨습니다!"
      assert_select "p", text: "2026-10-11 입금 분까지 확인되어 마감했습니다.", count: 1
      assert_select "p", text: "부분입금 기록", count: 0             # 마감 후 폼 미노출
    end
  end

  test "잔액 초과(잔액+1원) 기록은 422로 거부되고 상태·잔액이 불변이다 (결정 #3)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      invoice = invoices(:delta_issued)

      post app_invoice_payments_path(invoice),
           params: { payment: { amount: "100000", paid_on: "2026-10-10" } }
      assert_response :see_other

      post app_invoice_payments_path(invoice),
           params: { payment: { amount: "120001", paid_on: "2026-10-11" } }
      assert_response :unprocessable_entity
      assert_select "p", text: "입금 금액이 남은 잔액(120,000원)보다 큽니다. 잔액 이하로 입력해 주세요", count: 1
    end

    invoice = invoices(:delta_issued)
    assert invoice.reload.partially_paid?
    assert_equal 1, invoice.payments.count
    assert_equal 120_000, invoice.remaining_amount                  # 초과분 미반영
  end

  test "0·음수·쉼표·소수 금액은 422로 거부되고 미기록이다 (금액 무결성)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      %w[0 -1 1.5 10,000].each do |amount|
        post app_invoice_payments_path(invoices(:delta_issued)),
             params: { payment: { amount: amount, paid_on: "2026-10-10" } }
        assert_response :unprocessable_entity, "금액 #{amount.inspect}는 422로 거부되어야 한다"
        assert_select "p", text: "입금 금액은 1원 이상 1000000000원 이하로 입력해 주세요", count: 1
      end
    end

    invoice = invoices(:delta_issued)
    assert invoice.reload.issued?
    assert_equal 0, invoice.payments.count
    assert_equal 220_000, invoice.remaining_amount
  end

  test "빈 문자열 금액은 전액으로 승격되지 않는다 (Phase 6 검증)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      invoice = invoices(:delta_issued)

      # 금액 키 없는 원클릭(amount nil)은 전액 마감이지만, 빈 문자열은 부분입금 폼 미입력 그대로다
      post app_invoice_payments_path(invoice),
           params: { payment: { amount: "", paid_on: "2026-10-10" } }
      assert_response :unprocessable_entity
      assert_select "p", text: "입금 금액을 입력해 주세요", count: 1
      assert invoice.reload.issued?
      assert_equal 0, invoice.payments.count
      assert_equal 220_000, invoice.remaining_amount
    end
  end

  test "미래 입금일은 422로 거부되고 부분입금 폼에도 오류가 표시된다 (TIME-1·Phase 6 #1)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      post app_invoice_payments_path(invoices(:delta_issued)),
           params: { payment: { amount: "50000", paid_on: "2026-10-13" } }   # 기준일 +1일
      assert_response :unprocessable_entity
    end

    # 원클릭 박스·부분입금 폼 양쪽의 입금일 필드 아래 오류 문구(Phase 6 #1 수정)
    assert_select "p", text: "입금일은 오늘 또는 그 이전 날짜로 선택해 주세요", count: 2
    assert response.body.rindex("입금일은 오늘 또는 그 이전 날짜로 선택해 주세요") >
           response.body.index("부분입금 기록")                       # 부분입금 폼 안에서도 표시

    invoice = invoices(:delta_issued)
    assert invoice.reload.issued?
    assert_equal 0, invoice.payments.count
  end

  test "과거 입금일은 허용되고 지정일 그대로 기록된다 (TIME-1)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      invoice = invoices(:delta_issued)

      post app_invoice_payments_path(invoice),
           params: { payment: { amount: "50000", paid_on: "2026-09-30" } }
      assert_response :see_other
      assert_equal Date.new(2026, 9, 30), invoice.payments.sole.paid_on

      follow_redirect!
      assert_select "li", text: /2026-09-30/
    end
  end

  # ── 상태 매트릭스(INV-4 — PAY 진입) ──

  test "미수 계열 전 상태에서 원클릭 마감은 paid로 전이된다 (INV-4·PAYABLE_STATUSES)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)

      [ invoices(:delta_issued), invoices(:delta_viewed), invoices(:delta_overdue),
        invoices(:delta_promised), invoices(:delta_partially_paid) ].each do |invoice|
        post app_invoice_payments_path(invoice), params: { payment: { paid_on: "2026-10-12" } }
        assert_response :see_other, "#{invoice.issue_number}는 마감되어야 한다"
        assert invoice.reload.paid?, "#{invoice.issue_number}는 paid로 전이되어야 한다"
        assert_equal 1, invoice.payments.count
        assert_equal invoice.total_amount, invoice.payments.sum(:amount)
        assert_equal 0, invoice.remaining_amount
      end
    end
  end

  test "초안·무효 본 입금 기록은 422로 차단되고 어떤 경로로도 전이되지 않는다 (INV-4)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)

      [ invoices(:delta_draft), invoices(:delta_voided) ].each do |invoice|
        post app_invoice_payments_path(invoice), params: { payment: { paid_on: "2026-10-12" } }
        assert_response :unprocessable_entity
        assert_select "#alert", text: "입금을 기록할 수 없는 상태의 청구서입니다"

        post app_invoice_payments_path(invoice),
             params: { payment: { amount: "10000", paid_on: "2026-10-12" } }
        assert_response :unprocessable_entity
        assert_select "#alert", text: "입금을 기록할 수 없는 상태의 청구서입니다"
      end
    end

    assert invoices(:delta_draft).reload.draft?
    assert invoices(:delta_voided).reload.voided?
    assert_equal 0, invoices(:delta_draft).payments.count
    assert_equal 0, invoices(:delta_voided).payments.count
  end

  test "초안 상세는 입금 섹션을 렌더하지 않는다 (초안은 입금 대상 아님)" do
    sign_in_as users(:delta)
    get app_invoice_path(invoices(:delta_draft))
    assert_response :success
    assert_select "h2", text: "입금", count: 0
  end

  test "무효 상세는 입금 섹션은 유지하되 폼을 렌더하지 않는다 (P4 이력 조회·INV-6)" do
    sign_in_as users(:delta)
    get app_invoice_path(invoices(:delta_voided))
    assert_response :success

    assert_select "h2", text: "입금", count: 1
    assert_select "button", text: "입금 확인하고 마감", count: 0
    assert_select "p", text: "부분입금 기록", count: 0
  end

  # ── Phase 6 #2 — 0원 청구서 발행 차단 ──

  test "품목 단가 0원 초안은 저장되고 총액 0으로 유지된다 (Phase 6 #2 — 초안 허용)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:gamma)
      post app_invoices_path, params: draft_params(
        client_id: clients(:gamma_main).id, due_on: (Date.current + 30).to_s,
        rows: [ row(description: "무료 샘플", unit_price: "0") ]
      )
      assert_response :see_other
    end

    invoice = Invoice.order(:id).last
    assert invoice.reload.draft?
    assert_equal 0, invoice.total_amount
  end

  test "0원 초안 발행은 422로 차단되고 총액 안내 문구를 표시한다 (Phase 6 #2·PAY-1 교착 차단)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:gamma)
      invoice = create_gamma_draft(rows: [ row(description: "무료 샘플", unit_price: "0") ])

      patch issue_app_invoice_path(invoice)
      assert_response :unprocessable_entity
      assert_select "#alert", text: "청구서 총액은 1원 이상이어야 합니다"
      assert invoice.reload.draft?                                   # 상태 유지 — 발행 차단
      assert_nil invoice.token
    end
  end

  test "단가 1원 청구서는 발행되고 원클릭으로 마감된다 (Phase 6 #2 경계 — 최소 금액)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:gamma)
      invoice = create_gamma_draft(rows: [ row(description: "최소 금액", unit_price: "1") ])

      patch issue_app_invoice_path(invoice)
      assert_response :see_other
      assert invoice.reload.issued?
      assert_equal 1, invoice.total_amount

      post app_invoice_payments_path(invoice), params: { payment: { paid_on: "2026-10-12" } }
      assert_response :see_other
      assert invoice.reload.paid?
      assert_equal 1, invoice.payments.sole.amount
    end
  end

  # ── 회귀(03 §4) ──

  test "발행 422(월 한도) 재렌더 화면은 한도 문구로 정상 렌더된다 (회귀 #1 — issue! 자동 저장)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:gamma)
      3.times do
        patch issue_app_invoice_path(create_gamma_draft)
        assert_response :see_other
      end

      fourth = create_gamma_draft
      patch issue_app_invoice_path(fourth)
      assert_response :unprocessable_entity
      assert_select "#alert", text: "Free 플랜은 매월 3건까지 발행할 수 있습니다. Plus로 무제한 이용할 수 있습니다"
      assert_no_match(/Payments is invalid/, response.body)          # 자동 저장 회귀 부재
      assert_select "a", text: "← 청구서 목록"                        # show 재렌더 정상 완결
      assert fourth.reload.draft?
    end
  end

  test "입금 이력 보유 청구서의 무효 처리는 303으로 성공하고 이력을 보존한다 (회귀 #1 — void!·P4)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      invoice = invoices(:delta_viewed)

      post app_invoice_payments_path(invoice),
           params: { payment: { amount: "20000", paid_on: "2026-10-10" } }
      assert_response :see_other

      patch void_app_invoice_path(invoice)
      assert_response :see_other
      assert_equal "청구서가 무효 처리되었습니다.", flash[:notice]
      assert invoice.reload.voided?
      assert_nil invoice.token
      assert_equal 1, invoice.payments.count                         # 입금 이력 보존(P4)

      get app_invoice_path(invoice)
      assert_response :success
      assert_select "li", text: /20,000원/                           # 이력 조회 유지
      assert_select "button", text: "입금 확인하고 마감", count: 0
      assert_no_match(/Payments is invalid/, response.body)
    end
  end

  test "답변 422 재렌더에 입금 이력이 포함되어 렌더된다 (회귀 #2 — answer Passed nil)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      invoice = invoices(:delta_viewed)

      post app_invoice_payments_path(invoice),
           params: { payment: { amount: "20000", paid_on: "2026-10-10" } }
      assert_response :see_other

      patch answer_app_promise_path(promises(:delta_answered_inquiry)),
            params: { promise: { answer: "두 번째 답변" } }           # 재답변 차단 → 422 재렌더
      assert_response :unprocessable_entity
      assert_select "#alert", text: "문의에는 한 번만 답변할 수 있습니다"
      assert_no_match(/Passed nil/, response.body)                   # 템플릿 오류 회귀 부재
      assert_select "li", text: /20,000원/                           # 입금 이력 정상 렌더
    end
  end

  private

  # 폼 전송 형태(인덱스 키 해시)의 품목 행 1개 — App::InvoicesControllerTest와 동일 규격
  def row(description: "웹 개발", quantity: "1", unit_price: "100000")
    { description: description, quantity: quantity, unit_price: unit_price }
  end

  # 초안 생성 요청 본문 — 품목 행은 인덱스 키 해시(params.expect 문서형 배열 수신 형태)
  def draft_params(client_id:, rows:, due_on: nil)
    {
      invoice: {
        client_id: client_id, due_on: due_on, tax_mode: "separate", withholding_enabled: "0",
        bank_name: "국민은행", account_number: "123-45-678901", account_holder: "테스트예금주",
        items_attributes: rows.each_with_index.to_h { |attributes, index| [ index.to_s, attributes ] }
      }
    }
  end

  # gamma 초안 생성 헬퍼 — 303 검증 후 마지막 생성 레코드 반환
  def create_gamma_draft(rows: [ row ])
    post app_invoices_path, params: draft_params(
      client_id: clients(:gamma_main).id, due_on: (Date.current + 30).to_s, rows: rows
    )
    assert_response :see_other
    Invoice.order(:id).last
  end
end
