require "application_system_test_case"

# 표면 ③ 응답 여정 E2E(F-PROMISE) — 채무자가 공유 링크를 열고 응답 버튼으로 응답하면 감사
# 화면으로 전환되는 무가입 핵심 여정(PROMISE-1/2·P3). 버튼 문구는 PROMISE-1 원문이며, 약속
# 접수로 청구서가 promised로 전이된다(INV-4). 시나리오 기준: _workspace/05_review.md §Tester 8.
class ViewerPromiseTest < ApplicationSystemTestCase
  test "채무자가 이번 주 응답 버튼으로 응답하면 감사 화면으로 전환된다 (PROMISE-1/2 무가입 여정)" do
    invoice = invoices(:delta_issued)

    travel_to(Time.zone.parse("2026-10-14 10:00")) do
      visit viewer_path(invoice.token)

      assert_text "이 청구서에 응답하기"
      assert_text "가입이나 개인정보 입력은 필요하지 않습니다"      # P3 — 무가입·무입력
      assert_button "이번 주 내에 입금할게요"                       # PROMISE-1 원문
      assert_button "이미 입금했어요"

      click_on "이번 주 내에 입금할게요"
      assert_text "감사합니다. 발행인에게 전달했습니다."

      click_on "청구서로 돌아가기"                                  # ③→③ 복귀
      assert_text "이 청구서에 응답하기"
    end

    assert invoice.reload.promised?                                 # INV-4 — issued→promised
    assert_equal Date.new(2026, 10, 16), invoice.promises.sole.promised_on  # 수요일 → 이번 주 금
  end
end
