require "application_system_test_case"
require_relative "../test_helpers/reminder_factories"

# DASH-2·Q31 — 대시보드 「오늘의 액션」 나머지 세 종 중 「오늘 발송 예정」 카드의 실제 브라우저
# 여정 E2E(REM-11 당일 보류 창 — 2026-11-26 구현 확정·결정 기록 Q31). 로그인 → 대시보드의
# 오늘 발송 예정 카드(만기 예고 안내 라벨·보류하기)→ 확인창 승인 → 보류 처리 후 청구서 상세로
# 되돌아오는 흐름을 검증한다. 컨트롤러·쿼리 테스트가 API·산정 레벨인 것과 달리 카드 마크업과
# button_to(기존 REM-7 suspend 경로 재사용)의 실제 제출까지 확인한다.
# 제출은 네이티브 confirm stub + DOM 레벨 클릭으로 수행한다 — chromedriver 합성 클릭 드롭
# 실측과 절차는 test/system/app_invoice_reminders_test.rb 헤더 주석(2026-11-06)과 같다.
# 시간은 travel_to로 평일(2026-11-10 화 10시)을 고정한다(TIME-1). 발송 실행이 아닌 보류
# 흐름이라 솔라피 호출이 없지만, 보류 후 상세 화면 렌더까지 공용 stub 방어선과 동일하게
# 실호출 0을 유지한다(REM-10).
class AppDashboardActionsTest < ApplicationSystemTestCase
  include ReminderFactories

  fixtures :users, :clients, :invoices, :subscriptions, :payment_passes

  test "오늘 발송 예정 카드의 보류하기를 누르면 청구서 자동 안내가 보류되고 상세로 돌아온다 (DASH-2·Q31·REM-11)" do
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 11, 11))   # D-1 = 기준일 — 만기 예고 도래

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      log_in_as users(:delta)                                            # 수금 패스 보유 — 자격 있음
      visit app_root_path
      wait_for_turbo                                                    # 부트 대기 — confirm stub 주입 시점 보장
      page.execute_script("window.confirm = () => true")                # 네이티브 다이얼로그 미발생(관례 준용)

      assert_text "오늘의 액션"
      assert_text "오늘 발송 예정"                                       # 상태 뱃지
      assert_text "만기 예정 안내"                                       # template_key 라벨(invoice_notice)
      assert_text "오늘 오후 2시에 다음 안내를 보냅니다: 「만기 예정 안내」. 발송 전까지 보류할 수 있습니다."  # 실제 예정 시각(리뷰 C-1·C-2·W-4)

      dom_click_button "보류하기"                                        # confirm stub 승인 → Turbo 제출(REM-7 재사용)
      assert_text "이 청구서의 자동 안내를 보류했습니다. 예정된 발송은 취소됩니다."  # 성공 flash — 청구서 상세로 돌아온다
      assert_text "자동 안내가 보류 중입니다"                             # 상세의 보류 상태 안내

      visit app_root_path                                                # 대시보드 복귀 — 카드 소멸(보류 반영)
      wait_for_turbo
      # 부재 단언은 뱃지 span으로 좁힌다 — 빈 상태 안내 문구에도 "오늘 발송 예정" 문자열이 있어
      # assert_no_text는 공허하다(2026-11-26 리뷰 W-3③).
      assert_no_selector "span", text: "오늘 발송 예정"                  # reminders_dispatchable 제외 — 카드 소멸
    end
  end
end
