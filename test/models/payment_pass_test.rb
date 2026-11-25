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

  # ── PLAN-9②·Q27 — 회원 단위 차감(revoke_uses!) ──

  test "revoke_uses!는 만료 임박순으로 여러 패스에 걸쳐 차감한다 (PLAN-9②·Q27)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      user = users(:gamma) # 패스 fixture 없는 사용자 — 테스트가 보유 패스를 만든다
      soon = create_pass(user, remaining: 6, expires_at: Time.zone.parse("2026-11-05 23:59:59"))
      later = create_pass(user, remaining: 10, expires_at: Time.zone.parse("2026-12-25 23:59:59"))

      revoked, ignored = PaymentPass.revoke_uses!(user: user, count: 10)

      assert_equal [ 10, 0 ], [ revoked, ignored ]
      assert_equal 0, soon.reload.remaining_uses, "만료 임박 패스 먼저"
      assert_equal 6, later.reload.remaining_uses, "남은 수량은 다음 패스에서"
    end
  end

  test "revoke_uses!는 잔여 부족 시 0에서 종료하고 나머지를 무시한다 (PLAN-9② — 음수 방지)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      user = users(:gamma)
      pass = create_pass(user, remaining: 3, expires_at: Time.zone.parse("2026-11-05 23:59:59"))

      revoked, ignored = PaymentPass.revoke_uses!(user: user, count: 10)

      assert_equal [ 3, 7 ], [ revoked, ignored ]
      assert_equal 0, pass.reload.remaining_uses, "0에서 종료 — 음수 없음"
    end
  end

  test "revoke_uses!는 만료·소진 패스를 제외하고 유효 패스만 차감한다 (PLAN-9②)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      user = users(:gamma)
      usable = create_pass(user, remaining: 4, expires_at: Time.zone.parse("2026-11-05 23:59:59"))
      expired = create_pass(user, remaining: 10, expires_at: Time.zone.parse("2026-10-15 08:59:59"))
      exhausted = create_pass(user, remaining: 0, expires_at: Time.zone.parse("2026-12-25 23:59:59"))

      revoked, ignored = PaymentPass.revoke_uses!(user: user, count: 10)

      assert_equal [ 4, 6 ], [ revoked, ignored ]
      assert_equal 0, usable.reload.remaining_uses
      assert_equal 10, expired.reload.remaining_uses, "만료 패스 무변경"
      assert_equal 0, exhausted.reload.remaining_uses, "소진 패스 무변경"
    end
  end

  test "revoke_uses!는 보유 패스가 없으면 [0, count]를 반환한다 (PLAN-9② 경계)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      revoked, ignored = PaymentPass.revoke_uses!(user: users(:gamma), count: PaymentPass::TOTAL_USES)

      assert_equal [ 0, 10 ], [ revoked, ignored ]
    end
  end

  test "revoke_uses!는 count가 0·음수면 ArgumentError로 거부한다 (PLAN-9② 방어)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      user = users(:gamma)

      assert_raises(ArgumentError) { PaymentPass.revoke_uses!(user: user, count: 0) }
      assert_raises(ArgumentError) { PaymentPass.revoke_uses!(user: user, count: -1) }
    end
  end

  private

  def create_pass(user, remaining:, expires_at:)
    user.payment_passes.create!(total_uses: PaymentPass::TOTAL_USES,
                                remaining_uses: remaining, expires_at: expires_at)
  end
end
