require "test_helper"
require_relative "../../test_helpers/solapi_stubbing"

# 표면 격리 가드 — AUTH-7.5(전용 admin_sessions)·ADMIN-1(U1과 절대 분리)
class Admin::BaseGuardTest < ActionDispatch::IntegrationTest
  # T4(2026-11-20 — 05_review C-1): 대시보드 렌더가 load_solapi_balance로 솔라피 래퍼를
  # 직접 생성한다 — 200 렌더 테스트는 대역으로 교체해 외부 실호출을 차단한다.
  include SolapiStubbing
  setup { setup_admin_totp_secrets }

  test "비인증 /admin 접근은 관리자 로그인으로 리다이렉트된다 (AUTH-7.5)" do
    get admin_root_path
    assert_redirected_to new_admin_session_url
  end

  test "U1 세션으로는 /admin에 진입할 수 없다 (표면 격리)" do
    sign_in_as users(:alpha)
    get admin_root_path
    assert_redirected_to new_admin_session_url
    assert_equal 0, AdminSession.count
  end

  test "관리자 세션으로는 /app에 진입할 수 없다 (표면 격리)" do
    admin_login(admins(:ops))
    get app_root_path
    assert_redirected_to new_session_url
  end

  test "잠금 계정 세션 토큰은 여전히 유효하되 잠금은 세션에 영향을 주지 않는다 (AUTH-7.5 경계)" do
    admin_login(admins(:ops))
    # 잠금은 로그인 플로우만 차단하고 기존 세션을 즉시 파기하지 않는다(현 설계).
    5.times { admins(:ops).record_failed_attempt! }
    balance_stub = Object.new.tap { |o| o.define_singleton_method(:get_balance) { { balance: 1, point: 0 } } }
    with_solapi_client(balance_stub) { get admin_root_path }
    assert_response :success
  end
end
