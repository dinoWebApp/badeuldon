require "application_system_test_case"
require_relative "../test_helpers/fake_solapi_client"
require_relative "../test_helpers/solapi_stubbing"

# /app 청구서 상세 F-REM 회귀 E2E(REM-6/7/8) — 로그인 → 상세의 「자동 안내 현황」 섹션
# (상태 배지·다음 안내 라벨)→ 수동 발송(지금 1통 보내기 — 확인 대화상자·flash·발송 이력
# 갱신)→ 보류/재개 토글의 실제 브라우저 여정을 검증한다.
# 수동 발송은 컨트롤러가 SendService를 생성하므로 with_solapi_client 방어선으로 가로챈다
# (실호출 0 — REM-10·W-7). 시간은 travel_to로 평일 창(2026-11-10 화 10시)을 고정한다(TIME-1).
class AppInvoiceRemindersTest < ApplicationSystemTestCase
  include SolapiStubbing

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

      assert_text "자동 안내 현황"                                       # REM 섹션(비초안)
      assert_text "자동 안내 중"                                         # 진행 배지(녹색)
      assert_text "다음 안내:"                                           # 수동 발송 산정 표기
      assert_text "최종 안내(만기 14일 후)"                               # manual_step_key 산출
      assert_no_text "무료 플랜은 자동 발송이 없습니다"                    # delta는 자격 있음(REM-8)

      fake = FakeSolapiClient.new
      # Turbo가 확인 대화상자 승인 후 비동기로 요청을 보내므로(클릭 반환 시점에 요청이
      # 진행 중일 수 있다) flash·이력 갱신까지 stub을 유지한다 — 조기 해제 시 원본 래퍼로
      # 실제 API가 호출된다(REM-10 위반 — 절대 준수).
      with_solapi_client(fake) do
        accept_confirm do                                                # turbo_confirm 확인 대화상자
          click_button "지금 1통 보내기"
        end
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
      assert_text "자동 안내 중"                                         # 초기 — 진행 상태

      accept_confirm do                                                  # 「보류하기」(REM-11과 동일 동작)
        click_button "안내 보류하기"
      end
      assert_text "이 청구서의 자동 안내를 보류했습니다. 예정된 발송은 취소됩니다."
      assert_text "자동 안내가 보류 중입니다"                             # 상태 안내 박스
      assert_text "보류"                                                 # 중립 배지
      assert_no_button "지금 1통 보내기"                                  # 보류 중 수동 버튼 숨김

      visit app_invoice_path(invoice)                                    # 재적재 — Turbo 경합 없이 재개
      assert_text "자동 안내가 보류 중입니다"

      click_button "안내 재개하기"
      assert_text "이 청구서의 자동 안내를 재개했습니다. 다음 단계부터 이어집니다."
      assert_text "자동 안내 중"                                         # 진행 배지 복귀
      assert_button "지금 1통 보내기"                                    # 수동 버튼 복귀
    end
  end
end
