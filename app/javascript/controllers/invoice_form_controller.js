import { Controller } from "@hotwired/stimulus"

// 청구서 초안 폼(UI 보조) — 품목 행 추가·제거, 품목 라이브러리 프리필(CLIENT-2),
// 금액 실시간 요약. 산식은 app/models/invoice.rb의 Invoice.compute_amounts와 동일한
// 정수 연산(원 단위)이며, 최종 금액은 저장 시 서버 계산을 기준으로 한다.
export default class extends Controller {
  static targets = [
    "rows", "rowTemplate", "row", "itemSelect", "addRowButton",
    "subtotalValue", "taxValue", "totalValue",
    "withholdingValue", "netValue", "withholdingBlock", "withholdingCheckbox"
  ]

  static values = {
    items: Array,          // 품목 라이브러리 [{id, name, unit_price}]
    addedRows: { type: Number, default: 0 },  // 추가 행 인덱스 시드 — 렌더된 0..n 인덱스와 충돌하지 않게 큰 수부터
    maxItems: Number       // 행 수 상한 — Invoice::MAX_ITEMS를 폼에서 주입(단일 지점)
  }

  connect() {
    this.recalculate()
    this.syncAddRowButton()
  }

  // 품목 행 추가 — template의 __ROW_INDEX__ 자리표를 고유 인덱스로 치환해 붙인다.
  // 상한 도달 시 추가를 막는다(서버 검증 Invoice::MAX_ITEMS와 동일 상태를 유지).
  addRow() {
    if (this.atMaxItems()) return

    const index = 1_000_000 + this.addedRowsValue
    this.addedRowsValue += 1
    const html = this.rowTemplateTarget.innerHTML.replaceAll("__ROW_INDEX__", String(index))
    this.rowsTarget.insertAdjacentHTML("beforeend", html)
    this.syncAddRowButton()
  }

  // 품목 행 제거 — 저장된 행(id 보유)은 _destroy 플래그로 서버 삭제, 새 행은 DOM에서 제거한다.
  removeRow(event) {
    const row = event.target.closest('[data-invoice-form-target~="row"]')
    if (!row) return

    if (row.querySelector('input[name$="[id]"]')) {
      row.querySelector('[data-role="destroyFlag"]').checked = true
      row.hidden = true
    } else {
      row.remove()
    }
    this.recalculate()
    this.syncAddRowButton()
  }

  atMaxItems() {
    return this.maxItemsValue > 0 && this.activeRowCount() >= this.maxItemsValue
  }

  // 활성 행 수 — 숨김(삭제 예정) 처리된 저장 행은 상한에서 제외한다.
  activeRowCount() {
    return this.rowTargets.filter((row) => !row.hidden && !this.isDestroyed(row)).length
  }

  syncAddRowButton() {
    if (!this.hasAddRowButtonTarget) return

    this.addRowButtonTarget.disabled = this.atMaxItems()
  }

  // CLIENT-2 — 라이브러리 선택 시 설명·단가를 채운다(수량은 그대로 둔다).
  prefillFromLibrary(event) {
    const row = event.target.closest('[data-invoice-form-target~="row"]')
    const item = this.itemsValue.find((entry) => String(entry.id) === event.target.value)
    if (!row || !item) return

    row.querySelector('[data-role="description"]').value = item.name
    row.querySelector('[data-role="unitPrice"]').value = item.unit_price
    this.recalculate()
  }

  // 실시간 요약 — 서버 산식의 JS 미러(정수 연산 유지, 부동소수점 없음).
  //   부가세 별도: 부가세 = 공급가액의 10% 반올림(사사오입)
  //   부가세 포함: 공급가액 = (총액/1.1) 반올림, 부가세 = 총액 − 공급가액
  //   원천징수: 공급가액의 3.3% 내림
  recalculate() {
    let rowsSum = 0
    this.rowTargets.forEach((row) => {
      if (this.isDestroyed(row)) return
      const quantity = parseInt(row.querySelector('[data-role="quantity"]')?.value, 10) || 0
      const unitPrice = parseInt(row.querySelector('[data-role="unitPrice"]')?.value, 10) || 0
      rowsSum += quantity * unitPrice
    })

    const separate = this.element.querySelector('input[name="invoice[tax_mode]"][value="separate"]')?.checked
    let subtotal, taxAmount
    if (separate) {
      subtotal = rowsSum
      taxAmount = Math.floor((subtotal + 5) / 10)
    } else {
      subtotal = Math.floor((rowsSum * 10 + 5) / 11)
      taxAmount = rowsSum - subtotal
    }
    const totalAmount = subtotal + taxAmount

    const withholdingEnabled = this.withholdingCheckboxTarget.checked
    const withholding = withholdingEnabled ? Math.floor((subtotal * 33) / 1000) : 0

    this.subtotalValueTarget.textContent = this.won(subtotal)
    this.taxValueTarget.textContent = this.won(taxAmount)
    this.totalValueTarget.textContent = this.won(totalAmount)
    this.withholdingBlockTargets.forEach((block) => block.classList.toggle("hidden", !withholdingEnabled))
    this.withholdingValueTarget.textContent = this.won(withholding)
    this.netValueTarget.textContent = this.won(totalAmount - withholding)
  }

  isDestroyed(row) {
    const destroyFlag = row.querySelector('[data-role="destroyFlag"]')
    return destroyFlag ? destroyFlag.checked : false
  }

  won(amount) {
    return `${amount.toLocaleString("ko-KR")}원`
  }
}
