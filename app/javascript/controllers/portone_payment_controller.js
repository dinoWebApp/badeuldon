import { Controller } from "@hotwired/stimulus"

// 포트원 단건 결제 위젯 호출(F-PLAN — PLAN-4 수금 패스).
// UI 접점만 담당하는 Stimulus(규약 — 비즈니스 로직 금지): 주문 생성·승인 확정은
// 서버(App::OrdersController#create/#callback → Orders::PurchaseService)가 수행한다.
//
// KG이니시스 필수 파라미터(B1) — customer.fullName은 항상, phoneNumber·email은 PC 결제에서
// 필수(모바일은 선택). 값은 컨트롤러가 적재한 사용자 정보를 data 속성으로 받는다.
// redirectUrl(C2) — 설정하면 SDK가 결제 후 콜백 URL로 페이지를 이동시킨다. 미설정 반환값
// 방식은 모바일에서 결제 UI가 표시되지 않을 수 있다(포트원 문서 — U1은 모바일 웹 사용 주류).
// SDK가 응답 필드(paymentId·paymentToken·code·message)를 쿼리로 그대로 전달하므로 서버
// 콜백 파싱은 반환값 방식과 동일하다.
export default class extends Controller {
  static values = {
    storeId: String,
    channelKey: String,
    paymentId: String,
    amount: Number,
    callbackUrl: String,
    customerName: String,
    customerPhone: String,
    customerEmail: String
  }

  async pay() {
    if (typeof PortOne === "undefined") return // SDK 미로드(테스트 환경) — 서버 동작 무영향

    const customer = { fullName: this.customerNameValue } // KG이니시스 — 항상 필수
    if (this.customerPhoneValue) customer.phoneNumber = this.customerPhoneValue // PC 필수
    if (this.customerEmailValue) customer.email = this.customerEmailValue // PC 필수

    const response = await PortOne.requestPayment({
      storeId: this.storeIdValue,
      channelKey: this.channelKeyValue,
      paymentId: this.paymentIdValue,
      orderName: "수금 패스 10건권",
      totalAmount: this.amountValue,
      currency: "KRW",
      payMethod: "CARD",
      customer,
      redirectUrl: this.callbackUrlValue // C2 — 페이지 이동 방식(모바일 결제창 표시 보장)
    })
    if (response == null) return

    // 리다이렉트가 일어나지 않은 환경(PC 위젯이 Promise로 응답한 경우)의 폴백 — 기존과
    // 동일한 쿼리 규격으로 콜백 URL로 이동한다. 결제 ID는 서버가 채번한 주문 번호다.
    const params = new URLSearchParams({ paymentId: this.paymentIdValue })
    if (response.code !== undefined) {
      params.set("code", response.code)
      params.set("message", response.message ?? "")
    } else if (response.paymentToken !== undefined) {
      params.set("paymentToken", response.paymentToken)
    }
    window.location.href = `${this.callbackUrlValue}?${params.toString()}`
  }
}
