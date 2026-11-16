# 수금 패스 주문(F-PLAN — PLAN-4/5) — create: 단건 결제 대기 주문 생성 후 위젯 체크아웃으로
# 전환, callback: 포트원 위젯 결과(paymentId·paymentToken)를 받아 Orders::PurchaseService로
# 승인 확정. 결제 금액·주문 id는 서버가 생성한 값을 기준으로 한다(콜백 파라미터 금액은 신뢰
# 하지 않음).
class App::OrdersController < App::BaseController
  # PLAN-4 — 수금 패스 10건 4,000원 단건 결제. 대기 주문이 이미 있으면 재사용해 버튼 연타에도
  # 주문이 누적되지 않는다(멱등).
  def create
    @order = Current.user.orders.pending.collection_pass.first ||
             Current.user.orders.create!(product: :collection_pass,
                                         amount: Order.amount_for(:collection_pass),
                                         pg_order_id: SecureRandom.uuid)
    redirect_to app_billing_path(checkout: @order.pg_order_id), status: :see_other
  end

  # 포트one 위젯 결과 수신 — 실패(code 존재)는 안내로 흡수하고, 성공만 승인 확정을 시도한다.
  # 성공 응답의 paymentToken은 수동 승인 채널에서만 온다(즉시 승인 채널은 조회로 확정).
  def callback
    if payment_failed?
      redirect_to post_payment_redirect_path(order: current_user_order, failed: true),
                  status: :see_other,
                  alert: params[:message].presence || "결제가 취소되었습니다."
    else
      order = Orders::PurchaseService.new(order: current_user_order, payment_token: payment_token).call
      redirect_to post_payment_redirect_path(order: order), status: :see_other, notice: payment_notice(order)
    end
  rescue Orders::PurchaseService::PurchaseError => e
    redirect_to post_payment_redirect_path(order: current_user_order, failed: true),
                status: :see_other, alert: e.message
  end

  private

  # LEGAL-2 — 주문 품목별 결과 착지점. 수금 패스·구독 주문은 기존대로 요금제 화면,
  # 내용증명 주문은 해당 주문 상세(결제 상태·다운로드 버튼), 세금계산서 주문은 발행 주문 상세
  # (결제 상태·발행 상태 — TAX-2)로 돌려보낸다(Phase 6 C-1).
  def post_payment_redirect_path(order:, failed: false)
    if order.legal_doc?
      path = app_legal_document_path(order)
      failed ? "#{path}?payment_failed=1" : path
    elsif order.tax_invoice?
      app_tax_invoice_path(order)
    else
      app_billing_path
    end
  end

  # 품목별 완료 안내 문구(Phase 6 C-1 — tax_invoice 주문이 패스 문구로 떨어지지 않게 분기).
  def payment_notice(order)
    if order.legal_doc?
      "결제가 완료되었습니다. 내용증명 양식을 내려받을 수 있습니다."
    elsif order.tax_invoice?
      "전자세금계산서 발행 결제가 완료되었습니다. 발행 상태를 확인해 주세요."
    else
      "수금 패스(#{PaymentPass::TOTAL_USES}건)가 발급되었습니다."
    end
  end

  # 소유권 격리 — 본인 주문만 승인 대상이 된다(타인 paymentId 위조 콜백 차단).
  def current_user_order
    Current.user.orders.find_by!(pg_order_id: params[:paymentId])
  end

  def payment_failed?
    params[:code].present?
  end

  def payment_token
    params[:paymentToken].presence
  end
end
