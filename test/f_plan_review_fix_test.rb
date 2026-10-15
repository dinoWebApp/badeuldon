require "test_helper"
require_relative "test_helpers/fake_portone_client"

# F-PLAN 리뷰 수정(05_review 이슈 #1~#7) 회귀 — 결제·구독·한도 판정의 금전 무결성 계약.
# 검증 범위: #1 승인 모호 실패(pending 유지·재확인 합류·웹훅 회복 대기), #3 activate! 주기 기준,
# #5 GET 상태 변경 차단, #7 수금 패스 소비 연결.
# 웹훅 회복 시나리오(paymentId 보존 주문 PAID→발급·paymentId 보조 매칭·위조 결합 흡수)는
# portone_controller_test.rb, 체험 1회·갱신 멱등·해지 가드는 subscription/upgrade_service
# 테스트가 담당한다. 포트원 호출은 FakePortOneClient 주입으로 대체한다(실호출 금지).
# 시간은 travel_to로 KST 고정(TIME-1).
class FPlanReviewFixTest < ActiveSupport::TestCase
  setup do
    @user = users(:gamma) # 구독·수금 패스 fixture 없음 — 발급 수량 검증이 깨끗하다
  end

  # ── 이슈 #1 — 승인 모호 실패는 failed 확정하지 않는다(이중 결제 차단) ──

  test "승인 타임아웃은 실패로 확정하지 않고 pending 유지 + 결제 ID를 보존한다 (이슈 #1)" do
    order = @user.orders.create!(product: :collection_pass, amount: 4_000,
                                 pg_order_id: "order-fix1-timeout")
    fake = FakePortOneClient.new(
      raise_on: { confirm_payment: PortOne::ApiError.new(status: nil, code: "TIMEOUT",
                                                         message: "execution expired") },
      get_payment: { status: "READY" } # 재확인 — 아직 승인되지 않음(회복 대기 상태 재현)
    )

    error = assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: order, payment_token: "tok_fix1_timeout", client: fake).call
    end

    assert_match(/지연/, error.message)
    order.reload
    assert_predicate order, :pending?                        # failed 확정 금지 — 웹훅 회복 대기
    assert_equal "order-fix1-timeout", order.pg_payment_id   # 웹훅 PAID 매칭용 보존
    assert_equal true, order.metadata["pending_recovery"]    # 모호 실패 이력
    assert_empty @user.payment_passes.reload                 # 발급 없음
  end

  test "타임아웃 후 재확인에서 PAID면 정상 발급 경로로 합류한다 (이슈 #1)" do
    order = @user.orders.create!(product: :collection_pass, amount: 4_000,
                                 pg_order_id: "order-fix1-recheck")
    fake = FakePortOneClient.new(
      raise_on: { confirm_payment: PortOne::ApiError.new(status: nil, code: "TIMEOUT",
                                                         message: "execution expired") },
      get_payment: { id: "order-fix1-recheck", status: "PAID" }
    )

    result = Orders::PurchaseService.new(order: order, payment_token: "tok_fix1_done",
                                         client: fake).call

    assert_equal order.reload, result
    assert_predicate order, :paid?
    assert_equal "order-fix1-recheck", order.pg_payment_id
    assert_equal 1, @user.payment_passes.reload.count        # 정상 발급 — 회복 경로 합류

    # 재구매 방지 — 같은 주문 재승인은 이중 결제 없이 흡수된다
    error = assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: order.reload, payment_token: "tok_fix1_done",
                                  client: fake).call
    end
    assert_match(/이미 처리된 결제입니다/, error.message)
    assert_equal 1, @user.payment_passes.reload.count
  end

  test "타임아웃 후 재확인도 실패하면 pending을 유지해 웹훅 회복 경로를 연다 (이슈 #1)" do
    order = @user.orders.create!(product: :collection_pass, amount: 4_000,
                                 pg_order_id: "order-fix1-norecheck")
    ambiguous = PortOne::ApiError.new(status: nil, code: "TIMEOUT", message: "execution expired")
    fake = FakePortOneClient.new(raise_on: { confirm_payment: ambiguous, get_payment: ambiguous })

    error = assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: order, payment_token: "tok_fix1_dark", client: fake).call
    end

    assert_match(/지연/, error.message)
    order.reload
    assert_predicate order, :pending?                        # 조회 실패도 failed 확정 금지
    assert_equal "order-fix1-norecheck", order.pg_payment_id
    assert_empty @user.payment_passes.reload
  end

  # ── 이슈 #3 — activate! 주기 기준은 현재·체험 종료·기존 주기 종료 중 최댓값 ──

  test "체험 중 카드 등록은 체험 종료 후부터 유료 주기를 시작한다 (이슈 #3)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      subscription = @user.create_subscription!(plan: :plus, status: :trialing,
                                                trial_ends_at: Time.zone.parse("2026-10-29 09:00"))

      subscription.activate!(billing_key: "tok_billing_fix3_trial")

      subscription.reload
      assert_predicate subscription, :active?
      # 체험 잔여 14일이 유료 주기에 편입되지 않는다 — 첫 차감일은 체험 종료 + 1개월
      assert_equal Time.zone.parse("2026-10-29 09:00"), subscription.current_period_start
      assert_equal Time.zone.parse("2026-11-29 09:00"), subscription.current_period_end
    end
  end

  test "해지 잔여 기간 중 재등록은 기존 주기 종료 후부터 새 주기를 시작한다 (이슈 #3)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      subscription = @user.create_subscription!(plan: :plus, status: :cancelled,
                                                current_period_end: Time.zone.parse("2026-10-31 23:59:59"))

      subscription.activate!(billing_key: "tok_billing_fix3_cancel")

      subscription.reload
      assert_predicate subscription, :active?
      # 이미 결제된 기간과 새 주기가 겹치지 않는다 — 기존 주기 말이 새 주기의 시작
      assert_equal Time.zone.parse("2026-10-31 23:59:59"), subscription.current_period_start
      assert_equal Time.zone.parse("2026-11-30 23:59:59"), subscription.current_period_end
    end
  end

  # ── 이슈 #7 — Free 한도 초과 발행은 수금 패스를 소비한다 ──

  test "Free 한도 초과 발행은 수금 패스를 정확히 1건 소비해 허용된다 (이슈 #7)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      @user.create_subscription!(plan: :free)
      3.times { issue_invoice! }
      pass = @user.payment_passes.create!(total_uses: 10, remaining_uses: 10,
                                          expires_at: 30.days.from_now)

      fourth = build_invoice
      assert fourth.issue!, -> { fourth.errors.full_messages.join(", ") }

      assert_predicate fourth.reload, :issued?
      assert_equal 9, pass.reload.remaining_uses   # 정확히 1건 소비 — 소비 지점 연결(이슈 #7)
      assert_equal 4, @user.invoices.where(issued_at: Time.current.beginning_of_month..).count
    end
  end

  test "한도 내 발행은 수금 패스를 소비하지 않는다 (이슈 #7 — 초과분만 차감)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      @user.create_subscription!(plan: :free)
      pass = @user.payment_passes.create!(total_uses: 10, remaining_uses: 10,
                                          expires_at: 30.days.from_now)

      3.times { issue_invoice! }

      assert_equal 10, pass.reload.remaining_uses  # 무료 3건 — 차감 없음
    end
  end

  test "소진된 패스는 한도 판정을 통과시키지 않아 발행이 거부된다 (이슈 #7)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      @user.create_subscription!(plan: :free)
      3.times { issue_invoice! }
      pass = @user.payment_passes.create!(total_uses: 10, remaining_uses: 0,
                                          expires_at: 30.days.from_now)

      fourth = build_invoice
      assert_not fourth.issue!

      assert_includes fourth.errors[:base].join, "Free 플랜은 매월 3건까지"
      assert_not fourth.persisted?                         # 발행 저장 없음(발행 전이 없음)
      assert_equal 0, pass.reload.remaining_uses
      assert_equal 3, @user.invoices.where(issued_at: Time.current.beginning_of_month..).count
    end
  end

  private

  def build_invoice
    Invoice.new(
      user: @user, client: @user.clients.first,
      due_on: Date.current + 30, tax_mode: :separate, withholding_enabled: false,
      issuer_display_name: @user.display_name.presence || "테스트발행자",
      bank_name: "국민은행", account_number: "123-45-678901", account_holder: "테스트예금주",
      items_attributes: { "0" => { description: "리뷰 수정 회귀 품목", quantity: "1",
                                   unit_price: "100000" } }
    )
  end

  def issue_invoice!
    invoice = build_invoice
    assert invoice.issue!, -> { invoice.errors.full_messages.join(", ") }
    invoice.reload
  end
end

# 이슈 #5 — GET은 CSRF 검증 대상이 아니므로 상태 변경(해지)이 GET 경로에 닿지 않는다.
class FPlanReviewFixHttpTest < ActionDispatch::IntegrationTest
  test "발급 토큰 없는 card_callback GET은 상태 변경 없이 흡수된다 (이슈 #5 — GET 해지 차단)" do
    sign_in_as users(:epsilon) # plus/active fixture
    subscription = users(:epsilon).subscription

    get card_callback_app_subscription_path

    assert_response :redirect
    assert_redirected_to app_billing_path
    assert_match(/발급 토큰/, flash[:alert])
    assert_predicate subscription.reload, :active? # 해지로 이어지지 않는다
    assert_predicate subscription, :plus?
  end
end
