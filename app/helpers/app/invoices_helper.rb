module App
  # 청구서 화면(목록·상세·대시보드) 공통 — INV-4 상태 뱃지(DESIGN-2 상태색·DESIGN-5).
  # 연체는 enum이 아니라 만기일 비교 파생 판정(결정 #2)으로 뱃지를 결정한다.
  module InvoicesHelper
    # 상태 뱃지 — 연체 주황 / 대기·약속 중립 / 수금 완료 녹색 / 초안·무효 회색
    def invoice_status_badge(invoice)
      label, tone = invoice_badge_spec(invoice)
      content_tag :span, label, class: "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-bold #{tone}"
    end

    # CLIENT-2 — 품목 라이브러리를 폼 Stimulus 컨트롤러에 전달한다(선택 시 설명·단가 프리필).
    def invoice_library_json(items)
      items.map { |item| { id: item.id, name: item.name, unit_price: item.unit_price } }.to_json
    end

    private

    def invoice_badge_spec(invoice)
      if invoice.overdue?
        [ "연체", "bg-orange-50 text-orange-600 ring-1 ring-inset ring-orange-200" ]
      else
        case invoice.status
        when "draft"            then [ "초안", "bg-stone-100 text-stone-500 ring-1 ring-inset ring-stone-200" ]
        when "issued", "viewed" then [ "대기 중", "bg-stone-100 text-stone-600 ring-1 ring-inset ring-stone-200" ]
        when "promised"         then [ "약속 대기", "bg-stone-100 text-stone-600 ring-1 ring-inset ring-stone-200" ]
        when "partially_paid"   then [ "부분입금", "bg-stone-100 text-stone-600 ring-1 ring-inset ring-stone-200" ]
        when "paid"             then [ "수금 완료", "bg-green-50 text-green-700 ring-1 ring-inset ring-green-200" ]
        when "voided"           then [ "무효", "bg-stone-100 text-stone-400 ring-1 ring-inset ring-stone-200" ]
        else [ invoice.status, "bg-stone-100 text-stone-600 ring-1 ring-inset ring-stone-200" ]
        end
      end
    end
  end
end
