require "test_helper"

# 문의 답변 경로(F-PROMISE·PROMISE-6) 통합 테스트 — U1 답변 등록 303·뷰어 발행인 답변 표시,
# 1문의 1답변 재답변 차단(Phase 6 #2 플래시 표시), 빈 답변 422, 소유권 격리(타인 문의 404),
# 등록 notice 용어(Phase 6 #3 「거래처」). 시나리오 기준: _workspace/03_implementation.md
# 수정 이력 #2·#3, _workspace/05_review.md §Tester 5·7. KST 고정(TIME-1). 외부 API 호출 없음.
class App::PromisesControllerTest < ActionDispatch::IntegrationTest
  fixtures :users, :clients, :invoices, :promises

  test "무답변 문의 답변 등록은 303으로 완료되고 answered_at이 기록된다 (PROMISE-6)" do
    sign_in_as users(:delta)
    inquiry = promises(:delta_unanswered_inquiry)

    travel_to(Time.zone.parse("2026-10-15 11:00")) do
      patch answer_app_promise_path(inquiry),
            params: { promise: { answer: "네, 변경된 계좌로 입금해 주셔도 됩니다." } }
    end
    assert_response :see_other
    assert_redirected_to app_invoice_path(inquiry.invoice)

    follow_redirect!
    assert_select "#notice", text: "답변을 등록했습니다. 거래처가 청구서 링크에서 확인할 수 있습니다."  # Phase 6 #3

    assert_not_nil inquiry.reload.answered_at
    assert_equal "네, 변경된 계좌로 입금해 주셔도 됩니다.", inquiry.answer
    assert_equal Time.zone.parse("2026-10-15 11:00"), inquiry.answered_at
  end

  test "등록된 답변은 채무자 뷰어에 발행인 답변으로 표시된다 (PROMISE-6·P2)" do
    sign_in_as users(:delta)
    inquiry = promises(:delta_unanswered_inquiry)

    patch answer_app_promise_path(inquiry), params: { promise: { answer: "계좌는 변경되지 않았습니다." } }
    assert_response :see_other

    sign_out
    get viewer_path(inquiry.invoice.token)
    assert_response :success
    assert_select "section[aria-label='발행인 답변']" do
      assert_select "p", text: "계좌는 변경되지 않았습니다."
    end
  end

  test "답변한 문의의 재답변은 422로 차단되고 플래시로 안내된다 (1문의 1답변·Phase 6 #2)" do
    sign_in_as users(:delta)
    inquiry = promises(:delta_answered_inquiry)

    patch answer_app_promise_path(inquiry), params: { promise: { answer: "두 번째 답변" } }
    assert_response :unprocessable_entity
    assert_select "#alert", text: "문의에는 한 번만 답변할 수 있습니다"

    assert_equal "청구 총액에 부가세가 포함된 금액입니다.", inquiry.reload.answer  # 기존 답변 불변
  end

  test "빈 답변은 422로 차단되고 플래시로 안내된다 (PROMISE-6)" do
    sign_in_as users(:delta)
    inquiry = promises(:delta_unanswered_inquiry)

    patch answer_app_promise_path(inquiry), params: { promise: { answer: "" } }
    assert_response :unprocessable_entity
    assert_select "#alert", text: "답변 내용을 입력해 주세요"

    assert_nil inquiry.reload.answered_at
  end

  test "타인 청구서의 문의 답변은 404로 격리된다 (소유권 — Current.user 서브쿼리)" do
    sign_in_as users(:gamma)                                   # 프로필 완료 — delta 응답 스코프 밖
    inquiry = promises(:delta_unanswered_inquiry)

    patch answer_app_promise_path(inquiry), params: { promise: { answer: "위조 답변" } }
    assert_response :not_found

    assert_nil inquiry.reload.answered_at
    assert_nil inquiry.reload.answer
  end

  test "응답·약속 이력은 최신 우선으로 렌더되고 첫 행에 최신 배지가 표시된다 (P4·결정 #4)" do
    sign_in_as users(:delta)

    travel_to(Time.zone.parse("2026-10-14 12:00")) do
      get app_invoice_path(invoices(:delta_promised))            # fixture — 약속 이력 2건
    end
    assert_response :success

    assert_select "ol li", count: 2
    assert_select "ol li:first-child", text: /입금 예정일 지정/     # 최신 응답이 현재 약속 기준
    assert_select "ol li:first-child span", text: "최신", count: 1
    assert_select "ol li:first-child", text: /2026-10-23/        # 최신 약속일
    assert_select "ol li:last-child", text: /이번 주 내에 입금할게요/
    assert_select "ol li:last-child span", text: "최신", count: 0  # 배지는 첫 행 한정
    assert_select "ol li", text: /2026-10-16/                    # 구 약속일 이력 보존
  end
end
