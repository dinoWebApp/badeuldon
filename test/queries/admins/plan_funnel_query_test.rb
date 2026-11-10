require "test_helper"

# ADMIN-5 — 플랜 전환 퍼널 쿼리(Admins::PlanFunnelQuery).
# 시나리오 기준: PRD v0.31 ADMIN-5·Q4 —
# ① signups = 전체 사용자, ② trial_started = subscriptions.used_trial = true(체험 만료 후에도 유지 — PLAN-2),
# ③ plus_converted = plan plus · status active/cancelled(해지는 기간 말까지 Plus — PLAN-5) —
#   cancelled 제외하면 PLAN-5 위반으로 검출된다, ④ trialing도 plus이므로 전환 집계에 포함된다.
class Admins::PlanFunnelQueryTest < ActiveSupport::TestCase
  test "가입→체험→Plus 전환 퍼널을 집계한다 (ADMIN-5)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      clear_domain_tables
      User.delete_all
      # 3명 가입 — 전부 after_create로 Free 구독 행 자동 생성
      signer_a = User.create!(email: "funnel-a@example.com", password: "password")
      signer_b = User.create!(email: "funnel-b@example.com", password: "password")
      User.create!(email: "funnel-c@example.com", password: "password")

      # A — 체험 시작 후 만료 강등(expired) — used_trial 플래그는 유지(PLAN-2)
      signer_a.subscription.update!(used_trial: true, plan: :free, status: :expired)
      # B — Plus 활성
      signer_b.subscription.update!(plan: :plus, status: :active)
      # C — Plus로 전환했다가 해지(cancelled) — 전환 인구에 포함되어야 한다
      signer = User.find_by(email: "funnel-c@example.com")
      signer.subscription.update!(plan: :plus, status: :cancelled)

      row = Admins::PlanFunnelQuery.call

      assert_equal 3, row.signups
      assert_equal 1, row.trial_started
      assert_equal 2, row.plus_converted, "cancelled도 기간 말까지 Plus — PLAN-5 정합"
    end
  end

  test "trialing 중인 구독은 체험 시작엔 포함되고 Plus 전환엔 제외된다 (ADMIN-5 — active·cancelled 한정)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      clear_domain_tables
      User.delete_all
      User.create!(email: "funnel-t@example.com", password: "password")
                   .subscription.update!(plan: :plus, status: :trialing,
                                         trial_ends_at: 10.days.from_now, used_trial: true)

      row = Admins::PlanFunnelQuery.call

      assert_equal 1, row.trial_started
      assert_equal 0, row.plus_converted, "trialing는 전환 집계 제외 — active·cancelled만 산정"
    end
  end

  test "사용자가 없으면 퍼널 전 구간이 0이다 (빈 데이터)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      clear_domain_tables
      User.delete_all

      row = Admins::PlanFunnelQuery.call

      assert_equal 0, row.signups
      assert_equal 0, row.trial_started
      assert_equal 0, row.plus_converted
    end
  end
end
