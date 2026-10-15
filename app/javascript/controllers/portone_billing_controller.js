import { Controller } from "@hotwired/stimulus"

// 포트원 카드(자동결제) 빌링키 발급 위젯 호출(F-PLAN — PLAN-5 빌링키).
// UI 접점만 담당한다: 카드 인증 완료 시 위젯이 빌링키 발급 토큰(billingIssueToken)을 돌려주면
// 카드 등록 콜백(App::SubscriptionsController#update 경유 card_callback)으로 전달하고, 서버가
// 포트원 /billing-keys/confirm으로 빌링키 발급·활성화를 수행한다.
//
// KG이니시스 필수 파라미터(B1) — issueId(발급 건 고유 ID, 서버 채번 UUID)·issueName·
// customer.fullName은 항상, phoneNumber는 PC 발급에서 필수(모바일은 선택), offerPeriod는
// 모바일 발급에서 필수(PC는 선택 — 월 구독이므로 항상 전달). redirectUrl(C2)은 반환값 방식의
// 모바일 결제창 미표시 제약을 해소한다. SDK 리다이렉트는 응답 필드명 그대로 쿼리로 전달하므로
// 콜백이 billingIssueToken 파라미터를 수용하면 호환된다.
export default class extends Controller {
  static values = {
    storeId: String,
    channelKey: String,
    customerId: String,
    callbackUrl: String,
    customerName: String,
    customerPhone: String,
    issueId: String
  }

  async register(event) {
    event.preventDefault() // 위젯 호출로 흐름을 대체한다 — 폼·링크 전송은 없다.
    if (typeof PortOne === "undefined") return // SDK 미로드(테스트 환경) — 서버 동작 무영향

    const customer = {
      customerId: this.customerIdValue,
      fullName: this.customerNameValue // KG이니시스 — 항상 필수
    }
    if (this.customerPhoneValue) customer.phoneNumber = this.customerPhoneValue // PC 필수

    const response = await PortOne.requestIssueBillingKey({
      storeId: this.storeIdValue,
      channelKey: this.channelKeyValue,
      billingKeyMethod: "CARD",
      issueId: this.issueIdValue, // KG이니시스 필수 — 발급 건 고유 ID(ASCII)
      issueName: "받을돈 정기결제 등록", // KG이니시스 필수 — 발급 주문 명
      customer,
      offerPeriod: { interval: "1m" }, // KG이니시스 모바일 발급 필수 — 월 구독 제공 주기
      redirectUrl: this.callbackUrlValue // C2 — 페이지 이동 방식(모바일 결제창 표시 보장)
    })
    if (response == null) return

    if (response.code !== undefined) {
      window.alert(`카드 등록에 실패했습니다 (${response.message ?? response.code})`)
      return
    }

    // 리다이렉트가 일어나지 않은 환경(PC 위젯이 Promise로 응답한 경우)의 폴백 — 발급 토큰을
    // 서버로 전달한다(토큰 방식 — 클린 컷오버 결정 #3).
    window.location.href = `${this.callbackUrlValue}?issue_token=${encodeURIComponent(response.billingIssueToken ?? "")}`
  }
}
