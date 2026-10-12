module App
  # 청구서 화면(목록·상세·대시보드) 공통 — INV-4 상태 뱃지(DESIGN-2 상태색·DESIGN-5).
  # 연체는 enum이 아니라 만기일 비교 파생 판정(결정 #2)으로 뱃지를 결정한다.
  module InvoicesHelper
    # SHARE-2 — 링크 만료 임박 안내 시작 시점(만료 7일 전)
    LINK_EXPIRY_SOON_DAYS = 7

    # 상태 뱃지 — 연체 주황 / 대기·약속 중립 / 수금 완료 녹색 / 초안·무효 회색
    def invoice_status_badge(invoice)
      label, tone = invoice_badge_spec(invoice)
      content_tag :span, label, class: "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-bold #{tone}"
    end

    # CLIENT-2 — 품목 라이브러리를 폼 Stimulus 컨트롤러에 전달한다(선택 시 설명·단가 프리필).
    def invoice_library_json(items)
      items.map { |item| { id: item.id, name: item.name, unit_price: item.unit_price } }.to_json
    end

    # SHARE-2 — 링크 만료 상태 안내(유효기간 = 만기일 후 60일, token_expires_at end_of_day).
    # 만료 7일 전부터 「만료 임박」, 경과 시 「링크 만료」. 정상이면 nil(표기 없음).
    def link_expiry_notice(invoice)
      expires_at = invoice.token_expires_at
      return nil if expires_at.nil? || expires_at > LINK_EXPIRY_SOON_DAYS.days.from_now

      if expires_at > Time.current
        { label: "만료 임박", tone: "text-stone-500",
          text: "#{display_date(expires_at.to_date)}까지 열람할 수 있습니다." }
      else
        { label: "링크 만료", tone: "text-orange-600",
          text: "유효기간(만기일 + 60일)이 지났습니다." }
      end
    end

    private

    def invoice_badge_spec(invoice)
      if invoice.overdue?
        [ "연체", "bg-orange-50 text-orange-600 ring-1 ring-inset ring-orange-200" ]
      else
        case invoice.status
        when "draft"            then [ "초안", "bg-stone-100 text-stone-500 ring-1 ring-inset ring-stone-200" ]
        when "issued"           then [ "대기 중", "bg-stone-100 text-stone-600 ring-1 ring-inset ring-stone-200" ]
        # 열람(SHARE-3·INV-4) — 링크를 열람한 건. 뱃지 문구로만 대기 중과 구분한다(중립 톤 유지 — DESIGN-2 상태색 3종).
        when "viewed"           then [ "열람", "bg-stone-100 text-stone-600 ring-1 ring-inset ring-stone-200" ]
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
