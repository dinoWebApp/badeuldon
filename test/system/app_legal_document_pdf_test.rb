require "application_system_test_case"
require_relative "../test_helpers/portone_stubbing"
require_relative "../test_helpers/fake_portone_client"

# F-LEGAL 내용증명 PDF 브라우저 레벨 검증 — U1 실로그인 → 내용증명 상세(show) → 다운로드
# 버튼 노출 → 동일 인증 쿠키 경로(same-origin fetch)로 응답 본체를 직접 수령해 %PDF
# 시그니처·Content-Disposition을 단정한다(app_invoice_pdf_test 선례). 미결제 주문은
# 워터마크 미리보기, paid 주문은 정식 PDF — 두 응답이 서로 다른 바이트열임을 브라우저
# 세션에서도 비교 단정한다(C-1 회귀). 결제 확정은 FulfillPassService(프로덕션 확정점)로
# 수행한다 — 시스템 테스트 세션에서 Integration post는 불가하고, 웹훅 체인은
# legal_documents_controller_test(B-1 회귀)가 커버한다. 외부 API 실호출 0.
class AppLegalDocumentPdfTest < ApplicationSystemTestCase
  fixtures :users, :clients, :invoices

  def log_in_as(user, password: "password")
    visit new_session_path
    fill_in "이메일", with: user.email
    fill_in "비밀번호", with: password
    click_button "로그인"
    assert_text "로그인되었습니다."
  end

  test "내용증명 상세에서 미결제는 워터마크 미리보기 PDF를, paid는 정식 PDF를 받는다 (LEGAL-2·C-1)" do
    user = users(:delta)
    invoice = invoices(:delta_overdue) # 만기 2026-09-01 — 기준일에 D+30 초과 unsettled

    # 기준일 2026-11-20(TIME-1) — 세션 쿠키 expires=로그인+30일이 실제 시계로 평가되므로
    # 기준일+30 > 오늘(2026-11-11)이어야 브라우저가 쿠키를 유지한다(2026-10-12 기준일 실패 실측).
    travel_to(Time.zone.parse("2026-11-20 09:00")) do
      log_in_as user

      order = user.orders.create!(product: :collection_pass, item_type: :legal_doc,
                                  amount: Order::LEGAL_DOC_PRICE, pg_order_id: SecureRandom.uuid,
                                  metadata: { invoice_id: invoice.id })
      visit app_legal_document_path(order)
      assert_text "결제 대기" # pending 상태 카드
      assert_link "워터마크 미리보기 PDF 내려받기" # 미결제 상태 — 워터마크 미리보기 버튼(C-1)

      unpaid_report = fetch_pdf(download_app_legal_document_path(order))
      assert_equal "%PDF-", unpaid_report["magic"]
      assert_includes unpaid_report["disposition"], "attachment"

      # 결제 확정(프로덕션 확정점 재사용 — legal_doc는 paid 전환만, 패스 미발급)
      Orders::FulfillPassService.new(order: order, payment_id: "SYS-TEST-#{order.pg_order_id}").call
      assert_predicate order.reload, :paid?

      visit app_legal_document_path(order)
      assert_link "내용증명 PDF 내려받기" # paid 상태 — 정식 다운로드 버튼

      paid_report = fetch_pdf(download_app_legal_document_path(order))
      assert_equal "%PDF-", paid_report["magic"]
      assert_operator paid_report["size"], :>, 10_000 # Pretendard 한글 폰트 임베드(B-2 회귀)

      # 워터마크 미리보기 ≠ 정식 PDF — 브라우저 세션에서도 두 응답이 구별된다(C-1)
      assert_not_equal unpaid_report["size"], paid_report["size"]
    end
  end

  private

  # 다운로드 링크와 동일 인증 쿠키 경로(same-origin fetch)로 PDF 응답을 수령해 메타를 돌려준다.
  def fetch_pdf(url)
    report = page.evaluate_async_script(<<~JS, url)
      const [u, done] = arguments;
      fetch(u, { credentials: "same-origin" })
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
    report
  end
end
