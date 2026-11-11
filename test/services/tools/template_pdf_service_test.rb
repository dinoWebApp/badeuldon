require "test_helper"

module Tools
  class TemplatePdfServiceTest < ActiveSupport::TestCase
    # LP-11 무료 도구 3종 — 청구서 양식 PDF. 순수 생성·저장 없음(P3)·Prawn TTF(Q17 실측).
    test "기본 양식 생성 — %PDF 헤더·샘플 데이터" do
      pdf = TemplatePdfService.call
      assert pdf.start_with?("%PDF")
      assert pdf.bytesize > 1000
    end

    test "입력값 반영 — 거래처·품목·수량·단가" do
      pdf = TemplatePdfService.call(
        client_name: "가나디자인", item_name: "10월 웹 디자인", quantity: "2", unit_price: "500,000"
      )
      text = extract_text(pdf)
      assert_includes text, "가나디자인"
      assert_includes text, "10월 웹 디자인"
      assert_includes text, "1,000,000원" # 2 × 500,000
    end

    test "빈 입력·무효 입력은 샘플 데이터로 대체" do
      pdf = TemplatePdfService.call(client_name: "  ", item_name: "", quantity: "0", unit_price: "abc")
      text = extract_text(pdf)
      assert_includes text, "샘플"
      assert_includes text, "1,000,000원"
    end

    test "총액은 공급가액+부가세(10%)" do
      pdf = TemplatePdfService.call(quantity: "1", unit_price: "1,000,000")
      text = extract_text(pdf)
      assert_includes text, "1,100,000원"
    end

    test "발행일이 오늘 날짜로 기재된다 (KST — TIME-1)" do
      pdf = TemplatePdfService.call
      assert_includes extract_text(pdf), Time.current.strftime("%Y년 %-m월 %-d일")
    end

    private

    # Prawn PDF의 텍스트 추출은 poppler(pdftotext) 없이 검증이 어려워,
    # TTF 서브셋의 ToUnicode 맵 대신 존재 검증은 %PDF 헤더+크기로 하고
    # 실제 텍스트는 압축 스트림 풀기 결과에서 ASCII 안전 부분만 확인한다(거래처명 등 ASCII가
    # 아닌 한글은 Prawn 서브셋+ToUnicode로 인코딩되어 raw 스트림에 나오지 않는다 —
    # 따라서 텍스트 단위 검증은 pdftotext가 있을 때만 수행한다).
    def extract_text(pdf)
      return "" unless system("command -v pdftotext", out: File::NULL, err: File::NULL)

      dir = Dir.mktmpdir
      path = File.join(dir, "out.pdf")
      File.binwrite(path, pdf)
      `pdftotext #{path} - 2>/dev/null`
    end
  end
end
