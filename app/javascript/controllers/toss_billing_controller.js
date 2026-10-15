import { Controller } from "@hotwired/stimulus"

// 토스페이먼츠 카드(자동결제) 인증 위젯 호출(F-PLAN — PLAN-5 빌링키).
// UI 접점만 담당한다: 인증 완료 시 토스가 successUrl(App::SubscriptionsController#update 경유
// card_callback)로 authKey를 전달하고, 서버가 빌링키 발급·활성화를 수행한다.
export default class extends Controller {
  static values = {
    clientKey: String,
    customerKey: String,
    successUrl: String,
    failUrl: String
  }

  register(event) {
    event.preventDefault() // 위젯 호출로 흐름을 대체한다 — 폼·링크 전송은 없다.

    const tossPayments = TossPayments(this.clientKeyValue)

    tossPayments.requestBillingAuth("카드", {
      customerKey: this.customerKeyValue,
      successUrl: this.successUrlValue,
      failUrl: this.failUrlValue
    })
  }
}
