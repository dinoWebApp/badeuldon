# 토스페이먼츠 웹훅(F-PLAN — PLAN-5) — 결제 상태 변경 이벤트 수신. 토스 서버 → 우리 서버의
# 서버 간 호출이라 세션 인증·브라우저 검사·CSRF를 적용하지 않는다. 무결성은 이벤트 값을
# 신뢰하지 않고 get_payment로 토스 서버에서 결제를 재조회해 확정한다(위조 이벤트 차단).
# 응답은 항상 200(토스 규격) — 처리 불가 이벤트는 재시도해도 같은 결과라 재시도를 유발하지 않는다.
#
# 회복 경로(이슈 #1·#4) — 승인·차감이 실제로는 성공했는데 응답이 유실된 주문은 pending으로
# 남는다. 웹훅(DONE)이 이 주문을 찾아 상품별 확정(수금 패스 발급·갱신 주기 연장)을 수행한다:
# ① paymentKey 보존 주문(단건 승인 모호 실패)은 paymentKey로, ② paymentKey를 아직 모르는
# 갱신 주문은 이벤트의 orderId(서버 발급 멱등키)로 보조 매칭한다.
class Webhooks::TossController < ActionController::Base
  skip_forgery_protection

  # 토스 결제 상태 → 주문 상태 매핑. DONE=승인, CANCELED·PARTIAL_CANCELED=취소(환불),
  # ABORTED·EXPIRED=실패, 그 외(READY·IN_PROGRESS·WAITING_FOR_DEPOSIT)=대기.
  ORDER_STATUS_BY_TOSS = {
    "DONE" => "paid", "CANCELED" => "cancelled", "PARTIAL_CANCELED" => "cancelled",
    "ABORTED" => "failed", "EXPIRED" => "failed", "READY" => "pending",
    "IN_PROGRESS" => "pending", "WAITING_FOR_DEPOSIT" => "pending"
  }.freeze

  # paymentStatusChanged — 주문을 찾아 get_payment 재조회로 상태를 확정한다.
  # 수금 패스 주문의 취소(CANCELED — 토스 콘솔 환불)까지 상태만 동기화하며, 패스 회수·
  # 환불 처리는 정책상 토스 콘솔 수동 절차(PLAN-6)라 여기서 수행하지 않는다.
  def create
    event = JSON.parse(request.raw_post)
    sync_payment_status(event) if event["eventType"] == "paymentStatusChanged"
    head :ok
  rescue JSON::ParserError, ActiveRecord::RecordNotFound
    head :ok
  end

  private

  def sync_payment_status(event)
    data = event["data"] || {}
    payment_key = data["paymentKey"]
    return if payment_key.blank? # paymentKey 없는 이벤트는 재조회 불가 — 전체 스캔 방어

    order = locate_order(data, payment_key)
    return unless order # 알 수 없는 결제 — 흡수(재시도 무의미)

    payment = TossPayments::ClientService.new.get_payment(payment_key: payment_key)
    # orderId 보조 매칭 주문은 재조회 응답이 같은 주문의 결제임을 확인한다(위조 이벤트가
    # 타 주문 paymentKey와 결합되는 것 차단).
    return if order.toss_payment_key.blank? && payment[:orderId] != order.toss_order_id

    # 이벤트가 아니라 재조회 응답을 기준으로 확정한다(무결성). 이미 같은 상태면 무변경(멱등).
    status = ORDER_STATUS_BY_TOSS.fetch(payment[:status], order.status)
    apply_status(order, status, payment, payment_key)
  end

  def locate_order(data, payment_key)
    order = Order.find_by(toss_payment_key: payment_key)
    return order if order

    Order.find_by(toss_order_id: data["orderId"]) if data["orderId"].present?
  end

  # 주문 상태 반영 — pending→paid 전환은 상품별 확정을 동반한다. 그 밖의 전환
  # (pending→실패·취소, paid→cancelled 환불)은 단순 동기화다.
  def apply_status(order, status, payment, payment_key)
    return if order.status == status
    return settle_paid(order, payment, payment_key) if order.pending? && status == "paid"

    order.update!(status: status)
  end

  def settle_paid(order, payment, payment_key)
    if order.collection_pass?
      Orders::FulfillPassService.new(order: order, payment_key: payment_key,
                                     response: payment).call
    else
      Subscriptions::UpgradeService.new(user: order.user, action: :settle_renewal,
                                        order: order, payment: payment).call
    end
  end
end
