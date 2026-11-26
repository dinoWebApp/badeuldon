require "test_helper"
require_relative "../../test_helpers/fake_portone_client"

# 수금 패스 구매(F-PLAN — PLAN-4/5) — PurchaseService 승인 확정. 포트원 API는 FakePortOneClient
# 주입으로 대체한다(실호출 금지). 이중 콜백 흡수(SEC 멱등 — 발급 정확히 1회), 승인 금액·결제 ID의
# 서버 원값 기준, 즉시 승인 채널 폴백(조회 확정)을 검증한다. with_lock 실스레드 경합은
# purchase_service_concurrency_test.rb.
# 시나리오 기준: _workspace/03_implementation.md §1·§3 (수금 패스 구매 플로우).
class Orders::PurchaseServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:gamma)   # 주문·패스 fixture가 없는 사용자 — fixture 오염 없이 1:1 검증
    @order = @user.orders.create!(product: :collection_pass, amount: 4_000,
                                  pg_order_id: "order-pass-test-1")
  end

  test "승인 확정(paymentToken)은 주문을 paid로 바꾸고 10건 패스를 발급한다 (PLAN-4)" do
    # 승인 응답은 실제 스펙대로 pgTxId·paidAt만(대역 기본값) — 확정은 승인 뒤 재조회한 결제 건으로
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-pass-test-1", amount: 4_000)
    )

    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      result = Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1",
                                           client: fake).call

      assert_equal @order.reload, result
      assert_predicate @order, :paid?
      assert_equal "order-pass-test-1", @order.pg_payment_id  # paymentId = 서버 채번 주문번호
      assert_equal Time.zone.parse("2026-10-15 09:00"), @order.paid_at
      # 결제 응답 스냅샷 — 승인 뒤 재조회한 전체 결제 건(검증 대상)이 저장된다
      assert_equal({ "id" => "order-pass-test-1", "status" => "PAID",
                     "amount" => { "paid" => 4_000 }, "channel" => { "type" => "TEST" },
                     "currency" => "KRW" },
                   @order.metadata)
      assert_equal 1, fake.calls[:get_payment].size           # 승인 성공 뒤 재조회 1회

      pass = @user.payment_passes.sole
      assert_equal 10, pass.total_uses
      assert_equal 10, pass.remaining_uses
      assert_equal Time.zone.parse("2027-01-13 09:00"), pass.expires_at  # 발급일 +90일
    end
  end

  # 콜백 경로 정정 회귀(2026-11-25) — 승인(confirm) 200 응답은 ConfirmedPaymentSummary로
  # pgTxId·paidAt만 담는다(금액·채널 없음). 이전 구현은 승인 응답으로 검증해 운영의 정상
  # 결제가 전부 검증 실패 → failed 처리될 뻔했다(대역의 응답 자동 보강이 결함을 가렸다).
  test "승인 응답(pgTxId·paidAt만)은 검증에 쓰지 않고 재조회한 결제 건으로 정상 확정한다" do
    # confirm_payment는 대역 기본값(실제 스펙 형태 — pgTxId·paidAt만)을 쓴다
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-pass-test-1", amount: 4_000)
    )

    result = Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1",
                                         client: fake).call

    assert_equal @order.reload, result                      # 예외 없이 정상 확정
    assert_predicate @order, :paid?
    assert_equal 1, @user.payment_passes.count
    assert_equal 1, fake.calls[:confirm_payment].size
    assert_equal 1, fake.calls[:get_payment].size           # 승인 성공 뒤 재조회 1회
    # 확정 응답(검증 대상·metadata 스냅샷)은 재조회한 전체 결제 건이다
    assert_equal({ "id" => "order-pass-test-1", "status" => "PAID",
                   "amount" => { "paid" => 4_000 }, "channel" => { "type" => "TEST" },
                   "currency" => "KRW" },
                 @order.metadata)
  end

  test "승인 요청은 주문 레코드의 결제 ID(paymentId)·위젯 토큰·검증값(금액·테스트 여부·통화)을 보낸다" do
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-pass-test-1", amount: 4_000)
    )

    Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1", client: fake).call

    # totalAmount = 주문 원값, isTest = 환경 기대값(test 환경은 live_channel? false → true),
    # currency = KRW 단건 고정(R2-4)
    assert_equal [ { payment_id: "order-pass-test-1", payment_token: "tok_widget_1",
                     store_id: nil, total_amount: 4_000, is_test: true, currency: "KRW" } ],
                 fake.calls[:confirm_payment]
  end

  test "즉시 승인 채널(paymentToken 없음)은 결제 조회로 승인 사실을 확정한다" do
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-pass-test-1", amount: 4_000)
    )

    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      result = Orders::PurchaseService.new(order: @order, payment_token: nil, client: fake).call

      assert_equal @order.reload, result
      assert_predicate @order, :paid?
      assert_equal 1, @user.payment_passes.count
    end

    # 승인 API 호출 없이 조회 한 번으로 확정한다
    assert_empty fake.calls[:confirm_payment]
    assert_equal [ { payment_id: "order-pass-test-1", store_id: nil } ],
                 fake.calls[:get_payment]
  end

  test "이미 처리된 주문의 재승인은 거부되고 패스가 추가 발급되지 않는다 (SEC 멱등)" do
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-pass-test-1", amount: 4_000)
    )
    Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1", client: fake).call

    error = assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order.reload, payment_token: "tok_widget_1",
                                  client: fake).call
    end

    assert_match(/이미 처리된 결제입니다/, error.message)
    assert_equal 1, @user.payment_passes.count              # 발급 정확히 1회
    assert_equal 1, @user.orders.count
  end

  test "명확한 승인 실패(PG 거절) 시 주문은 failed로 기록되고 PG 원문이 보존된다" do
    fake = FakePortOneClient.new(raise_on: { confirm_payment:
                            PortOne::ApiError.new(status: 400, code: "PG_PROVIDER_ERROR",
                                                  message: "PG사 처리 중 오류가 발생했습니다",
                                                  pg_code: "F1001", pg_message: "카드 한도 초과") })

    error = assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_bad", client: fake).call
    end

    assert_match(/결제 승인에 실패했습니다/, error.message)
    order = @order.reload
    assert_predicate order, :failed?
    assert_equal({ "code" => "PG_PROVIDER_ERROR", "message" => "PG사 처리 중 오류가 발생했습니다",
                   "pg_code" => "F1001", "pg_message" => "카드 한도 초과" }, order.metadata)
    assert_nil order.pg_payment_id                           # 승인 확정 전이라 미기록
    assert_empty @user.payment_passes
  end

  test "모호 실패(타임아웃) 후 재확인 PAID면 정상 발급 경로로 합류한다 (이슈 #1)" do
    fake = FakePortOneClient.new(
      raise_on: { confirm_payment:
                  PortOne::ApiError.new(status: nil, code: "TIMEOUT", message: "응답 시간 초과") },
      get_payment: FakePortOneClient.paid_payment(id: "order-pass-test-1", amount: 4_000)
    )

    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      result = Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1",
                                           client: fake).call

      assert_equal @order.reload, result                    # 예외 없이 정상 확정
      assert_predicate @order, :paid?
      assert_equal 1, @user.payment_passes.count
    end
  end

  test "모호 실패 후 미승인(READY)이면 pending·paymentId 보존으로 회복을 연다 (이슈 #1)" do
    fake = FakePortOneClient.new(
      raise_on: { confirm_payment:
                  PortOne::ApiError.new(status: nil, code: "TIMEOUT", message: "응답 시간 초과") },
      get_payment: { id: "order-pass-test-1", status: "READY" }
    )

    error = assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1", client: fake).call
    end

    assert_match(/결제 확인이 지연되고 있습니다/, error.message)
    order = @order.reload
    assert_predicate order, :pending?                       # failed 확정 금지 — 이중 결제 방지
    assert_equal "order-pass-test-1", order.pg_payment_id   # 웹훅 회복 대상 식별키 보존
    assert_predicate order.metadata["pending_recovery"], :present?
    assert_empty @user.payment_passes
  end

  # 콜백 경로 정정 회귀(2026-11-25) — 승인은 성공했는데 그 뒤 재조회가 실패하면 결제가 이미
  # 성립했을 수 있다. failed 확정 없이 pending 유지로 웹훅 회복을 열어야 한다(이중 결제 방지).
  test "승인은 성공하고 재조회가 실패하면 failed가 아닌 pending 유지로 웹훅 회복을 연다" do
    fake = FakePortOneClient.new(
      raise_on: { get_payment:
                  PortOne::ApiError.new(status: nil, code: "TIMEOUT", message: "응답 시간 초과") }
    )

    error = assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1", client: fake).call
    end

    assert_match(/결제 확인이 지연되고 있습니다/, error.message)
    order = @order.reload
    assert_predicate order, :pending?                       # 승인이 성립했을 수 있으므로 failed 금지
    assert_equal "order-pass-test-1", order.pg_payment_id   # 웹훅 회복 대상 식별키 보존
    assert_predicate order.metadata["pending_recovery"], :present?
    assert_equal "TIMEOUT", order.metadata["code"]          # 재조회 실패 원문 보존
    assert_empty @user.payment_passes
    assert_equal 1, fake.calls[:confirm_payment].size       # 승인 자체는 1회 성공
    assert_equal 1, fake.calls[:get_payment].size           # 재조회 1회 실패 — 재시도 없음
  end

  # B-1 회귀(F-LEGAL Phase 6) — legal_doc 주문은 metadata["invoice_id"]가 청구 역참조의
  # 유일 경로다. 모호 실패·명확 실패 경로도 기존 metadata를 병합해 보존해야 한다.
  test "모호 실패(회복 대기)도 legal_doc 주문의 metadata.invoice_id를 보존한다 (B-1)" do
    legal_order = @user.orders.create!(product: :collection_pass, item_type: :legal_doc,
                                       amount: Order::LEGAL_DOC_PRICE,
                                       pg_order_id: "order-legal-pending-1",
                                       metadata: { invoice_id: 123 })
    fake = FakePortOneClient.new(
      raise_on: { confirm_payment:
                  PortOne::ApiError.new(status: nil, code: "TIMEOUT", message: "응답 시간 초과") },
      get_payment: { id: "order-legal-pending-1", status: "READY" }
    )

    assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: legal_order, payment_token: "tok_widget_1",
                                  client: fake).call
    end

    order = legal_order.reload
    assert_predicate order, :pending?
    assert_equal 123, order.metadata["invoice_id"]
    assert_predicate order.metadata["pending_recovery"], :present?
  end

  test "명확한 승인 실패도 legal_doc 주문의 metadata.invoice_id를 보존한다 (B-1)" do
    legal_order = @user.orders.create!(product: :collection_pass, item_type: :legal_doc,
                                       amount: Order::LEGAL_DOC_PRICE,
                                       pg_order_id: "order-legal-failed-1",
                                       metadata: { invoice_id: 456 })
    fake = FakePortOneClient.new(raise_on: { confirm_payment:
                            PortOne::ApiError.new(status: 400, code: "PG_PROVIDER_ERROR",
                                                  message: "PG사 처리 중 오류가 발생했습니다",
                                                  pg_code: "F1001", pg_message: "카드 한도 초과") })

    assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: legal_order, payment_token: "tok_widget_bad",
                                  client: fake).call
    end

    order = legal_order.reload
    assert_predicate order, :failed?
    assert_equal 456, order.metadata["invoice_id"]
    assert_equal "PG_PROVIDER_ERROR", order.metadata["code"]
  end

  test "결제 확정은 legal_doc 주문의 metadata.invoice_id를 결제 응답과 병합해 보존한다 (B-1)" do
    legal_order = @user.orders.create!(product: :collection_pass, item_type: :legal_doc,
                                       amount: Order::LEGAL_DOC_PRICE,
                                       pg_order_id: "order-legal-paid-1",
                                       metadata: { invoice_id: 789 })
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-legal-paid-1",
                                                  amount: Order::LEGAL_DOC_PRICE)
    )

    Orders::PurchaseService.new(order: legal_order, payment_token: "tok_widget_1",
                                client: fake).call

    order = legal_order.reload
    assert_predicate order, :paid?
    assert_equal 789, order.metadata["invoice_id"]
    assert_equal "PAID", order.metadata["status"]
  end

  # ── PLAN-5 결제 확정 검증(재리뷰 R-1·R-2·R2-1·R2-4 — Tester 단계 고정) ──
  # 대역의 승인 응답은 스펙대로 pgTxId·paidAt만 돌려주고, 검증 대상은 승인 뒤 재조회한
  # 전체 결제 건이다(콜백 경로 정정 2026-11-25). 검증 실패는 모호 실패가 아니라 결정적
  # 불일치라 failed 확정·문의 안내가 정답이고, 승인 뒤 재조회 실패(조회 오류·미승인)는
  # pending 유지로 웹훅 회복을 연다(실패 확정 금지).

  test "재조회 결제 금액이 주문과 다르면 PurchaseError로 안내하고 주문을 failed로 확정한다 (PLAN-5·R-1)" do
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-pass-test-1", amount: 100)
    )

    error = assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1", client: fake).call
    end

    assert_equal "결제 확인에 실패했습니다. 고객지원(문의)으로 연락해 주세요.", error.message
    assert_not_includes error.message, "100"                     # 내부 값(금액) 미노출
    assert_not_includes error.message, "amount_mismatch"         # 내부 사유 코드 미노출
    order = @order.reload
    assert_predicate order, :failed?
    assert_nil order.paid_at
    assert_predicate order, :verification_failed?
    assert_equal Order::VERIFICATION_FAILED_CODE, order.metadata["code"]
    assert_equal Order::VERIFICATION_FAILED_MESSAGE, order.metadata["message"]
    assert_equal "amount_mismatch", order.metadata.dig("verification", "reason")
    assert_equal "order-pass-test-1", order.pg_payment_id        # 결제 ID 스냅샷 보존(R2-5)
    assert_empty @user.payment_passes                            # 패스 발급 없음
    assert_equal 1, fake.calls[:confirm_payment].size            # 승인 1회 — 재시도 루프 없음
    assert_equal 1, fake.calls[:get_payment].size                # 재조회 1회로 거절 확정
  end

  test "재조회 결제 채널이 LIVE면(비운영 기대) channel_mismatch로 failed 확정한다 (PLAN-5·R-2)" do
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-pass-test-1", amount: 4_000,
                                                  live: true) # 운영 채널 결제를 비운영에 통과 시도
    )

    assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1", client: fake).call
    end

    order = @order.reload
    assert_predicate order, :failed?
    assert_equal "channel_mismatch", order.metadata.dig("verification", "reason")
    assert_empty @user.payment_passes
  end

  test "재조회 결제 통화가 USD면 currency_mismatch로 failed 확정한다 (R2-4)" do
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-pass-test-1", amount: 4_000,
                                                  currency: "USD")
    )

    assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1", client: fake).call
    end

    order = @order.reload
    assert_predicate order, :failed?
    assert_equal "currency_mismatch", order.metadata.dig("verification", "reason")
    assert_empty @user.payment_passes
  end

  test "즉시 승인 채널(토큰 없음)의 재조회도 검증 실패면 failed 확정한다 — 전 경로가 확정점을 지난다" do
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-pass-test-1", amount: 500)
    )

    assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order, payment_token: nil, client: fake).call
    end

    order = @order.reload
    assert_predicate order, :failed?
    assert_predicate order, :verification_failed?
    assert_empty @user.payment_passes
    assert_empty fake.calls[:confirm_payment]                    # 토큰 없음 — 승인 요청 없음
  end

  test "모호 실패(TIMEOUT) 회복 재조회가 검증 실패면 pending 회복이 아니라 failed 확정이다 (R-1)" do
    fake = FakePortOneClient.new(
      raise_on: { confirm_payment: PortOne::ApiError.new(status: nil, code: "TIMEOUT",
                                                         message: "응답 시간 초과") },
      get_payment: FakePortOneClient.paid_payment(id: "order-pass-test-1", amount: 100)
    )

    error = assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1", client: fake).call
    end

    assert_equal "결제 확인에 실패했습니다. 고객지원(문의)으로 연락해 주세요.", error.message
    order = @order.reload
    assert_predicate order, :failed?
    assert_not_predicate order.metadata["pending_recovery"], :present? # 회복 대상 아님 — 검증 거절
    assert_equal "amount_mismatch", order.metadata.dig("verification", "reason")
    assert_empty @user.payment_passes
  end

  test "ALREADY_PAID 회복 재조회도 검증 실패면 failed 확정한다 (이슈 C1 경계)" do
    fake = FakePortOneClient.new(
      raise_on: { confirm_payment: PortOne::ApiError.new(status: 400, code: "ALREADY_PAID",
                                                         message: "이미 승인된 결제입니다") },
      get_payment: FakePortOneClient.paid_payment(id: "order-pass-test-1", amount: 300)
    )

    assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1", client: fake).call
    end

    order = @order.reload
    assert_predicate order, :failed?
    assert_equal "amount_mismatch", order.metadata.dig("verification", "reason")
    assert_empty @user.payment_passes
  end

  test "승인 성공 뒤 재조회가 PAID가 아니면 failed 확정 없이 pending 유지로 웹훅 회복을 연다 (콜백 정정)" do
    fake = FakePortOneClient.new(
      get_payment: { id: "order-pass-test-1", status: "PAY_PENDING" } # 아직 승인 전 — 조회 성공
    )

    error = assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_1", client: fake).call
    end

    assert_match(/결제 확인이 지연되고 있습니다/, error.message)
    order = @order.reload
    assert_predicate order, :pending?                            # 실패 확정 금지 — 이중 결제 방지
    assert_not_predicate order, :verification_failed?
    assert_equal "order-pass-test-1", order.pg_payment_id
    assert_predicate order.metadata["pending_recovery"], :present?
    assert_empty @user.payment_passes
    assert_equal 1, fake.calls[:confirm_payment].size
    assert_equal 1, fake.calls[:get_payment].size                # 재시도 없음
  end

  test "승인 요청 자체의 명확한 거부는 검증 실패 코드를 남기지 않는다 (record_failure! 경로와 구분)" do
    fake = FakePortOneClient.new(
      raise_on: { confirm_payment: PortOne::ApiError.new(status: 400, code: "PG_PROVIDER_ERROR",
                                                         message: "카드 한도 초과") }
    )

    assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: @order, payment_token: "tok_widget_bad", client: fake).call
    end

    order = @order.reload
    assert_predicate order, :failed?
    assert_not_predicate order, :verification_failed?
    assert_nil order.metadata["verification"]                    # 검증 실패 기록 아님 — PG 거절
    assert_equal "PG_PROVIDER_ERROR", order.metadata["code"]
    assert_nil order.pg_payment_id
    assert_empty @user.payment_passes
  end

  test "legal_doc 주문의 검증 실패 기록도 metadata.invoice_id를 보존한다 (B-1 병합)" do
    legal_order = @user.orders.create!(product: :collection_pass, item_type: :legal_doc,
                                       amount: Order::LEGAL_DOC_PRICE,
                                       pg_order_id: "order-legal-verify-1",
                                       metadata: { invoice_id: 789 })
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-legal-verify-1",
                                                  amount: Order::LEGAL_DOC_PRICE - 4_900)
    )

    assert_raises(Orders::PurchaseService::PurchaseError) do
      Orders::PurchaseService.new(order: legal_order, payment_token: "tok_widget_1",
                                  client: fake).call
    end

    order = legal_order.reload
    assert_predicate order, :failed?
    assert_predicate order, :verification_failed?
    assert_equal 789, order.metadata["invoice_id"]               # 청구 역참조 보존 — B-1
    assert_equal Order::VERIFICATION_FAILED_CODE, order.metadata["code"]
  end

  test "세금계산서 주문도 검증 통과 시 paid 확정이고 패스는 발급되지 않는다 (TAX-1·PLAN-5)" do
    tax_order = @user.orders.create!(product: :collection_pass, item_type: :tax_invoice,
                                     amount: 300, pg_order_id: "order-tax-purchase-1",
                                     metadata: { invoice_id: 999_999 }) # 실존하지 않는 청구 — 발행 단계는 전제 밖
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: "order-tax-purchase-1", amount: 300)
    )

    result = Orders::PurchaseService.new(order: tax_order, payment_token: "tok_widget_1",
                                         client: fake).call

    assert_equal tax_order.reload, result
    assert_predicate tax_order, :paid?
    assert_not_nil tax_order.paid_at
    assert_equal 300, tax_order.metadata.dig("amount", "paid")   # 재조회 결제 건 스냅샷
    assert_empty @user.payment_passes                            # 세금계산서 주문은 발급물 없음
    assert_equal 1, fake.calls[:confirm_payment].size
    assert_equal [ { payment_id: "order-tax-purchase-1", payment_token: "tok_widget_1",
                     store_id: nil, total_amount: 300, is_test: true, currency: "KRW" } ],
                 fake.calls[:confirm_payment]                    # 검증값(원값·환경 기대·KRW) 전달
  end
end
