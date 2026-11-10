import { Controller } from "@hotwired/stimulus"

// CLIENT-4 — 발행 폼 거래처 선택 시 지급 성적표 요약 fetch(scorecard_app_invoices_path).
// invoice-form(품목·금액 계산)과 무결을 유지하기 위해 별도 컨트롤러로 분리한다.
export default class extends Controller {
  static targets = ["select", "summary"]
  static values = { url: String }

  connect() {
    // 수정 화면 진입 시 기존 거래처가 선택되어 있으면 즉시 로드
    if (this.selectTarget.value) this.load()
  }

  onChange() {
    this.load()
  }

  load() {
    const clientId = this.selectTarget.value
    if (!clientId) {
      this.summaryTarget.innerHTML = ""
      this.summaryTarget.hidden = true
      return
    }

    fetch(`${this.urlValue}?client_id=${encodeURIComponent(clientId)}`, {
      headers: { Accept: "text/html" }
    })
      .then((response) => {
        if (!response.ok) throw new Error("scorecard fetch failed")
        return response.text()
      })
      .then((html) => {
        this.summaryTarget.innerHTML = html
        this.summaryTarget.hidden = false
      })
      .catch(() => {
        this.summaryTarget.hidden = true
      })
  }
}
