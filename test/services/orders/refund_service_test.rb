require "test_helper"
require_relative "../../test_helpers/portone_stubbing"
require_relative "../../test_helpers/fake_portone_client"

# 관리자 환불 실행(PLAN-9·ADMIN-11·Q27) 서비스 테스트 — 시나리오 기준:
# PRD §6.10 PLAN-9·§6.18 ADMIN-11·§10 Q27 + _workspace/05_review.md §8 Tester 중점 1~4
# (C-1 dunning 잔존 회귀·C-2 시도/실패 감사·상품 4종·재조회 판정 경계).
# 포트원은 FakePortOneClient를 생성자(client:)로 주입 — 실호출 0건. 잡(C-1 재시도)은
# 내부에서 기본 클라이언트를 만들므로 with_portone_client로 감싼다. 시간은 travel_to KST 고정.
module Orders
  class RefundServiceTest < ActiveSupport::TestCase
    include PortOneStubbing

    setup do
      @admin = admins(:ops)
      @user = users(:gamma) # 구독·주문·패스 없는 사용자 — 테스트가 자식 레코드를 만든다
      travel_to(Time.zone.parse("2026-11-25 10:00"))
    end

    teardown { travel_back }

    # ── 정상 — 상품 4종 (PLAN-9·Q27) ────────────────────────────────────────────

    test "Plus 주문 환불은 구독을 즉시 Free로 되돌리고 빌링키 복사본을 정리한다 (PLAN-9①·Q27)" do
      subscription = @user.create_subscription!(plan: :plus, status: :active,
                                                pg_billing_key: "tok_refund_sub",
                                                current_period_start: Time.zone.parse("2026-11-01 00:00"),
                                                current_period_end: Time.zone.parse("2026-11-30 23:59:59"))
      order = @user.orders.create!(product: :plus_monthly, amount: 9_900, status: :paid,
                                   pg_order_id: "order-rf-plus-1", pg_payment_id: "pay-rf-plus-1",
                                   paid_at: Time.zone.parse("2026-11-01 09:00"),
                                   pg_billing_key: "tok_refund_sub",
                                   metadata: { "note" => "원기록 보존 확인용" })
      copy = @user.orders.create!(product: :plus_monthly, amount: 9_900, status: :paid,
                                  pg_order_id: "order-rf-plus-2", pg_payment_id: "pay-rf-plus-2",
                                  paid_at: Time.zone.parse("2026-10-01 09:00"),
                                  pg_billing_key: "tok_refund_sub")
      other_key = @user.orders.create!(product: :plus_monthly, amount: 9_900, status: :paid,
                                       pg_order_id: "order-rf-plus-3", pg_payment_id: "pay-rf-plus-3",
                                       paid_at: Time.zone.parse("2026-09-01 09:00"),
                                       pg_billing_key: "tok_other_key")
      beta_copy = users(:beta).orders.create!(product: :plus_monthly, amount: 9_900, status: :paid,
                                              pg_order_id: "order-rf-beta-1",
                                              pg_payment_id: "pay-rf-beta-1",
                                              paid_at: Time.zone.parse("2026-10-01 09:00"),
                                              pg_billing_key: "tok_refund_sub")

      result = refund(order)

      assert result.success?
      assert_match(/구독 즉시 Free 전환/, result.message)
      assert_predicate order.reload, :cancelled?
      assert order.refunded_at.present?
      assert_equal "이중 결제 정정", order.refund_reason
      refund_info = order.metadata["refund"]
      assert_equal @admin.email, refund_info["executed_by"]
      assert_equal 9_900, refund_info["amount"]
      assert_equal "이중 결제 정정", refund_info["reason"]
      assert refund_info["executed_at"].present?
      assert_equal "원기록 보존 확인용", order.metadata["note"], "기존 metadata 키는 보존된다"
      assert_predicate subscription.reload, :free?
      assert_predicate subscription, :expired?
      assert_nil subscription.pg_billing_key
      assert_nil subscription.current_period_start
      assert_nil subscription.current_period_end
      assert_nil copy.reload.pg_billing_key, "같은 회원·같은 키 복사본도 정리된다"
      assert_equal "tok_other_key", other_key.reload.pg_billing_key, "다른 키 주문 행은 불변"
      assert_equal "tok_refund_sub", beta_copy.reload.pg_billing_key, "다른 회원 주문 행은 불변"
      assert_equal 1, refund_audits("order_refund_attempt", order).count
      assert_equal 1, refund_audits("order_refund", order).count
    end

    test "수금 패스 주문 환불은 회원의 유효 패스에서 만료 임박순으로 10건 차감한다 (PLAN-9②·Q27)" do
      create_pass(remaining: 6, expires_at: Time.zone.parse("2026-12-15 23:59:59"))
      create_pass(remaining: 10, expires_at: Time.zone.parse("2027-01-14 23:59:59"))
      order = paid_pass_order("order-rf-pass-1")

      result = refund(order)

      assert result.success?
      assert_match(/수금 패스 10건 차감\z/, result.message)
      passes = @user.payment_passes.order(:expires_at)
      assert_equal [ 0, 6 ], passes.pluck(:remaining_uses), "만료 임박 패스 먼저 차감(잔여 6 → 0, 다음 패스 10 → 6)"
      assert passes.all? { |pass| pass.reload.remaining_uses >= 0 }
      assert_equal 1, refund_audits("order_refund", order).count
    end

    test "내용증명 주문 환불은 주문 기록만 변경하고 발행물·패스를 건드리지 않는다 (PLAN-9③·Q27)" do
      order = @user.orders.create!(product: :collection_pass, item_type: :legal_doc,
                                   amount: Order::LEGAL_DOC_PRICE, status: :paid,
                                   pg_order_id: "order-rf-legal-1", pg_payment_id: "pay-rf-legal-1",
                                   paid_at: Time.zone.parse("2026-11-20 09:00"))

      result = refund(order)

      assert result.success?
      assert_match(/발행물은 그대로 유지/, result.message)
      assert_predicate order.reload, :cancelled?
      assert order.refunded?
      assert_empty @user.payment_passes, "패스 발급 없음"
      assert_equal 0, @user.orders.where.not(id: order.id).count, "주문 외 생성 없음"
    end

    test "세금계산서 주문 환불도 주문 기록만 변경한다 (PLAN-9③·Q27)" do
      order = @user.orders.create!(product: :collection_pass, item_type: :tax_invoice,
                                   amount: 300, status: :paid,
                                   pg_order_id: "order-rf-tax-1", pg_payment_id: "pay-rf-tax-1",
                                   paid_at: Time.zone.parse("2026-11-20 09:00"))

      result = refund(order)

      assert result.success?
      assert_match(/발행물은 그대로 유지/, result.message)
      assert_predicate order.reload, :cancelled?
      assert_equal 0, TaxInvoice.where(user_id: @user.id).count, "발행 레코드는 무변경(취소 요청 없음)"
      assert_equal 1, refund_audits("order_refund", order).count
    end

    test "쿠폰가(실차감액) Plus 주문도 재조회 금액 기준으로 성공한다 (경계 — P6 회귀)" do
      @user.create_subscription!(plan: :plus, status: :active, pg_billing_key: "tok_refund_coupon")
      order = @user.orders.create!(product: :plus_monthly, amount: 7_425, status: :paid,
                                   pg_order_id: "order-rf-coupon", pg_payment_id: "pay-rf-coupon",
                                   paid_at: Time.zone.parse("2026-11-01 09:00"))

      result = refund(order, client: ok_client(order, paid: 7_425))

      assert result.success?, "재조회 paid가 주문 금액(쿠폰가)이면 성공 — 정가 9,900과 비교하지 않는다"
      assert_predicate order.reload, :cancelled?
    end

    # ── 경계 ────────────────────────────────────────────────────────────────────

    test "패스 잔여가 모자라면 0에서 종료하고 미차감 수량을 보고한다 (PLAN-9②·Q27)" do
      create_pass(remaining: 3, expires_at: Time.zone.parse("2026-12-15 23:59:59"))
      order = paid_pass_order("order-rf-pass-short")

      result = refund(order)

      assert result.success?
      assert_match(/수금 패스 3건 차감\(미차감 7건\)/, result.message)
      assert_equal 0, @user.payment_passes.sole.reload.remaining_uses, "음수로 넘어가지 않는다"
    end

    test "이미 Free(만료) 구독의 Plus 주문 환불은 무변경 보고를 남긴다 (W-6·Q27)" do
      subscription = @user.create_subscription!(plan: :free, status: :expired)

      result = refund(plus_order("order-rf-free-expired"))

      assert result.success?
      assert_match(/구독은 이미 Free\(무변경\)/, result.message)
      assert_predicate subscription.reload, :expired?
      assert_predicate subscription, :free?
    end

    test "이미 Free(이용 중 상태) 구독도 무변경 보고를 남기고 dunning 잔존 필드는 비운다 (W-6·C-1)" do
      subscription = @user.create_subscription!(plan: :free, status: :active,
                                                pg_billing_key: "tok_free_active",
                                                dunning_stage: 1,
                                                next_retry_at: Time.zone.parse("2026-11-28 06:05"),
                                                last_payment_failed_at: Time.zone.parse("2026-11-24 06:05"))
      copy = @user.orders.create!(product: :plus_monthly, amount: 9_900, status: :paid,
                                  pg_order_id: "order-rf-free-active-copy",
                                  pg_payment_id: "pay-rf-free-active-copy",
                                  paid_at: Time.zone.parse("2026-11-01 09:00"),
                                  pg_billing_key: "tok_free_active")

      result = refund(plus_order("order-rf-free-active"))

      assert result.success?
      assert_match(/구독은 이미 Free\(무변경\)/, result.message)
      assert_predicate subscription.reload, :active?, "expire! 미실행 — 상태 유지"
      assert_predicate subscription, :free?
      assert_nil subscription.last_payment_failed_at, "dunning 실패 시각은 잔존 시 비운다"
      assert_nil copy.reload.pg_billing_key, "키 복사본 정리는 이미 Free여도 실행된다"
    end

    test "C-1 회귀: dunning 진행 구독의 이전 paid 주문 환불은 재시도 상태를 비우고 재등록 후에도 차감이 없다 (PLAN-9①)" do
      subscription = @user.create_subscription!(plan: :plus, status: :active,
                                                pg_billing_key: "tok_dunning_refund",
                                                dunning_stage: 1,
                                                next_retry_at: Time.zone.parse("2026-11-28 06:05"),
                                                last_payment_failed_at: Time.zone.parse("2026-11-24 06:05"))
      order = plus_order("order-rf-c1-prev", billing_key: "tok_dunning_refund")

      result = refund(order)

      assert result.success?
      subscription.reload
      assert_equal 0, subscription.dunning_stage
      assert_nil subscription.next_retry_at
      assert_nil subscription.last_payment_failed_at
      assert_predicate subscription, :free?
      assert_not_predicate subscription, :dunning_active?

      # 회원이 새 카드로 재등록 — dunning 상태 없음을 확인한다(C-1 사고 경로)
      subscription.activate!(billing_key: "tok_new_card")
      assert_not_predicate subscription.reload, :dunning_active?

      # 재시도 잡 실행 — 차감 API 호출·새 주문이 없어야 한다(잡은 내부에서 기본 클라이언트를
      # 만들므로 with_portone_client 필수 — 실호출 방어)
      fake = FakePortOneClient.new
      travel_to(Time.zone.parse("2026-11-28 06:10")) do
        with_portone_client(fake) do
          Subscriptions::DunningRetryJob.perform_now(subscription.id)
        end
      end
      assert_empty fake.calls.values.flatten, "재시도 잡이 새 카드로 차감을 시도하지 않는다"
      assert_equal 1, @user.orders.reload.count, "환불된 주문만 존재 — 새 pending 주문 없음"
    end

    test "콘솔 선취소(취소 요청 거부·재조회 CANCELLED)는 재조회로 수렴해 정산 1회로 끝난다 (PLAN-9 재동기화)" do
      order = plus_order("order-rf-preconsole")
      client = FakePortOneClient.new(
        raise_on: { cancel_payment: PortOne::ApiError.new(status: 409,
                                                          code: "PAYMENT_ALREADY_CANCELLED",
                                                          message: "이미 취소된 결제입니다") },
        get_payment: { id: order.pg_order_id, status: "CANCELLED",
                       amount: { paid: order.amount, cancelled: order.amount } }
      )

      result = refund(order, client: client)

      assert result.success?
      assert_equal 1, client.calls[:cancel_payment].count, "취소 요청은 1회 시도된다"
      assert_equal 1, refund_audits("order_refund", order).count, "정산(성공 감사) 정확히 1회"
    end

    test "웹훅이 먼저 cancelled로 만든 주문도 실행으로 정산 1회가 된다 (선행 도착·PLAN-9 재동기화)" do
      order = plus_order("order-rf-webhook-first").tap do |record|
        record.update!(status: :cancelled) # 웹훅 apply_status와 같은 결과 — refunded_at은 없음
      end

      result = refund(order, client: ok_client(order))

      assert result.success?
      assert order.reload.refunded?
      assert_equal 1, refund_audits("order_refund", order).count
    end

    test "이미 환불된 주문의 재실행은 사전 가드로 실패하고 PG 호출·감사가 추가되지 않는다 (멱등)" do
      order = paid_pass_order("order-rf-idem")
      assert refund(order, client: ok_client(order)).success?
      audits_before = AuditLog.where(target_type: "Order", target_id: order.id).count

      retry_client = FakePortOneClient.new(raise_on: { cancel_payment: StandardError.new("PG 호출 금지") })
      result = refund(order, client: retry_client)

      assert_not result.success?
      assert_match(/이미 환불 처리된 주문입니다/, result.errors.first)
      assert_empty retry_client.calls.values.flatten, "재실행은 PG 호출이 없다"
      assert_equal audits_before, AuditLog.where(target_type: "Order", target_id: order.id).count
    end

    # ── 예외 — PG 재조회 판정 실패(로컬 무변경 + 시도·실패 감사) ───────────────────

    test "재조회 ApiError는 실패하고 시도·실패 감사를 남긴다 (PLAN-9 fail-closed·C-2)" do
      order = paid_pass_order("order-rf-api-error")
      client = FakePortOneClient.new(
        raise_on: { get_payment: PortOne::ApiError.new(status: 503, code: "INTERNAL_SERVER_ERROR",
                                                       message: "재조회 실패") }
      )

      result = refund(order, client: client)

      assert_not result.success?
      assert_match(/포트원 API 오류로 취소를 확정하지 못했습니다/, result.errors.first)
      assert_predicate order.reload, :paid?, "로컬 무변경"
      assert_not order.refunded?
      assert_equal 1, refund_audits("order_refund_attempt", order).count
      assert_equal 1, refund_audits("order_refund_failed", order).count
      assert_equal 0, refund_audits("order_refund", order).count
    end

    test "재조회 비-ApiError 예외(SSL·파싱 등)도 실패 Result로 흡수된다 (W-1·C-2)" do
      order = paid_pass_order("order-rf-ssl")
      client = FakePortOneClient.new(raise_on: { get_payment: StandardError.new("SSL handshake failed") })

      result = refund(order, client: client)

      assert_not result.success?
      assert_match(/재조회 중 오류로 취소를 확정하지 못했습니다/, result.errors.first)
      assert_predicate order.reload, :paid?
      assert_equal 1, refund_audits("order_refund_attempt", order).count
      assert_equal 1, refund_audits("order_refund_failed", order).count
    end

    test "PARTIAL_CANCELLED 재조회는 명시 실패다 (PLAN-9 — 부분 취소 범위 밖)" do
      order = paid_pass_order("order-rf-partial")
      client = FakePortOneClient.new(
        get_payment: { id: order.pg_order_id, status: "PARTIAL_CANCELLED",
                       amount: { paid: order.amount, cancelled: 0 } }
      )

      result = refund(order, client: client)

      assert_not result.success?
      assert_match(/부분 취소된 결제입니다/, result.errors.first)
      assert_predicate order.reload, :paid?
      assert_equal 1, refund_audits("order_refund_failed", order).count
    end

    # ADMIN-2·Q32 — PG 취소 뒤 확정 실패(fail_with_audit) 경로의 order_refund_failed 감사에도
    # ip가 기록되는지 고정(C-2 실패 감사와 Q32 ip 전달의 교집합). PARTIAL_CANCELLED는
    # PG 취소 실행 뒤 재조회 판정에서 실패한다 — fail_with_audit이 도는 최단 경로.
    test "확정 실패 감사(order_refund_failed)에도 요청자 IP가 기록된다 (ADMIN-2·Q32)" do
      order = paid_pass_order("order-rf-failed-ip")
      client = FakePortOneClient.new(
        get_payment: { id: order.pg_order_id, status: "PARTIAL_CANCELLED",
                       amount: { paid: order.amount, cancelled: 0 } }
      )

      result = Orders::RefundService.new(admin: @admin, order: order, reason: "이중 결제 정정",
                                         client: client, ip: "203.0.113.13").call

      assert_not result.success?
      failed = refund_audits("order_refund_failed", order).sole
      assert_equal "203.0.113.13", failed.ip
    end

    test "amount.paid 누락·0·주문 금액 미만은 결제 완료 사실 미확인으로 실패다 (W-3 — fail-closed)" do
      order = paid_pass_order("order-rf-paid-fact")
      base = { id: order.pg_order_id, status: "CANCELLED" }
      responses = [
        base.merge(amount: { cancelled: order.amount }),                       # paid 누락
        base.merge(amount: { paid: 0, cancelled: order.amount }),              # paid 0
        base.merge(amount: { paid: order.amount - 1, cancelled: order.amount }) # 미만
      ]

      responses.each do |response|
        result = refund(order, client: FakePortOneClient.new(get_payment: response))

        assert_not result.success?, "paid=#{response[:amount][:paid].inspect}는 통과하면 안 된다"
        assert_match(/결제 완료 사실.*확인할 수 없습니다/, result.errors.first)
      end

      assert_predicate order.reload, :paid?
      assert_equal responses.size, refund_audits("order_refund_attempt", order).count
      assert_equal responses.size, refund_audits("order_refund_failed", order).count
    end

    test "재조회 응답의 결제 ID가 주문과 다르면 실패다 (W-3 — 무결성 확인)" do
      order = paid_pass_order("order-rf-id-mismatch")
      client = FakePortOneClient.new(
        get_payment: { id: "payment-of-another-order", status: "CANCELLED",
                       amount: { paid: order.amount, cancelled: order.amount } }
      )

      result = refund(order, client: client)

      assert_not result.success?
      assert_match(/결제 ID 불일치/, result.errors.first)
      assert_predicate order.reload, :paid?
    end

    test "상태 PAID(미취소) 재조회는 전액 취소 미확인으로 실패다 (PLAN-9 fail-closed)" do
      order = paid_pass_order("order-rf-still-paid")
      client = FakePortOneClient.new(
        get_payment: { id: order.pg_order_id, status: "PAID",
                       amount: { paid: order.amount, cancelled: 0 } }
      )

      result = refund(order, client: client)

      assert_not result.success?
      assert_match(/전액 취소를 확인할 수 없습니다\(상태: PAID\)/, result.errors.first)
      assert_predicate order.reload, :paid?
    end

    test "취소 합계는 SUCCEEDED 항목만 더한다 — REQUESTED·FAILED만 있으면 실패다 (W-2)" do
      order = paid_pass_order("order-rf-cancel-list")
      client = FakePortOneClient.new(
        get_payment: { id: order.pg_order_id, status: "PAID",
                       amount: { paid: order.amount },
                       cancellations: [ { status: "REQUESTED", totalAmount: 4_000 },
                                        { status: "FAILED", totalAmount: 4_000 } ] }
      )

      result = refund(order, client: client)

      assert_not result.success?, "확정되지 않은 취소 항목은 합산되지 않는다"
      assert_match(/전액 취소를 확인할 수 없습니다/, result.errors.first)
      assert_predicate order.reload, :paid?
    end

    test "상태가 CANCELLED가 아니어도 SUCCEEDED 취소 합계가 주문 금액 이상이면 전액 취소로 인정한다 (경계)" do
      order = paid_pass_order("order-rf-cancel-sum")
      client = FakePortOneClient.new(
        get_payment: { id: order.pg_order_id, status: "PAID",
                       amount: { paid: order.amount },
                       cancellations: [ { status: "SUCCEEDED", totalAmount: 4_000 } ] }
      )

      result = refund(order, client: client)

      assert result.success?, "취소 합계 경로 — 상태 지연 반영 응답도 정산을 수렴시킨다"
      assert_predicate order.reload, :cancelled?
    end

    test "비동기 취소(REQUESTED) 진행 중 안내로 실패하고 재실행 안내를 돌려준다 (W-4b)" do
      order = paid_pass_order("order-rf-async")
      client = FakePortOneClient.new(
        cancel_payment: { cancellation: { status: "REQUESTED" } },
        get_payment: { id: order.pg_order_id, status: "PAID",
                       amount: { paid: order.amount, cancelled: 0 } }
      )

      result = refund(order, client: client)

      assert_not result.success?
      assert_equal "취소가 비동기로 진행 중입니다. 잠시 후 다시 실행해 주세요.", result.errors.first
      assert_predicate order.reload, :paid?
      assert_equal 1, refund_audits("order_refund_failed", order).count
    end

    test "흡수한 취소 요청 오류 코드가 실패 메시지에 보존된다 (W-4a)" do
      order = paid_pass_order("order-rf-w4a")
      client = FakePortOneClient.new(
        raise_on: { cancel_payment: PortOne::ApiError.new(status: 403, code: "STORE_FORBIDDEN",
                                                          message: "스토어 권한 없음") },
        get_payment: { id: order.pg_order_id, status: "PAID",
                       amount: { paid: order.amount, cancelled: 0 } }
      )

      result = refund(order, client: client)

      assert_not result.success?
      assert_match(/\A포트원 취소 요청 오류: STORE_FORBIDDEN —/, result.errors.first)
      assert_predicate order.reload, :paid?
    end

    # ── 예외 — 사전 가드(PG 호출 0·감사 0) ───────────────────────────────────────

    test "blank 사유는 사전 가드로 실패하고 PG 호출·감사가 없다 (ADMIN-11 사유 필수)" do
      order = paid_pass_order("order-rf-blank")
      fake = FakePortOneClient.new

      result = refund(order, reason: "   ", client: fake)

      assert_not result.success?
      assert_equal "환불 사유는 필수입니다.", result.errors.first
      assert_empty fake.calls.values.flatten
      assert_equal 0, AuditLog.where(target_type: "Order", target_id: order.id).count
    end

    test "pending·failed 주문은 사전 가드로 실패한다 (PLAN-9 — 결제 완료 건 한정)" do
      pending = @user.orders.create!(product: :collection_pass, item_type: :pass,
                                     amount: 4_000, pg_order_id: "order-rf-pending")
      failed = @user.orders.create!(product: :collection_pass, item_type: :pass,
                                    amount: 4_000, status: :failed,
                                    pg_order_id: "order-rf-failed")
      fake = FakePortOneClient.new

      [ pending, failed ].each do |order|
        result = refund(order, client: fake)

        assert_not result.success?
        assert_match(/결제 완료·취소 상태의 주문만 환불할 수 있습니다/, result.errors.first)
      end
      assert_empty fake.calls.values.flatten
      assert_equal 0, AuditLog.where(target_type: "Order", target_id: pending.id).count
      assert_equal 0, AuditLog.where(target_type: "Order", target_id: failed.id).count
    end

    test "paid_at 없는 cancelled 주문(가상계좌 말소 등)은 사전 가드로 실패한다 (PLAN-9)" do
      order = @user.orders.create!(product: :collection_pass, item_type: :pass,
                                   amount: 4_000, status: :cancelled,
                                   pg_order_id: "order-rf-no-paidat")
      fake = FakePortOneClient.new

      result = refund(order, client: fake)

      assert_not result.success?
      assert_match(/결제가 완료된 적이 없는 주문은 환불할 수 없습니다/, result.errors.first)
      assert_empty fake.calls.values.flatten
    end

    test "pg_order_id가 없는 주문은 사전 가드로 실패한다 (PLAN-9 — 취소 대상 식별 불가)" do
      order = paid_pass_order("order-rf-no-pgid")
      order.update_columns(pg_order_id: "") # NOT NULL 컬럼 — 공백으로 가드 도달(운영 도달 불가 방어선)
      fake = FakePortOneClient.new

      result = refund(order, client: fake)

      assert_not result.success?
      assert_match(/포트원 결제 ID가 없어 취소를 실행할 수 없습니다/, result.errors.first)
      assert_empty fake.calls.values.flatten
    end

    # ── 예외 — 감사·로컬 확정(C-2 회귀) ──────────────────────────────────────────

    test "시도 감사 기록에 실패하면 PG 호출 없이 중단한다 (C-2 — 기록 없는 취소 금지)" do
      order = paid_pass_order("order-rf-audit-fail")
      fake = FakePortOneClient.new

      with_failing_audit_record(StandardError.new("감사 기록 실패")) do
        result = refund(order, client: fake)

        assert_not result.success?
        assert_match(/환불 시도 기록\(감사 로그\)에 실패해 실행을 중단했습니다/, result.errors.first)
      end

      assert_empty fake.calls.values.flatten, "감사 없이 PG 취소를 보내지 않는다"
      assert_predicate order.reload, :paid?
      assert_not order.refunded?
      assert_equal 0, AuditLog.where(target_type: "Order", target_id: order.id).count
    end

    test "C-2 회귀: PG 취소·재조회 성공 뒤 로컬 확정 예외는 실패 Result로 흡수되고 실패 감사를 남긴다 (W-1)" do
      create_pass(remaining: 10, expires_at: Time.zone.parse("2026-12-15 23:59:59"))
      order = paid_pass_order("order-rf-c2")

      result = with_failing_pass_revoke(ActiveRecord::StatementInvalid.new("SQLite3::BusyException")) do
        refund(order, client: ok_client(order))
      end

      assert_not result.success?, "로컬 확정 예외가 밖으로 새지 않는다(500 금지)"
      assert_match(/환불 기록 중 오류\(ActiveRecord::StatementInvalid\)/, result.errors.first)
      assert_predicate order.reload, :paid?, "주문은 실행 전 상태(paid)로 미정산 잔존"
      assert_not order.refunded?
      assert_equal 10, @user.payment_passes.sole.reload.remaining_uses, "되돌리기도 롤백된다"
      assert_equal 1, refund_audits("order_refund_attempt", order).count
      assert_equal 1, refund_audits("order_refund_failed", order).count
      assert_equal 0, refund_audits("order_refund", order).count
    end

    # ── 멱등·경합 ────────────────────────────────────────────────────────────────

    test "같은 주문에 순차 2회 실행은 두 번째가 사전 가드로 실패한다 (경합·이중 제출)" do
      order = plus_order("order-rf-twice")
      assert refund(order, client: ok_client(order)).success?

      second = refund(order, client: ok_client(order))

      assert_not second.success?
      assert_match(/이미 환불 처리된 주문입니다/, second.errors.first)
      assert_equal 1, refund_audits("order_refund", order).count, "성공 감사는 1건"
    end

    private

    def refund(order, reason: "이중 결제 정정", client: nil)
      Orders::RefundService.new(admin: @admin, order: order, reason: reason,
                                client: client || ok_client(order)).call
    end

    # 전액 취소 확정 응답 — 재조회(get_payment)만 신뢰하는 서비스 계약에 맞춘다.
    def ok_client(order, paid: nil)
      FakePortOneClient.new(
        get_payment: { id: order.pg_order_id, status: "CANCELLED",
                       amount: { paid: paid || order.amount, cancelled: paid || order.amount } }
      )
    end

    def plus_order(pg_order_id, billing_key: "tok_refund_sub")
      @user.orders.create!(product: :plus_monthly, amount: 9_900, status: :paid,
                           pg_order_id: pg_order_id, pg_payment_id: "pay-#{pg_order_id}",
                           paid_at: Time.zone.parse("2026-11-01 09:00"),
                           pg_billing_key: billing_key)
    end

    def paid_pass_order(pg_order_id)
      @user.orders.create!(product: :collection_pass, item_type: :pass, amount: 4_000,
                           status: :paid, pg_order_id: pg_order_id,
                           pg_payment_id: "pay-#{pg_order_id}",
                           paid_at: Time.zone.parse("2026-11-20 09:00"))
    end

    def create_pass(remaining:, expires_at:)
      @user.payment_passes.create!(total_uses: PaymentPass::TOTAL_USES,
                                   remaining_uses: remaining, expires_at: expires_at)
    end

    def refund_audits(action, order)
      AuditLog.where(action: action, target_type: order.class.name, target_id: order.id)
    end

    def with_failing_audit_record(exception)
      original = AuditLogs::RecordService.method(:call)
      AuditLogs::RecordService.define_singleton_method(:call) { |*| raise exception }
      yield
    ensure
      AuditLogs::RecordService.define_singleton_method(:call, original)
    end

    def with_failing_pass_revoke(exception)
      original = PaymentPass.method(:revoke_uses!)
      PaymentPass.define_singleton_method(:revoke_uses!) { |**| raise exception }
      yield
    ensure
      PaymentPass.define_singleton_method(:revoke_uses!, original)
    end
    # ADMIN-2·Q32 — 컨트롤러가 넘긴 요청자 IP(ClientIp.of)가 시도·완료 감사까지 전달되는지 고정.
    test "ip를 넘기면 시도·완료 감사에 요청자 IP가 기록된다 (ADMIN-2·Q32)" do
      order = plus_order("order-rf-ip-1")

      result = Orders::RefundService.new(admin: @admin, order: order, reason: "이중 결제 정정",
                                         client: ok_client(order), ip: "203.0.113.7").call

      assert result.success?
      assert_equal "203.0.113.7", refund_audits("order_refund_attempt", order).order(:id).last.ip
      assert_equal "203.0.113.7", refund_audits("order_refund", order).order(:id).last.ip
    end

    test "ip를 넘기지 않은 기존 호출의 감사는 ip가 nil로 유지된다 (하위호환)" do
      order = plus_order("order-rf-ip-2")

      result = refund(order)

      assert result.success?
      assert_nil refund_audits("order_refund", order).order(:id).last.ip
    end
  end
end
