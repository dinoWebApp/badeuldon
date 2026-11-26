require "test_helper"
require_relative "../../test_helpers/portone_stubbing"
require_relative "../../test_helpers/fake_portone_client"

# 포트원 웹훅(PLAN-5) HTTP 테스트 — Transaction.* 이벤트 수신. 이벤트 값을 신뢰하지 않고
# get_payment 재조회로 무결성을 확정하는 동작(위조 이벤트 차단), 상품별 확정(수금 패스 발급·
# 갱신 주기 연장), 멱등 재시도 흡수, 미지원 type·깨진 JSON의 200 흡수를 검증한다.
# 재조회는 FakePortOneClient로 대체한다(실호출 금지).
# 시나리오 기준: _workspace/03_implementation.md §1(웹훅 이벤트)·§3.
class Webhooks::PortOneControllerTest < ActionDispatch::IntegrationTest
  include PortOneStubbing

  test "Transaction.Paid는 재조회 PAID로 수금 패스 주문을 확정하고 패스를 발급한다 (이슈 #1)" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-webhook-paid-1")
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-webhook-paid-1", amount: 4_000)
    )

    with_portone_client(fake) do
      post_event "Transaction.Paid", "order-webhook-paid-1"
    end

    assert_response :ok
    order.reload
    assert_predicate order, :paid?
    assert_equal "order-webhook-paid-1", order.pg_payment_id
    pass = users(:gamma).payment_passes.sole
    assert_equal 10, pass.remaining_uses
    # 이벤트가 아니라 재조회 응답으로 확정했다 — paymentId로 정확히 1회 조회
    assert_equal [ { payment_id: "order-webhook-paid-1", store_id: nil } ],
                 fake.calls[:get_payment]
  end

  test "Transaction.Paid 재시도는 멱등으로 흡수되고 패스가 추가 발급되지 않는다 (SEC 멱등)" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-webhook-retry-1")
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-webhook-retry-1", amount: 4_000)
    )

    with_portone_client(fake) do
      2.times { post_event "Transaction.Paid", "order-webhook-retry-1" }
    end

    assert_response :ok
    assert_equal 1, users(:gamma).payment_passes.count     # 발급 정확히 1회
    assert_predicate order.reload, :paid?
  end

  # 재리뷰 2회차 R2-1 회귀 — 검증 실패로 failed가 된 주문에 뒤늦은 Transaction.Paid가 와도
  # 범용 상태 동기화(order.update!)로 검증 없이 paid로 뒤집히면 안 된다. 포트원에서 실제 PAID인
  # 결제(소액·테스트 채널)라 재조회가 PAID를 돌려주는 상황에서도 paid 전환은 pending 주문의
  # 확정 경로(settle_paid → FulfillPassService 검증)로만 일어난다.
  test "검증 실패로 failed가 된 주문은 뒤늦은 Transaction.Paid로도 paid로 되돌려지지 않는다 (재리뷰 2회차 R2-1)" do
    order = users(:gamma).orders.create!(
      product: :collection_pass, amount: 4_000, pg_order_id: "order-webhook-bypass-1",
      status: :failed,
      metadata: { "code" => Order::VERIFICATION_FAILED_CODE,
                  "message" => Order::VERIFICATION_FAILED_MESSAGE,
                  "verification" => { "reason" => "amount_mismatch", "detail" => "paid=100 expected=4000" } }
    )
    # 재조회는 포트원 실제 상태(PAID·금액 일치)를 돌려준다 — 그래도 상태 동기화가 paid로 바꾸지 않는다
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-webhook-bypass-1", amount: 4_000)
    )

    updated_at_before = order.reload.updated_at
    with_portone_client(fake) do
      post_event "Transaction.Paid", "order-webhook-bypass-1"
    end

    assert_response :ok
    order.reload
    assert_predicate order, :failed?                       # paid로 되돌려지지 않는다
    assert_nil order.paid_at                               # 확정(발급) 없음 — paid_at 미기록
    assert_equal Order::VERIFICATION_FAILED_CODE, order.metadata["code"]  # 검증 실패 기록 보존
    assert_empty users(:gamma).payment_passes              # 수금 패스 발급 없음
    assert_equal updated_at_before, order.updated_at, "범용 상태 동기화(update!)가 실행되지 않는다"
  end

  test "재조회 응답이 타 결제면 위조 이벤트로 무변경 흡수한다" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-webhook-forged-1")
    fake = FakePortOneClient.new(get_payment: { id: "payment-of-other-order", status: "PAID" })

    with_portone_client(fake) do
      post_event "Transaction.Paid", "order-webhook-forged-1"
    end

    assert_response :ok
    assert_predicate order.reload, :pending?               # 이벤트 값으로 확정하지 않는다
    assert_empty users(:gamma).payment_passes
  end

  test "Transaction.Paid는 pending Plus 갱신 주문을 settle_renewal로 확정하고 주기를 연장한다 (이슈 #4)" do
    users(:gamma).create_subscription!(plan: :plus, status: :active,
                                       pg_billing_key: "tok_billing_1",
                                       current_period_end: Time.zone.parse("2026-10-31 23:59:59"))
    order = users(:gamma).orders.create!(product: :plus_monthly, amount: 9_900,
                                         pg_order_id: "order-webhook-renew-1",
                                         metadata: { "ambiguous" => true })
    fake = FakePortOneClient.new(get_payment: { id: "order-webhook-renew-1", status: "PAID" })

    travel_to(Time.zone.parse("2026-11-02 09:00")) do
      with_portone_client(fake) do
        post_event "Transaction.Paid", "order-webhook-renew-1"
      end
    end

    assert_response :ok
    order.reload
    assert_predicate order, :paid?
    assert_equal "order-webhook-renew-1", order.pg_payment_id
    subscription = users(:gamma).subscription.reload
    assert_predicate subscription, :active?                # 웹훅 확정 — 만료 아님
    assert_equal Time.zone.parse("2026-10-31 23:59:59"), subscription.current_period_start
    assert_equal Time.zone.parse("2026-11-30 23:59:59"), subscription.current_period_end
  end

  test "Transaction.Cancelled는 paid 주문을 cancelled로 동기화한다 (콘솔 환불)" do
    fake = FakePortOneClient.new(get_payment: { id: orders(:delta_pass_order).pg_order_id,
                                                status: "CANCELLED" })

    with_portone_client(fake) do
      post_event "Transaction.Cancelled", orders(:delta_pass_order).pg_order_id
    end

    assert_response :ok
    assert_predicate orders(:delta_pass_order).reload, :cancelled?
  end

  test "Transaction.Failed는 pending 주문을 failed로 동기화한다" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-webhook-failed-1")
    fake = FakePortOneClient.new(get_payment: { id: "order-webhook-failed-1", status: "FAILED" })

    with_portone_client(fake) do
      post_event "Transaction.Failed", "order-webhook-failed-1"
    end

    assert_response :ok
    assert_predicate order.reload, :failed?
    assert_empty users(:gamma).payment_passes
  end

  test "Transaction.PartialCancelled도 cancelled로 동기화한다" do
    fake = FakePortOneClient.new(get_payment: { id: orders(:delta_pass_order).pg_order_id,
                                                status: "PARTIAL_CANCELLED" })

    with_portone_client(fake) do
      post_event "Transaction.PartialCancelled", orders(:delta_pass_order).pg_order_id
    end

    assert_response :ok
    assert_predicate orders(:delta_pass_order).reload, :cancelled?
  end

  # ── PLAN-9 환불 실행과의 정합(03_implementation §4 — 웹훅 무변경 판단 근거) ──

  test "환불 실행 뒤 Transaction.Cancelled 후행 도착은 무변경으로 흡수된다 (PLAN-9 멱등)" do
    order = orders(:delta_pass_order)
    refund_fake = FakePortOneClient.new(get_payment: { id: order.pg_order_id, status: "CANCELLED",
                                                       amount: { paid: order.amount,
                                                                 cancelled: order.amount } })
    with_portone_client(refund_fake) do
      result = Orders::RefundService.new(admin: admins(:ops), order: order,
                                         reason: "이중 결제 정정").call
      assert result.success?, "전제: 환불 실행이 성공해야 한다"
    end
    refunded_at = order.reload.refunded_at
    assert_equal 1, AuditLog.where(action: "order_refund", target_type: "Order",
                                   target_id: order.id).count

    hook_fake = FakePortOneClient.new(get_payment: { id: order.pg_order_id, status: "CANCELLED" })
    with_portone_client(hook_fake) do
      post_event "Transaction.Cancelled", order.pg_order_id
    end

    assert_response :ok
    order.reload
    assert_equal refunded_at, order.refunded_at, "정산 기록은 보존된다"
    assert_predicate order, :cancelled?
    assert_equal 1, AuditLog.where(action: "order_refund", target_type: "Order",
                                   target_id: order.id).count, "감사·정산 중복 없음(멱등)"
  end

  test "웹훅이 먼저 status만 cancelled로 만든 주문은 실행으로 정산 1회가 된다 (PLAN-9 선행 도착)" do
    order = orders(:delta_pass_order)
    hook_fake = FakePortOneClient.new(get_payment: { id: order.pg_order_id, status: "CANCELLED" })
    with_portone_client(hook_fake) do
      post_event "Transaction.Cancelled", order.pg_order_id
    end
    assert_predicate order.reload, :cancelled?
    assert_nil order.refunded_at, "웹훅은 상태만 동기화 — 정산 기록 없음"

    refund_fake = FakePortOneClient.new(get_payment: { id: order.pg_order_id, status: "CANCELLED",
                                                       amount: { paid: order.amount,
                                                                 cancelled: order.amount } })
    with_portone_client(refund_fake) do
      result = Orders::RefundService.new(admin: admins(:ops), order: order,
                                         reason: "콘솔 선취소 정산").call
      assert result.success?
    end

    order.reload
    assert order.refunded_at.present?
    assert_equal 1, AuditLog.where(action: "order_refund", target_type: "Order",
                                   target_id: order.id).count, "정산 정확히 1회"
  end

  test "미지원 type(BillingKey.*)는 포트원 호출 없이 200으로 흡수된다" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-webhook-billingkey-1")
    fake = FakePortOneClient.new

    with_portone_client(fake) do
      post_event "BillingKey.Issued", "order-webhook-billingkey-1"
    end

    assert_response :ok
    assert_empty fake.calls.values.flatten                 # 재조회 없음 — 동기화 대상 아님
    assert_predicate order.reload, :pending?
  end

  test "paymentId가 없는 이벤트는 재조회 없이 200으로 흡수된다" do
    fake = FakePortOneClient.new

    with_portone_client(fake) do
      post "/webhooks/portone", params: { type: "Transaction.Paid", data: {} }.to_json,
           headers: { "Content-Type" => "application/json" }
    end

    assert_response :ok
    assert_empty fake.calls.values.flatten
  end

  test "알 수 없는 결제의 이벤트는 200으로 흡수된다" do
    fake = FakePortOneClient.new

    with_portone_client(fake) do
      post_event "Transaction.Paid", "order-unknown-payment"
    end

    assert_response :ok                                    # 재시도해도 같은 결과 — 흡수
    assert_empty fake.calls.values.flatten                 # 주문 탐색 실패 — 재조회 없음
  end

  test "깨진 JSON 본문도 200으로 흡수된다 (재시도 유발 금지)" do
    fake = FakePortOneClient.new

    with_portone_client(fake) do
      post "/webhooks/portone", params: "{broken-json", headers: { "Content-Type" => "application/json" }
    end

    assert_response :ok
    assert_empty fake.calls.values.flatten
  end


  # ── PLAN-5 결제 확정 검증 — 웹훅 경로(재리뷰 R-1·R-2·Tester §7-6) ──
  # 웹훅도 같은 확정점(FulfillPassService 검증)을 지나므로 금액·채널·통화가 주문과 다른
  # 재조회 결제는 확정하지 않는다. 응답은 200(포트원 규격 — 재시도해도 같은 거절로 흡수).

  test "재조회 결제 금액이 주문과 다르면 웹훅은 확정하지 않고 주문을 failed로 기록한다 (PLAN-5·R-1)" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-webhook-amount-1")
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-webhook-amount-1", amount: 100)
    )

    with_portone_client(fake) do
      post_event "Transaction.Paid", "order-webhook-amount-1"
    end

    assert_response :ok                                        # 재시도 유발 금지 — 흡수
    order.reload
    assert_predicate order, :failed?
    assert_predicate order, :verification_failed?
    assert_nil order.paid_at
    assert_equal "amount_mismatch", order.metadata.dig("verification", "reason")
    assert_equal order.pg_order_id, order.pg_payment_id        # 웹훅 경로도 결제 ID 스냅샷(R2-5)
    assert_empty users(:gamma).payment_passes
    assert_equal [ { payment_id: "order-webhook-amount-1", store_id: nil } ],
                 fake.calls[:get_payment]                      # 이벤트 값이 아니라 재조회로 확정
  end

  test "재조회 결제 채널이 LIVE면 웹훅도 channel_mismatch로 거절한다 (PLAN-5·R-2)" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-webhook-channel-1")
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-webhook-channel-1", amount: 4_000,
                                                  live: true)
    )

    with_portone_client(fake) do
      post_event "Transaction.Paid", "order-webhook-channel-1"
    end

    assert_response :ok
    order.reload
    assert_predicate order, :failed?
    assert_equal "channel_mismatch", order.metadata.dig("verification", "reason")
    assert_empty users(:gamma).payment_passes
  end

  test "재조회 결제 통화가 USD면 웹훅도 currency_mismatch로 거절한다 (R2-4)" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-webhook-currency-1")
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-webhook-currency-1", amount: 4_000,
                                                  currency: "USD")
    )

    with_portone_client(fake) do
      post_event "Transaction.Paid", "order-webhook-currency-1"
    end

    assert_response :ok
    order.reload
    assert_predicate order, :failed?
    assert_equal "currency_mismatch", order.metadata.dig("verification", "reason")
    assert_empty users(:gamma).payment_passes
  end

  test "검증 실패 주문에 같은 Paid 이벤트가 다시 와도 무변경 흡수된다 (멱등 — R2-5 재기록 없음)" do
    order = users(:gamma).orders.create!(product: :collection_pass, amount: 4_000,
                                         pg_order_id: "order-webhook-repeat-1")
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-webhook-repeat-1", amount: 100)
    )

    with_portone_client(fake) do
      post_event "Transaction.Paid", "order-webhook-repeat-1"   # 첫 이벤트 — 검증 실패 → failed 기록
    end

    assert_response :ok
    first_metadata = order.reload.metadata
    assert_predicate order, :failed?

    # 두 번째 이벤트 — 재조회는 또 실패지만 mark_verification_failed!가 이미 failed인 주문을
    # 건드리지 않는다(멱등) — metadata가 중복 누적·덮어쓰이지 않는다
    with_portone_client(fake) do
      post_event "Transaction.Paid", "order-webhook-repeat-1"
    end

    assert_response :ok
    order.reload
    assert_predicate order, :failed?
    assert_equal first_metadata, order.metadata, "재기록은 무변경 — metadata 누적 없다"
    assert_empty users(:gamma).payment_passes
  end

  test "일반 PG 거절로 failed가 된 주문도 뒤늦은 Transaction.Paid로 paid로 되돌려지지 않는다 (R2-1 — failed 전체 가드)" do
    order = users(:gamma).orders.create!(
      product: :collection_pass, amount: 4_000, pg_order_id: "order-webhook-pgfailed-1",
      status: :failed,
      metadata: { "code" => "PG_PROVIDER_ERROR", "message" => "카드 한도 초과",
                  "pg_code" => "F1001", "pg_message" => "한도초과" }
    )
    # 재조회는 포트원 실제 상태(PAID·금액 일치)를 돌려준다 — 그래도 상태 동기화는 paid로 바꾸지 않는다
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-webhook-pgfailed-1", amount: 4_000)
    )

    updated_at_before = order.reload.updated_at
    with_portone_client(fake) do
      post_event "Transaction.Paid", "order-webhook-pgfailed-1"
    end

    assert_response :ok
    order.reload
    assert_predicate order, :failed?
    assert_nil order.paid_at
    assert_equal "PG_PROVIDER_ERROR", order.metadata["code"]   # 원래 실패 사유 보존
    assert_nil order.metadata["verification"]                  # 검증 실패 기록으로 오인되지 않는다
    assert_empty users(:gamma).payment_passes
    assert_equal updated_at_before, order.updated_at, "범용 상태 동기화(update!)가 실행되지 않는다"
  end

  private

  def post_event(type, payment_id)
    post "/webhooks/portone",
         params: { type: type, data: { paymentId: payment_id } }.to_json,
         headers: { "Content-Type" => "application/json" }
  end
end
