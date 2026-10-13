require "test_helper"

# DASH-2 오늘의 액션 실데이터(F-PROMISE) — 마감 대기(PROMISE-7: 입금 완료 회신 ∩ unsettled),
# 답변 대기(PROMISE-6: 무답변 문의) 조건부 카드, 소멸 조건, 소유권 격리, 무액션 빈 상태 분기
# (기존 어설션 회귀). 시나리오 기준: _workspace/03_implementation.md §2,
# _workspace/05_review.md §Tester 4·9. KST 기준일 2026-10-12 고정(TIME-1). 외부 API 호출 없음.
class App::DashboardsActionsTest < ActionDispatch::IntegrationTest
  fixtures :users, :clients, :invoices, :promises

  test "입금 완료 회신이 있는 미마감 청구서는 마감 대기 카드로 표시된다 (PROMISE-7·DASH-2)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      get app_root_path
      assert_response :success

      assert_select "article", text: /마감 대기/ do |cards|
        assert_equal 1, cards.size
        assert_match(/델타파트너스 · 330,000원/, cards.first.text)
        assert_match(/거래처가 「이미 입금했어요」라고 회신했습니다\. 확인 후 마감해 주세요\./, cards.first.text)
      end
      assert_select "a[href=?]", app_invoice_path(invoices(:delta_partially_paid)),
                    text: "청구서 확인", count: 1
    end
  end

  test "무답변 문의는 답변 대기 카드로 표시되고 답변하면 카드가 소멸한다 (PROMISE-6·DASH-2)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      get app_root_path
      assert_response :success

      assert_select "article", text: /답변 대기/ do |cards|
        assert_equal 1, cards.size
        assert_match(/델타파트너스의 문의/, cards.first.text)
        assert_match(/입금 계좌가 변경되었는지/, cards.first.text)
      end
      assert_select "a[href=?]", app_invoice_path(invoices(:delta_due_soon)),
                    text: "문의에 답변하기", count: 1

      # 답변 등록 → 답변 대기 소멸(PROMISE-6 — 소멸 조건은 answered_at 기록)
      assert promises(:delta_unanswered_inquiry).answer!("계좌는 변경되지 않았습니다.")
      get app_root_path
      assert_select "article", text: /답변 대기/, count: 0
    end
  end

  test "마감 확정 후에는 마감 대기 카드가 소멸한다 (PROMISE-7 — 마감 자체는 PAY 도메인)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      # PAY 후속 도메인 부재 — U1 마감 확정 상태(paid)를 직접 세팅해 소멸 조건을 검증한다.
      invoices(:delta_partially_paid).update!(status: :paid)

      get app_root_path
      assert_select "article", text: /마감 대기/, count: 0     # settled 제외 — 소멸
      assert_select "article", text: /답변 대기/, count: 1     # 답변 대기는 유지
      assert_select "p", text: "오늘 할 일이 없습니다", count: 0
    end
  end

  test "타인 청구서의 응답은 대시보드에 표시되지 않는다 (소유권 격리 — Current.user 스코프)" do
    sign_in_as users(:gamma)                                   # 프로필 완료·청구서 0건
    get app_root_path
    assert_response :success

    assert_select "article", text: /마감 대기/, count: 0        # delta 소유 회신 비노출
    assert_select "article", text: /답변 대기/, count: 0        # delta 소유 문의 비노출
    assert_select "p", text: "오늘 할 일이 없습니다", count: 1   # 무액션 — 빈 상태 유지
  end

  test "청구서 0건·응답 0건이면 기존 빈 상태 문구만 렌더한다 (DASH-2 분기 회귀)" do
    sign_in_as users(:gamma)
    get app_root_path
    assert_response :success

    assert_select "p", text: "오늘 할 일이 없습니다", count: 1
    assert_select "p", text: /오늘 발송 예정·약속일 도래/, count: 1
    assert_select "article", text: /마감 대기/, count: 0
    assert_select "article", text: /답변 대기/, count: 0
  end
end
