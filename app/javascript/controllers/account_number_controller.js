import { Controller } from "@hotwired/stimulus"

// 계좌번호 자동 하이픈(AUTH-1.3 UI 보조) — 입력 중 숫자를 4자리 단위로 묶어 보여줄 뿐,
// 검증·저장 형식 등 도메인 로직은 담당하지 않는다(Stimulus는 UI 동작 1개만).
export default class extends Controller {
  connect() {
    this.format = this.format.bind(this)
    this.element.addEventListener("input", this.format)
  }

  disconnect() {
    this.element.removeEventListener("input", this.format)
  }

  format(event) {
    const digits = event.target.value.replace(/\D/g, "").slice(0, 20)
    event.target.value = digits.replace(/(\d{4})(?=\d)/g, "$1-")
  }
}
