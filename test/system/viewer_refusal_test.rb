require "application_system_test_case"

# 표면 ③ 수신 거부 E2E(F-REM — VIEW-7·PROMISE-2·P3) — 비로그인 채무자가 링크에서
# 진입 링크(하단 고지 아래) → <details> 펼침(의사 재확인 — JS 불요, VIEW-1 인앱 대응) →
# 접수 → 전용 완료 화면의 전 여정을 실제 브라우저로 검증한다. 접수는 기존 응답 경로의
# kind=refusal 재사용이라 rate_limit(10회/10분)도 함께 적용된다.
# 완료 화면·뷰어 전체는 마케팅 요소·③→① 링크가 없다(VIEW-8·SURF-4).
class ViewerRefusalTest < ApplicationSystemTestCase
  test "채무자가 수신 거부를 진입·재확인·접수하면 완료 화면으로 끝난다 (VIEW-7 E2E·비로그인)" do
    invoice = invoices(:delta_issued)
    visit viewer_path(invoice.token)

    assert_text "받을돈을 통해 테스트발행자님이 보낸 청구서입니다"        # VIEW-2 — 먼저 정상 열람
    assert_text "본 서비스는 채권 추심 업무를 수행하지 않습니다."          # VIEW-5 고지

    # 진입 — 하단 고지 아래 작은 링크(VIEW-8 화이트리스트 요소). <summary>는 JS 없는
    # 재확인 단계라 link/button이 아닌 네이티브 요소다(VIEW-1 인앱 대응).
    find("summary", text: "추가 안내 수신 거부").click                     # <details> 펼침 = 재확인
    assert_text "거부 접수 시 이 번호로는 이 청구서 관련 안내를 더 이상 보내지 않습니다."

    click_on "수신 거부 접수하기"                                         # 비인증 POST(PROMISE-2)
    assert_text "수신 거부가 접수되었습니다."                             # 전용 완료 화면(PRG)
    assert_text "이 번호로는 이 청구서 관련 안내를 더 이상 보내지 않습니다."
    assert_text "청구서 확인과 입금은 언제든 기존 링크에서 할 수 있습니다."  # P1 — 거래 계속 가능

    assert invoices(:delta_issued).client.reload.refused?                 # 번호 단위 즉시 중단
    assert invoices(:delta_issued).reload.sequence_finished?              # 해당 청구 시퀀스 종결

    # VIEW-8·SURF-4 — 완료 화면의 링크는 청구서 복귀(③→③)뿐이다
    links = page.all("a").map { |anchor| anchor[:href] }
    assert_not_empty links
    assert links.all? { |href| href.include?("/b/") }
  end

  test "접수 후 청구서로 돌아가면 열람·응답은 계속 가능하다 (VIEW-7 — 발송만 중단·P1)" do
    invoice = invoices(:delta_issued)
    invoice.client.update_column(:refused_at, Time.zone.parse("2026-10-12 09:00"))

    visit viewer_path(invoice.token)
    assert_text "BD-20260901-001"                                         # 청구 내용 그대로 열람
    assert_text "이번 주 내에 입금할게요"                                  # 응답 액션 유지(PROMISE-1)
    assert_text "추가 안내 수신 거부"                                      # 거부 진입도 유지(재접수 가능)
  end
end
