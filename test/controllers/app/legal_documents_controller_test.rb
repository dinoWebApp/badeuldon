require "test_helper"
require_relative "../../test_helpers/portone_stubbing"
require_relative "../../test_helpers/fake_portone_client"

# 내용증명 양식(F-LEGAL — LEGAL-1/2) HTTP 테스트 — create→웹훅 확정→download 전 체인을
# 컨트롤러 경유로 재현한다(B-1 회귀: 결제 확정이 orders.metadata를 덮어쓰지 않는다).
# 결제 승인·재조회는 FakePortOneClient로 스텁한다(실호출 금지 — PLAN-5).
# 대상 청구: delta_overdue(만기 2026-09-01 — 기준일 2026-10-12에 D+30 초과 unsettled).
class App::LegalDocumentsControllerTest < ActionDispatch::IntegrationTest
  include PortOneStubbing

  setup do
    @user = users(:delta)
    @invoice = invoices(:delta_overdue)
    @pass_count = @user.payment_passes.count
    travel_to(Time.zone.parse("2026-10-12 09:00"))
  end

  teardown do
    travel_back
  end

  test "비인증 접근은 로그인 화면으로 리다이렉트된다 (AUTH-1)" do
    get app_legal_documents_path

    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "B-1 회귀: create→웹훅 Transaction.Paid 확정→metadata.invoice_id 보존→정식 PDF 다운로드" do
    sign_in_as @user

    post app_legal_documents_path, params: { invoice_id: @invoice.id }
    assert_response :redirect
    order = @user.orders.legal_docs.sole
    assert_equal @invoice.id, order.metadata["invoice_id"]

    fake = FakePortOneClient.new(get_payment: { id: order.pg_order_id, status: "PAID" })
    with_portone_client(fake) do
      post "/webhooks/portone",
           params: { type: "Transaction.Paid", data: { paymentId: order.pg_order_id } }.to_json,
           headers: { "Content-Type" => "application/json" }
    end
    assert_response :ok

    order.reload
    assert_predicate order, :paid?
    assert_equal @invoice.id, order.metadata["invoice_id"]  # 덮어쓰기로 소실되지 않는다

    get download_app_legal_document_path(order)
    assert_response :ok
    assert_equal "application/pdf", response.media_type
    assert_match(/\A%PDF/, response.body)

    # legal_doc 주문은 패스를 발급하지 않는다(기존 fixture 패스 건수 불변)
    assert_equal @pass_count, @user.payment_passes.count
  end

  test "C-1: 미결제 주문 download은 워터마크 미리보기 PDF를 돌려준다 (LEGAL-2)" do
    sign_in_as @user
    order = create_legal_order

    get download_app_legal_document_path(order)

    assert_response :ok
    assert_equal "application/pdf", response.media_type
    assert_match(/\A%PDF/, response.body)
    clean_pdf = LegalDocuments::ContentProofPdfService.call(invoice: @invoice)
    # 워터마크 옵션은 정식 PDF와 다른(더 큰) 바이트열을 낸다 — 워터마크가 실제 렌더됐음을 간접 검증
    assert response.body.bytesize != clean_pdf.bytesize || response.body != clean_pdf
  end

  test "C-1: 결제 완료 주문 download은 워터마크 없는 정식 PDF를 돌려준다 (LEGAL-2)" do
    sign_in_as @user
    order = create_legal_order
    confirm_paid!(order)

    get download_app_legal_document_path(order)

    assert_response :ok
    assert_equal "application/pdf", response.media_type
    assert_match(/\A%PDF/, response.body)
    assert_equal LegalDocuments::ContentProofPdfService.call(invoice: @invoice), response.body
  end

  test "C-2: 동일 청구에 결제 완료 주문이 있으면 새 주문을 만들지 않고 기존 주문으로 안내한다 (LEGAL-2)" do
    sign_in_as @user
    paid_order = create_legal_order
    confirm_paid!(paid_order)

    assert_no_difference -> { @user.orders.legal_docs.count } do
      post app_legal_documents_path, params: { invoice_id: @invoice.id }
    end

    assert_response :redirect
    assert_redirected_to app_legal_document_path(paid_order)
    assert_predicate paid_order.reload, :paid?
  end

  test "W-3: 청구가 마감(paid)된 뒤에도 결제 완료 주문의 재다운로드는 허용된다" do
    sign_in_as @user
    order = create_legal_order
    confirm_paid!(order)
    @invoice.update!(status: :paid)  # 마감 — 대상 조건 재검증 없이 스냅샷 제공(W-3 확정 정책)

    get download_app_legal_document_path(order)

    assert_response :ok
    assert_match(/\A%PDF/, response.body)
  end

  test "미결제 주문이 대상이 아닌 청구(마감됨)를 참조하면 상태 안내로 되돌린다 (LEGAL-1 가드)" do
    sign_in_as @user
    order = create_legal_order
    @invoice.update!(status: :paid)  # 미결제 주문 + 마감 청구 — 정식·미리보기 모두 부적격

    get download_app_legal_document_path(order)

    assert_response :redirect
    assert_redirected_to app_legal_document_path(order)
  end

  test "타인의 legal_doc 주문은 404다 (소유권 격리)" do
    sign_in_as users(:gamma)
    order = @user.orders.create!(product: :collection_pass, item_type: :legal_doc,
                                 amount: Order::LEGAL_DOC_PRICE, pg_order_id: SecureRandom.uuid,
                                 metadata: { invoice_id: @invoice.id })

    get app_legal_document_path(order)

    assert_response :not_found
  end

  test "타인의 legal_doc 주문 download도 404다 (소유권 격리 — PDF 유출 방지)" do
    sign_in_as users(:gamma)
    order = @user.orders.create!(product: :collection_pass, item_type: :legal_doc,
                                 amount: Order::LEGAL_DOC_PRICE, pg_order_id: SecureRandom.uuid,
                                 metadata: { invoice_id: @invoice.id })

    get download_app_legal_document_path(order)

    assert_response :not_found
  end

  private

  def create_legal_order
    @user.orders.create!(product: :collection_pass, item_type: :legal_doc,
                         amount: Order::LEGAL_DOC_PRICE, pg_order_id: SecureRandom.uuid,
                         metadata: { invoice_id: @invoice.id })
  end

  def confirm_paid!(order)
    fake = FakePortOneClient.new(get_payment: { id: order.pg_order_id, status: "PAID" })
    with_portone_client(fake) do
      post "/webhooks/portone",
           params: { type: "Transaction.Paid", data: { paymentId: order.pg_order_id } }.to_json,
           headers: { "Content-Type" => "application/json" }
    end
    assert_response :ok
    order.reload
    assert_predicate order, :paid?
  end
end
