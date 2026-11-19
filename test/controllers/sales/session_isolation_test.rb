require "test_helper"

# 표면 세션 격리(SALES-7 — F-SALES). U1(/app·서명 쿠키)·관리자(/admin·admin_session_token)·
# 영업(/sales·sales_session_token) 3원 분리 — 쿠키 키·토큰 테이블 모두 별도.
# 시나리오 기준: PRD §6.20 SALES-7·_workspace/05_review.md §4 Tester 중점 7번.
class Sales::SessionIsolationTest < ActionDispatch::IntegrationTest
  setup do
    setup_admin_totp_secrets
  end

  test "U1 세션으로는 /sales에 진입할 수 없다 (표면 격리)" do
    sign_in_as users(:gamma)
    get sales_root_path
    assert_redirected_to new_sales_session_path
    assert_equal 0, SalesRepSession.count
  end

  test "영업 세션으로는 /app·/admin에 진입할 수 없다 (표면 격리)" do
    sales_login(sales_reps(:sales_kim))

    get app_root_path
    assert_redirected_to new_session_url

    get admin_root_path
    assert_redirected_to new_admin_session_url
  end

  test "세 세션은 한 브라우저에서 공존하며 상호 침투하지 않는다 (SALES-7 쿠키 키 분리)" do
    sign_in_as users(:gamma)
    admin_login(admins(:ops), at: Time.current)
    sales_login(sales_reps(:sales_kim))

    get app_root_path
    assert_response :success, "U1 세션 유지"
    get admin_root_path
    assert_response :success, "관리자 세션 유지"
    get sales_root_path
    assert_response :success, "영업 세션 유지"
  end

  test "U1 로그아웃은 영업 세션에 영향을 주지 않는다 (쿠키 키 분리 — SALES-7)" do
    sign_in_as users(:gamma)
    sales_login(sales_reps(:sales_kim))

    delete session_path # U1 로그아웃 — cookies.signed[:session_id] 삭제 방식
    assert_response :see_other

    get app_root_path
    assert_redirected_to new_session_url, "U1 세션은 종료"
    get sales_root_path
    assert_response :success, "영업 세션은 유지된다"
  end

  test "영업 로그아웃은 U1·관리자 세션에 영향을 주지 않는다 (SALES-7)" do
    sign_in_as users(:gamma)
    admin_login(admins(:ops), at: Time.current)
    sales_login(sales_reps(:sales_kim))

    delete sales_session_path

    get sales_root_path
    assert_redirected_to new_sales_session_path, "영업 세션은 종료"
    get app_root_path
    assert_response :success
    get admin_root_path
    assert_response :success
  end

  test "비활동 2시간 경과 세션은 재검증에서 만료된다 (SALES-7 IDLE_TTL)" do
    login_at = Time.zone.parse("2026-11-19 09:00")
    travel_to(login_at) { sales_login(sales_reps(:sales_kim)) }

    travel_to(login_at + SalesRepSession::IDLE_TTL - 1.second) do
      get sales_root_path
      assert_response :success, "2시간 직전은 유효하며 활동 시각이 갱신된다"
    end

    # 마지막 활동(갱신 시점) + 2시간 경과 — 재검증형 만료 기준점 이동 확인.
    travel_to(login_at + (SalesRepSession::IDLE_TTL * 2) + 1.second) do
      get sales_root_path
      assert_redirected_to new_sales_session_path
    end
  end

  test "절대 만료(12시간) 경과 세션은 활동 갱신과 무관하게 만료된다 (SALES-7 ABSOLUTE_TTL)" do
    login_at = Time.zone.parse("2026-11-19 09:00")
    travel_to(login_at) { sales_login(sales_reps(:sales_kim)) }

    # 중간에 계속 활동해도(비활동 만료 회피 — 갱신 간격은 IDLE_TTL 이내) 12시간 절대 한계는
    # 넘을 수 없다. 90분 간격 방문으로 비활동 만료를 피한다.
    [ 1.5.hours, 3.hours, 4.5.hours ].each do |offset|
      travel_to(login_at + offset) { get sales_root_path }
      assert_response :success
    end

    travel_to(login_at + SalesRepSession::ABSOLUTE_TTL + 1.second) do
      get sales_root_path
      assert_redirected_to new_sales_session_path
      assert_empty sales_reps(:sales_kim).sales_rep_sessions.reload.usable
    end
  end

  test "무효 토큰은 세션 파기 후 로그인 화면으로 리다이렉트된다 (SALES-7)" do
    sales_login(sales_reps(:sales_kim))
    # 쿠키에는 토큰이 남아 있지만 토큰 테이블에서 제거 — "DB에 없는 무효 토큰"과 같은 경로다.
    SalesRepSession.delete_all

    get sales_root_path
    assert_redirected_to new_sales_session_path
    assert_nil session[:sales_session_token], "파기 — 토큰 키 제거"
  end
end
