import { Controller } from "@hotwired/stimulus"

// 토스페이먼츠 단건 결제 위젯 호출(F-PLAN — PLAN-4 수금 패스).
// UI 접점만 담당하는 Stimulus(규약 — 비즈니스 로직 금지): 주문 생성·승인 확정은
// 서버(App::OrdersController#create/#callback → Orders::PurchaseService)가 수행한다.
export default class extends Controller {
  static values = {
    clientKey: String,
    orderId: String,
    amount: Number,
    successUrl: String,
    failUrl: String
  }

  pay() {
    const tossPayments = TossPayments(this.clientKeyValue)

    tossPayments.requestPayment("카드", {
      amount: this.amountValue,
      orderId: this.orderIdValue,
      orderName: "수금 패스 10건권",
      successUrl: this.successUrlValue,
      failUrl: this.failUrlValue
    })
  }
}
