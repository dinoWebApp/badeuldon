require "test_helper"

# F-SALES recurring 결선(SALES-2·5 — TIME-1 KST 접미사)과 Job→Service 위임.
# 시나리오 기준: PRD §6.20 SALES-2(매주 월요일 00:00 KST)·SALES-5(매월 1일 00:05 KST)·
# _workspace/05_review.md §2 TIME-1 판정.
class SalesRecurringTest < ActiveSupport::TestCase
  test "recurring.yml에 로테이션·정산 항목이 production·development 양쪽에 있다 (TIME-1)" do
    recurring = YAML.safe_load(File.read(Rails.root.join("config/recurring.yml")),
                               permitted_classes: [], aliases: true)
    expectations = {
      "sales_referral_codes_rotate" => { klass: "Sales::RotateReferralCodesJob", cron: "0 0 * * 1" },
      "sales_monthly_settlement" => { klass: "Sales::MonthlySettlementJob", cron: "5 0 1 * *" }
    }
    %w[production development].each do |env|
      expectations.each do |key, spec|
        entry = recurring.dig(env, key) || recurring[key]
        assert_not_nil entry, "recurring.yml #{env}에 #{key} 없음"
        assert_equal spec[:klass], entry["class"]
        schedule_pattern = /#{Regexp.escape(spec[:cron])} Asia\/Seoul\z/
        assert_match schedule_pattern, entry["schedule"], "#{key} 스케줄은 KST 접미사 cron이다"
      end
    end
  end

  test "로테이션 Job은 활동 rep 전체의 코드를 재생성하고 정지 rep는 제외한다 (SALES-2)" do
    travel_to(Time.zone.parse("2026-11-23 00:00")) do
      Sales::RotateReferralCodesJob.perform_now

      sales_reps(:sales_kim).reload
      assert_not_nil sales_reps(:sales_kim).sales_referral_codes.find_by(valid_from: Date.current)
      assert_not_nil sales_reps(:officer_park).sales_referral_codes.find_by(valid_from: Date.current)
      assert_nil sales_reps(:suspended_choi).sales_referral_codes.find_by(valid_from: Date.current)
    end
  end

  test "정산 Job은 직전월 스냅샷을 생성한다 (SALES-5)" do
    user = User.create!(email: "job-settle@example.com", password: "password123",
                        referred_by_sales_rep_id: sales_reps(:officer_park).id)
    user.orders.create!(product: :plus_monthly, amount: 9_900, status: :paid,
                        pg_order_id: "pg-job-settle", paid_at: 1.month.ago.beginning_of_month + 5.days)

    Sales::MonthlySettlementJob.perform_now

    snapshot = SalesCommission.sole
    assert_equal sales_reps(:officer_park).id, snapshot.sales_rep_id
    assert_equal [ 1.month.ago.year, 1.month.ago.month ], [ snapshot.year, snapshot.month ]
    assert_equal 9_900, snapshot.base_amount
    assert_equal 1_485, snapshot.amount
  end
end
