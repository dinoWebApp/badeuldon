# 내용증명 양식(F-LEGAL — LEGAL-1/2/3/4·Q5) — D+30 초과 미수 청구의 내용증명 양식 PDF를
# 건당 5,000원으로 판매한다. 결제는 기존 포트원 단건 플로우(수금 패스 Order 선례)를 그대로
# 재사용한다: 주문 생성 → 위젯 체크아웃(show 뷰) → App::OrdersController#callback →
# Orders::PurchaseService → Orders::FulfillPassService(item_type legal_doc는 paid 전환만).
# 주문과 청구의 결합은 orders.metadata(invoice_id)로 한다(item_type 외 스키마 변경 없음).
# LEGAL-2(PRD v0.38) — 결제 완료(paid) 주문은 워터마크 없는 정식 PDF, 미결제 주문은
# "미리보기 — 미결제" 워터마크가 찍힌 미리보기 PDF만 제공한다(무료 정식 제공 방지).
class App::LegalDocumentsController < App::BaseController
  before_action :set_order, only: %i[ show download ]
  before_action :set_portone_context, only: :show

  # LEGAL-1 — 발급 이력(내용증명 주문 최신순) + 새로 발급 가능한 대상(D+30 초과 미수 청구)
  def index
    @orders = Current.user.orders.legal_docs.order(created_at: :desc)
    @legal_targets = Current.user.invoices.unsettled.includes(:client)  # W-1 — N+1 제거
                          .select { |invoice| LegalDocuments::ContentProofPdfService.legal_target?(invoice) }
                          .sort_by(&:due_on)
  end

  # LEGAL-3 — 고지문 표시(생성 요청 화면). 대상 청구는 select + invoice_id 직접 진입 모두 지원.
  def new
    @legal_targets = Current.user.invoices.unsettled.includes(:client)
                          .select { |invoice| LegalDocuments::ContentProofPdfService.legal_target?(invoice) }
                          .sort_by(&:due_on)
  end

  # LEGAL-2 — 5,000원 단건 주문 생성(위젯 체크아웃으로 전환). 같은 청구에 결제 완료(paid)
  # 주문이 있으면 새 주문을 만들지 않고 그 주문으로 안내해 이중 결제를 차단하고(C-2),
  # 대기 주문이 있으면 재사용해 연타로 주문이 누적되지 않는다(멱등 — OrdersController#create 선례).
  def create
    invoice = scoped_legal_target(params[:invoice_id])
    if invoice.nil?
      redirect_to new_app_legal_document_path, status: :see_other,
                  alert: "내용증명 대상 청구서를 선택해 주세요."
      return
    end

    paid_order = find_paid_legal_order(invoice)
    if paid_order
      redirect_to app_legal_document_path(paid_order), status: :see_other,
                  notice: "이 청구는 이미 결제가 완료되었습니다. 기존 주문에서 내려받아 주세요."
      return
    end

    @order = find_pending_legal_order(invoice) || Current.user.orders.create!(
      product: :collection_pass,  # 단건 결제 채널 동작상 값 채움 — 품목 구분은 item_type(Order 주석 참조)
      item_type: :legal_doc,
      amount: Order::LEGAL_DOC_PRICE,
      pg_order_id: SecureRandom.uuid,
      metadata: { invoice_id: invoice.id }
    )
    redirect_to app_legal_document_path(@order), status: :see_other,
                notice: "주문이 생성되었습니다. 결제를 진행해 주세요."
  end

  # 결제 상태 + 체크아웃 위젯(pending) 또는 다운로드 버튼(paid).
  # 콜백 실패 착지(?payment_failed=1)는 안내 flash로 소비한다(W-5 — 결제 실패 복귀 UX).
  def show
    @invoice = order_invoice(@order)
    flash.now[:alert] = "결제가 승인되지 않았습니다. 다시 시도해 주세요." if params[:payment_failed].present?
  end

  # LEGAL-2 — paid 주문은 정식 PDF, 미결제 주문은 워터마크 미리보기 PDF(파일명:
  # 내용증명_{청구번호}.pdf). paid 주문의 재다운로드는 청구가 마감(paid)된 뒤에도 허용한다
  # (W-3 확정 정책 — 이미 대가를 지급했으므로 PAY-6 회계 보관용 취지로 대상 조건 재검증 없이
  # 스냅샷을 제공한다). W-4 — 문서 다운로드 행위 자체는 P4 기록 대상(발신)이 아니므로
  # 별도 기록하지 않는다(주문 레코드가 발급 이력의 기록이다).
  def download
    invoice = order_invoice(@order)
    raise LegalDocuments::ContentProofPdfService::LegalDocNotAvailable, "대상 청구서를 찾을 수 없습니다" if invoice.nil?

    pdf = LegalDocuments::ContentProofPdfService.call(
      invoice: invoice,
      watermark: !@order.paid?,
      enforce_target: !@order.paid?
    )
    send_data pdf,
              filename: "내용증명_#{invoice.issue_number}.pdf",
              type: "application/pdf"
  rescue LegalDocuments::ContentProofPdfService::LegalDocNotAvailable => e
    redirect_to app_legal_document_path(@order), status: :see_other, alert: e.message
  end

  private

  def set_order
    @order = Current.user.orders.legal_docs.find(params[:id])  # 소유권 격리
  end

  # D+30 초과 미수 청구만 내용증명 대상(LEGAL-1). 소유권은 Current.user.invoices로 담보한다.
  def scoped_legal_target(invoice_id)
    return nil if invoice_id.blank?

    invoice = Current.user.invoices.unsettled.find_by(id: invoice_id)
    return nil if invoice.blank? || !LegalDocuments::ContentProofPdfService.legal_target?(invoice)

    invoice
  end

  # C-2 — 같은 청구에 이미 결제 완료 주문이 있으면 재주문하지 않는다(이중 결제 차단).
  # create에서 pending 재사용과 함께 이중 가드를 이룬다(paid 우선 → pending 재사용).
  def find_paid_legal_order(invoice)
    Current.user.orders.paid.legal_docs
                .find_by("JSON_EXTRACT(metadata, '$.invoice_id') = ?", invoice.id)
  end

  def find_pending_legal_order(invoice)
    Current.user.orders.pending.legal_docs
                .find_by("JSON_EXTRACT(metadata, '$.invoice_id') = ?", invoice.id)
  end

  # orders.metadata(invoice_id) → 청구 레코드. 소유권은 이미 @order에서 격리됐으므로
  # Invoice는 id 역참조만 수행한다(없으면 nil — 무결성은 metadata 기록 시점 보장).
  def order_invoice(order)
    invoice_id = order.metadata.is_a?(Hash) ? order.metadata["invoice_id"] : nil
    Invoice.find_by(id: invoice_id)
  end

  # 포트원 위젯 파라미터(B1 — KG이니시스 필수 고객 정보). BillingsController와 동일 적재.
  def set_portone_context
    @portone_store_id = Rails.application.credentials.dig(:portone, :store_id)
    @portone_channel_key_normal = Rails.application.credentials.dig(:portone, :channel_key_normal)
    @portone_customer_name = Current.user.display_name
    @portone_customer_phone = Current.user.phone
    @portone_customer_email = Current.user.email
  end
end
