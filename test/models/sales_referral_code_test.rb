require "test_helper"

# 추천 코드 모델(SALES-2 — F-SALES). 8자 안전 문자열·현재 유효 창(양끝 포함)·이력 검증.
# 시나리오 기준: PRD §6.20 SALES-2·_workspace/05_review.md §4 Tester 중점 10번.
class SalesReferralCodeTest < ActiveSupport::TestCase
  test "generate_code는 8자이고 혼동 문자(O·I·L·0·1)를 제외한 알파벳으로만 구성된다 (SALES-2)" do
    20.times do
      code = SalesReferralCode.generate_code
      assert_equal 8, code.length
      code.each_char do |ch|
        assert_includes SalesReferralCode::SAFE_ALPHABET, ch
        assert_not_includes %w[O I L 0 1], ch
      end
    end
  end

  test "SAFE_ALPHABET은 혼동 문자를 배제한다 (SALES-2)" do
    alphabet = SalesReferralCode::SAFE_ALPHABET
    assert_equal 31, alphabet.size # 26 - 3(O·I·L) + 8(2~9)
    %w[O I L 0 1].each { |excluded| assert_not_includes alphabet, excluded }
  end

  test "current_valid는 오늘(KST)을 양끝 포함으로 판정한다 (SALES-2·TIME-1)" do
    code = sales_reps(:sales_kim).sales_referral_codes.create!(
      code: "TODAY001", valid_from: Date.current, valid_until: Date.current
    )
    assert_includes SalesReferralCode.current_valid, code, "당일 발급·당일 만료도 유효(양끝 포함)"
  end

  test "current_valid는 valid_until이 어제인 만료 코드를 제외한다 (SALES-2 만료 거부)" do
    expired = sales_referral_codes(:sales_kim_expired) # valid_until = 어제
    assert_not_includes SalesReferralCode.current_valid, expired
    assert expired.expired?
  end

  test "current_valid는 valid_from이 내일인 미발효 코드를 제외한다 (SALES-2)" do
    future = sales_reps(:sales_kim).sales_referral_codes.create!(
      code: "FUTURE01", valid_from: Date.current + 1.day, valid_until: Date.current + 6.days
    )
    assert_not_includes SalesReferralCode.current_valid, future
    assert_not future.expired?
  end

  test "expired?는 valid_until이 어제일 때만 true다 (경계 — 어제 vs 오늘)" do
    assert sales_referral_codes(:sales_kim_expired).expired?
    assert_not sales_referral_codes(:sales_kim_current).expired?
  end

  test "code는 대소문자·공백 정규화되고 8자·전역 유니크를 강제한다 (SALES-2)" do
    rep = SalesRep.create!(email: "norm@example.com", password: "password123", name: "n")
    row = rep.sales_referral_codes.create!(code: "  ab12cd34  ", valid_from: Date.current,
                                           valid_until: Date.current + 1)
    assert_equal "AB12CD34", row.code

    short = rep.sales_referral_codes.build(code: "ABC", valid_from: Date.current,
                                           valid_until: Date.current + 1)
    assert_not short.valid?
    assert short.errors[:code].present?

    dup = sales_reps(:officer_park).sales_referral_codes.build(
      code: "KIM2026A", valid_from: Date.current, valid_until: Date.current + 1
    )
    assert_not dup.valid?, "코드는 전역 유니크다"
  end

  test "valid_until이 valid_from보다 이전이면 검증 오류다" do
    row = sales_reps(:sales_kim).sales_referral_codes.build(
      code: "REVERSED", valid_from: Date.current, valid_until: Date.current - 1.day
    )
    assert_not row.valid?
    assert_includes row.errors[:valid_until], "은(는) 유효 시작일보다 이전일 수 없습니다"
  end
end
