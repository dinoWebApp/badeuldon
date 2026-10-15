require "test_helper"

# 수금 패스(F-PLAN — PLAN-4) 모델 — 10건권·90일 유효, 사용 차감(use!)과 소진·만료 차단.
# with_lock 실스레드 동시 사용 검증은 payment_pass_concurrency_test.rb(SQLite 직렬화)에서 수행한다.
# 시나리오 기준: PRD §6.10 PLAN-4, _workspace/03_implementation.md §2. 외부 API 호출 없음.
class PaymentPassTest < ActiveSupport::TestCase
  setup do
    @pass = users(:delta).payment_passes.create!(
      total_uses: PaymentPass::TOTAL_USES, remaining_uses: PaymentPass::TOTAL_USES,
      expires_at: PaymentPass::VALIDITY_DAYS.days.from_now
    )
  end

  test "10건 90일 기준 상수다 (PLAN-4)" do
    assert_equal 10, PaymentPass::TOTAL_USES
    assert_equal 90, PaymentPass::VALIDITY_DAYS
  end

  test "잔여 1 이상이고 유효기간 내면 사용 가능하다 — 잔여 0은 불가 (경계)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      @pass.update!(remaining_uses: 1)
      assert_predicate @pass, :usable?

      @pass.update!(remaining_uses: 0)
      assert_not_predicate @pass, :usable?
    end
  end

  test "유효기간이 지나면 사용할 수 없다 — 만료일 당일은 가능 (경계·TIME-1)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      @pass.update!(expires_at: Time.zone.parse("2026-10-15 09:00") - 1.second)

      assert_not_predicate @pass, :usable?
    end
  end

  test "사용 차감은 잔여 횟수를 1씩 줄인다" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      assert_equal 9, @pass.use!.reload.remaining_uses
    end
  end

  test "10회 사용 후 11번째는 소진 예외로 차단된다 (PLAN-4 — 상한)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      10.times { @pass.use! }
      assert_equal 0, @pass.reload.remaining_uses

      error = assert_raises(PaymentPass::UsesExhausted) { @pass.use! }
      assert_equal 0, @pass.reload.remaining_uses  # 음수로 넘어가지 않는다
      assert_match(/모두 사용되었거나 만료/, error.message)
    end
  end

  test "만료된 패스의 사용은 소진 예외로 차단된다 (PLAN-4 — 90일)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      @pass.update!(remaining_uses: 5, expires_at: 1.second.ago)

      assert_raises(PaymentPass::UsesExhausted) { @pass.use! }
      assert_equal 5, @pass.reload.remaining_uses  # 차감되지 않는다
    end
  end

  test "usable 스코프는 소진·만료 패스를 제외한다 (요금제 페이지 목록 기준)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      exhausted = users(:delta).payment_passes.create!(
        total_uses: 10, remaining_uses: 0, expires_at: 30.days.from_now
      )
      expired = users(:delta).payment_passes.create!(
        total_uses: 10, remaining_uses: 10, expires_at: 1.second.ago
      )

      usable_ids = users(:delta).payment_passes.usable.ids
      assert_includes usable_ids, @pass.id
      assert_not_includes usable_ids, exhausted.id
      assert_not_includes usable_ids, expired.id
    end
  end
end
