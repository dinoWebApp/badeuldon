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

  # log_in_as는 공용 케이스(test/application_system_test_case.rb — W-7 경화 2026-11-26)의
  # 정의를 쓴다. chromedriver 합성 클릭 드롭으로 로그인 제출이 빠지는 플레이크가 관측됐어서
  # 제출을 dom_click_button(DOM 레벨 클릭)으로 수행한다 — 이 파일의 자체 정의는 제거했다.

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

  # VIEW-7 — 수신 거부한 거래처의 청구는 재개할 수 없다(채무자 의사 — U1이 되돌리는 경로 없음).
  # 종결 청구라도 「안내 다시 보내기」를 노출하지 않고 거부 접수 배너가 사유를 설명한다.
  test "수신 거부한 거래처의 종결 청구는 재개 버튼 없이 거부 안내만 보여준다 (VIEW-7)" do
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 10, 27))
    invoice.update_columns(sequence_finished_at: Time.zone.parse("2026-11-09 14:00"))
    mark_refused(invoice.client, at: Time.zone.parse("2026-11-09 15:00"))

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      log_in_as users(:delta)
      visit app_invoice_path(invoice)
      wait_for_turbo

      assert_text "이 거래처가 추가 안내 수신을 거부했습니다"               # 거부 배너 — 사유 설명
      assert_no_text "안내 다시 보내기"                                    # 재개 버튼·보조 문구 미노출
      assert_no_button "안내 다시 보내기"
    end
  end

  # VIEW-7 — 보류·수신 거부 겹침: 거래처가 거부한 뒤 청구에 보류·종결 마킹이 남은 상태에서도
  # 「안내 재개하기」가 노출되지 않는다(재개해도 REFUSED 가드로 발송이 없다 — 죽은 버튼 방지).
  test "수신 거부한 거래처의 보류 중 청구는 재개 버튼 없이 거부 안내만 보여준다 (VIEW-7 — 겹침)" do
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 10, 27))
    invoice.update_columns(
      reminders_suspended_at: Time.zone.parse("2026-11-09 14:00"),
      sequence_finished_at: Time.zone.parse("2026-11-09 14:30")
    )
    mark_refused(invoice.client, at: Time.zone.parse("2026-11-09 15:00"))

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      log_in_as users(:delta)
      visit app_invoice_path(invoice)
      wait_for_turbo

      assert_text "이 거래처가 추가 안내 수신을 거부했습니다"               # 거부 배너가 우선 — 사유 설명
      assert_no_text "안내 재개하기"                                       # 보류 재개 버튼 미노출
      assert_no_text "안내 다시 보내기"
      assert_no_button "안내 재개하기"
    end
  end

  # PLAN-3·Q28·W-4 — 상한 도달 청구 상세(브라우저). 상한 안내 상자·「상한 도달」 배지를 보이고
  # 막힌 발송 버튼과 「다음 안내」 라벨을 노출하지 않는다(죽은 버튼 방지 — 컨트롤러 테스트와
  # 같은 판정을 실제 브라우저 렌더로 재확인).
  test "상한 도달 청구 상세는 상한 안내 상자·배지를 보이고 발송 버튼·다음 안내 라벨을 숨긴다 (PLAN-3·Q28)" do
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 11, 27))
    5.times do
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "issue_notice",
                         recipient_role: :debtor, status: :sent, origin: :manual)
    end

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      log_in_as users(:delta)
      visit app_invoice_path(invoice)
      wait_for_turbo

      assert_text "발송 상한에 도달했습니다"                               # 상한 안내 상자
      assert_text "입금을 기록하면 나가는 안내"                             # 자동 1회성은 계속 발송된다(Q10)
      assert_text "상한 도달"                                              # 상태 배지(중립) — 「자동 안내 중」 대체
      assert_no_text "지금 1통 보내기"                                     # 직접 발송 버튼 숨김
      assert_no_button "지금 1통 보내기"
      assert_no_text "안내 보류하기"                                       # 보류 버튼 숨김
      assert_no_text "다음 안내:"                                          # 수동 발송 산정 라벨 숨김
    end
  end

  # 마지막 수정 반례(Tester 2026-11-26) — 수동 상한만 도달한 청구 상세(브라우저). 자동 상한과
  # 달리 상자·배지가 없고(「자동 안내 중」 배지 유지), 활성 분기 안에서 「지금 1통 보내기」
  # 버튼과 「다음 안내:」 라벨만 한 줄 안내로 대체된다(「안내 보류하기」는 유지 — 보류는
  # 발송 조작이 아니다). 컨트롤러 테스트(PLAN-3·W-3)와 같은 판정을 실제 브라우저 렌더로 재확인.
  test "수동 상한만 도달한 청구 상세는 보류하기와 한 줄 안내를 보이고 직접 발송 버튼·다음 안내 라벨을 숨긴다 (PLAN-3·W-3)" do
    invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                      due_on: Date.new(2026, 11, 27))
    5.times do
      MessageLog.create!(invoice: invoice, user: invoice.user, template_key: "partial_paid",
                         recipient_role: :debtor, status: :sent)          # 자동 1회성 5통 — 수동 상한만 도달
    end

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      log_in_as users(:delta)                                             # 공용 헬퍼 — DOM 클릭 제출
      visit app_invoice_path(invoice)
      wait_for_turbo

      assert_text "자동 안내 중"                                           # 자동 상한이 아니라 진행 배지 유지
      assert_text "안내 보류하기"                                          # 보류 버튼은 유지
      assert_text "직접 안내는 청구 건당 5통을 모두 보내 더 보낼 수 없습니다"  # 한 줄 안내
      assert_no_text "지금 1통 보내기"                                     # 직접 발송 버튼 숨김
      assert_no_text "다음 안내:"                                          # 라벨 숨김
      assert_no_text "발송 상한에 도달했습니다"                            # 자동 상한 표시는 아니다
    end
  end

  # VIEW-7·W-1 — 거래처 목록 카드(브라우저). 수신 거부 + 거래처 보류 겹침 카드에는 재개·보류
  # 버튼이 모두 없고 「수신 거부」 배지가 사유를 설명한다(죽은 버튼 방지 — W-1 수정의
  # 실제 브라우저 렌더 재확인).
  test "수신 거부 + 보류가 겹친 거래처 목록 카드는 재개·보류 버튼 없이 수신 거부 배지를 보여준다 (VIEW-7·W-1)" do
    client = clients(:delta_main)                                          # delta의 유일 거래처 — 카드 단독
    client.update_columns(
      reminders_suspended_at: Time.zone.parse("2026-11-09 14:00"),
      refused_at: Time.zone.parse("2026-11-09 15:00")
    )

    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      log_in_as users(:delta)
      visit app_clients_path
      wait_for_turbo

      assert_text "수신 거부"                                              # 거부 배지 — 사유 설명
      assert_no_button "재개"                                              # 죽은 버튼 미노출(W-1)
      assert_no_button "보류"                                              # 거부는 액션 없음 — 보류 버튼도 미노출
      assert_link "수정"                                                   # 편집 링크는 그대로(button_to 아님)
    end
  end
end
