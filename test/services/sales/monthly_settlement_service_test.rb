require "test_helper"
require_relative "../../test_helpers/fake_portone_client"

# 월 수수료 정산(SALES-5·Q24 — F-SALES). 역할 정책(sales 20%·12개월 캡 / officer 15%·무기한)·
# 기준 실차감액(orders.amount — 첫달 할인가 포함)·환불 제외·upsert 멱등(재실행 동일·
# paid 스냅샷 보존)·경계(±1초)·개별 rep 실패 후 계속.
# 시나리오 기준: PRD §6.20 SALES-5·Q24·_workspace/05_review.md §4 Tester 중점 9번.
class Sales::MonthlySettlementServiceTest < ActiveSupport::TestCase
  setup do
    @sales_rep = SalesRep.create!(email: "settle-sales@example.com", password: "password123",
                                  name: "정산영업", role: :sales)
    @officer_rep = SalesRep.create!(email: "settle-officer@example.com", password: "password123",
                                    name: "정산감투", role: :officer)
  end

  def referred_user(rep:, email:, created_at: nil)
    user = User.create!(email:, password: "password123", referred_by_sales_rep_id: rep.id)
    user.update_columns(created_at:) if created_at
    user
  end

  def plus_paid_order(user, amount:, paid_at:, refunded: false)
    user.orders.create!(product: :plus_monthly, amount:, status: :paid,
                        pg_order_id: "pg-#{user.id}-#{paid_at.to_i}",
                        paid_at:, refunded_at: (refunded ? paid_at + 1.day : nil))
  end

  test "officer는 무기한 — 가입 13개월째 결제도 15%로 집계한다 (Q24 역할 이원화)" do
    user = referred_user(rep: @officer_rep, email: "officer-u1@example.com",
                         created_at: Time.zone.parse("2025-08-10 09:00"))
    plus_paid_order(user, amount: 9_900, paid_at: Time.zone.parse("2026-09-05 10:00")) # 13개월째

    Sales::MonthlySettlementService.new(year: 2026, month: 9).call

    snapshot = @officer_rep.sales_commissions.sole
    assert_equal 9_900, snapshot.base_amount
    assert_equal 15, snapshot.rate
    assert_equal 1_485, snapshot.amount
    assert snapshot.pending?
  end

  test "sales는 20%이고 12개월 캡 경계(±1초)를 포함 판정한다 (Q24 — paid_at 경계)" do
    # 캡 경계 안(= created_at + 12개월 정각)·밖(+1초) — 같은 대상월에 2명 배치
    inside = referred_user(rep: @sales_rep, email: "sales-in@example.com",
                           created_at: Time.zone.parse("2026-01-15 10:00:00"))
    outside = referred_user(rep: @sales_rep, email: "sales-out@example.com",
                            created_at: Time.zone.parse("2026-01-15 10:00:00"))
    plus_paid_order(inside, amount: 9_900,
                    paid_at: Time.zone.parse("2027-01-15 10:00:00"))     # = +12개월(포함)
    plus_paid_order(outside, amount: 9_900,
                    paid_at: Time.zone.parse("2027-01-15 10:00:01"))     # = +12개월+1초(제외)

    Sales::MonthlySettlementService.new(year: 2027, month: 1).call

    snapshot = @sales_rep.sales_commissions.sole
    assert_equal 9_900, snapshot.base_amount, "경계 포함 판정 — 정각 결제만 집계"
    assert_equal 20, snapshot.rate
    assert_equal 1_980, snapshot.amount
  end

  test "sales 캡 — 가입 12개월이 지난 결제는 집계에서 제외된다 (Q24 12개월 캡)" do
    user = referred_user(rep: @sales_rep, email: "sales-cap@example.com",
                         created_at: Time.zone.parse("2025-09-20 09:00"))
    plus_paid_order(user, amount: 9_900, paid_at: Time.zone.parse("2026-10-05 10:00")) # 12개월+경과

    Sales::MonthlySettlementService.new(year: 2026, month: 10).call

    assert_empty @sales_rep.sales_commissions, "캡 외 결제만 있으면 스냅샷 미생성"
  end

  test "기준 금액은 실차감액(orders.amount — 첫 달 할인가 포함)이다 (SALES-5·Q24)" do
    user = referred_user(rep: @sales_rep, email: "sales-amount@example.com",
                         created_at: Time.zone.parse("2026-09-01 09:00"))
    plus_paid_order(user, amount: 7_920, paid_at: Time.zone.parse("2026-09-10 10:00")) # 첫달 20% 할인가

    Sales::MonthlySettlementService.new(year: 2026, month: 9).call

    assert_equal 7_920, @sales_rep.sales_commissions.sole.base_amount
    assert_equal 1_584, @sales_rep.sales_commissions.sole.amount, "(7,920 × 20%).floor"
  end

  test "환불(refunded_at)·미결제(pending·failed)·비Plus 상품은 제외된다 (SALES-5)" do
    user = referred_user(rep: @officer_rep, email: "officer-filter@example.com")
    plus_paid_order(user, amount: 9_900, paid_at: Time.zone.parse("2026-09-01 10:00"), refunded: true)
    user.orders.create!(product: :plus_monthly, amount: 9_900,
                        pg_order_id: "pg-pending-1", paid_at: nil)                      # pending
    user.orders.create!(product: :plus_monthly, amount: 9_900, status: :failed,
                        pg_order_id: "pg-failed-1", paid_at: nil)                       # failed
    user.orders.create!(product: :collection_pass, amount: 4_000, status: :paid,
                        pg_order_id: "pg-pass-1", paid_at: Time.zone.parse("2026-09-02 10:00"))

    Sales::MonthlySettlementService.new(year: 2026, month: 9).call

    assert_empty @officer_rep.sales_commissions, "집계 대상 0원 — 스냅샷 미생성"
  end

  test "절사(floor)와 개별 요율 오버라이드가 반영된다 (Q24 effective_rate 스냅샷)" do
    @sales_rep.update!(commission_rate: 30)
    user = referred_user(rep: @sales_rep, email: "sales-override@example.com",
                         created_at: Time.zone.parse("2026-09-01 09:00"))
    plus_paid_order(user, amount: 9_950, paid_at: Time.zone.parse("2026-09-10 10:00"))

    Sales::MonthlySettlementService.new(year: 2026, month: 9).call

    snapshot = @sales_rep.sales_commissions.sole
    assert_equal 30, snapshot.rate
    assert_equal 2_985, snapshot.amount, "(9,950 × 30% = 2,985.0).floor"
  end

  test "upsert 멱등 — 재실행해도 동일 스냅샷이며 중복 행이 없다 (SEC-5)" do
    user = referred_user(rep: @officer_rep, email: "officer-idem@example.com")
    plus_paid_order(user, amount: 9_900, paid_at: Time.zone.parse("2026-09-05 10:00"))

    Sales::MonthlySettlementService.new(year: 2026, month: 9).call
    first = @officer_rep.sales_commissions.sole
    Sales::MonthlySettlementService.new(year: 2026, month: 9).call

    assert_equal 1, @officer_rep.sales_commissions.count
    assert_equal first.attributes.except("updated_at", "settled_at"),
                 first.reload.attributes.except("updated_at", "settled_at")
  end

  test "pending 스냅샷은 재집계 값으로 갱신된다 — 환불 반영 회복 경로 (SALES-5 upsert)" do
    user = referred_user(rep: @officer_rep, email: "officer-regen@example.com")
    order = plus_paid_order(user, amount: 9_900, paid_at: Time.zone.parse("2026-09-05 10:00"))
    Sales::MonthlySettlementService.new(year: 2026, month: 9).call
    assert_equal 1_485, @officer_rep.sales_commissions.sole.amount

    order.update!(refunded_at: Time.zone.parse("2026-09-20 12:00"))
    Sales::MonthlySettlementService.new(year: 2026, month: 9).call

    assert_equal 1, @officer_rep.sales_commissions.count
    assert_equal 0, @officer_rep.sales_commissions.sole.reload.base_amount, "환불 반영 재집계"
    assert_equal 0, @officer_rep.sales_commissions.sole.amount
  end

  test "paid 스냅샷은 재집계로 덮지 않는다 — 지급 확정 금액 보존 (SALES-5·SEC-5)" do
    user = referred_user(rep: @officer_rep, email: "officer-paid@example.com")
    order = plus_paid_order(user, amount: 9_900, paid_at: Time.zone.parse("2026-09-05 10:00"))
    Sales::MonthlySettlementService.new(year: 2026, month: 9).call
    commission = @officer_rep.sales_commissions.sole
    commission.mark_paid!
    paid_amount = commission.amount
    updated_at_before = commission.updated_at

    order.update!(refunded_at: Time.zone.parse("2026-09-20 12:00")) # 재집계 조건 변화
    Sales::MonthlySettlementService.new(year: 2026, month: 9).call

    assert_equal paid_amount, commission.reload.amount, "paid 행은 무변경"
    assert commission.paid?
    assert_equal updated_at_before, commission.updated_at, "update! 호출 없이 조기 반환"
  end

  test "무실적 rep은 스냅샷을 만들지 않는다 (SALES-5)" do
    referred_user(rep: @officer_rep, email: "officer-zero@example.com") # 결제 없는 유치 사용자

    Sales::MonthlySettlementService.new(year: 2026, month: 9).call

    assert_empty @officer_rep.sales_commissions
    assert_empty @sales_rep.sales_commissions
  end

  test "개별 rep 실패(요율 검증 위반)는 로그 후 계속 — 다른 rep 정산은 정상 생성된다 (SALES-5)" do
    # W-2 검증 우회(update_column)로 101%를 심어 SalesCommission rate 검증 실패를 유도한다 —
    # 서비스가 rescue로 흡수해 나머지 rep를 계속 처리하는지 검증한다.
    @sales_rep.update_column(:commission_rate, 101) # rubocop:disable Rails/SkipsModelValidations
    bad_user = referred_user(rep: @sales_rep, email: "sales-bad@example.com",
                             created_at: Time.zone.parse("2026-09-01 09:00"))
    plus_paid_order(bad_user, amount: 9_900, paid_at: Time.zone.parse("2026-09-05 10:00"))
    good_user = referred_user(rep: @officer_rep, email: "officer-good@example.com")
    plus_paid_order(good_user, amount: 9_900, paid_at: Time.zone.parse("2026-09-06 10:00"))

    Sales::MonthlySettlementService.new(year: 2026, month: 9).call

    assert_empty @sales_rep.sales_commissions.reload, "실패 rep는 스냅샷 없음(로그 흡수)"
    assert_equal 1_485, @officer_rep.sales_commissions.sole.amount, "나머지 rep는 정상 집계"
  end

  test "대상월 기본값은 직전월(KST)이다 (SALES-5 매월 1일 00:05 Job)" do
    user = referred_user(rep: @officer_rep, email: "officer-prev@example.com")

    travel_to(Time.zone.parse("2026-11-01 00:05")) do
      plus_paid_order(user, amount: 9_900, paid_at: Time.zone.parse("2026-10-31 23:59"))
      plus_paid_order(user, amount: 9_900, paid_at: Time.zone.parse("2026-11-01 00:01"))

      Sales::MonthlySettlementService.new.call
    end

    snapshot = @officer_rep.sales_commissions.sole
    assert_equal [ 2026, 10 ], [ snapshot.year, snapshot.month ], "직전월(10월)만 집계"
    assert_equal 9_900, snapshot.base_amount
  end

  # PLAN-9 — 관리자 환불 실행(status cancelled·refunded_at)은 정산 기준 금액에서 제외된다
  # (기존 환불 제외 스코프 not_refunded가 실행 경로까지 커버함을 실제 실행 경로로 고정).
  test "환불 실행된 주문은 수수료 기준 금액에서 제외된다 (SALES-5·PLAN-9)" do
    user = referred_user(rep: @officer_rep, email: "settle-refund@example.com",
                         created_at: Time.zone.parse("2026-08-10 09:00"))
    order = plus_paid_order(user, amount: 9_900, paid_at: Time.zone.parse("2026-09-05 10:00"))

    travel_to(Time.zone.parse("2026-09-08 10:00")) do
      result = Orders::RefundService.new(
        admin: admins(:ops), order: order, reason: "이중 결제 정정",
        client: FakePortOneClient.new(get_payment: { id: order.pg_order_id, status: "CANCELLED",
                                                     amount: { paid: order.amount,
                                                               cancelled: order.amount } })
      ).call
      assert result.success?, "전제: 환불 실행이 성공해야 한다"
    end

    Sales::MonthlySettlementService.new(year: 2026, month: 9).call

    assert_empty @officer_rep.sales_commissions,
                 "환불 실행 건은 정산 기준 금액에서 제외 — 기준 0은 스냅샷 미생분(SKIP 가드)"
  end
end
