require "application_system_test_case"

# 표면 ③ 청구서 뷰어 E2E(저장소 첫 시스템 테스트) — 채무자가 공유 링크로 청구서를 보는
# 핵심 여정. 검증: VIEW-2/3/5 표시·계좌 복사(clipboard JS)·VIEW-8 앵커 0개·VIEW-6 무효 여정.
# 클립보드 권한 프롬프트에 의존하지 않도록 writeText를 스텁해 실제 전달값을 단언한다.
# 시나리오 기준: _workspace/05_review.md §8-b, _workspace/03_implementation.md §2.1.
class ViewerTest < ApplicationSystemTestCase
  test "채무자가 링크를 열면 청구 내용·고지문이 표시되고 계좌 복사가 동작한다 (VIEW-2/3/5·VIEW-1)" do
    invoice = invoices(:delta_issued)
    visit viewer_path(invoice.token)

    assert_text "받을돈을 통해 테스트발행자님이 보낸 청구서입니다"      # VIEW-2 발행인 표시
    assert_text "BD-20260901-001"                                    # 청구번호
    assert_text "웹 개발"                                             # 품목
    assert_text "220,000원"                                          # 청구 총액
    assert_text "입금 시 입금자명을 '델타파트너스'으로 입력해 주세요."     # PAY-3
    assert_text "본 서비스는 채권 추심 업무를 수행하지 않습니다."          # VIEW-5 고지문

    # VIEW-8·SURF-4 — 뷰어 DOM에 링크 앵커가 없다(③→① 유출·가입 유도 차단)
    assert_empty page.all("a")

    # 계좌 복사 — clipboard 스텁으로 전달값 확인 + 「복사됨」 피드백(VIEW-3)
    page.execute_script(<<~JS)
      window.__badeuldonCopied = null;
      navigator.clipboard.writeText = (text) => {
        window.__badeuldonCopied = text;
        return Promise.resolve();
      };
    JS
    find("button[data-action='clipboard#copy']").click
    assert_text "복사됨"
    assert_equal "신한은행 110-234-567890 김델타", page.evaluate_script("window.__badeuldonCopied")
  end

  test "클립보드 불가 환경에서는 source 선택으로 수동 복사를 유도한다 (VIEW-3 fallback)" do
    visit viewer_path(invoices(:delta_issued).token)

    # 비보안 컨텍스트 등 clipboard API 거부 환경 재현 — fallback은 source 선택 + 안내 라벨
    page.execute_script(<<~JS)
      navigator.clipboard.writeText = () => Promise.reject(new Error("denied"));
    JS
    find("button[data-action='clipboard#copy']").click
    assert_text "선택됨 — 복사해 주세요"
    assert_equal "신한은행 110-234-567890 김델타", page.evaluate_script("window.getSelection().toString()")
  end

  test "무효 토큰 여정은 VIEW-6 안내만 노출하고 링크가 없다 (VIEW-6·SURF-4)" do
    visit viewer_path("Z" * 43)

    assert_text "링크가 만료되었거나 폐기되었습니다."
    assert_text "발행인에게 직접 연락해 주세요."
    assert_no_text "청구번호"                                         # 청구 내용 미노출
    assert_empty page.all("a")
  end
end
