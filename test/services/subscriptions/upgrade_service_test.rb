require "test_helper"
require_relative "../../test_helpers/fake_portone_client"

# 구독 플로우(F-PLAN — PLAN-2/5) — UpgradeService 단일 진입점(#call + action 디스패치).
# 포트원 API는 FakePortOneClient 주입으로 대체한다(실호출 금지). 체험→활성→해지→만료·갱신의
# 상태 전이는 구현 보고 §3 플로우 기준. 빌링키 발급·차감은 정기결제 채널(channel_key_billing)
# 라우팅과 결제 ID(paymentId = pg_order_id) 전달을 함께 검증한다. 시간은 travel_to로 KST 고정(TIME-1).
class Subscriptions::UpgradeServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:gamma)
    @billing_channel_key = "test-channel-billing" # 주입값 — 로컬 credentials 유무와 무관하게 밀봉
  end

  # ── start_trial (체험 시작 — PLAN-2) ──

  test "Free 사용자의 체험 시작은 Plus 체험 중 전환과 14일 종료일을 기록한다 (PLAN-2)" do
    @user.create_subscription!(plan: :free)
    fake = FakePortOneClient.new

    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      Subscriptions::UpgradeService.new(user: @user, action: :start_trial, client: fake).call

      subscription = @user.subscription.reload
      assert_predicate subscription, :plus?
      assert_predicate subscription, :trialing?
      assert_equal Time.zone.parse("2026-10-29 09:00"), subscription.trial_ends_at
    end
    assert_empty fake.calls.values.flatten  # 체험 시작은 포트원 호출이 없다
  end

  test "구독 행이 없는 레거시 사용자도 체험 시작이 가능하다 (즉석 Free 생성)" do
    assert_nil @user.subscription  # fixture 사용자 — 구독 행 없음(폴백 대상)

    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      Subscriptions::UpgradeService.new(user: @user, action: :start_trial,
                                        client: FakePortOneClient.new).call

      assert_predicate @user.subscription.reload, :trialing?
    end
  end

  test "Plus 이용 중 사용자의 체험 시작은 거부되고 상태가 유지된다 (이중 체험 차단)" do
    @user.create_subscription!(plan: :plus, status: :active, pg_billing_key: "tok_billing_1")

    error = assert_raises(Subscriptions::UpgradeService::UpgradeError) do
      Subscriptions::UpgradeService.new(user: @user, action: :start_trial,
                                        client: FakePortOneClient.new).call
    end

    assert_match(/이미 Plus/, error.message)
    assert_predicate @user.subscription.reload, :active?   # 전이 없음
  end

  test "체험 이력이 있는 사용자의 재체험 시작은 1회 가드로 거부된다 (PLAN-2 — 이슈 #2)" do
    @user.create_subscription!(plan: :free, status: :expired, used_trial: true)

    error = assert_raises(Subscriptions::UpgradeService::UpgradeError) do
      Subscriptions::UpgradeService.new(user: @user, action: :start_trial,
                                        client: FakePortOneClient.new).call
    end

    assert_match(/무료 체험은 계정당 1회만/, error.message)
    assert_predicate @user.subscription.reload, :expired?  # 전이 없음
  end

  # ── register_card (카드 등록·빌링키 발급 — PLAN-5) ──

  test "카드 등록은 발급 토큰으로 빌링키를 교환해 저장하고 Plus 이용 중으로 전환한다" do
    @user.create_subscription!(plan: :free)
    fake = FakePortOneClient.new(issue_billing_key: { billingKey: "tok_billing_issued" })

    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      Subscriptions::UpgradeService.new(user: @user, action: :register_card,
                                        issue_token: "issue_card_1", channel_key: @billing_channel_key, client: fake).call

      subscription = @user.subscription.reload
      assert_predicate subscription, :plus?
      assert_predicate subscription, :active?             # 체험 경유가 아니다 — 즉시 이용 중
      assert_equal "tok_billing_issued", subscription.pg_billing_key
      assert_equal Time.zone.parse("2026-11-15 09:00"), subscription.current_period_end
      assert_empty @user.orders                           # 카드 등록은 주문을 만들지 않는다
    end
    # 발급 요청 — 정기결제 채널·구독의 포트원 고객 키(customer.id)로 라우팅된다
    assert_equal [ { issue_token: "issue_card_1", channel_key: @billing_channel_key,
                     customer_id: @user.subscription.pg_customer_key, store_id: nil } ],
                 fake.calls[:issue_billing_key]
  end

  test "발급 토큰 없는 카드 등록은 거부되고 포트원을 호출하지 않는다" do
    @user.create_subscription!(plan: :free)
    fake = FakePortOneClient.new

    error = assert_raises(Subscriptions::UpgradeService::UpgradeError) do
      Subscriptions::UpgradeService.new(user: @user, action: :register_card, issue_token: "",
                                        client: fake).call
    end

    assert_match(/발급 토큰/, error.message)
    assert_empty fake.calls.values.flatten
    assert_predicate @user.subscription.reload, :active?   # free/active 유지
  end

  test "빌링키 발급 실패 시 거부되고 구독이 유지된다 (포트원 ApiError 전파)" do
    @user.create_subscription!(plan: :free)
    fake = FakePortOneClient.new(raise_on: { issue_billing_key:
                            PortOne::ApiError.new(status: 400, code: "PG_PROVIDER_ERROR",
                                                  message: "유효하지 않은 카드입니다") })

    error = assert_raises(Subscriptions::UpgradeService::UpgradeError) do
      Subscriptions::UpgradeService.new(user: @user, action: :register_card,
                                        issue_token: "issue_bad", channel_key: @billing_channel_key, client: fake).call
    end

    assert_match(/카드 등록에 실패했습니다/, error.message)
    assert_match(/유효하지 않은 카드입니다/, error.message)
    subscription = @user.subscription.reload
    assert_predicate subscription, :free?                  # 플랜 전환 없음
    assert_nil subscription.pg_billing_key
  end

  # ── cancel (해지 — PLAN-5) ──

  test "이용 중 Plus의 해지는 취소 상태로 바꾸고 기간 말까지 Plus를 유지한다" do
    @user.create_subscription!(plan: :plus, status: :active, pg_billing_key: "tok_billing_1",
                               current_period_start: Time.zone.parse("2026-10-01 00:00"),
                               current_period_end: Time.zone.parse("2026-10-31 23:59:59"))

    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      Subscriptions::UpgradeService.new(user: @user, action: :cancel,
                                        client: FakePortOneClient.new).call

      subscription = @user.subscription.reload
      assert_predicate subscription, :cancelled?
      assert_predicate subscription, :plus?                      # 기간 유지
      assert_equal Time.zone.parse("2026-10-31 23:59:59"), subscription.current_period_end
    end
  end

  test "Plus가 아닌 구독의 해지는 거부된다 (Free 해지는 넌센스 상태 방지 — 이슈 #6)" do
    @user.create_subscription!(plan: :free)   # free/active

    error = assert_raises(Subscriptions::UpgradeService::UpgradeError) do
      Subscriptions::UpgradeService.new(user: @user, action: :cancel,
                                        client: FakePortOneClient.new).call
    end

    assert_match(/해지할 이용 중인 Plus/, error.message)
    subscription = @user.subscription.reload
    assert_predicate subscription, :active?
    assert_predicate subscription, :free?
  end

  test "체험 중 구독도 해지할 수 있다 (Plus 이용 중 포함 — 이슈 #6)" do
    @user.create_subscription!(plan: :plus, status: :trialing, trial_ends_at: 10.days.from_now)

    Subscriptions::UpgradeService.new(user: @user, action: :cancel,
                                      client: FakePortOneClient.new).call

    assert_predicate @user.subscription.reload, :cancelled?
    assert_predicate @user.subscription, :plus?
  end

  # ── expire (체험 종료 강등 — 멱등) ──

  test "체험 종료 강등은 Free로 복귀시키고 카드 정보를 폐기한다" do
    @user.create_subscription!(plan: :plus, status: :trialing, trial_ends_at: 1.day.ago,
                               pg_billing_key: "tok_billing_1")

    travel_to(Time.zone.parse("2026-10-15 06:00")) do
      Subscriptions::UpgradeService.new(user: @user, action: :expire,
                                        client: FakePortOneClient.new).call

      subscription = @user.subscription.reload
      assert_predicate subscription, :free?
      assert_predicate subscription, :expired?
      assert_nil subscription.pg_billing_key
    end
  end

  test "이미 만료된 구독의 강등은 무변경으로 흡수된다 (잡 재실행 멱등)" do
    @user.create_subscription!(plan: :free, status: :expired)

    result = Subscriptions::UpgradeService.new(user: @user, action: :expire,
                                               client: FakePortOneClient.new).call

    assert_equal @user.subscription.reload, result
    assert_predicate @user.subscription, :expired?
  end

  # ── renew (자동 갱신 — 잡 전용) ──

  test "갱신은 빌링키 차감 후 주문(paid)을 남기고 주기를 1개월 연장한다 (PLAN-2·PLAN-5)" do
    @user.create_subscription!(plan: :plus, status: :active, pg_billing_key: "tok_billing_1",
                               pg_customer_key: "cust_1",
                               current_period_start: Time.zone.parse("2026-10-01 00:00"),
                               current_period_end: Time.zone.parse("2026-10-31 23:59:59"))
    fake = FakePortOneClient.new(
      charge_billing_key: { payment: { id: "payment_renew_1", status: "PAID" } }
    )

    travel_to(Time.zone.parse("2026-11-01 06:05")) do
      Subscriptions::UpgradeService.new(user: @user, action: :renew, channel_key: @billing_channel_key, client: fake).call

      order = @user.orders.sole
      assert_predicate order, :paid?
      assert_predicate order, :plus_monthly?
      assert_equal 9_900, order.amount
      assert_not_nil order.paid_at
      assert_equal({ "payment" => { "id" => "payment_renew_1", "status" => "PAID" } },
                   order.metadata)

      subscription = @user.subscription.reload
      assert_predicate subscription, :active?                # 갱신 — 만료 아님
      # 주기 연장은 이전 주기 종료일을 시작으로 한다
      assert_equal Time.zone.parse("2026-10-31 23:59:59"), subscription.current_period_start
      assert_equal Time.zone.parse("2026-11-30 23:59:59"), subscription.current_period_end
    end
    charge = fake.calls[:charge_billing_key].sole
    assert_equal 9_900, charge[:amount]                      # 서버 원값 차감
    assert_equal "tok_billing_1", charge[:billing_key]
    assert_equal "받을돈 Plus 월 구독", charge[:order_name]
    assert_equal @billing_channel_key, charge[:channel_key]  # 정기결제 채널
    assert_equal @user.orders.sole.pg_order_id, charge[:payment_id]  # 결제 ID = 주문번호
    assert_equal @user.orders.sole.pg_order_id, @user.orders.sole.pg_payment_id
  end

  test "명확한 차감 실패는 실패 주문 기록과 즉시 만료를 한 번에 수행한다 (dunning 없음)" do
    @user.create_subscription!(plan: :plus, status: :active, pg_billing_key: "tok_billing_1",
                               current_period_end: Time.zone.parse("2026-10-31 23:59:59"))
    fake = FakePortOneClient.new(raise_on: { charge_billing_key:
                            PortOne::ApiError.new(status: 400, code: "PG_PROVIDER_ERROR",
                                                  message: "PG사 승인이 거절되었습니다",
                                                  pg_code: "F1001", pg_message: "한도초과") })

    error = assert_raises(Subscriptions::UpgradeService::UpgradeError) do
      travel_to(Time.zone.parse("2026-11-01 06:05")) do
        Subscriptions::UpgradeService.new(user: @user, action: :renew, channel_key: @billing_channel_key, client: fake).call
      end
    end

    assert_match(/자동 결제에 실패했습니다/, error.message)
    order = @user.orders.sole
    assert_predicate order, :failed?
    assert_equal({ "code" => "PG_PROVIDER_ERROR", "message" => "PG사 승인이 거절되었습니다",
                   "pg_code" => "F1001", "pg_message" => "한도초과" }, order.metadata)
    subscription = @user.subscription.reload
    assert_predicate subscription, :free?                    # 즉시 강등
    assert_predicate subscription, :expired?
    assert_nil subscription.pg_billing_key
  end

  test "모호한 차감 실패(타임아웃)는 구독을 유지하고 pending 주문으로 회복을 연다 (이슈 #4)" do
    @user.create_subscription!(plan: :plus, status: :active, pg_billing_key: "tok_billing_1",
                               current_period_end: Time.zone.parse("2026-10-31 23:59:59"))
    fake = FakePortOneClient.new(raise_on: { charge_billing_key:
                            PortOne::ApiError.new(status: nil, code: "TIMEOUT",
                                                  message: "응답 시간 초과") })

    error = assert_raises(Subscriptions::UpgradeService::UpgradeError) do
      travel_to(Time.zone.parse("2026-11-01 06:05")) do
        Subscriptions::UpgradeService.new(user: @user, action: :renew, channel_key: @billing_channel_key, client: fake).call
      end
    end

    assert_match(/자동 결제 확인이 지연되고 있습니다/, error.message)
    order = @user.orders.sole
    assert_predicate order, :pending?                        # 실패 확정 금지 — 실제 성공일 수 있음
    assert_predicate order.metadata["ambiguous"], :present?  # 모호 실패 이력
    subscription = @user.subscription.reload
    assert_predicate subscription, :active?                  # 구독 유지
    assert_equal Time.zone.parse("2026-10-31 23:59:59"), subscription.current_period_end
  end

  test "잔존 pending 갱신 주문은 같은 결제 ID로 재사용된다 (포트원 중복 차감 거부 의존 — 이슈 #4)" do
    @user.create_subscription!(plan: :plus, status: :active, pg_billing_key: "tok_billing_1",
                               current_period_end: Time.zone.parse("2026-10-31 23:59:59"))
    leftover = @user.orders.create!(product: :plus_monthly, amount: 9_900,
                                    pg_order_id: "order-renew-leftover-1")
    fake = FakePortOneClient.new(
      charge_billing_key: { payment: { id: "order-renew-leftover-1", status: "PAID" } }
    )

    travel_to(Time.zone.parse("2026-11-01 06:05")) do
      Subscriptions::UpgradeService.new(user: @user, action: :renew, channel_key: @billing_channel_key, client: fake).call

      assert_equal 1, @user.orders.count                     # 새 주문 누적 없음
      assert_predicate leftover.reload, :paid?
      assert_equal "order-renew-leftover-1", leftover.pg_payment_id
    end
    assert_equal "order-renew-leftover-1", fake.calls[:charge_billing_key].sole[:payment_id]
  end

  test "주기가 남은 이용 중 구독의 갱신은 차감도 주문도 만들지 않는다 (멱등)" do
    @user.create_subscription!(plan: :plus, status: :active, pg_billing_key: "tok_billing_1",
                               current_period_end: 10.days.from_now)
    fake = FakePortOneClient.new

    Subscriptions::UpgradeService.new(user: @user, action: :renew, channel_key: @billing_channel_key, client: fake).call

    assert_empty fake.calls[:charge_billing_key]
    assert_empty @user.orders
    assert_predicate @user.subscription.reload, :active?
  end

  test "웹훅 회복은 pending 갱신 주문을 paid로 확정하고 주기를 연장한다 (settle_renewal — 이슈 #4)" do
    subscription = @user.create_subscription!(plan: :plus, status: :active,
                                              pg_billing_key: "tok_billing_1",
                                              current_period_end: Time.zone.parse("2026-10-31 23:59:59"))
    order = @user.orders.create!(product: :plus_monthly, amount: 9_900,
                                 pg_order_id: "order-renew-pending-1",
                                 metadata: { "ambiguous" => true })
    fake = FakePortOneClient.new

    travel_to(Time.zone.parse("2026-11-02 09:00")) do
      result = Subscriptions::UpgradeService.new(
        user: @user, action: :settle_renewal, order: order,
        payment: { id: "payment_settle_1", status: "PAID" }, client: fake
      ).call

      assert_equal order.reload, result
      assert_predicate order, :paid?
      assert_equal "payment_settle_1", order.pg_payment_id
      subscription.reload
      assert_equal Time.zone.parse("2026-10-31 23:59:59"), subscription.current_period_start
      assert_equal Time.zone.parse("2026-11-30 23:59:59"), subscription.current_period_end
    end
  end

  test "웹훅 회복은 Plus 갱신 주문이 아니면 거부된다 (settle_renewal 가드)" do
    pass_order = @user.orders.create!(product: :collection_pass, amount: 4_000,
                                      pg_order_id: "order-pass-not-renewal-1")

    error = assert_raises(Subscriptions::UpgradeService::UpgradeError) do
      Subscriptions::UpgradeService.new(user: @user, action: :settle_renewal, order: pass_order,
                                        payment: { id: "payment_x", status: "PAID" },
                                        client: FakePortOneClient.new).call
    end

    assert_match(/Plus 갱신 주문이 아닙니다/, error.message)
    assert_predicate pass_order.reload, :pending?
  end

  test "갱신 대상이 아니면(해지·카드 부재) 차감 없이 만료 강등한다" do
    @user.create_subscription!(plan: :plus, status: :cancelled, pg_billing_key: "tok_billing_1",
                               current_period_end: 1.day.ago)
    fake = FakePortOneClient.new

    Subscriptions::UpgradeService.new(user: @user, action: :renew, channel_key: @billing_channel_key, client: fake).call

    assert_empty fake.calls[:charge_billing_key]             # 차감 시도 없음
    assert_predicate @user.subscription.reload, :expired?
    assert_predicate @user.subscription, :free?
  end

  test "이용 중이어도 빌링키가 없으면 갱신 없이 만료 강등한다" do
    @user.create_subscription!(plan: :plus, status: :active,   # 카드 정보 없음
                               current_period_end: 1.day.ago)
    fake = FakePortOneClient.new

    Subscriptions::UpgradeService.new(user: @user, action: :renew, channel_key: @billing_channel_key, client: fake).call

    assert_empty fake.calls[:charge_billing_key]
    assert_predicate @user.subscription.reload, :expired?
  end

  test "알 수 없는 처리는 거부된다 (진입점 가드)" do
    error = assert_raises(Subscriptions::UpgradeService::UpgradeError) do
      Subscriptions::UpgradeService.new(user: @user, action: :teleport,
                                        client: FakePortOneClient.new).call
    end

    assert_match(/알 수 없는 구독 처리/, error.message)
  end
end
