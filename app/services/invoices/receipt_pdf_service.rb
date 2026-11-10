# 수금완료 증빙 PDF(PAY-6, 결정 기록 Q17) — 마감(paid)된 청구서의 회계 보관용 증빙 문서를
# Prawn으로 생성해 문자열로 반환한다. 발행자(/app) 다운로드 전용이며 VIEW-4 뷰어 PDF는
# 별개 후속(Q17 — 이번 범위 밖). 한글 렌더는 번들한 Pretendard TTF(vendor/fonts — TrueType/glyf outline)로 해결한다. OTF(CFF-outline)는 Prawn TrueType 서브셋과 비호환으로 텍스트 전무(B-2 실측) — TTF만 허용.
# 생성은 순수 문자열 조립이라 멱등·부작용 없고, 마감이 아닌 청구는 PdfNotAvailable로
# 예외화한다 — 컨트롤러가 안내로 변환한다. 금액은 정수 원(INV 산식과 동일 컬럼 사용, TIME-1
# 시간 기준은 Time.current).
module Invoices
  class ReceiptPdfService
    class PdfNotAvailable < StandardError; end

    FONT_ROOT = Rails.root.join("vendor/fonts")
    FOOTER_TEXT = "본 문서는 받을돈에서 생성된 수금 완료 증빙입니다"

    # invoice는 호출 측(컨트롤러)에서 이미 소유권 스코프를 통과한 레코드다.
    def self.call(invoice:)
      new(invoice: invoice).call
    end

    def initialize(invoice:)
      raise PdfNotAvailable, "수금이 마감된 청구서만 증빙을 생성할 수 있습니다" unless invoice.paid?

      @invoice = invoice
    end

    def call
      Prawn::Document.new(page_size: "A4", margin: [ 56, 56, 56, 56 ]) do |pdf|
        register_fonts(pdf)
        render_title(pdf)
        render_summary(pdf)
        render_items(pdf)
        render_amounts(pdf)
        render_footer(pdf)
      end.render
    end

    private

    def register_fonts(pdf)
      pdf.font_families.update(
        "Pretendard" => {
          normal: FONT_ROOT.join("Pretendard-Regular.ttf").to_s,
          bold: FONT_ROOT.join("Pretendard-Bold.ttf").to_s
        }
      )
      pdf.font "Pretendard"
    end

    def render_title(pdf)
      pdf.font "Pretendard", style: :bold, size: 22 do
        pdf.text "수금 완료 증빙"
      end
      pdf.move_down 4
      pdf.font_size 10 do
        pdf.text "청구번호 #{@invoice.issue_number}", color: "78716C"
      end
      pdf.stroke_horizontal_rule
      pdf.move_down 16
    end

    def render_summary(pdf)
      paid_on = @invoice.payments.maximum(:paid_on)  # PAY-1/2 — 마감 입금일(입금일 최대값)
      rows = [
        [ "거래처명", @invoice.client.name ],
        [ "청구번호", @invoice.issue_number ],
        [ "발행일", format_date(@invoice.issued_at&.to_date) ],
        [ "입금일", format_date(paid_on) ]
      ]
      pdf.table(rows.each.map { |label, value| [ { content: label, font_style: :bold }, value ] },
                width: 483, cell_style: { size: 11, padding: [ 6, 8, 6, 8 ] }) do
        row(0..3).columns(0).background_color = "F5F5F4"
      end
      pdf.move_down 20
    end

    def render_items(pdf)
      pdf.font "Pretendard", style: :bold, size: 13 do
        pdf.text "품목 내역"
      end
      pdf.move_down 6
      header = [ "품목명", "수량", "단가", "합계" ].each_with_index.map do |label, i|
        { content: label, align: i.zero? ? :left : :right, font_style: :bold,
          background_color: "F5F5F4" }
      end
      body = @invoice.items.order(:id).map do |item|
        [ item.description, item.quantity.to_s, won(item.unit_price), won(item.quantity.to_i * item.unit_price.to_i) ]
      end.each do |cells|
        cells.each_with_index { |text, i| cells[i] = { content: text, align: i.zero? ? :left : :right } }
      end
      pdf.table([ header ] + body, width: 483,
                column_widths: { 0 => 223, 1 => 60, 2 => 100, 3 => 100 },
                cell_style: { size: 10, padding: [ 6, 8, 6, 8 ] })
      pdf.move_down 20
    end

    def render_amounts(pdf)
      rows = [ [ "공급가액", won(@invoice.subtotal) ],
               [ "부가세", won(@invoice.tax_amount) ] ]
      if @invoice.withholding_enabled?  # INV-2 — 원천징수는 옵션 건에만 표기
        rows << [ "원천징수(3.3%)", "-#{won(@invoice.withholding_amount)}" ]
        rows << [ "실수령액", won(@invoice.net_amount) ]
      end
      rows << [ { content: "총액", font_style: :bold }, { content: won(@invoice.total_amount), font_style: :bold } ]
      pdf.table(rows, width: 483, cell_style: { size: 11, padding: [ 6, 8, 6, 8 ] }) do
        rows(-1).background_color = "ECFDF5"  # DESIGN-2 완료 녹색 계열
      end
    end

    def render_footer(pdf)
      pdf.move_down 24
      pdf.font_size 9 do
        pdf.text "생성일시: #{format_datetime(Time.current)}", color: "78716C"
        pdf.text FOOTER_TEXT, color: "78716C"
      end
    end

    # 앱 표기(display_date·display_datetime — base_helper)와 동일 ISO 서식으로 통일한다.
    def format_date(date)
      date&.strftime("%Y-%m-%d") || "-"
    end

    def format_datetime(time)
      time.strftime("%Y-%m-%d %H:%M")
    end

    # 뷰 헬퍼(won)는 이 계층에서 사용할 수 없으므로 동일 포맷(원 단위 3자리 콤마+원,
    # DESIGN-3)을 재현한다.
    def won(amount)
      "#{ActiveSupport::NumberHelper.number_to_delimited(amount.to_i)}원"
    end
  end
end
