require "test_helper"

# 월 정산 스냅샷 모델(SALES-5·Q24 — F-SALES). pending→paid 전이·mark_paid! 멱등·검증.
class SalesCommissionTest < ActiveSupport::TestCase
  setup do
    @commission = sales_reps(:sales_kim).sales_commissions.create!(
      year: 2026, month: 10, base_amount: 19_800, rate: 20, amount: 3_960
    )
  end

  test "mark_paid!는 paid 전환과 지급 시각을 기록하고 재호출은 false다 (SALES-5·SEC-5)" do
    assert @commission.mark_paid!
    assert @commission.paid?
    assert_not_nil @commission.paid_at

    assert_not @commission.mark_paid!, "이미 지급된 정산은 재처리되지 않는다"
    assert_equal "paid", @commission.reload.status
  end

  test "period_label은 year.month 2자리 형식이다 (SALES-6)" do
    assert_equal "2026.10", @commission.period_label
  end

  test "rate는 0~100 정수만 허용한다 (SALES-5 — W-2의 2차 방어선)" do
    @commission.rate = 101
    assert_not @commission.valid?
    @commission.rate = -1
    assert_not @commission.valid?
    @commission.rate = 20.5
    assert_not @commission.valid?
    @commission.rate = 100
    assert @commission.valid?
  end

  test "month는 1~12만 허용하고 base_amount·amount는 0 이상 정수다" do
    @commission.month = 13
    assert_not @commission.valid?

    @commission.month = 10
    @commission.base_amount = -100
    assert_not @commission.valid?

    @commission.base_amount = 0
    @commission.amount = 0
    assert @commission.valid?, "무실적 월의 0원 스냅샷도 유효하다"
  end

  test "복합 유니크(rep·연월)는 월 1행 스냅샷을 강제한다 — DB 수준 (SALES-5)" do
    dup = sales_reps(:sales_kim).sales_commissions.build(
      year: 2026, month: 10, base_amount: 1, rate: 20, amount: 0
    )
    assert dup.valid?, "모델 검증은 통과 — 유니크는 DB 복합 인덱스로 강제된다"
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save! }

    other = sales_reps(:officer_park).sales_commissions.create!(
      year: 2026, month: 10, base_amount: 9_900, rate: 15, amount: 1_485
    )
    assert other.persisted?, "다른 rep의 같은 연월은 허용된다"
  end
end
