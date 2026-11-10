require "test_helper"

# ADMIN-1·5 — 관리자 대시보드 컨트롤러(Run B). 시나리오 기준: 05_review.md §3·4 제안 6 —
# ① 관리자 로그인 200·핵심 섹션 렌더, ② 지표 수치를 시드로 검증 —
#   MRR = active Plus × 9,900(cancelled 제외)·당월 매출은 환불 기록 주문 제외(ADMIN-4·3-S),
#   북극성 = 발행 후 30일 내 수금 완료율(마감 0건 "-"). 쿼리 수학 자체는
#   test/queries/admins/ 5종이 계약 고정하며 여기선 렌더 정합을 검증한다.
class Admin::DashboardsControllerTest < ActionDispatch::IntegrationTest
  setup { setup_admin_totp_secrets }

  test "관리자 로그인 상태에서 대시보드가 핵심 섹션과 함께 렌더된다 (ADMIN-1)" do
    admin_login(admins(:ops))

    get admin_root_path

    assert_response :success
    assert_match "운영", response.body
    assert_match "MRR", response.body
    assert_match "매출", response.body
  end

  test "MRR은 active Plus 인원 × 9,900으로 렌더되고 cancelled는 제외된다 (ADMIN-5·PLAN-2)" do
    seed_empty_domain
    admin_login(admins(:ops))
      active_plus = User.create!(email: "dash-plus@example.com", password: "password")
      active_plus.subscription.update!(plan: :plus, status: :active)
      cancelled_plus = User.create!(email: "dash-cancel@example.com", password: "password")
      cancelled_plus.subscription.update!(plan: :plus, status: :cancelled)

      get admin_root_path

    assert_response :success
    assert_match "9,900", response.body, "active Plus 1명 — 9,900₩ (cancelled 1명 제외)"
  end

  test "당월 매출은 환불 기록 주문 제외가 렌더에 반영된다 (ADMIN-4·3-S)" do
    seed_empty_domain
    admin_login(admins(:ops))
    buyer = User.create!(email: "dash-rev@example.com", password: "password")
    order_a = buyer.orders.create!(product: :plus_monthly, amount: 9_900,
                                   pg_order_id: "order-dash-rev", status: :paid,
                                   paid_at: Time.current - 2.weeks)
    order_b = buyer.orders.create!(product: :collection_pass, amount: 4_000,
                                   pg_order_id: "order-dash-rev2", status: :paid,
                                   paid_at: Time.current - 1.week)

    get admin_root_path
    assert_response :success
    assert_match "13,900", response.body, "환불 전 당월 매출 9,900 + 4,000 렌더"

    order_a.mark_refunded!("이중 결제 정정")
    get admin_root_path

    assert_response :success
    assert_no_match "13,900", response.body, "환불 기록 주문 제외 — 4,000만 잔존"
    # 쿼리 수학 계약은 RevenueStatsQueryTest가 고정하며 여기선 렌더 정합만 검증한다.
  end

  test "북극성은 30일 내 마감 비율로 렌더되고 마감 0건은 '-'이다 (ADMIN-5·리뷰 제안 6)" do
    seed_empty_domain
    admin_login(admins(:ops))
    owner = User.create!(email: "dash-ns@example.com", password: "password")
    client = owner.clients.create!(name: "대시상사", contact_name: "김대시", phone: "010-5555-6666")
    fast = seed_paid_invoice(owner, client, "dash-fast", 5.days.ago)
    Payment.create!(invoice: fast, amount: 100_000, paid_on: Date.current) # 발행 +5일 — 30일 이내

    get admin_root_path
    assert_response :success
    assert_match "100.0", response.body, "30일 내 마감 1건 — 100.0%"

    Payment.destroy_all
    get admin_root_path
    assert_response :success
    assert_no_match "100.0", response.body, "마감 0건 — 북극성 '-' 표기(비율 렌더 소멸)"
  end

  test "비인증 접근은 관리자 로그인으로 리다이렉트된다 (표면 격리)" do
    get admin_root_path
    assert_redirected_to new_admin_session_url
  end

  private

  # 다른 테스트 파일의 fixture·시드와 독립된 델타 판정을 위해 플랜·매출 도메인을 비운다.
  def seed_empty_domain
    clear_domain_tables
    User.delete_all
  end

  def seed_paid_invoice(user, client, label, issued_at)
    user.invoices.create!(
      client: client, due_on: Date.current + 10, status: :paid,
      tax_mode: :separate, withholding_enabled: false,
      issuer_display_name: "테스트발행자",
      bank_name: "국민은행", account_number: "123-45-678901", account_holder: "테스트",
      issue_number: "BD-20990101-#{label}", token: SecureRandom.urlsafe_base64(32),
      issued_at: issued_at,
      items_attributes: { "0" => { description: "시드 품목", quantity: "1", unit_price: "100000" } }
    ).reload
  end
end
