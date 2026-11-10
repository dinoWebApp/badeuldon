require "application_system_test_case"

# PAY-6 수금완료 증빙 PDF 브라우저 레벨 검증(Q17) — U1 실로그인 → paid 청구 상세 →
# 다운로드 버튼 노출 확인 → 동일 URL을 브라우저 fetch로 수령해 %PDF 시그니처·파일명
# Content-Disposition 헤더를 단정한다. headless Chrome의 파일 다운로드는 브라우저별
# 저장 경로 통제가 불안정하므로, 다운로드 링크와 동일 인증 쿠키 경로(same-origin fetch)
# 로 응답 본체를 직접 수신한다 — 컨트롤러 테스트(리뷰어 임시 검증 후 삭제)와 별개로
# 실제 브라우저 세션에서의 응답을 검증하는 보강이다.
class AppInvoicePdfTest < ApplicationSystemTestCase
  fixtures :users, :clients, :invoices

  def log_in_as(user, password: "password")
    visit new_session_path
    fill_in "이메일", with: user.email
    fill_in "비밀번호", with: password
    click_button "로그인"
    assert_text "로그인되었습니다."
  end

  test "paid 청구 상세에서 수금완료 증빙 PDF를 받는다 (PAY-6·Q17)" do
    invoice = invoices(:delta_paid)

    log_in_as users(:delta)
    visit app_invoice_path(invoice)
    assert_link "수금완료 증빙 PDF" # 마감 상태에만 노출되는 다운로드 버튼(Q17)

    report = page.evaluate_async_script(<<~JS, payment_pdf_app_invoice_path(invoice))
      const [url, done] = arguments;
      fetch(url, { credentials: "same-origin" })
        .then((res) => res.arrayBuffer().then((buf) => {
          const bytes = new Uint8Array(buf);
          let binary = "";
          for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
          done(JSON.stringify({
            magic: binary.slice(0, 5),
            size: bytes.length,
            disposition: res.headers.get("Content-Disposition") || ""
          }));
        }))
        .catch((e) => done(JSON.stringify({ error: String(e) })));
    JS
    report = JSON.parse(report)
    assert_nil report["error"], "PDF 수령 실패: #{report['error']}"
    assert_equal "%PDF-", report["magic"] # Prawn 산출 시그니처
    assert_operator report["size"], :>, 10_000 # Pretendard 한글 폰트 임베드 — 0바이트 방지(B-2 회귀)
    assert_includes report["disposition"], "attachment" # 다운로드 응답임을 헤더로 단정
  end
end
