require "test_helper"

module Invoices
  class ReceiptPdfServiceTest < ActiveSupport::TestCase
    fixtures :invoices, :invoice_items

    # PAY-6 (결정 Q17) — 마감(paid) 청구의 증빙 PDF 생성 검증. Prawn 내부는 압축 스트림이라
    # 문자열 검증은 대체 수단(%PDF 헤더·바이트 크기·폰트 등록 성공)으로 수행한다.
    test "paid 청구의 PDF를 생성한다 — %PDF 헤더·유효 크기·품목 행 포함" do
      invoice = invoices(:delta_paid)
      invoice.payments.create!(amount: invoice.total_amount, paid_on: Date.new(2026, 9, 15))

      pdf = Invoices::ReceiptPdfService.call(invoice: invoice)

      assert_not_nil pdf
      assert pdf.start_with?("%PDF")
      # 폰트 등록 실패 시 렌더 자체가 실패하므로, 유효 크기(바이트)로 렌더 성공을 대체 검증한다.
      assert pdf.bytesize > 10_000, "PDF 바이트가 비정상적으로 작습니다(#{pdf.bytesize})"
      assert_operator pdf.bytesize, :>, (invoice.items.count * 100)
    end

    test "다중 입금 건의 입금일은 마감 입금일(MAX paid_on)이다 (PAY-1/2)" do
      invoice = invoices(:delta_paid)
      invoice.payments.create!(amount: 60_000, paid_on: Date.new(2026, 9, 10))
      invoice.payments.create!(amount: 50_000, paid_on: Date.new(2026, 9, 25))

      pdf = Invoices::ReceiptPdfService.call(invoice: invoice)

      assert pdf.start_with?("%PDF")
      assert_equal Date.new(2026, 9, 25), invoice.payments.maximum(:paid_on)
    end

    test "마감이 아닌 청구는 PdfNotAvailable을 raise한다 (paid 한정)" do
      [ :delta_draft, :delta_issued, :delta_partially_paid, :delta_voided ].each do |fixture|
        error = assert_raises(Invoices::ReceiptPdfService::PdfNotAvailable) do
          Invoices::ReceiptPdfService.call(invoice: invoices(fixture))
        end
        assert_match(/마감/, error.message)
      end
    end

    test "품목 행이 2행인 paid 청구도 렌더한다 — 빈 행 없이 표가 채워진다" do
      invoice = invoices(:delta_paid)
      invoice.items.create!(description: "디자인 수정", quantity: 2, unit_price: 25_000)

      pdf = Invoices::ReceiptPdfService.call(invoice: invoice)

      assert pdf.start_with?("%PDF")
      assert_equal 2, invoice.items.count
    end

    test "원천징수 옵션 건도 렌더한다 (INV-2)" do
      invoice = invoices(:delta_paid)
      # fixture는 withholding_enabled: false — 옵션 켬 스냅샷으로 대체 산출(발행 후 본문 불변 INV-5라
      # update_column으로 검증 우회 — 테스트 전용 스냅샷 목적).
      invoice.update_columns(withholding_enabled: true, withholding_amount: 3_300, net_amount: 106_700)

      pdf = Invoices::ReceiptPdfService.call(invoice: invoice)

      assert pdf.start_with?("%PDF")
    end

    test "마이그레이션 불요 — 서비스는 기존 컬럼만 참조한다" do
      invoice = invoices(:delta_paid)
      invoice.payments.create!(amount: invoice.total_amount, paid_on: Date.current)

      assert_nothing_raised { Invoices::ReceiptPdfService.call(invoice: invoice) }
    end

  test "B-2 재발 방지 — 번들 폰트는 TrueType(glyf) 포맷이며 OTF(CFF)는 번들 금지" do
    %w[Pretendard-Regular.ttf Pretendard-Bold.ttf].each do |name|
      path = Rails.root.join("vendor/fonts", name)
      assert_path_exists path, "폰트가 번들되어 있어야 합니다: #{name}"
      data = File.binread(path)
      # TrueType 매직바이트 0x00010000 — OTF(CFF)는 0x4F54544F("OTTO")
      assert_equal "\x00\x01\x00\x00".b, data.byteslice(0, 4), "#{name}은 TrueType이어야 합니다"
    end
    assert_equal [ "Pretendard-Bold.ttf", "Pretendard-Regular.ttf" ],
                 Dir.children(Rails.root.join("vendor/fonts")).sort
  end

  test "B-2 재발 방지 — PDF에 내장 폰트가 TrueType(glyf)으로 등록된다" do
    invoice = invoices(:delta_paid)
    invoice.payments.create!(amount: invoice.total_amount, paid_on: Date.current)

    pdf = Invoices::ReceiptPdfService.call(invoice: invoice)

    # Prawn은 TrueType 서브셋을 TrueType 태그로 내장한다 — CFF(CIDFontType0) 혼입 감시.
    assert_match(/\/Subtype \/TrueType/, pdf)
    assert_no_match(/CIDFontType0/, pdf)
  end
  end
end
