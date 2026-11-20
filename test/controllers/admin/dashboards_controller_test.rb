require "test_helper"
require_relative "../../test_helpers/solapi_stubbing"

# ADMIN-1·5 — 관리자 대시보드 컨트롤러(Run B). 시나리오 기준: 05_review.md §3·4 제안 6 —
# ① 관리자 로그인 200·핵심 섹션 렌더, ② 지표 수치를 시드로 검증 —
#   MRR = active Plus × 9,900(cancelled 제외)·당월 매출은 환불 기록 주문 제외(ADMIN-4·3-S),
#   북극성 = 발행 후 30일 내 수금 완료율(마감 0건 "-"). 쿼리 수학 자체는
#   test/queries/admins/ 5종이 계약 고정하며 여기선 렌더 정합을 검증한다.
# T4(2026-11-20) — 솔라피 잔액(ADMIN-5·REM-10) 표시·캐시·fallback 추가. 대시보드 렌더가
# load_solapi_balance로 래퍼를 직접 생성하므로(C-1 — 05_review) 모든 렌더 요청은
# with_solapi_balance로 생성자를 대역화한다(AGENTS 테스트 전략 — 외부 API 실호출 금지).
class FakeSolapiBalanceClient
  attr_reader :get_balance_calls

  def initialize(balance: { balance: 1_000_000, point: 0 }, error: nil)
    @balance = balance
    @error = error
    @get_balance_calls = 0
  end

  def get_balance
    @get_balance_calls += 1
    raise @error if @error

    @balance
  end
end

class Admin::DashboardsControllerTest < ActionDispatch::IntegrationTest
  include SolapiStubbing

  setup { setup_admin_totp_secrets }

  test "관리자 로그인 상태에서 대시보드가 핵심 섹션과 함께 렌더된다 (ADMIN-1)" do
    admin_login(admins(:ops))
    with_solapi_balance { get admin_root_path }

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

      with_solapi_balance { get admin_root_path }

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

    with_solapi_balance { get admin_root_path }
    assert_response :success
    assert_match "13,900", response.body, "환불 전 당월 매출 9,900 + 4,000 렌더"

    order_a.mark_refunded!("이중 결제 정정")
    with_solapi_balance { get admin_root_path }
    assert_response :success
    assert_no_match(/13,900/, response.body, "환불 기록 주문 제외 — 4,000만 잔존")
    # 쿼리 수학 계약은 RevenueStatsQueryTest가 고정하며 여기선 렌더 정합만 검증한다.
  end

  test "북극성은 30일 내 마감 비율로 렌더되고 마감 0건은 '-'이다 (ADMIN-5·리뷰 제안 6)" do
    seed_empty_domain
    admin_login(admins(:ops))
    owner = User.create!(email: "dash-ns@example.com", password: "password")
    client = owner.clients.create!(name: "대시상사", contact_name: "김대시", phone: "010-5555-6666")
    fast = seed_paid_invoice(owner, client, "dash-fast", 5.days.ago)
    Payment.create!(invoice: fast, amount: 100_000, paid_on: Date.current) # 발행 +5일 — 30일 이내

    with_solapi_balance { get admin_root_path }
    assert_response :success
    assert_match "100.0", response.body, "30일 내 마감 1건 — 100.0%"

    Payment.destroy_all
    with_solapi_balance { get admin_root_path }
    assert_response :success
    assert_no_match(/100\.0/, response.body, "마감 0건 — 북극성 '-' 표기(비율 렌더 소멸)")
  end

  test "비인증 접근은 관리자 로그인으로 리다이렉트된다 (표면 격리)" do
    get admin_root_path
    assert_redirected_to new_admin_session_url
  end

  # ── T4(2026-11-20) — 솔라피 잔액 표시(ADMIN-5·REM-10) ──

  test "솔라피 잔액이 메시지 발송 지표 영역에 통화 표기로 렌더된다 (ADMIN-5·REM-10)" do
    admin_login(admins(:ops))
    with_solapi_balance(FakeSolapiBalanceClient.new(balance: { balance: 120_000, point: 0 })) do
      get admin_root_path
    end

    assert_response :success
    assert_match "솔라피 잔액", response.body
    assert_match "120,000₩", response.body, "ko locale — 통화 기호 접미사"
    assert_no_match(/충전 필요/, response.body, "임계 이상 — 경고 배지 없음")
  end

  test "잔액이 임계(50,000원) 미만이면 주황 경고·충전 필요 배지가 렌더된다 (ADMIN-5)" do
    admin_login(admins(:ops))
    with_solapi_balance(FakeSolapiBalanceClient.new(balance: { balance: 30_000, point: 0 })) do
      get admin_root_path
    end

    assert_response :success
    assert_match "30,000₩", response.body, "ko locale — 통화 기호 접미사"
    assert_match "충전 필요", response.body
    assert_match "text-orange-600", response.body
  end

  test "잔액 조회 실패는 '일시 조회 불가'로 폴백하고 대시보드 500이 아니다 (ADMIN-5)" do
    admin_login(admins(:ops))
    error = Solapi::ApiError.new(status: nil, code: "TIMEOUT", message: "read timeout")
    with_solapi_balance(FakeSolapiBalanceClient.new(error: error)) do
      get admin_root_path
    end

    assert_response :success
    # 잔액 값 <strong>은 중립 회색 "일시 조회 불가"로 폴백 — 매출 카드 등 다른 ₩ 표기와
    # 구분해 잔액 칸 자체를 특정한다.
    assert_select "strong.tabular-nums.text-stone-400", text: "일시 조회 불가"
    assert_no_match(/충전 필요/, response.body)
  end

  test "성공 잔액은 5분 캐시된다 — 재요청은 래퍼를 재호출하지 않는다 (호출 절제)" do
    admin_login(admins(:ops))
    fake = FakeSolapiBalanceClient.new
    with_balance_memory_cache do
      with_solapi_balance(fake) do
        2.times { get admin_root_path }
      end
    end

    assert_equal 1, fake.get_balance_calls, "두 번째 요청은 캐시 히트 — 외부 호출 1회뿐"
  end

  test "조회 실패는 1분 센티널 캐시된다 — 재요청은 래퍼를 재호출하지 않는다 (낙수 방지)" do
    admin_login(admins(:ops))
    error = Solapi::ApiError.new(status: nil, code: "CONNECTION", message: "refused")
    fake = FakeSolapiBalanceClient.new(error: error)
    with_balance_memory_cache do
      with_solapi_balance(fake) do
        2.times { get admin_root_path }
      end
    end

    assert_equal 1, fake.get_balance_calls, "실패 :unavailable 센티널 — 장애 중 재시도 폭주 차단"
  end

  private

  # C-1 해소(05_review) — 렌더 경로의 솔라피 래퍼 생성을 대역으로 교체한다. 기본 대역은
  # 임계 이상 잔액(경고 배지 비발생)으로 기존 지표 렌더 검증에 개입하지 않게 한다.
  def with_solapi_balance(fake = nil)
    fake ||= FakeSolapiBalanceClient.new
    with_solapi_client(fake) { yield fake }
  end

  # 테스트 환경 캐시는 null_store라 캐시 동작을 검증하려면 메모리 스토어으로 잠시 교체한다.
  # 세션(AdminSession)·지표는 캐시 비의존이라 교체 영향이 없다.
  def with_balance_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end

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
