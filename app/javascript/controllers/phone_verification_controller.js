import { Controller } from "@hotwired/stimulus"

// 휴대폰 인증(AUTH-9 — 가입 폼 내 2단계 비동기). 번호 입력 → 인증 요청(fetch POST
// /registration/send_phone_code) → 코드 입력 → 확인(fetch POST /registration/verify_phone_code)
// 순서로 상태 전환한다. 인증 통과 전에는 가입 submit을 막는다(서버도 이중 검증 — 우회 불가).
// 도메인 로직은 서버가 단일 판정점이며 이 컨트롤러는 상태 표시·fetch 조립만 한다.
export default class extends Controller {
  static targets = ["phone", "sendButton", "codeGroup", "code", "verifyButton", "status", "submit"]

  static classes = ["verified"]

  connect() {
    this.verified = false
  }

  async send() {
    if (this.sending) return
    const phone = this.phoneTarget.value.trim()
    if (!phone) {
      this.showStatus("휴대폰 번호를 입력해 주세요.", false)
      return
    }

    this.sending = true
    this.setButton(this.sendButtonTarget, "발송 중…", true)
    try {
      const data = await this.post(sendPhoneCodePath(), { phone })
      if (data.ok) {
        this.codeGroupTarget.classList.remove("hidden")
        this.codeTarget.focus()
        this.showStatus(`인증번호를 발송했습니다 (${data.phone}). 5분 이내에 입력해 주세요.`, true)
      } else {
        this.showStatus(data.error, false)
      }
    } catch {
      this.showStatus("인증번호 발송에 실패했습니다. 잠시 후 다시 시도해 주세요.", false)
    } finally {
      this.setButton(this.sendButtonTarget, "인증번호 받기", false)
      this.sending = false
    }
  }

  async verify() {
    if (this.verifying || this.verified) return
    const phone = this.phoneTarget.value.trim()
    const code = this.codeTarget.value.trim()
    if (!code) {
      this.showStatus("인증번호를 입력해 주세요.", false)
      return
    }

    this.verifying = true
    this.setButton(this.verifyButtonTarget, "확인 중…", true)
    try {
      const data = await this.post(verifyPhoneCodePath(), { phone, code })
      if (data.ok) {
        this.verified = true
        this.codeGroupTarget.classList.add("hidden")
        this.phoneTarget.readOnly = true
        this.sendButtonTarget.disabled = true
        this.showStatus("휴대폰 인증이 완료되었습니다.", true)
        this.submitTarget.disabled = false
      } else {
        this.showStatus(data.error, false)
      }
    } catch {
      this.showStatus("인증번호 확인에 실패했습니다. 잠시 후 다시 시도해 주세요.", false)
    } finally {
      this.setButton(this.verifyButtonTarget, "인증번호 확인", false)
      this.verifying = false
    }
  }

  // 뷰 상태 표시 — 성공/실패 색상은 상태색(DESIGN-2)을 따른다.
  showStatus(message, ok) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("text-emerald-700", ok)
    this.statusTarget.classList.toggle("text-red-600", !ok)
    this.statusTarget.classList.remove("hidden")
  }

  setButton(button, label, busy) {
    button.textContent = label
    button.disabled = busy
  }

  async post(path, body) {
    const token = document.querySelector('meta[name="csrf-token"]').content
    const response = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      body: JSON.stringify(body)
    })
    return response.json()
  }
}

// 경로 헬퍼(URL 하드코딩 금지 — 라우트 헬퍼를 data 속성으로 주입받아 사용).
function sendPhoneCodePath() {
  return document.querySelector("[data-phone-verification-send-path]").dataset.phoneVerificationSendPath
}

function verifyPhoneCodePath() {
  return document.querySelector("[data-phone-verification-verify-path]").dataset.phoneVerificationVerifyPath
}
