require "test_helper"

module Tools
  class TaxCalculatorServiceTest < ActiveSupport::TestCase
    # LP-11 무료 도구 2종 — 원천징수 3.3%(INV-2 선례)·부가세 10%·실수령액 계산. 순수 함수(P3).
    test "기본 계산 — 공급가액 1,000,000" do
      result = TaxCalculatorService.call(amount_raw: "1000000")
      assert_equal 1_000_000, result.supply_amount
      assert_equal 33_000, result.withholding_amount
      assert_equal 100_000, result.tax_amount
      assert_equal 967_000, result.net_amount
      assert_equal 1_100_000, result.total_amount
    end

    test "콤마 포함 입력 처리" do
      assert_equal 967_000, TaxCalculatorService.call(amount_raw: "1,000,000").net_amount
    end

    test "부가세 포함 입력 — 총액 1,100,000이면 공급가액 1,000,000 환산" do
      result = TaxCalculatorService.call(amount_raw: "1100000", vat_included: "true")
      assert_equal 1_000_000, result.supply_amount
      assert_equal 33_000, result.withholding_amount
      assert_equal 967_000, result.net_amount
    end

    test "부가세 미포함 플래그는 총액을 그대로 공급가액으로 취급" do
      result = TaxCalculatorService.call(amount_raw: "1100000", vat_included: "false")
      assert_equal 1_100_000, result.supply_amount
    end

    test "절사 반올림 — 원 단위 floor (INV-2 산식 동일)" do
      result = TaxCalculatorService.call(amount_raw: "99999")
      assert_equal 3299, result.withholding_amount      # 3299.967 → 3299
      assert_equal 9999, result.tax_amount              # 9999.9 → 9999
    end

    test "0·음수·비숫자 입력은 InvalidAmount" do
      assert_raises(TaxCalculatorService::InvalidAmount) { TaxCalculatorService.call(amount_raw: "0") }
      assert_raises(TaxCalculatorService::InvalidAmount) { TaxCalculatorService.call(amount_raw: "-100") }
      assert_raises(TaxCalculatorService::InvalidAmount) { TaxCalculatorService.call(amount_raw: "") }
      assert_raises(TaxCalculatorService::InvalidAmount) { TaxCalculatorService.call(amount_raw: "abc") }
    end
  end
end
