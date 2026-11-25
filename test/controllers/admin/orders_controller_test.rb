require "test_helper"
require_relative "../../test_helpers/portone_stubbing"
require_relative "../../test_helpers/fake_portone_client"

# ADMIN-4·11 — 결제·매출 관리 컨트롤러. 시나리오 기준: 05_review.md §4 제안 1·2 —
# ① B-1 환불 폼 E2E 회귀(최우선): 폼이 생성하는 페이로드 `order: { refund_reason }` PATCH →
#   303 + refunded? + order_refund 감사 1건(B-1에서 최상위 refund_reason은 400이었다),
# ② 이중 기록 422·감사 미기록, ③ blank 사유 422(W-1 — 500 금지)·감사 미기록,
# ④ index 필터(status·refund 화이트리스트 — 비화이트리스트 무시), ⑤ 비인증·U1 세션 차단.
# ADMIN-11 전환(2026-11-24) — 기록 전용 mark_refunded는 refund 실행 경로로 대체됐다
# (PLAN-9 — 실제 PG 취소 포함, 외부 호출은 FakePortOneClient 대역으로 차단).
class Admin::OrdersControllerTest < ActionDispatch::IntegrationTest
  include PortOneStubbing
  setup { setup_admin_totp_secrets }

  # ── B-1 환불 폼 E2E 회귀(최우선) ──

  test "환불 폼과 동일 페이로드(order[refund_reason]) PATCH는 303·실행·감사 1건이다 (B-1 회귀)" do
    admin_login(admins(:ops))
    order = orders(:delta_pass_order)
    fake = FakePortOneClient.new(
      get_payment: { id: order.pg_order_id, status: "CANCELLED",
                     amount: { paid: order.amount, cancelled: order.amount } }
    )

    # app/views/admin/orders/show.html.erb 폼이 실제 생성하는 네임스페이스 — B-1 수정 계약
    assert_difference -> { AuditLog.where(action: "order_refund").count }, +1 do
      with_portone_client(fake) do
        patch refund_admin_order_path(order),
              params: { order: { refund_reason: "이중 결제 정정" } }
      end
    end

    assert_response :see_other
    assert_redirected_to admin_order_path(order)
    assert order.reload.refunded?
    assert_equal "이중 결제 정정", order.refund_reason
    assert_equal "cancelled", order.status, "환불 실행으로 결제 취소 상태가 된다(PLAN-9)"
  end

  test "이미 환불 처리된 건의 재요청은 422이고 감사를 추가로 남기지 않는다 (이중 기록 차단)" do
    admin_login(admins(:ops))
    order = orders(:delta_pass_order)
    order.mark_refunded!("첫 기록")
    # PG 호출 금지 보증 — 사전 가드가 걸어야 하므로 호출 시 즉시 실패하는 대역을 둔다.
    fake = FakePortOneClient.new(raise_on: { cancel_payment: StandardError.new("PG 호출 금지") })

    assert_no_difference -> { AuditLog.where(action: "order_refund").count } do
      with_portone_client(fake) do
        patch refund_admin_order_path(order),
              params: { order: { refund_reason: "두 번째 시도" } }
      end
    end

    assert_response :unprocessable_entity
    assert_equal "첫 기록", order.reload.refund_reason, "사유가 덮어써지지 않는다"
  end

  test "blank 사유 요청은 422이고 감사를 남기지 않는다 (W-1 — 500 금지)" do
    admin_login(admins(:ops))
    order = orders(:delta_pass_order)
    fake = FakePortOneClient.new(raise_on: { cancel_payment: StandardError.new("PG 호출 금지") })

    with_portone_client(fake) do
      patch refund_admin_order_path(order), params: { order: { refund_reason: "" } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "환불 사유는 필수입니다"
    assert_not order.reload.refunded?, "데이터 오염 없음"
    assert_equal 0, AuditLog.where(action: "order_refund").count, "실패는 감사 미기록"
  end

  # ── ADMIN-11 실행 결과 응답·권한(PLAN-9) ──

  test "owner의 환불 실행 성공은 303과 flash 요약을 돌려준다 (ADMIN-11·PLAN-9)" do
    admin_login(admins(:ops))
    order = orders(:delta_pass_order)
    fake = FakePortOneClient.new(get_payment: cancelled_payment_for(order))

    with_portone_client(fake) do
      patch refund_admin_order_path(order),
            params: { order: { refund_reason: "이중 결제 정정" } }
    end

    assert_response :see_other
    assert_redirected_to admin_order_path(order)
    assert_match "환불을 실행했습니다", flash[:notice]
    assert_match "수금 패스 10건 차감", flash[:notice], "flash에 상품별 되돌리기 요약이 포함된다"
  end

  test "PG 실패 대역은 422와 alert으로 응답하고 500이 아니다 (W-1)" do
    admin_login(admins(:ops))
    order = orders(:delta_pass_order)
    fake = FakePortOneClient.new(
      raise_on: { get_payment: PortOne::ApiError.new(status: 503, code: "INTERNAL_SERVER_ERROR",
                                                     message: "재조회 실패") }
    )

    with_portone_client(fake) do
      patch refund_admin_order_path(order),
            params: { order: { refund_reason: "이중 결제 정정" } }
    end

    assert_response :unprocessable_entity
    assert_match "포트원 API 오류로 취소를 확정하지 못했습니다", response.body
    assert_predicate order.reload, :paid?, "로컬 무변경"
  end

  test "staff의 refund 직접 요청은 거부·감사되고 PG 호출·로컬 변경이 없다 (ADMIN-1·ADMIN-11)" do
    admin_login(admins(:staffuser))
    order = orders(:delta_pass_order)
    fake = FakePortOneClient.new(raise_on: { cancel_payment: StandardError.new("PG 호출 금지") })

    assert_difference -> { AuditLog.where(action: "admin_console_denied", admin_id: admins(:staffuser).id).count }, +1 do
      with_portone_client(fake) do
        patch refund_admin_order_path(order),
              params: { order: { refund_reason: "staff 시도" } }
      end
    end

    assert_redirected_to admin_root_path
    assert_match "최고 관리자(owner)만", flash[:alert]
    assert_empty fake.calls.values.flatten, "staff는 PG 취소를 실행할 수 없다"
    assert_predicate order.reload, :paid?
    assert_not order.refunded?
    assert_equal 0, AuditLog.where(action: "order_refund", target_type: "Order", target_id: order.id).count
  end

  test "staff 상세에는 실행 폼이 없고 owner 상세에는 있다 (ADMIN-11)" do
    admin_login(admins(:staffuser))
    get admin_order_path(orders(:delta_pass_order))
    assert_response :success
    assert_match "환불 실행은 최고 관리자(owner)만", response.body
    assert_no_match "order[refund_reason]", response.body, "staff에게 폼을 노출하지 않는다"

    admin_login(admins(:ops), at: Time.current + 40.seconds) # TOTP after: 재사용 차단 회피
    get admin_order_path(orders(:delta_pass_order))
    assert_response :success
    assert_match "order[refund_reason]", response.body
  end

  # ── ADMIN-11 상세 화면 분기(W-5) ──

  test "환불 완료 실행 건 상세는 실행자·금액·완료 문구를 표시하고 폼이 없다 (ADMIN-11)" do
    admin_login(admins(:ops))
    order = orders(:delta_pass_order)
    execute_refund(order)

    get admin_order_path(order)

    assert_response :success
    assert_match "환불이 완료된 주문입니다", response.body
    assert_match "ops@example.com", response.body, "실행자 표기"
    assert_match "4,000₩", response.body, "환불 금액 표기"
    assert_no_match "order[refund_reason]", response.body, "완료 건에는 폼이 없다"
  end

  test "과거 기록 전용 건(레거시) 상세는 기록 전용 문구를 표시하고 완료 문구가 없다 (W-5e)" do
    admin_login(admins(:ops))
    order = orders(:delta_pass_order)
    order.mark_refunded!("레거시 기록 전용") # refunded_at만 있고 metadata["refund"]는 없음

    get admin_order_path(order)

    assert_response :success
    assert_match "과거 기록 전용 방식으로 기록된 주문입니다", response.body
    assert_no_match "완료되었습니다", response.body, "실행 건 문구를 레거시 건에 쓰지 않는다"
    assert_no_match "order[refund_reason]", response.body
  end

  test "콘솔 선취소 건(cancelled·refunded_at 없음) 상세는 정산 안내와 실행 폼을 보여준다 (ADMIN-11)" do
    admin_login(admins(:ops))
    order = orders(:delta_pass_order)
    order.update!(status: :cancelled) # 포트원 콘솔 선취소 — 웹훅이 상태만 동기화한 상태

    get admin_order_path(order)

    assert_response :success
    assert_match "포트원에서 이미 취소된 결제입니다", response.body
    assert_match "order[refund_reason]", response.body, "정산 완료를 위한 같은 폼 노출"
  end

  test "결제 완료 적 없는 건(pending·failed)에는 실행 폼이 없다 (ADMIN-11)" do
    admin_login(admins(:ops))
    pending_order = users(:delta).orders.create!(product: :collection_pass, item_type: :pass,
                                                 amount: 4_000,
                                                 pg_order_id: "order-view-pending")
    failed_order = users(:delta).orders.create!(product: :collection_pass, item_type: :pass,
                                                amount: 4_000, status: :failed,
                                                pg_order_id: "order-view-failed")

    get admin_order_path(pending_order)
    assert_response :success
    assert_match "결제가 완료된 적이 없어 환불할 수 없습니다", response.body
    assert_no_match "order[refund_reason]", response.body

    get admin_order_path(failed_order)
    assert_response :success
    assert_match "결제가 완료된 적이 없어 환불할 수 없습니다", response.body
    assert_no_match "order[refund_reason]", response.body
  end

  test "실행 중 서비스 예외는 500이 아니라 422 안내로 흡수된다 (W-1 안전망)" do
    admin_login(admins(:ops))
    order = orders(:delta_pass_order)

    with_refund_service_raising(StandardError.new("boom")) do
      patch refund_admin_order_path(order),
            params: { order: { refund_reason: "이중 결제 정정" } }
    end

    assert_response :unprocessable_entity
    assert_match "환불 실행 중 오류가 발생했습니다", response.body
    assert_predicate order.reload, :paid?
  end

  # ── 목록·상세 ──

  test "index는 목록·플랜 분포·체험 만료 예정 섹션을 렌더한다 (ADMIN-4)" do
    admin_login(admins(:ops))

    get admin_orders_path

    assert_response :success
    assert_match "delta@example.com", response.body
    assert_match "환불", response.body # 환불 필터 UI 존재
  end

  test "index 필터는 status·refund 화이트리스트만 적용하고 비화이트리스트는 무시한다 (ADMIN-4)" do
    admin_login(admins(:ops))

    get admin_orders_path, params: { status: "paid", refund: "not_refunded" }
    assert_response :success
    assert_match "delta@example.com", response.body

    get admin_orders_path, params: { refund: "refunded" }
    assert_response :success
    assert_no_match "delta@example.com", response.body, "환불 기록 없음 — 목록에서 제외"

    # SQL 주입성 문자열·무효 enum — 무시되어 전체 목록(500 없음)
    get admin_orders_path, params: { status: "DROP TABLE orders", refund: "ZZZ" }
    assert_response :success
    assert_match "delta@example.com", response.body
  end

  test "show는 주문 상세를 렌더한다 (ADMIN-4)" do
    admin_login(admins(:ops))

    get admin_order_path(orders(:delta_pass_order))

    assert_response :success
    assert_match "delta@example.com", response.body
  end

  test "index 상태 필터 cancelled과 환불 필터가 동작하고 환불됨 표기를 한다 (ADMIN-4·11)" do
    admin_login(admins(:ops))
    order = orders(:delta_pass_order)
    execute_refund(order)

    get admin_orders_path, params: { status: "cancelled" }
    assert_response :success
    assert_match "delta@example.com", response.body, "취소·환불 상태 필터에 환불 실행 건이 포함된다"
    assert_match "환불됨", response.body

    get admin_orders_path, params: { refund: "refunded" }
    assert_response :success
    assert_match "delta@example.com", response.body

    get admin_orders_path, params: { refund: "not_refunded" }
    assert_response :success
    assert_no_match "delta@example.com", response.body, "환불된 건은 미환불 필터에서 제외된다"
  end

  # ── 접근 제어 ──

  test "비인증 접근은 관리자 로그인으로 리다이렉트된다 (표면 격리)" do
    get admin_orders_path
    assert_redirected_to new_admin_session_url
  end

  test "U1 세션으로는 진입할 수 없다 (표면 격리)" do
    sign_in_as users(:alpha)

    get admin_orders_path

    assert_redirected_to new_admin_session_url
    assert_equal 0, AdminSession.count
  end

  private

  # 전액 취소 확정 응답 — 컨트롤러 계약(서비스가 기본 클라이언트를 만드는 경로)에 맞춘 대역.
  def cancelled_payment_for(order)
    { id: order.pg_order_id, status: "CANCELLED",
      amount: { paid: order.amount, cancelled: order.amount } }
  end

  # 실제 실행 경로로 환불 완료 상태를 만든다(대역 주입 — 실호출 0).
  def execute_refund(order)
    fake = FakePortOneClient.new(get_payment: cancelled_payment_for(order))
    with_portone_client(fake) do
      result = Orders::RefundService.new(admin: admins(:ops), order: order,
                                         reason: "이중 결제 정정").call
      assert result.success?, "전제: 환불 실행이 성공해야 한다"
    end
    order.reload
  end

  def with_refund_service_raising(exception)
    original = Orders::RefundService.method(:new)
    Orders::RefundService.define_singleton_method(:new) do |*|
      Object.new.tap { |instance| instance.define_singleton_method(:call) { raise exception } }
    end
    yield
  ensure
    Orders::RefundService.define_singleton_method(:new, original)
  end
end
