# TAX-1 — 전자세금계산서 발행(건당 300원·Q21 포트원 단건 재사용). 내용증명(LegalDocuments)의
# 건당 결제 플로우 선례 그대로: 미리보기(new) → 주문 생성(create) → 위젯 체크아웃(show) →
# 콜백·웹훅 확정(FulfillTaxInvoiceService → IssueService — 결제 완료 후에만 발행). 주문과 청구의
# 결합은 orders.metadata(invoice_id)다. 발행 이력·취소는 show에서 제공한다(TAX-2·1건 1발행).
class App::TaxInvoicesController < App::BaseController
  before_action :set_order, only: %i[ show cancel ]
  before_action :set_portone_context, only: :show

  # 발행 전 확인 미리보기(공급자/공급받는자/품목/금액) — 대상은 paid 청구 한정.
  def new
    @invoice = scoped_invoice(params[:invoice_id])
    if @invoice.nil? || !@invoice.paid?
      redirect_to app_invoices_path, status: :see_other,
                  alert: "수금이 마감된 청구서만 발행할 수 있습니다." and return
    end
  end

  # Q21 — 300원 단건 주문 생성(위젯 체크아웃으로 전환). 결제는 create에서 하지 않고 주문만
  # 만든다(발행 자체는 결제 완료 후 웹훅·콜백 확정점에서만 수행 — 이중 발행 차단 1차 가드).
  # Phase 6 C-2 — paid 주문 가드로 이중 결제 차단(SOAP 실패로 발행 레코드가 미생성된 청구의
  # 재결제 방지 — LEGAL find_paid_legal_order 선례). W-2 — 생성 책임은 CreateOrderService로.
  def create
    @invoice = scoped_invoice(params[:invoice_id])
    return redirect_unpaid_invoice unless @invoice&.paid?

    paid_order = Order.tax_invoice_order_for(@invoice, paid: true)
    return redirect_existing_paid_order(paid_order) if paid_order

    guard_message = issue_guard_message(@invoice)
    return redirect_guard_message(guard_message) if guard_message

    @order = TaxInvoices::CreateOrderService.call(user: Current.user, invoice: @invoice)
    redirect_to app_tax_invoice_path(@order), status: :see_other,
                notice: "주문이 생성되었습니다. 결제를 진행해 주세요."
  end

  # 결제 상태 + 발행 상태(TAX-2) + 체크아웃 위젯(pending) 표시.
  def show
    @invoice = order_invoice(@order)
    @tax_invoice = @invoice&.tax_invoice
    flash.now[:alert] = "결제가 승인되지 않았습니다. 다시 시도해 주세요." if params[:payment_failed].present?
  end

  # 발급 취소(TAX-1 — 취소도 과금 전제). 국세청 전송 전에만 가능하며 실패 사유를 안내한다.
  def cancel
    @tax_invoice = order_invoice(@order)&.tax_invoice
    if @tax_invoice.nil?
      redirect_to app_tax_invoice_path(@order), status: :see_other,
                  alert: "발행 기록을 찾을 수 없습니다."
      return
    end

    TaxInvoices::CancelService.new(tax_invoice: @tax_invoice).call
    redirect_to app_invoice_path(@tax_invoice.invoice), status: :see_other,
                notice: "전자세금계산서 발급이 취소되었습니다."
  rescue TaxInvoices::CancelService::NotCancelable => e
    redirect_to app_tax_invoice_path(@order), status: :see_other, alert: e.message
  end

  private

  def set_order
    @order = Current.user.orders.tax_invoices.find(params[:id])  # 소유권 격리
  end

  def scoped_invoice(invoice_id)
    return nil if invoice_id.blank?

    Current.user.invoices.find_by(id: invoice_id)
  end

  # 발행 가드(순서 안내 — IssueService.verify_guards!와 동일 기준을 U1 문구로 표현).
  def issue_guard_message(invoice)
    return "전자세금계산서 발행 설정을 먼저 완료해 주세요." unless Current.user.tax_invoice_ready?
    return "거래처 사업자번호가 없어 발행할 수 없습니다(개인 거래처는 비대상입니다)." if invoice.client.corp_num.blank?
    return "이미 발행 요청된 청구서입니다." if TaxInvoice.for_invoice(invoice).exists?

    nil
  end

  # Phase 6 C-2/W-2 — create 분기 수렴용 리다이렉트 헬퍼들.
  def redirect_unpaid_invoice
    redirect_to app_invoices_path, status: :see_other,
                alert: "수금이 마감된 청구서만 발행할 수 있습니다."
  end

  def redirect_existing_paid_order(order)
    redirect_to app_tax_invoice_path(order), status: :see_other,
                notice: "이 청구는 이미 결제가 완료되었습니다. 기존 주문에서 발행 상태를 확인해 주세요."
  end

  def redirect_guard_message(message)
    redirect_to new_app_tax_invoice_path(invoice_id: @invoice.id), status: :see_other, alert: message
  end

  def order_invoice(order)
    invoice_id = order.metadata.is_a?(Hash) ? order.metadata["invoice_id"] : nil
    Invoice.find_by(id: invoice_id)
  end

  # 포트원 위젯 파라미터(B1 — KG이니시스 필수 고객 정보. LegalDocumentsController 선례).
  def set_portone_context
    @portone_store_id = Rails.application.credentials.dig(:portone, :store_id)
    @portone_channel_key_normal = Rails.application.credentials.dig(:portone, :channel_key_normal)
    @portone_customer_name = Current.user.display_name
    @portone_customer_phone = Current.user.phone
    @portone_customer_email = Current.user.email
  end
end
