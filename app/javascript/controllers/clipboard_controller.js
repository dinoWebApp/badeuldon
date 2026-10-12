import { Controller } from "@hotwired/stimulus"

// 클립보드 복사(UI 동작 1개) — 링크 복사(SHARE-6)·뷰어 계좌 복사(VIEW-3) 공용.
// navigator.clipboard 실패(비보안 컨텍스트 등) 시 source 텍스트를 선택 상태로 만들어
// 수동 복사로 유도한다(fallback — 플랜 리스크 노트). 검증·저장 등 도메인 로직은 없다.
export default class extends Controller {
  static targets = ["source", "label"]

  static values = {
    text: String,
    copiedLabel: { type: String, default: "복사됨" },
    selectedLabel: { type: String, default: "선택됨 — 복사해 주세요" },
  }

  disconnect() {
    this.clearTimer()
  }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.textValue)
      this.flash(this.copiedLabelValue)
    } catch {
      this.selectSource()
    }
  }

  // 클립보드 API 불가 환경 fallback — source 텍스트를 선택해 수동 복사를 유도한다.
  selectSource() {
    if (!this.hasSourceTarget) {
      this.flash(this.copiedLabelValue)
      return
    }

    this.sourceTarget.focus()
    this.sourceTarget.select()
    this.flash(this.selectedLabelValue)
  }

  // 복사 결과 피드백 — 라벨을 잠시 교체 후 원문으로 복원한다.
  flash(message) {
    if (!this.hasLabelTarget) return

    this.clearTimer()
    this.originalLabel ??= this.labelTarget.textContent
    this.labelTarget.textContent = message
    this.timer = setTimeout(() => {
      this.labelTarget.textContent = this.originalLabel
      this.originalLabel = null
    }, 2000)
  }

  clearTimer() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
  }
}
