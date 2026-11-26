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

    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: order.pg_order_id,
                                                  amount: Order::LEGAL_DOC_PRICE)
    )
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

  test "F-1: 검증 실패 주문이 있는 청구의 create는 새 주문을 만들지 않고 그 주문으로 되돌린다" do
    sign_in_as @user
    failed_order = create_legal_order
    failed_order.mark_verification_failed!(reason: "amount_mismatch", detail: "paid=100 expected=5000")

    assert_no_difference -> { @user.orders.legal_docs.count } do
      post app_legal_documents_path, params: { invoice_id: @invoice.id }
    end

    assert_response :redirect
    assert_redirected_to app_legal_document_path(failed_order)
    assert_equal Order::VERIFICATION_FAILED_REORDER_NOTICE, flash[:alert]
  end

  test "F-1: 검증 실패 주문이 있으면 대기 주문이 있어도 재사용해 결제창을 열지 않는다" do
    sign_in_as @user
    failed_order = create_legal_order
    failed_order.mark_verification_failed!(reason: "channel_mismatch", detail: "type=LIVE expected=TEST")
    create_legal_order  # 대기 주문이 함께 있어도 검증 실패 주문이 우선이다(pending 가드보다 앞)

    assert_no_difference -> { @user.orders.legal_docs.count } do
      post app_legal_documents_path, params: { invoice_id: @invoice.id }
    end

    assert_redirected_to app_legal_document_path(failed_order)
  end

  test "F-1 회귀: 검증 실패 주문이 없으면 대기 주문을 재사용해 결제 진행을 안내한다 (기존 동작)" do
    sign_in_as @user
    pending_order = create_legal_order

    assert_no_difference -> { @user.orders.legal_docs.count } do
      post app_legal_documents_path, params: { invoice_id: @invoice.id }
    end

    assert_response :redirect
    assert_redirected_to app_legal_document_path(pending_order)
    assert_match "주문이 생성되었습니다", flash[:notice]
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

  # ── PLAN-9 환불 실행 — 회원 표기(Q27·W-5c) ──

  test "환불된 주문은 목록에 환불됨 배지로 남는다 (PLAN-9)" do
    sign_in_as @user
    order = create_legal_order
    confirm_paid!(order)
    refund!(order)

    get app_legal_documents_path

    assert_response :success
    assert_match order.pg_order_id, response.body, "환불 주문도 발급 이력에 남는다(P4)"
    assert_match "환불됨", response.body
  end

  test "환불된 주문 상세는 환불 안내를 보여주고 정식 다운로드 버튼이 없다 (PLAN-9·W-5c)" do
    sign_in_as @user
    order = create_legal_order
    confirm_paid!(order)
    refund!(order)

    get app_legal_document_path(order)

    assert_response :success
    assert_match "이 주문은 환불되었습니다.", response.body
    assert_match "새로 주문해 주세요", response.body, "재주문 안내"
    assert_no_match "내용증명 PDF 내려받기", response.body, "정식 PDF 다운로드 버튼은 노출하지 않는다"
  end

  test "환불된 주문의 download는 정식 PDF가 아닌 워터마크 미리보기를 돌려준다 (기존 paid 한정 규칙)" do
    sign_in_as @user
    order = create_legal_order
    confirm_paid!(order)
    refund!(order)

    get download_app_legal_document_path(order)

    assert_response :ok
    assert_equal "application/pdf", response.media_type
    assert_not_equal LegalDocuments::ContentProofPdfService.call(invoice: @invoice), response.body,
                     "환불 건은 정식(워터마크 없는) PDF를 돌려주지 않는다"
  end

  private

  def create_legal_order
    @user.orders.create!(product: :collection_pass, item_type: :legal_doc,
                         amount: Order::LEGAL_DOC_PRICE, pg_order_id: SecureRandom.uuid,
                         metadata: { invoice_id: @invoice.id })
  end

  def confirm_paid!(order)
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: order.pg_order_id,
                                                  amount: Order::LEGAL_DOC_PRICE)
    )
    with_portone_client(fake) do
      post "/webhooks/portone",
           params: { type: "Transaction.Paid", data: { paymentId: order.pg_order_id } }.to_json,
           headers: { "Content-Type" => "application/json" }
    end
    assert_response :ok
    order.reload
    assert_predicate order, :paid?
  end

  # PLAN-9 — 실제 실행 경로로 환불 상태를 만든다(서비스에 client: 주입 — 실호출 0).
  def refund!(order)
    fake = FakePortOneClient.new(get_payment: { id: order.pg_order_id, status: "CANCELLED",
                                                amount: { paid: order.amount,
                                                          cancelled: order.amount } })
    result = Orders::RefundService.new(admin: admins(:ops), order: order,
                                       reason: "이중 결제 정정", client: fake).call
    assert result.success?, "전제: 환불 실행이 성공해야 한다"
    order.reload
  end

  # ── PLAN-5 채널 키 선택기·검증 실패 주문 안내(R2-2)·R2-1 워터마크 — Tester 단계 ──
  # 채널 키는 선택기를 테스트 값으로 고정해 실제 credentials(로컬/CI 차이)에 의존하지 않는다.

  test "검증 실패 주문은 뒤늦은 Transaction.Paid로도 확정되지 않고 미리보기(워터마크) PDF만 준다 (R2-1·LEGAL-2)" do
    sign_in_as @user
    order = create_legal_order
    order.mark_verification_failed!(reason: "amount_mismatch", detail: "paid=100 expected=5000")
    assert_predicate order.reload, :failed?

    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: order.pg_order_id,
                                                  amount: Order::LEGAL_DOC_PRICE)
    )
    with_portone_client(fake) do
      post "/webhooks/portone",
           params: { type: "Transaction.Paid", data: { paymentId: order.pg_order_id } }.to_json,
           headers: { "Content-Type" => "application/json" }
    end

    assert_response :ok
    order.reload
    assert_predicate order, :failed?
    assert_nil order.paid_at
    assert_equal @invoice.id, order.metadata["invoice_id"]     # 검증 실패 기록 병합 후에도 보존(B-1)
    assert_empty users(:gamma).payment_passes

    get download_app_legal_document_path(order)
    assert_response :ok
    assert_equal "application/pdf", response.media_type
    assert_not_equal LegalDocuments::ContentProofPdfService.call(invoice: @invoice), response.body,
                     "미결제 취급 — 워터마크 미리보기만 제공한다(정식 PDF 유출 차단)"
  end

  test "검증 실패 주문 상세는 문의 안내를 보여주고 재주문 유도가 없다 (R2-2)" do
    sign_in_as @user
    order = create_legal_order
    order.mark_verification_failed!(reason: "amount_mismatch", detail: "paid=100 expected=5000")

    get app_legal_document_path(order)

    assert_response :success
    assert_match "결제 확인에 실패했습니다. 다시 결제하지 말고 고객지원(문의)으로 연락해 주세요.", response.body
    assert_match "고객지원에 문의", response.body               # 문의 링크(티켓)
    assert_no_match "새 양식 발급", response.body               # 재주문 버튼 없음
    assert_no_match "새로 주문해 주세요", response.body
    assert_no_match "확인하고 있으니", response.body            # F-2 — 자동 확인 중 함축 문구 없음
  end

  test "검증 실패 안내는 payment_failed 파라미터보다 우선이다 (R2-2)" do
    sign_in_as @user
    order = create_legal_order
    order.mark_verification_failed!(reason: "channel_mismatch", detail: "type=LIVE expected=TEST")

    get app_legal_document_path(order, params: { payment_failed: "1" })

    assert_response :success
    assert_match "결제 확인에 실패했습니다. 다시 결제하지 말고 고객지원(문의)으로 연락해 주세요.", response.body
    assert_no_match "결제가 승인되지 않았습니다", response.body # 위젯 실패 문구로 덮어쓰지 않는다
  end

  test "일반 결제 실패 주문 상세는 기존 재주문 안내를 유지한다 (R2-2 회귀)" do
    sign_in_as @user
    order = create_legal_order
    order.update!(status: :failed, metadata: { invoice_id: @invoice.id,
                                               code: "PG_PROVIDER_ERROR", message: "카드 한도 초과" })

    get app_legal_document_path(order)

    assert_response :success
    assert_match "새로 주문해 주세요", response.body
    assert_match "새 양식 발급", response.body                  # 재주문 버튼 유지
    assert_no_match "다시 결제하지 말고 고객지원", response.body
  end

  test "F-3: pending 회복 대기 주문의 payment_failed 착지는 재시도 안내 대신 회복 안내를 보여준다" do
    sign_in_as @user
    order = create_legal_order
    order.update!(metadata: order.metadata.merge("pending_recovery" => true))

    get app_legal_document_path(order, params: { payment_failed: "1" })

    assert_response :success
    assert_match "결제 확인이 지연되고 있습니다. 승인 결과는 잠시 후 자동으로 반영됩니다.", response.body
    assert_no_match "결제가 승인되지 않았습니다", response.body  # "다시 시도"로 덮어쓰지 않는다
  end

  test "채널 키가 없는 환경의 결제 대기 상세는 결제 버튼 대신 안내를 보여준다 (PLAN-5·W-1)" do
    sign_in_as @user
    order = create_legal_order

    with_portone_channel_keys(normal: nil) do
      get app_legal_document_path(order)
    end

    assert_response :success
    assert_match "결제 채널이 설정되지 않았습니다", response.body
    assert_select "button", text: "결제하기", count: 0
    assert_select "[data-controller=portone-payment]", count: 1  # 위젯 블록 유지 — W-1 결정 범위
  end

  test "채널 키가 있고 연락처가 없으면 연락처 등록 안내를 보여준다 (PLAN-5)" do
    sign_in_as @user
    order = create_legal_order
    @user.update!(phone: nil)

    with_portone_channel_keys(normal: "test-channel-normal-sentinel") do
      get app_legal_document_path(order)
    end

    assert_response :success
    assert_match "결제에는 연락처가 필요합니다", response.body
    assert_select "button", text: "결제하기", count: 0
  end

  test "채널 키·연락처가 모두 있으면 결제 버튼과 선택기 키 값을 심는다 (PLAN-5)" do
    sign_in_as @user
    order = create_legal_order

    with_portone_channel_keys(normal: "test-channel-normal-sentinel") do
      get app_legal_document_path(order)
    end

    assert_response :success
    assert_select "button", text: "결제하기", count: 1
    assert_select "[data-portone-payment-channel-key-value=test-channel-normal-sentinel]", count: 1
  end
end
