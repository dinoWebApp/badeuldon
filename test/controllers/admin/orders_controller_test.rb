require "test_helper"

# ADMIN-4 — 결제·매출 관리 컨트롤러(Run B). 시나리오 기준: 05_review.md §4 제안 1·2 —
# ① B-1 환불 폼 E2E 회귀(최우선): 폼이 생성하는 페이로드 `order: { refund_reason }` PATCH →
#   303 + refunded? + order_refund 감사 1건(B-1에서 최상위 refund_reason은 400이었다),
# ② 이중 기록 422·감사 미기록, ③ blank 사유 422(W-1 — 500 금지)·감사 미기록,
# ④ index 필터(status·refund 화이트리스트 — 비화이트리스트 무시), ⑤ 비인증·U1 세션 차단.
class Admin::OrdersControllerTest < ActionDispatch::IntegrationTest
  setup { setup_admin_totp_secrets }

  # ── B-1 환불 폼 E2E 회귀(최우선) ──

  test "환불 폼과 동일 페이로드(order[refund_reason]) PATCH는 303·기록·감사 1건이다 (B-1 회귀)" do
    admin_login(admins(:ops))
    order = orders(:delta_pass_order)

      # app/views/admin/orders/show.html.erb 폼이 실제 생성하는 네임스페이스 — B-1 수정 계약
      assert_difference -> { AuditLog.where(action: "order_refund").count }, +1 do
        patch mark_refunded_admin_order_path(order),
              params: { order: { refund_reason: "이중 결제 정정" } }
      end

    assert_response :see_other
    assert_redirected_to admin_order_path(order)
    assert order.reload.refunded?
    assert_equal "이중 결제 정정", order.refund_reason
  end

  test "이미 환불 기록된 건의 재요청은 422이고 감사를 추가로 남기지 않는다 (이중 기록 차단)" do
    admin_login(admins(:ops))
    order = orders(:delta_pass_order)
    order.mark_refunded!("첫 기록")

    assert_no_difference -> { AuditLog.where(action: "order_refund").count } do
      patch mark_refunded_admin_order_path(order),
            params: { order: { refund_reason: "두 번째 시도" } }
    end

    assert_response :unprocessable_entity
    assert_equal "첫 기록", order.reload.refund_reason, "사유가 덮어써지지 않는다"
  end

  test "blank 사유 요청은 422이고 감사를 남기지 않는다 (W-1 — 500 금지)" do
    admin_login(admins(:ops))
    order = orders(:delta_pass_order)

    patch mark_refunded_admin_order_path(order), params: { order: { refund_reason: "" } }

    assert_response :unprocessable_entity
    assert_includes response.body, "환불 사유는 필수입니다"
    assert_not order.reload.refunded?, "데이터 오염 없음"
    assert_equal 0, AuditLog.where(action: "order_refund").count, "실패는 감사 미기록"
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
end
