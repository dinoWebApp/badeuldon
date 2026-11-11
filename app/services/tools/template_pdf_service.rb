# 청구서 양식 PDF(LLP-11 무료 도구 3종). GET params(선택 입력)로 양식을 조립해 PDF 바이트를
# 돌려준다 — 미입력 시 양식 샘플 데이터. 저장·쿠키 없음(P3)·멱등 순수 생성.
# Prawn은 TTF만 지원(Q17 실측 — OTF/CFF 비호환) — vendor/fonts Pretendard TTF 재사용
# (Invoices::ReceiptPdfService 패턴 준용).
module Tools
  class TemplatePdfService
    FONT_ROOT = Rails.root.join("vendor/fonts")

    SAMPLE = {
      client_name: "OOO 상사 (샘플)",
      item_name: "프리랜서 서비스",
      quantity: 1,
      unit_price: 1_000_000
    }.freeze

    def self.call(client_name: nil, item_name: nil, quantity: nil, unit_price: nil)
      new(client_name: client_name, item_name: item_name, quantity: quantity, unit_price: unit_price).call
    end

    def initialize(client_name:, item_name:, quantity:, unit_price:)
      @client_name = clean(client_name) || SAMPLE[:client_name]
      @item_name = clean(item_name) || SAMPLE[:item_name]
      @quantity = parse_int(quantity) || SAMPLE[:quantity]
      @unit_price = parse_int(unit_price) || SAMPLE[:unit_price]
    end

    def call
      Prawn::Document.new(page_size: "A4", margin: [ 56, 56, 56, 56 ]) do |pdf|
        register_fonts(pdf)
        render_title(pdf)
        render_info(pdf)
        render_items(pdf)
        render_amounts(pdf)
        render_deposit_note(pdf)
      end.render
    end

    private

    def clean(value)
      value.to_s.strip.presence
    end

    def parse_int(value)
      n = value.to_s.delete(",").to_i
      n.positive? ? n : nil
    end

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
      pdf.font "Pretendard", style: :bold, size: 24 do
        pdf.text "청구서", align: :center
      end
      pdf.move_down 20
    end

    def render_info(pdf)
      rows = [
        [ "거래처", @client_name ],
        [ "발행일", Time.current.strftime("%Y년 %-m월 %-d일") ]
      ]
      pdf.table(rows.each.map { |label, value| [ { content: label, font_style: :bold }, value ] },
                width: 483, cell_style: { size: 11, padding: [ 6, 8, 6, 8 ] }) do
        row(0..1).columns(0).background_color = "F5F5F4"
      end
      pdf.move_down 24
    end

    def render_items(pdf)
      header = [ "품목", "수량", "단가", "합계" ].each_with_index.map do |label, i|
        { content: label, align: i.zero? ? :left : :right, font_style: :bold, background_color: "F5F5F4" }
      end
      line_total = @quantity * @unit_price
      body = [ [ @item_name, @quantity.to_s, won(@unit_price), won(line_total) ] ].each do |cells|
        cells.each_with_index { |text, i| cells[i] = { content: text, align: i.zero? ? :left : :right } }
      end
      pdf.table([ header ] + body, width: 483,
                column_widths: { 0 => 223, 1 => 60, 2 => 100, 3 => 100 },
                cell_style: { size: 10, padding: [ 6, 8, 6, 8 ] })
      pdf.move_down 20
    end

    def render_amounts(pdf)
      supply = @quantity * @unit_price
      tax = (supply * 0.10).floor
      rows = [ [ "공급가액", won(supply) ],
               [ "부가세", won(tax) ],
               [ { content: "합계", font_style: :bold }, { content: won(supply + tax), font_style: :bold } ] ]
      pdf.table(rows, width: 483, cell_style: { size: 11, padding: [ 6, 8, 6, 8 ] }) do
        rows(-1).background_color = "F0FDF4"
      end
    end

    def render_deposit_note(pdf)
      pdf.move_down 28
      pdf.font "Pretendard", style: :bold, size: 12 do
        pdf.text "입금 안내"
      end
      pdf.move_down 4
      pdf.font_size 10 do
        pdf.text "입금 계좌: (은행명) (계좌번호) (예금주)", color: "78716C"
        pdf.text "입금 기한: 발행일로부터 30일", color: "78716C"
      end
    end

    def won(amount)
      "#{ActiveSupport::NumberHelper.number_to_delimited(amount)}원"
    end
  end
end
