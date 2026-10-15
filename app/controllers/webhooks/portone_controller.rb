# 포트원 웹훅(PLAN-5) — 결제 트랜잭션 이벤트 수신. 포트원 서버 → 우리 서버의 서버 간 호출이라
# 세션 인증·브라우저 검사·CSRF를 적용하지 않는다. 무결성은 이벤트 값을 신뢰하지 않고
# get_payment로 포트원 서버에서 결제를 재조회해 확정한다(포트원 권장 전략 — 위조 이벤트 차단).
# 응답은 항상 200(포트원 규격 — 처리 불가 이벤트는 재시도해도 같은 결과라 재시도를 유발하지
# 않는다. 알 수 없는 type도 에러 없이 흡수한다).
#
# 이벤트 본문(웹훅 버전 2024-04-25) — { type: "Transaction.Paid", data: { paymentId, ... } }.
# data.paymentId는 위젯·빌링키 결제 모두 서버가 채번한 pg_order_id다.
#
# 회복 경로(이슈 #1·#4) — 승인·차감이 실제로는 성공했는데 응답이 유실된 주문은 pending으로
# 남는다. 웹훅이 이 주문을 찾아 상품별 확정(수금 패스 발급·갱신 주기 연장)을 수행한다.
class Webhooks::PortOneController < ActionController::Base
  skip_forgery_protection

  # 결제 확정·소멸 트랜잭션만 동기화 대상 — 결제창 오픈(Ready)·승인 대기(PayPending)·취소 요청
  # (CancelPending)·빌링키 발급 계열(BillingKey.*)·미지원 신규 type은 흡수한다.
  SYNCED_EVENT_TYPES = %w[
    Transaction.Paid
    Transaction.Failed
    Transaction.Cancelled
    Transaction.PartialCancelled
  ].freeze

  # 포트원 결제 상태 → 주문 상태 매핑. PAID=승인, CANCELLED 계열=취소(환불),
  # FAILED=실패, 그 외(READY·PAY_PENDING·VIRTUAL_ACCOUNT_ISSUED)=대기(현상 유지).
  ORDER_STATUS_BY_PORTONE = {
    "PAID" => "paid",
    "CANCELLED" => "cancelled", "PARTIAL_CANCELLED" => "cancelled",
    "CONSOLE_CANCELLED" => "cancelled", "FAILED" => "failed"
  }.freeze

  def create
    event = JSON.parse(request.raw_post)
    sync_payment_status(event) if SYNCED_EVENT_TYPES.include?(event["type"])
    head :ok
  rescue JSON::ParserError, ActiveRecord::RecordNotFound
    head :ok
  end

  private

  # paymentStatusChanged 이벤트와 달리 트랜잭션 이벤트 — paymentId로 주문을 찾아
  # get_payment 재조회로 상태를 확정한다. 수금 패스 주문의 취소(Transaction.Cancelled —
  # 포트원 콘솔 환불)까지 상태만 동기화하며, 패스 회수·환불 처리는 정책상 콘솔 수동 절차
  # (PLAN-6)라 여기서 수행하지 않는다.
  def sync_payment_status(event)
    payment_id = event.dig("data", "paymentId")
    return if payment_id.blank? # paymentId 없는 이벤트는 재조회 불가 — 전체 스캔 방어

    order = locate_order(payment_id)
    return unless order # 알 수 없는 결제 — 흡수(재시도 무의미)

    payment = PortOne::ClientService.new.get_payment(payment_id: payment_id)
    # 재조회 응답이 같은 주문의 결제임을 확인한다(위조 이벤트가 타 주문 paymentId와
    # 결합되는 것 차단).
    return if payment[:id] != order.pg_order_id

    # 이벤트가 아니라 재조회 응답을 기준으로 확정한다(무결성). 이미 같은 상태면 무변경(멱등).
    status = ORDER_STATUS_BY_PORTONE.fetch(payment[:status], order.status)
    apply_status(order, status, payment)
  end

  # paymentId(pg_order_id)로 조회한다. 결제 ID 스냅샷(pg_payment_id)도 보조 경로로 둔다 —
  # 두 컬럼은 같은 값을 담지만 웹훅 매칭의 1차·보조 키 역할을 나눈다.
  def locate_order(payment_id)
    Order.find_by(pg_order_id: payment_id) || Order.find_by(pg_payment_id: payment_id)
  end

  # 주문 상태 반영 — pending→paid 전환은 상품별 확정을 동반한다. 그 밖의 전환
  # (pending→실패·취소, paid→cancelled 환불)은 단순 동기화다.
  def apply_status(order, status, payment)
    return if order.status == status
    return settle_paid(order, payment) if order.pending? && status == "paid"

    order.update!(status: status)
  end

  def settle_paid(order, payment)
    if order.collection_pass?
      Orders::FulfillPassService.new(order: order, payment_id: order.pg_order_id,
                                     response: payment).call
    else
      Subscriptions::UpgradeService.new(user: order.user, action: :settle_renewal,
                                        order: order, payment: payment).call
    end
  end
end
