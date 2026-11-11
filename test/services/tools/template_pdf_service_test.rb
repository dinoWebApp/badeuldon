require "test_helper"
require "pdf-reader"

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

    # Prawn PDF의 텍스트 추출은 순수 Ruby인 PDF::Reader로 수행한다 —
    # 기존 시스템 pdftotext(poppler)는 CI Linux에서 poppler 설치 후에도 한글 빈 출력(플랫폼 차이 실측),
    # PDF::Reader는 TTF 서브셋의 ToUnicode 맵을 따라 플랫폼 무관하게 한글을 추출한다.
    def extract_text(pdf)
      io = StringIO.new(pdf)
      PDF::Reader.new(io).pages.map(&:text).join("\n")
    end
  end
end
