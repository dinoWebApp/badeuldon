require "application_system_test_case"
require_relative "../test_helpers/fake_solapi_client"
require_relative "../test_helpers/reminder_factories"
require_relative "../test_helpers/solapi_stubbing"

# /app 청구서 상세 F-REM 회귀 E2E(REM-6/7/8) — 로그인 → 상세의 「자동 안내 현황」 섹션
# (상태 배지·다음 안내 라벨)→ 수동 발송(지금 1통 보내기 — flash·발송 이력
# 갱신)→ 보류/재개 토글의 실제 브라우저 여정을 검증한다.
# button_to 제출은 네이티브 confirm stub + DOM 레벨 클릭으로 수행한다 — 2026-11-06 CI 2회
# 실패 + 로컬 재현 실측에서 근원이 확정됐다: selenium-webdriver 4.50 + Chrome 156 조합에서
# chromedriver 합성 클릭이 세션 상태에 따라 pointerdown 이하 이벤트를 통째로 드롭해 폼이
# 아예 제출되지 않는다(accept_confirm 시절의 ModalNotFound도 같은 근원 — 클릭 유실 →
# 다이얼로그 미발생). DOM 클릭은 8/8 성공으로 검증됐다(상세는 07_test_report.md §7).
# 대가로 대화상자 문구 자체 검증은 포기한다 — REM-6/7/8의 목적은 안내 흐름이지
# 다이얼로그 UI가 아니다.
# 수동 발송은 컨트롤러가 SendService를 생성하므로 with_solapi_client 방어선으로 가로챈다
# (실호출 0 — REM-10·W-7). 시간은 travel_to로 평일 창(2026-11-10 화 10시)을 고정한다(TIME-1).
class AppInvoiceRemindersTest < ApplicationSystemTestCase
  include SolapiStubbing
  include ReminderFactories

  fixtures :users, :clients, :invoices, :subscriptions, :payment_passes

  def log_in_as(user, password: "password")
    visit new_session_path
    fill_in "이메일", with: user.email
    fill_in "비밀번호", with: password
    click_button "로그인"
    assert_text "로그인되었습니다."
  end

  test "상세 화면은 자동 안내 현황·다음 안내 라벨을 보여주고 수동 발송이 이력을 남긴다 (REM-6·8)" do
    invoice = invoices(:delta_issued)                                   # 만기 10-01 → final_d14 구간

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      log_in_as users(:delta)                                           # 수금 패스 보유 — 자격 있음
      visit app_invoice_path(invoice)
      wait_for_turbo                                                    # 부트 대기 — confirm stub 주입 시점 보장
      page.execute_script("window.confirm = () => true")                # 네이티브 다이얼로그 미발생(헤더 주석)

      assert_text "자동 안내 현황"                                       # REM 섹션(비초안)
      assert_text "자동 안내 중"                                         # 진행 배지(녹색)
      assert_text "다음 안내:"                                           # 수동 발송 산정 표기
      assert_text "최종 안내(만기 14일 후)"                               # manual_step_key 산출
      assert_no_text "무료 플랜은 자동 발송이 없습니다"                    # delta는 자격 있음(REM-8)

      fake = FakeSolapiClient.new
      # Turbo가 confirm 승인(stub true 고정) 후 비동기로 요청을 보내므로(클릭 반환 시점에 요청이
      # 진행 중일 수 있다) flash·이력 갱신까지 stub을 유지한다 — 조기 해제 시 원본 래퍼로
      # 실제 API가 호출된다(REM-10 위반 — 절대 준수).
      with_solapi_client(fake) do
        dom_click_button "지금 1통 보내기"                                 # confirm stub 승인 → Turbo 제출
        assert_text "거래처에게 안내를 발송했습니다."                     # REM-8 성공 flash
        assert_text "발송 이력"                                          # REM-6 이력 섹션 갱신
      end
      assert_text "최종 안내(만기 14일 후)"
      assert_text "발송됨"                                               # 상태 배지(녹색)
      assert_text "거래처 · 직접 발송"                                   # origin=manual 채널 표기
      assert_equal 1, fake.calls.size                                    # 실호출 대역 1회
    end
  end

  test "보류하면 재개 버튼으로 전환되고 재개하면 다음 단계가 이어진다 (REM-7)" do
    invoice = invoices(:delta_due_soon)

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      log_in_as users(:delta)
      visit app_invoice_path(invoice)
      wait_for_turbo                                                    # 부트 대기 — confirm stub 주입 시점 보장
      page.execute_script("window.confirm = () => true")                # 네이티브 다이얼로그 미발생(헤더 주석)
      assert_text "자동 안내 중"                                         # 초기 — 진행 상태

      dom_click_button "안내 보류하기"                                    # 「보류하기」(REM-11과 동일 동작 — stub 승인)
      assert_text "이 청구서의 자동 안내를 보류했습니다. 예정된 발송은 취소됩니다."
      assert_text "자동 안내가 보류 중입니다"                             # 상태 안내 박스
      assert_text "보류"                                                 # 중립 배지
      assert_no_button "지금 1통 보내기"                                  # 보류 중 수동 버튼 숨김

      visit app_invoice_path(invoice)                                    # 재적재 — 재개 클릭
      wait_for_turbo                                                    # 모든 visit 후 부트 보장 — 클릭 유실 방지
      assert_text "자동 안내가 보류 중입니다"

      dom_click_button "안내 재개하기"                                    # confirm 없는 폼 — Turbo 제출 경로만 보장
      assert_text "이 청구서의 자동 안내를 재개했습니다. 다음 단계부터 이어집니다."
      assert_text "자동 안내 중"                                         # 진행 배지 복귀
      assert_button "지금 1통 보내기"                                    # 수동 버튼 복귀
    end
  end

  # Phase 7(05_review §4-4) — 만기 17일 전 청구서의 수동 발송은 "(내일)" 박힌 만기 전날
  # 전용 문구(invoice_notice)가 아니라 발행 안내(issue_notice)로 라벨링·발송된다(운영 실측
  # 결함 회귀 — REM-8·Q11). 컨트롤러 테스트가 API 레벨인 것과 달리 버튼 라벨·이력 라벨의
  # 뷰 정합까지 검증한다.
  test "만기 17일 전 청구서의 다음 안내 라벨과 발송 이력은 발행 안내로 표기된다 (REM-8·Q11)" do
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 11, 27))     # 기준일 기준 만기 17일 전

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      log_in_as users(:delta)
      visit app_invoice_path(invoice)
      wait_for_turbo
      page.execute_script("window.confirm = () => true")

      assert_text "다음 안내:"
      assert_text "발행 안내"                                              # issue_notice 라벨
      assert_no_text "만기 예정 안내"                                       # invoice_notice 라벨 아님 — "(내일)" 전용 템플릿

      fake = FakeSolapiClient.new
      with_solapi_client(fake) do
        dom_click_button "지금 1통 보내기"
        assert_text "거래처에게 안내를 발송했습니다."
      end
      assert_text "발송 이력"
      assert_text "발행 안내"                                              # 이력 행 라벨 — template_key 정합
      assert_equal "issue_notice", fake.calls.sole[:template_key]
    end
  end
end
