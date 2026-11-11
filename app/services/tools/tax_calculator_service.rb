# 3.3% 계산기(LLP-11 무료 도구 2종·INV-2 원천징수 3.3% 선례 산식). 공급가액 기준으로
# 원천징수 3.3%·부가세 10%·실수령액을 계산하는 순수 함수 — 상태·저장 없음(P3).
# 부가세 포함 입력(총액 기준)이면 공급가액을 원 단위로 환산해 계산한다.
module Tools
  class TaxCalculatorService
    Result = Data.define(:supply_amount, :withholding_amount, :tax_amount, :net_amount, :total_amount)

    class InvalidAmount < StandardError; end

    VAT_RATE = 0.10
    WITHHOLDING_RATE = 0.033

    # amount_raw: GET params 원문("1,000,000" 허용)·vat_included: 부가세 포함 총액 입력 여부.
    def self.call(amount_raw:, vat_included: false)
      new(amount_raw: amount_raw, vat_included: vat_included).call
    end

    def initialize(amount_raw:, vat_included:)
      @amount_raw = amount_raw.to_s.delete(",")
      @vat_included = ActiveModel::Type::Boolean.new.cast(vat_included)
    end

    def call
      supply = resolve_supply
      raise InvalidAmount, "공급가액은 1원 이상 숫자로 입력해 주세요" unless supply.positive?

      withholding = (supply * WITHHOLDING_RATE).floor  # 원 단위 절사 — INV-2 산식과 동일
      tax = (supply * VAT_RATE).floor
      Result.new(
        supply_amount: supply,
        withholding_amount: withholding,
        tax_amount: tax,
        net_amount: supply - withholding,
        total_amount: supply + tax
      )
    end

    private

    def resolve_supply
      raw = @amount_raw.to_i
      return 0 unless raw.positive?

      @vat_included ? (raw / (1 + VAT_RATE)).round : raw  # 부가세 환산은 반올림(1,100,000→1,000,000)
    end
  end
end
