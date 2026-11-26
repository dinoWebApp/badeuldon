# TAX-1 — 전자세금계산서 발행(건당 300원·Q21 포트원 단건 재사용). 내용증명(LegalDocuments)의
# 건당 결제 플로우 선례 그대로: 미리보기(new) → 주문 생성(create) → 위젯 체크아웃(show) →
# 콜백·웹훅 확정(FulfillTaxInvoiceService → IssueService — 결제 완료 후에만 발행). 주문과 청구의
# 결합은 orders.metadata(invoice_id)다. 발행 이력·취소는 show에서 제공한다(TAX-2·1건 1발행).
class App::TaxInvoicesController < App::BaseController
  include TaxInvoiceGate

  before_action :set_order, only: %i[ show cancel ]
  before_action :set_portone_context, only: :show
  # TAX-4 — 운영 준비 게이트(기본 꺼짐): new·create 직접 URL 접속을 대시보드로 되돌린다.
  # show·cancel은 유지한다 — 이미 결제·발행한 사용자의 상태 조회·취소 경로는 끊지 않는다(Q26).
  before_action :require_tax_invoice_feature, only: %i[ new create ]
  # TAX-3 ② — 발행 화면 진입(new·create 공용) 가드(리뷰 C-1). 기능 게이트 다음에 대상
  # 청구 로드 → 자격·전제 판정으로 막히면 청구서 상세로 되돌린다 — 패널이 같은 사유를
  # 안내하고, 발행 화면(결제 버튼이 남은 화면)으로 되돌리면 막다른 길이 된다.
  before_action :load_issue_invoice, only: %i[ new create ]
  before_action :guard_issue_entry, only: %i[ new create ]

  # 발행 전 확인 미리보기(공급자/공급받는자/품목/금액) — 대상 로드·가드는 before_action이 담당한다.
  def new; end

  # Q21 — 300원 단건 주문 생성(위젯 체크아웃으로 전환). 결제는 create에서 하지 않고 주문만
  # 만든다(발행 자체는 결제 완료 후 웹훅·콜백 확정점에서만 수행 — 이중 발행 차단 1차 가드).
  # Phase 6 C-2 — paid 주문 가드로 이중 결제 차단(SOAP 실패로 발행 레코드가 미생성된 청구의
  # 재결제 방지 — LEGAL find_paid_legal_order 선례). W-2 — 생성 책임은 CreateOrderService로.
  # F-1(마감 리뷰 2026-11-25) — 같은 청구에 검증 실패 주문이 있으면 그 주문 상세로 되돌린다
  # (paid 가드보다 앞 — pending 재사용으로 결제창을 다시 열게 두지 않는다). TAX-3 — 대상
  # 로드·자격 가드는 before_action이 담당하고, IneligibleUser 서비스 예외는 이중 방어로
  # 유지한다(결제 전 차단).
  def create
    blocked_order = Order.verification_failed_for(Current.user, item_type: :tax_invoice, invoice_id: @invoice.id)
    return redirect_verification_failed_order(blocked_order) if blocked_order

    paid_order = Order.tax_invoice_order_for(@invoice, paid: true)
    return redirect_existing_paid_order(paid_order) if paid_order

    @order = TaxInvoices::CreateOrderService.call(user: Current.user, invoice: @invoice)
    redirect_to app_tax_invoice_path(@order), status: :see_other,
                notice: "주문이 생성되었습니다. 결제를 진행해 주세요."
  rescue TaxInvoices::CreateOrderService::IneligibleUser => e
    redirect_guard_message(e.message)
  end

  # 결제 상태 + 발행 상태(TAX-2) + 체크아웃 위젯(pending) 표시.
  def show
    @invoice = order_invoice(@order)
    @tax_invoice = @invoice&.tax_invoice
    # TAX-3/4(리뷰 C-2) — pending 주문의 상세는 결제 화면이기도 하다. 꺼짐·부적격이면 결제
    # 진입을 막고 안내를 넘긴다(뷰가 체크아웃 대신 안내 카드 — 조회는 200 유지, paid는 ④ 허용).
    @tax_invoice_blocked_notice = tax_invoice_payment_block_notice if @order.pending?
    set_payment_failure_alert
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

  # 결제 실패 착지(?payment_failed=1) 안내. 우선순위(R2-2 + F-2·F-3 — 마감 리뷰 2026-11-25):
  # ① 검증 실패 주문(PLAN-5 결제 확정 검증 거절 — Order#verification_failed?)은 다시 결제하게
  # 두면 안 된다(잘못 걸러진 정상 결제라면 이중 결제) — 문의 안내. ② pending 회복 대기 주문
  # (승인 됐거나 될 수 있으나 재조회 실패 — Order#pending_recovery_waiting?)은 "다시 시도"
  # 대신 회복 안내. ③ 그 외 결제 실패 착지는 기존 재시도 안내. 뷰도 ① 판정으로 재발행 버튼을
  # 숨긴다(app/views/app/tax_invoices/show.html.erb).
  def set_payment_failure_alert
    if @order.verification_failed?
      flash.now[:alert] = Order::VERIFICATION_FAILED_USER_NOTICE
    elsif @order.pending_recovery_waiting?
      flash.now[:alert] = Order::PENDING_RECOVERY_NOTICE
    elsif params[:payment_failed].present?
      flash.now[:alert] = "결제가 승인되지 않았습니다. 다시 시도해 주세요."
    end
  end

  def set_order
    @order = Current.user.orders.tax_invoices.find(params[:id])  # 소유권 격리
  end

  def scoped_invoice(invoice_id)
    return nil if invoice_id.blank?

    Current.user.invoices.find_by(id: invoice_id)
  end

  # TAX-3 ② — 발행 대상 청구 로드(new·create 공용). 미마감 청구는 목록으로 되돌린다
  # (기존 new·create의 동작을 그대로 이동 — 소유권 격리는 scoped_invoice(Current.user
  # 스코프)로 담보한다).
  def load_issue_invoice
    @invoice = scoped_invoice(params[:invoice_id])
    return if @invoice&.paid?

    redirect_to app_invoices_path, status: :see_other,
                alert: "수금이 마감된 청구서만 발행할 수 있습니다."
  end

  # TAX-3 ② — 발행 진입 가드(리뷰 C-1 — new·create 공용). 막힌 사유는 issue_guard_message
  # (IssueService.verify_guards!와 동일 기준을 U1 문구로 표현)로 판정해 청구서 상세로
  # 되돌린다 — 청구 상세 패널이 같은 사유를 안내한다.
  def guard_issue_entry
    guard_message = issue_guard_message(@invoice)
    return if guard_message.blank?

    redirect_to app_invoice_path(@invoice), status: :see_other, alert: guard_message
  end

  # 발행 가드(순서 안내 — IssueService.verify_guards!와 동일 기준을 U1 문구로 표현).
  # TAX-3 — 발급 자격(간이과세·면세사업자)을 맨 앞에서 판정한다(문구는 User 단일 출처).
  def issue_guard_message(invoice)
    return Current.user.tax_invoice_ineligibility_notice unless Current.user.tax_invoice_eligible?
    return "전자세금계산서 발행 설정을 먼저 완료해 주세요." unless Current.user.tax_invoice_ready?
    return "거래처 사업자번호가 없어 발행할 수 없습니다(개인 거래처는 비대상입니다)." if invoice.client.corp_num.blank?
    return "이미 발행 요청된 청구서입니다." if TaxInvoice.for_invoice(invoice).exists?

    nil
  end

  # Phase 6 C-2/W-2 — create 분기 수렴용 리다이렉트 헬퍼들.
  def redirect_existing_paid_order(order)
    redirect_to app_tax_invoice_path(order), status: :see_other,
                notice: "이 청구는 이미 결제가 완료되었습니다. 기존 주문에서 발행 상태를 확인해 주세요."
  end

  # F-1 — 검증 실패 주문이 있는 청구의 재발행 create 차단. 그 주문 상세로 되돌린다
  # (상세 화면이 검증 실패 안내를 보여 준다 — LegalDocumentsController 선례).
  def redirect_verification_failed_order(order)
    redirect_to app_tax_invoice_path(order), status: :see_other,
                alert: Order::VERIFICATION_FAILED_REORDER_NOTICE
  end

  # TAX-3 — 가드 안내 수렴점(리뷰 C-1 — 대상을 청구서 상세로 통일). new로 되돌리면 결제
  # 버튼이 남은 막다른 길이 되며, 무한 리다이렉트가 생긴다. create의 IneligibleUser
  # rescue도 같은 경로로 수렴한다(이중 방어 — 컨트롤러 가드가 먼저 걸린다).
  def redirect_guard_message(message)
    redirect_to app_invoice_path(@invoice), status: :see_other, alert: message
  end

  def order_invoice(order)
    invoice_id = order.metadata.is_a?(Hash) ? order.metadata["invoice_id"] : nil
    Invoice.find_by(id: invoice_id)
  end

  # 포트원 위젯 파라미터(B1 — KG이니시스 필수 고객 정보. LegalDocumentsController 선례).
  def set_portone_context
    @portone_store_id = Rails.application.credentials.dig(:portone, :store_id)
    @portone_channel_key_normal = PortOne::ChannelKey.normal  # 환경 선택기(PLAN-5)
    @portone_customer_name = Current.user.display_name
    @portone_customer_phone = Current.user.phone
    @portone_customer_email = Current.user.email
  end
end
