require "test_helper"

# 주문(F-PLAN — PLAN-2/4/5) 모델 — 상품 정가 단일 지점·기본 상태(pending)·금액·주문번호 검증.
# 시나리오 기준: PRD §6.10 PLAN-2·PLAN-4, _workspace/03_implementation.md §2. 외부 API 호출 없음.
class OrderTest < ActiveSupport::TestCase
  test "정가는 상품별 단일 지점에서만 산정된다 (PLAN-2 Plus 9,900원·PLAN-4 패스 4,000원)" do
    assert_equal 9_900, Order.amount_for(:plus_monthly)
    assert_equal 4_000, Order.amount_for(:collection_pass)
  end

  test "신규 주문은 결제 대기(pending) 상태로 시작한다" do
    order = Order.new(user: users(:delta), product: :collection_pass,
                      amount: 4_000, pg_order_id: "order-new-1")

    assert_predicate order, :pending?
  end

  test "금액은 0 이하·비정수를 거부하고 주문번호는 필수다" do
    base = { user: users(:delta), product: :collection_pass, pg_order_id: "order-new-2" }

    assert_not_predicate Order.new(**base, amount: 0), :valid?
    assert_not_predicate Order.new(**base, amount: -1), :valid?
    assert_not_predicate Order.new(**base, amount: 100.5), :valid?
    assert_not_predicate Order.new(user: users(:delta), product: :collection_pass,
                                   amount: 4_000), :valid?  # pg_order_id 누락
  end

  test "주문번호는 중복될 수 없다 (포트원 paymentId 고유)" do
    attrs = { user: users(:delta), product: :collection_pass, amount: 4_000,
              pg_order_id: "order-delta-pass-0001" }  # orders.yml fixture와 동일 값

    duplicate = Order.new(**attrs)
    assert_not_predicate duplicate, :valid?
    assert_predicate duplicate.errors[:pg_order_id], :any?
  end

  test "pg_* 결제 컬럼(pg_order_id·pg_payment_id·pg_billing_key)은 값을 유지한다 (rename 데이터 보존)" do
    # fixture — rename 전 값이 그대로 조회된다(orders.yml delta_pass_order 고정값)
    fixture_order = orders(:delta_pass_order)
    assert_equal "order-delta-pass-0001", fixture_order.pg_order_id
    assert_equal "pay-delta-pass-0001", fixture_order.pg_payment_id

    # 쓰기→재적재 — 세 컬럼 모두 라운드트립 보존(차감 주문이 세 값을 함께 남기는 형태)
    order = users(:delta).orders.create!(product: :plus_monthly, amount: 9_900,
                                         pg_order_id: "order-rename-rt-1")
    order.update!(status: :paid, pg_payment_id: "order-rename-rt-1",
                  pg_billing_key: "bk_rename_rt_1")

    reloaded = Order.find(order.id)
    assert_equal "order-rename-rt-1", reloaded.pg_order_id
    assert_equal "order-rename-rt-1", reloaded.pg_payment_id
    assert_equal "bk_rename_rt_1", reloaded.pg_billing_key
  end

  # ── ADMIN-4(Run B) — 환불 기록·목록 필터 스코프 ──

  test "mark_refunded!는 refunded_at과 사유를 기록하고 true를 반환한다 (ADMIN-4)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      order = orders(:delta_pass_order)

      assert order.mark_refunded!("이중 결제 정정")
      order.reload
      assert order.refunded?
      assert_not_nil order.refunded_at
      assert_equal "이중 결제 정정", order.refund_reason
      # 상태 enum은 paid 이력을 보존한다 — refunded는 refunded_at 판정(모델 주석 계약)
      assert_predicate order, :paid?
    end
  end

  test "mark_refunded!는 blank 사유를 ArgumentError로 거부한다 (ADMIN-4·W-1 경계)" do
    order = orders(:delta_pass_order)

    error = assert_raises(ArgumentError) { order.mark_refunded!("") }
    assert_equal "환불 사유는 필수입니다", error.message
    assert_raises(ArgumentError) { order.mark_refunded!(nil) }
    order.reload
    assert_not order.refunded?, "거부 시 데이터가 오염되지 않는다"
  end

  test "mark_refunded!는 이미 환불 기록된 건에 false를 반환한다 (이중 기록 차단)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      order = orders(:delta_pass_order)
      order.mark_refunded!("첫 기록")
      first_refunded_at = order.reload.refunded_at

      assert_not order.mark_refunded!("두 번째 시도"), "재요청은 false — 컨트롤러 422 경로"
      assert_equal first_refunded_at, order.reload.refunded_at, "최초 기록 시각이 유지된다"
      assert_equal "첫 기록", order.refund_reason, "사유가 덮어써지지 않는다"
    end
  end

  test "환불 스코프는 refunded_at 기준으로 paid/failed 이력을 모두 포괄한다 (ADMIN-4 필터)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      order = orders(:delta_pass_order)
      order.mark_refunded!("첫 기록")
      refunded_failed = users(:delta).orders.create!(product: :collection_pass, amount: 4_000,
                                                     pg_order_id: "order-scope-failed",
                                                     status: :failed)
      refunded_failed.mark_refunded!("결제 실패 후 환불 완료")

      assert_includes Order.refunded, order.reload
      assert_includes Order.refunded, refunded_failed
      assert_not_includes Order.not_refunded, order
      assert_includes Order.not_refunded, users(:delta).orders.create!(
        product: :collection_pass, amount: 4_000, pg_order_id: "order-scope-paid", status: :paid
      )
      assert_includes Order.paid, order
      assert_includes Order.failed, refunded_failed
    end
  end

  # ── PLAN-5 결제 확정 검증 실패 기록(재리뷰 R2-5 — 단일 구현 계약) ──

  test "mark_verification_failed!는 pending 주문을 failed로 바꾸고 결제 ID·검증 사유를 남긴다 (PLAN-5)" do
    travel_to(Time.zone.parse("2026-11-25 10:00")) do
      order = users(:delta).orders.create!(product: :collection_pass, amount: 4_000,
                                           pg_order_id: "order-verify-failed-1")

      assert order.mark_verification_failed!(reason: "amount_mismatch",
                                             detail: "paid=100 expected=4000"),
             "적용되면 true를 반환한다"

      order.reload
      assert_predicate order, :failed?
      assert_predicate order, :verification_failed?
      assert_nil order.paid_at
      assert_equal "order-verify-failed-1", order.pg_payment_id       # 결제 ID 스냅샷
      assert_equal Order::VERIFICATION_FAILED_CODE, order.metadata["code"]
      assert_equal Order::VERIFICATION_FAILED_MESSAGE, order.metadata["message"]
      assert_equal({ "reason" => "amount_mismatch", "detail" => "paid=100 expected=4000" },
                   order.metadata["verification"])
    end
  end

  test "mark_verification_failed!는 기존 metadata(invoice_id)를 보존하고 병합한다 (B-1 선례)" do
    order = users(:delta).orders.create!(product: :collection_pass, item_type: :legal_doc,
                                         amount: Order::LEGAL_DOC_PRICE,
                                         pg_order_id: "order-verify-merge-1",
                                         metadata: { invoice_id: 42 })

    assert order.mark_verification_failed!(reason: "channel_mismatch",
                                           detail: "type=LIVE expected=TEST")

    order.reload
    assert_equal 42, order.metadata["invoice_id"], "청구 역참조가 유실되지 않는다"
    assert_equal Order::VERIFICATION_FAILED_CODE, order.metadata["code"]
    assert_equal "channel_mismatch", order.metadata.dig("verification", "reason")
  end

  test "mark_verification_failed!는 이미 확정된 주문을 건드리지 않고 false를 반환한다 (경합 멱등)" do
    travel_to(Time.zone.parse("2026-11-25 10:00")) do
      # 이미 paid — 확정 뒤의 늦은 검증 실패 통지로 되돌리지 않는다
      paid_order = users(:delta).orders.create!(product: :collection_pass, amount: 4_000,
                                                pg_order_id: "order-verify-paid-1")
      paid_order.update!(status: :paid, paid_at: Time.current, pg_payment_id: "order-verify-paid-1")
      assert_not paid_order.mark_verification_failed!(reason: "amount_mismatch",
                                                      detail: "paid=1 expected=4000"),
                "paid 확정은 되돌리지 않는다"
      paid_order.reload
      assert_predicate paid_order, :paid?
      assert_not_nil paid_order.paid_at
      assert_nil paid_order.metadata&.dig("code"), "paid 주문에 검증 실패 코드가 남지 않는다"

      # 이미 failed(일반 PG 거절) — 사유를 검증 실패로 덮어쓰지 않는다
      failed_order = users(:delta).orders.create!(product: :collection_pass, amount: 4_000,
                                                  pg_order_id: "order-verify-failed-2",
                                                  status: :failed,
                                                  metadata: { code: "PG_PROVIDER_ERROR",
                                                              message: "카드 한도 초과" })
      assert_not failed_order.mark_verification_failed!(reason: "amount_mismatch",
                                                        detail: "paid=1 expected=4000")
      failed_order.reload
      assert_equal "PG_PROVIDER_ERROR", failed_order.metadata["code"]
      assert_nil failed_order.metadata["verification"]
      assert_not_predicate failed_order, :verification_failed?
    end
  end

  test "verification_failed?는 검증 실패 코드가 남은 failed만 참이다 (일반 실패·paid·pending은 거짓)" do
    verify_failed = users(:delta).orders.create!(product: :collection_pass, amount: 4_000,
                                                 pg_order_id: "order-verify-pred-1")
    verify_failed.mark_verification_failed!(reason: "amount_mismatch", detail: "x")

    assert_predicate verify_failed.reload, :verification_failed?

    normal_failed = users(:delta).orders.create!(product: :collection_pass, amount: 4_000,
                                                 pg_order_id: "order-verify-pred-2",
                                                 status: :failed,
                                                 metadata: { code: "PG_PROVIDER_ERROR" })
    assert_not_predicate normal_failed, :verification_failed?

    paid = users(:delta).orders.create!(product: :collection_pass, amount: 4_000,
                                        pg_order_id: "order-verify-pred-3")
    paid.update!(status: :paid, paid_at: Time.current,
                 metadata: { code: Order::VERIFICATION_FAILED_CODE })
    assert_not_predicate paid.reload, :verification_failed?     # paid면 코드가 있어도 거짓

    pending = users(:delta).orders.create!(product: :collection_pass, amount: 4_000,
                                           pg_order_id: "order-verify-pred-4")
    assert_not_predicate pending, :verification_failed?
  end
end
