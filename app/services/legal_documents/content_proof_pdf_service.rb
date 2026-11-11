# 내용증명 양식 PDF(LEGAL-1~4, 결정 기록 Q5·Q17) — 만기 D+30 초과 미수(unsettled) 청구의
# 근거 자료(청구 내역·발송 이력 REM-6·약속 이력 Q14 판정·부분입금 내역)를 자동 반영한
# 내용증명 양식을 Prawn으로 생성해 문자열로 반환한다. Invoices::ReceiptPdfService(Q17 패턴)를
# 준용하며, 한글 렌더는 번들한 Pretendard TTF(vendor/fonts — TrueType/glyf outline)로
# 해결한다(OTF/CFF는 Prawn 텍스트 전무 실측 — B-2).
#
# 생성은 순수 문자열 조립이라 멱등·부작용 없고 결제 완료 전에도 기술적으로 가능하나,
# 접근 제어(LEGAL-2 — 결제 완료 후에만 다운로드)는 App::LegalDocumentsController가 담당한다.
# 대상 가드는 대상 정의의 단일 출처로서 서비스가 수행한다: unsettled가 아닌 청구(초안·
# 수금완료·무효)와 D+30 미도달 청구는 LegalDocNotAvailable로 예외화한다(컨트롤러가 안내로 변환).
# LEGAL-3 고지문(법률 자문 부존재)·LEGAL-4 직접 발송 안내는 양식 본문에 필수 포함한다.
module LegalDocuments
  class ContentProofPdfService
    class LegalDocNotAvailable < StandardError; end

    FONT_ROOT = Rails.root.join("vendor/fonts")
    # LEGAL-3 — 고지문(출시 전 법률 검토 전제 — Q5). 생성 화면과 PDF 양쪽에 동일 문언을 사용한다.
    LEGAL_NOTICE = "본 서비스는 법률 자문을 제공하지 않습니다. 본 양식은 이용자가 작성한 청구·발송 기록을 정리한 참고 자료이며, 필요 시 변호사 등 법률 전문가의 검토를 권장합니다."
    # LEGAL-4 — 발송 대행 부존재 안내
    DIRECT_SEND_NOTICE = "본 서비스는 내용증명 발송을 대행하지 않습니다. 우체국 등기 등 실제 발송은 이용자가 직접 수행해야 합니다."
    # 발송 이력 표기 상한(양식 1매 분량 가드 — 최근순)
    MESSAGE_LOG_LIMIT = 10

    # D+30 초과 판정(LEG-1 — REF 배너·App::ReferralsController와 동일 조건: due_on+30 < 오늘).
    def self.legal_target?(invoice, today: Date.current)
      invoice.unsettled? && invoice.due_on.present? && invoice.due_on + 30 < today
    end

    # invoice는 호출 측(컨트롤러)에서 이미 소유권 스코프를 통과한 레코드다.
    # watermark: true면 대각 워터마크("미리보기 — 미결제")를 모든 페이지에 찍은 미리보기 PDF를
    # 반환한다(C-1 — LEGAL-2 PRD v0.38 "미결제는 워터마크 미리보기만").
    # enforce_target: false면 대상 가드(unsettled+D+30)를 생략한다 — 이미 결제 완료한 주문의
    # 재다운로드는 청구가 마감(paid)된 뒤에도 허용한다(W-3 확정 정책 — PAY-6 회계 보관용 취지).
    def self.call(invoice:, today: Date.current, watermark: false, enforce_target: true)
      new(invoice: invoice, today: today, watermark: watermark,
          enforce_target: enforce_target).call
    end

    def initialize(invoice:, today: Date.current, watermark: false, enforce_target: true)
      if enforce_target
        raise LegalDocNotAvailable, "만기일이 30일 이상 지난 미수금 청구서만 생성할 수 있습니다" unless self.class.legal_target?(invoice, today: today)
      end

      @invoice = invoice
      @today = today
      @watermark = watermark
    end

    def call
      Prawn::Document.new(page_size: "A4", margin: [ 56, 56, 56, 56 ]) do |pdf|
        register_fonts(pdf)
        render_title(pdf)
        render_parties(pdf)
        render_invoice_items(pdf)
        render_amounts(pdf)
        render_message_logs(pdf)
        render_promises(pdf)
        render_payments(pdf)
        render_notices(pdf)
        stamp_watermark(pdf) if @watermark
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
        pdf.text "내용증명"
      end
      pdf.move_down 4
      pdf.font_size 10 do
        pdf.text "청구번호 #{@invoice.issue_number} · 생성일 #{format_date(@today)}", color: "78716C"
      end
      pdf.stroke_horizontal_rule
      pdf.move_down 16
    end

    # LEGAL-1 ② — 발신인(U1 표시명·사업자 유형)·수신인(거래처명)
    def render_parties(pdf)
      section_title(pdf, "발신인 · 수신인")
      rows = [
        [ "발신인", @invoice.issuer_display_name ],
        [ "사업자 유형", issuer_business_type ],
        [ "수신인", @invoice.client.name ]
      ]
      pdf_table(pdf, rows, width: 483, cell_style: { size: 11, padding: [ 6, 8, 6, 8 ] })
    end

    # AUTH-1.3 프로필의 사업자 유형 enum 표기(사업자/프리랜서 — 미설정은 "-")
    def issuer_business_type
      { "business" => "사업자", "freelancer" => "프리랜서" }.fetch(@invoice.user.business_type, "-")
    end

    # LEGAL-1 ③ — 청구 내역(품목 행·공급가액·부가세·총액)
    def render_invoice_items(pdf)
      section_title(pdf, "청구 내역")
      header = [ "품목명", "수량", "단가", "합계" ].each_with_index.map do |label, i|
        { content: label, align: i.zero? ? :left : :right, font_style: :bold,
          background_color: "F5F5F4" }
      end
      body = @invoice.items.order(:id).map do |item|
        [ item.description, item.quantity.to_s, won(item.unit_price),
          won(item.quantity.to_i * item.unit_price.to_i) ]
      end.each do |cells|
        cells.each_with_index { |text, i| cells[i] = { content: text, align: i.zero? ? :left : :right } }
      end
      pdf_table(pdf, [ header ] + body, width: 483,
                column_widths: { 0 => 223, 1 => 60, 2 => 100, 3 => 100 },
                cell_style: { size: 10, padding: [ 6, 8, 6, 8 ] })
      pdf.move_down 16
    end

    def render_amounts(pdf)
      rows = [ [ "만기일", format_date(@invoice.due_on) ],
               [ "공급가액", won(@invoice.subtotal) ],
               [ "부가세", won(@invoice.tax_amount) ] ]
      if @invoice.withholding_enabled?  # INV-2 — 원천징수는 옵션 건에만 표기
        rows << [ "원천징수(3.3%)", "-#{won(@invoice.withholding_amount)}" ]
      end
      rows << [ { content: "청구 총액", font_style: :bold },
                { content: won(@invoice.total_amount), font_style: :bold } ]
      rows << [ { content: "미수 잔액", font_style: :bold },
                { content: won(@invoice.remaining_amount), font_style: :bold } ]
      pdf_table(pdf, rows, width: 483, cell_style: { size: 11, padding: [ 6, 8, 6, 8 ] }) do
        rows(-1).background_color = "FFF7ED"  # DESIGN-2 연체 주황 계열 — 미수 잔액 강조
      end
      pdf.move_down 20
    end

    # LEGAL-1 ④ — 발송 이력(REM-6 — message_logs 최근순·상한 10건)
    def render_message_logs(pdf)
      logs = MessageLog.where(invoice_id: @invoice.id, recipient_role: :debtor)
                       .where.not(sent_at: nil)
                       .order(sent_at: :desc).limit(MESSAGE_LOG_LIMIT)
      section_title(pdf, "발송 이력 (리마인더 최근 #{MESSAGE_LOG_LIMIT}건)")
      if logs.empty?
        pdf.font_size 10 do
          pdf.text "기록된 발송 이력이 없습니다.", color: "78716C"
        end
      else
        rows = logs.map { |log| [ format_datetime(log.sent_at), template_label(log.template_key) ] }
        pdf_table(pdf, rows, width: 483, cell_style: { size: 10, padding: [ 5, 8, 5, 8 ] })
      end
      pdf.move_down 16
    end

    # LEGAL-1 ⑤ — 약속 이력(promises — 약속일·Q14 파생 판정 3상태)
    def render_promises(pdf)
      section_title(pdf, "입금 약속 이력")
      promises = @invoice.promises.where.not(promised_on: nil).order(:promised_on)
      if promises.empty?
        pdf.font_size 10 do
          pdf.text "기록된 입금 약속이 없습니다.", color: "78716C"
        end
      else
        closing_paid_on = @invoice.payments.maximum(:paid_on)  # Q14 — 마감 입금일 기준 판정
        rows = promises.map do |promise|
          [ format_date(promise.promised_on), promise_status_label(promise, closing_paid_on) ]
        end
        pdf_table(pdf, rows, width: 483, cell_style: { size: 10, padding: [ 5, 8, 5, 8 ] })
      end
      pdf.move_down 16
    end

    # Q14 파생 판정(Clients::PromiseComplianceQuery.status_key와 동일 정의 — 단일 출처 주석 준용).
    # 서비스 가드가 unsettled 청구 한정이므로 판정은 2상태다: 판정 중(약속일 도과 전)·
    # 미이행(도과 후 미수). paid 이행 확정 분기는 이 양식의 대상(미수)에서 발생하지 않는다.
    def promise_status_label(promise, _closing_paid_on)
      promised_on = promise.promised_on
      label = promised_on < @today ? "미이행" : "판정 중"
      "#{label} (약속일 #{format_date(promised_on)})"
    end

    # LEGAL-1 ⑥ — 부분입금 내역(payments — 입금일·금액)
    def render_payments(pdf)
      section_title(pdf, "입금 내역")
      payments = @invoice.payments.order(:paid_on)
      if payments.empty?
        pdf.font_size 10 do
          pdf.text "기록된 입금이 없습니다.", color: "78716C"
        end
      else
        rows = payments.map { |payment| [ format_date(payment.paid_on), won(payment.amount) ] }
        rows << [ { content: "입금 합계", font_style: :bold },
                  { content: won(@invoice.payments_total), font_style: :bold } ]
        pdf_table(pdf, rows, width: 483, cell_style: { size: 10, padding: [ 5, 8, 5, 8 ] })
      end
      pdf.move_down 16
    end

    # LEGAL-3 고지문 + LEGAL-4 직접 발송 안내(양식 하단 필수 문언)
    def render_notices(pdf)
      section_title(pdf, "안내")
      pdf.font_size 9 do
        pdf.text LEGAL_NOTICE, color: "78716C", leading: 4
        pdf.move_down 6
        pdf.text DIRECT_SEND_NOTICE, color: "78716C", leading: 4
        pdf.move_down 6
        pdf.text "본 문서는 받을돈에서 생성된 내용증명 양식입니다. 생성일시: #{format_datetime(Time.current)}", color: "78716C"
      end
    end

    # C-1(LEGAL-2) — 미결제 미리보기용 대각 워터마크. 본문 전문은 그대로 담기지만 대가 지급
    # 없는 실사용(인쇄·발송)을 어렵게 한다. 모든 페이지에 적용한다.
    def stamp_watermark(pdf)
      pdf.create_stamp("preview_watermark") do
        pdf.rotate(38, origin: [ pdf.bounds.right * 0.1, pdf.bounds.top * 0.25 ]) do
          pdf.font "Pretendard", style: :bold
          pdf.font_size 46
          pdf.fill_color "78716C"
          pdf.transparent(0.22) { pdf.draw_text "미리보기 — 미결제", at: [ 0, 0 ] }
        end
      end
      pdf.page_count.times { |i| pdf.go_to_page(i + 1); pdf.stamp("preview_watermark") }
    end

    def section_title(pdf, text)
      pdf.font "Pretendard", style: :bold, size: 13 do
        pdf.text text
      end
      pdf.move_down 6
    end

    def pdf_table(pdf, rows, **options, &block)
      decorated = rows.each.map { |row|
        row.map { |cell| cell.is_a?(Hash) ? cell : { content: cell } }
      }
      decorated.each { |row| row.each_with_index { |cell, i| cell[:align] ||= :left if i.zero? } }
      pdf.table(decorated, **options, &block)
    end

    # 채무자 향 리마인더 템플릿 표기(알림톡 템플릿 키의 사람용 라벨 — 기록 정리 목적의
    # 사실적 표기에 한정한다). 미지정 키는 키 원문을 그대로 노출한다(P4 — 기록 왜곡 금지).
    def template_label(template_key)
      {
        "invoice_notice" => "청구 안내",
        "d1" => "독촉 1차(만기 전날)",
        "overdue_d1" => "독촉 2차(연체 1일)",
        "d7" => "독촉 3차(연체 7일)",
        "final_d14" => "최종 안내(연체 14일)",
        "promise_d1" => "약속 리마인더(전날)",
        "promise_overdue" => "약속 경과 안내",
        "partial_paid" => "부분입금 확인",
        "paid_thanks" => "입금 감사"
      }.fetch(template_key, template_key)
    end

    # 앱 표기(display_date·display_datetime — base_helper)와 동일 ISO 서식으로 통일한다.
    def format_date(date)
      date&.strftime("%Y-%m-%d") || "-"
    end

    def format_datetime(time)
      time.strftime("%Y-%m-%d %H:%M")
    end

    # 뷰 헬퍼(won)는 이 계층에서 사용할 수 없으므로 동일 포맷(원 단위 3자리 콤마+원,
    # DESIGN-3)을 재현한다(ReceiptPdfService와 동일).
    def won(amount)
      "#{ActiveSupport::NumberHelper.number_to_delimited(amount.to_i)}원"
    end
  end
end
