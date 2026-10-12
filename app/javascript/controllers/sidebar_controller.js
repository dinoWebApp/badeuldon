import { Controller } from "@hotwired/stimulus"

// 표면 ② 사이드바 — 모바일 드로어 열기/닫기 토글만 담당하는 UI 컨트롤러(비즈니스 로직 없음).
export default class extends Controller {
  static targets = ["drawer", "backdrop", "toggle"]

  connect() {
    this.close()
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.drawerTarget.classList.remove("hidden")
    this.backdropTarget.classList.remove("hidden")
    this.setExpanded(true)
  }

  close() {
    this.drawerTarget.classList.add("hidden")
    this.backdropTarget.classList.add("hidden")
    this.setExpanded(false)
  }

  get isOpen() {
    return !this.drawerTarget.classList.contains("hidden")
  }

  setExpanded(value) {
    if (this.hasToggleTarget) {
      this.toggleTarget.setAttribute("aria-expanded", String(value))
    }
  }
}
