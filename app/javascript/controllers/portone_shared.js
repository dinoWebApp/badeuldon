// 포트원 위젯 컨트롤러(portone_payment·portone_billing) 공통 헬퍼 — 정리 추출(동작 변경 없음).
// UI 접점 보조만 담당하며 주문·빌링키 확정 등 비즈니스 로직은 서버가 수행한다(규약).
export function portoneSdkAvailable() {
  return typeof PortOne !== "undefined" // SDK 미로드(테스트 환경) — 호출부는 서버 동작 무영향으로 종료
}

// KG이니시스 customer 객체 조립 — fullName은 항상 필수, phoneNumber는 PC에서 필수(모바일 선택).
// requireEmail=true이면 빈 값이라도 email 키를 싣는다(빌링키 발급 — KG이니시스 REQUIRED).
export function buildPortoneCustomer({ fullName, phone, email, requireEmail = false }) {
  const customer = { fullName } // KG이니시스 — 항상 필수
  if (phone) customer.phoneNumber = phone // PC 필수
  if (requireEmail || email) customer.email = email ?? ""
  return customer
}
