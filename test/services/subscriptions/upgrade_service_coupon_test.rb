require "test_helper"
require_relative "../../test_helpers/fake_portone_client"

# 쿠폰 첫 차감 결제 시나리오(ADMIN-4 — Q12 불변식). UpgradeService renew 경유의 Plus 첫 차감에
# 예약 쿠폰을 적용하며, 6건 불변식 중 결제 경유 4건을 검증한다:
# ① 첫 차감 orders.amount = 할인가 + metadata에 coupon_code ② used_count는 결제 성공 시점
# 1회 증가(멱등 — charge 실패 시 미증가) ③ 재과금(두 번째 갱신)은 정상가 ④ 중복 적용 경로 없음.
# 포트원은 FakePortOneClient 주입(실호출 금지).
class Subscriptions::UpgradeServiceCouponTest < ActiveSupport::TestCase
  setup do
    @user = users(:gamma)
    @billing_channel_key = "test-channel-billing"
    @subscription = @user.create_subscription!(
      plan: :plus, status: :active, pg_billing_key: "tok_billing_c1", pg_customer_key: "cust_c1",
      current_period_start: Time.zone.parse("2026-10-01 00:00"),
      current_period_end: Time.zone.parse("2026-10-31 23:59:59")
    )
    @subscription.update!(coupon_id: coupons(:amount_coupon).id)
  end

  test "첫 차감은 쿠폰 할인가로 진행되고 주문 금액·metadata에 쿠폰이 기록된다 (불변식 1)" do
    fake = FakePortOneClient.new(charge_billing_key: { payment: { id: "payment_c1", status: "PAID" } })

    travel_to(Time.zone.parse("2026-11-01 06:05")) do
      Subscriptions::UpgradeService.new(user: @user, action: :renew,
                                        channel_key: @billing_channel_key, client: fake).call
    end

    charge = fake.calls[:charge_billing_key].sole
    assert_equal 7_900, charge[:amount]                       # 9,900 − 2,000
    order = @user.orders.sole
    assert_equal 7_900, order.amount                          # orders.amount = 할인가
    assert_equal "SAVE2000", order.metadata["coupon"]["code"] # metadata coupon_code 기록
    assert_equal "amount", order.metadata["coupon"]["discount_type"]
  end

  test "used_count는 결제 성공 시점에 1회 증가하고 쿠폰 예약은 해제된다 (불변식 2 — 멱등)" do
    fake = FakePortOneClient.new

    travel_to(Time.zone.parse("2026-11-01 06:05")) do
      Subscriptions::UpgradeService.new(user: @user, action: :renew,
                                        channel_key: @billing_channel_key, client: fake).call
    end

    assert_equal 1, coupons(:amount_coupon).reload.used_count
    assert_nil @subscription.reload.coupon_id
  end

  test "charge 실패 시 used_count는 증가하지 않고 쿠폰 예약이 유지된다 (불변식 2 — 실패 미소비)" do
    fake = FakePortOneClient.new(raise_on: { charge_billing_key:
                            PortOne::ApiError.new(status: 400, code: "PG_PROVIDER_ERROR",
                                                  message: "PG사 승인이 거절되었습니다") })

    error = assert_raises(Subscriptions::UpgradeService::UpgradeError) do
      travel_to(Time.zone.parse("2026-11-01 06:05")) do
        Subscriptions::UpgradeService.new(user: @user, action: :renew,
                                          channel_key: @billing_channel_key, client: fake).call
      end
    end

    assert_match(/자동 결제에 실패했습니다/, error.message)
    assert_equal 0, coupons(:amount_coupon).reload.used_count # 성공 기준 소비 — 미증가
    assert_equal coupons(:amount_coupon).id, @subscription.reload.coupon_id
    # 재등록(activate!) 후 재시도 — 쿠폰 예약은 유지되고 pending 주문 재사용으로 같은 할인가 시도
    @subscription.activate!(billing_key: "tok_billing_retry")
    @subscription.update!(current_period_end: Time.zone.parse("2026-11-01 08:00")) # 재갱신 도래
    retry_fake = FakePortOneClient.new
    travel_to(Time.zone.parse("2026-11-01 09:00")) do
      Subscriptions::UpgradeService.new(user: @user, action: :renew,
                                        channel_key: @billing_channel_key, client: retry_fake).call
    end
    assert_equal 7_900, retry_fake.calls[:charge_billing_key].sole[:amount]
    assert_equal 7_900, @user.orders.order(:created_at).last.reload.amount
    assert_equal 1, coupons(:amount_coupon).reload.used_count # 성공 시점에만 증가
  end

  test "재과금(두 번째 갱신)은 정상가로 차감된다 (불변식 3 — Q12 재과금 할인 없음)" do
    fake = FakePortOneClient.new(charge_billing_key: { payment: { id: "payment_seq", status: "PAID" } })

    travel_to(Time.zone.parse("2026-11-01 06:05")) do
      Subscriptions::UpgradeService.new(user: @user, action: :renew,
                                        channel_key: @billing_channel_key, client: fake).call
    end
    travel_to(Time.zone.parse("2026-12-01 06:05")) do
      Subscriptions::UpgradeService.new(user: @user, action: :renew,
                                        channel_key: @billing_channel_key, client: fake).call
    end

    amounts = fake.calls[:charge_billing_key].map { |call| call[:amount] }
    assert_equal [ 7_900, 9_900 ], amounts                    # 첫 차감만 할인·재과금 정상가
    assert_equal 1, coupons(:amount_coupon).reload.used_count # 두 번 결제여도 1회만 소비
  end

  test "이미 성공한 Plus 결제가 있으면 쿠폰이 무효화되고 정상가로 차감된다 (불변식 4 — 중복 적용 차단)" do
    @user.orders.create!(product: :plus_monthly, amount: 9_900, status: :paid,
                         pg_order_id: "order-paid-first-1", paid_at: 1.month.ago)
    fake = FakePortOneClient.new

    travel_to(Time.zone.parse("2026-11-01 06:05")) do
      Subscriptions::UpgradeService.new(user: @user, action: :renew,
                                        channel_key: @billing_channel_key, client: fake).call
    end

    assert_equal 9_900, fake.calls[:charge_billing_key].sole[:amount] # 정상가
    assert_equal 0, coupons(:amount_coupon).reload.used_count         # 소비되지 않음
    assert_nil @subscription.reload.coupon_id                         # 예약 해제
  end

  test "첫 차감 시점에 쿠폰이 무효해졌으면(만료·한도) 결제가 중단되고 정가 폴백이 없다" do
    coupons(:amount_coupon).update!(active: false)
    fake = FakePortOneClient.new

    error = assert_raises(Subscriptions::UpgradeService::UpgradeError) do
      travel_to(Time.zone.parse("2026-11-01 06:05")) do
        Subscriptions::UpgradeService.new(user: @user, action: :renew,
                                          channel_key: @billing_channel_key, client: fake).call
      end
    end

    assert_match(/결제가 중단되었습니다/, error.message)
    assert_empty fake.calls[:charge_billing_key]              # 차감 시도 없음 — 금액 불일치 방지
    assert_equal 0, coupons(:amount_coupon).reload.used_count
    assert_empty @user.orders                                 # 주문 선기록도 없음
  end

  # C-2(Q12) 회귀 — 리뷰 제안 2: 모호 실패(TIMEOUT) → 웹훅 회복(settle_renewal) 경로에서도
  # 쿠폰이 정산돼야 한다(used_count 증가·예약 해제·metadata coupon 보존·재과금 정상가).
  test "모호 실패 후 웹훅 회복도 쿠폰을 정산하고 재과금은 정상가다 (C-2 회귀)" do
    fake = FakePortOneClient.new(raise_on: { charge_billing_key:
                            PortOne::ApiError.new(status: nil, code: "TIMEOUT",
                                                  message: "응답 대기 시간 초과") })

    error = assert_raises(Subscriptions::UpgradeService::UpgradeError) do
      travel_to(Time.zone.parse("2026-11-01 06:05")) do
        Subscriptions::UpgradeService.new(user: @user, action: :renew,
                                          channel_key: @billing_channel_key, client: fake).call
      end
    end
    assert_match(/자동 결제 확인이 지연되고 있습니다/, error.message)

    order = @user.orders.sole
    assert_predicate order, :pending?                      # 모호 실패 — pending 잔존
    assert_equal 0, coupons(:amount_coupon).reload.used_count
    assert_equal coupons(:amount_coupon).id, @subscription.reload.coupon_id

    # 웹훅 Transaction.Paid 도착 — 실제로는 차감 성공이었음
    travel_to(Time.zone.parse("2026-11-01 07:00")) do
      Subscriptions::UpgradeService.new(user: @user, action: :settle_renewal, order: order,
                                        payment: { id: "payment_settle_c1", status: "PAID" },
                                        client: FakePortOneClient.new).call
    end

    assert_equal 1, coupons(:amount_coupon).reload.used_count   # 회복 경로도 1회 소비
    assert_nil @subscription.reload.coupon_id                   # 예약 해제
    order.reload
    assert_predicate order, :paid?
    assert_equal "payment_settle_c1", order.pg_payment_id
    assert_equal "SAVE2000", order.metadata["coupon"]["code"]   # P4 — 쿠폰 기록 보존
    assert_equal "PAID", order.metadata["status"]               # @payment 원문 공존

    # 다음 갱신 — 재과금은 정상가(중복 할인 없음)
    @subscription.update!(current_period_end: Time.zone.parse("2026-12-01 08:00"))
    renew_fake = FakePortOneClient.new
    travel_to(Time.zone.parse("2026-12-01 09:00")) do
      Subscriptions::UpgradeService.new(user: @user, action: :renew,
                                        channel_key: @billing_channel_key, client: renew_fake).call
    end
    assert_equal 9_900, renew_fake.calls[:charge_billing_key].sole[:amount]
    assert_equal 1, coupons(:amount_coupon).reload.used_count
  end

  # 리뷰 비고 1 후속 — settle 중 consume! 가드 실패(W-1 경합 도달) 시 트랜잭션 롤백으로 주문이
  # pending에 잔존하고, 슬롯이 비워진 뒤 웹훅 재시도로 정상 정산된다(웹훅은 PG 재전송·익일 잡
  # 재시도와 함께 회복 경로가 열려 있음).
  test "settle 중 쿠폰 한도 가드 실패 시 주문은 pending 잔존하고 재시도로 정산된다" do
    order = @user.orders.create!(product: :plus_monthly, amount: 7_900, status: :pending,
                                 pg_order_id: "order_settle_race")
    coupon = coupons(:amount_coupon)
    coupon.update!(max_redemptions: 1, used_count: 1)       # 경합으로 잔여 0인 상태 재현

    error = assert_raises(Subscriptions::UpgradeService::UpgradeError) do
      Subscriptions::UpgradeService.new(user: @user, action: :settle_renewal, order: order,
                                        payment: { id: "payment_settle_race", status: "PAID" },
                                        client: FakePortOneClient.new).call
    end
    assert_match(/한도가 소진되었습니다/, error.message)
    assert_predicate order.reload, :pending?                # 롤백 — paid 확정 없음
    assert_equal coupon.id, @subscription.reload.coupon_id  # 예약 해제도 함께 롤백 — 유지
    assert_equal 1, coupon.reload.used_count

    coupon.update!(used_count: 0)                           # 슬롯 확보 — 웹훅 재시도
    Subscriptions::UpgradeService.new(user: @user, action: :settle_renewal, order: order,
                                      payment: { id: "payment_settle_race", status: "PAID" },
                                      client: FakePortOneClient.new).call

    assert_predicate order.reload, :paid?
    assert_equal 1, coupon.reload.used_count
    assert_equal "payment_settle_race", order.pg_payment_id
    assert_equal "SAVE2000", order.metadata["coupon"]["code"]
  end

  test "percent 쿠폰도 첫 차감에 절사 할인가로 적용된다" do
    @subscription.update!(coupon_id: coupons(:active_coupon).id)
    fake = FakePortOneClient.new

    travel_to(Time.zone.parse("2026-11-01 06:05")) do
      Subscriptions::UpgradeService.new(user: @user, action: :renew,
                                        channel_key: @billing_channel_key, client: fake).call
    end

    assert_equal 7_920, fake.calls[:charge_billing_key].sole[:amount] # 9,900 × 80%
    assert_equal 7_920, @user.orders.sole.amount
    assert_equal "WELCOME2026", @user.orders.sole.metadata["coupon"]["code"]
  end

  test "percent 쿠폰의 재과금(두 번째 갱신)도 정상가로 차감된다 (불변식 3 — percent)" do
    @subscription.update!(coupon_id: coupons(:active_coupon).id)
    fake = FakePortOneClient.new

    travel_to(Time.zone.parse("2026-11-01 06:05")) do
      Subscriptions::UpgradeService.new(user: @user, action: :renew,
                                        channel_key: @billing_channel_key, client: fake).call
    end
    travel_to(Time.zone.parse("2026-12-01 06:05")) do
      Subscriptions::UpgradeService.new(user: @user, action: :renew,
                                        channel_key: @billing_channel_key, client: fake).call
    end

    amounts = fake.calls[:charge_billing_key].map { |call| call[:amount] }
    assert_equal [ 7_920, 9_900 ], amounts                   # 첫 차감만 20% 할인·재과금 정상가
    assert_equal 1, coupons(:active_coupon).reload.used_count
    assert_nil @subscription.reload.coupon_id
  end
end
