# 무료 도구 뷰 헬퍼(LP-11) — 표현 로직만 담당(뷰에서 쿼리·모델 호출 없음).
module ToolsHelper
  # 금액 표기(원 단위 3자리 콤마+원 — DESIGN-3) — Invoices::ReceiptPdfService won과 동일 서식.
  def tools_won(amount)
    "#{ActiveSupport::NumberHelper.number_to_delimited(amount.to_i)}원"
  end

  # 복사 버튼(클립보드 — data 속성 기반 최소 JS, tools#copy_script가 일괄 바인딩).
  def tools_copy_button(text, label: "복사")
    tag.button(label, type: "button", class: "tools-copy-btn inline-flex min-h-9 items-center rounded-lg border border-stone-300 bg-white px-3 py-1.5 text-xs font-bold text-stone-700 transition hover:border-emerald-700 hover:text-emerald-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-700",
               data: { copy_text: text })
  end

  # 도구별 메타(제목·설명 — 색인 허용·LP 유입 목적). content_for :head로 출력.
  def tools_meta(title, description)
    content_for :head do
      tag.title(title) +
        tag.meta(name: "description", content: description)
    end
  end

  # 주 CTA(가입 유도 — LP-12 준수 문구).
  def tools_cta(text: "독촉 메시지를 이제 받을돈으로 자동 보내세요", link_label: "받을돈 무료로 시작하기")
    tag.div(class: "mt-8 rounded-2xl border border-emerald-800/20 bg-emerald-50 p-5 sm:p-6") do
      tag.p(text, class: "text-sm font-semibold text-emerald-900") +
        tag.div(class: "mt-3") do
          link_to link_label, new_registration_path,
                  class: "inline-flex min-h-11 items-center rounded-lg bg-emerald-800 px-5 py-2.5 text-sm font-bold text-white shadow-sm transition hover:bg-emerald-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-700"
        end
    end
  end
end
