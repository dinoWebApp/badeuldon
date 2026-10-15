# 수금 패스 주문(F-PLAN — PLAN-4/5) — create: 단건 결제 대기 주문 생성 후 위젯 체크아웃으로
# 전환, callback: 토스 리다이렉트(paymentKey)를 받아 Orders::PurchaseService로 승인 확정.
# 결제 금액·주문 id는 서버가 생성한 값을 기준으로 한다(콜백 파라미터 금액은 신뢰하지 않음).
class App::OrdersController < App::BaseController
  # PLAN-4 — 수금 패스 10건 4,000원 단건 결제. 대기 주문이 이미 있으면 재사용해 버튼 연타에도
  # 주문이 누적되지 않는다(멱등).
  def create
    @order = Current.user.orders.pending.collection_pass.first ||
             Current.user.orders.create!(product: :collection_pass,
                                         amount: Order.amount_for(:collection_pass),
                                         toss_order_id: SecureRandom.uuid)
    redirect_to app_billing_path(checkout: @order.toss_order_id), status: :see_other
  end

  # 토스 위젯 성공/실패 리다이렉트 — 성공(paymentKey 존재)만 승인 확정을 시도한다.
  def callback
    if payment_key.present?
      Orders::PurchaseService.new(order: current_user_order, payment_key: payment_key).call
      redirect_to app_billing_path, status: :see_other,
                  notice: "수금 패스(#{PaymentPass::TOTAL_USES}건)가 발급되었습니다."
    else
      redirect_to app_billing_path, status: :see_other,
                  alert: params[:message].presence || "결제가 취소되었습니다."
    end
  rescue Orders::PurchaseService::PurchaseError => e
    redirect_to app_billing_path, status: :see_other, alert: e.message
  end

  private

  # 소유권 격리 — 본인 주문만 승인 대상이 된다(타인 paymentKey 위조 콜백 차단).
  def current_user_order
    Current.user.orders.find_by!(toss_order_id: params[:orderId])
  end

  def payment_key
    params[:paymentKey].presence
  end
end
