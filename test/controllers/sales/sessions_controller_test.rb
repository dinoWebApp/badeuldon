require "test_helper"

# 영업 직원 로그인(SALES-1·7 — F-SALES). 단일 단계(2FA 불요)·통일 오류 문구(열거 방지)·
# 5회 실패 잠금+감사·정지 계정 차단·rate limit(10/3분).
# 시나리오 기준: PRD §6.20 SALES-1·7·AUTH-7.3 준용·_workspace/05_review.md §4 Tester 중점 8번.
class Sales::SessionsControllerTest < ActionDispatch::IntegrationTest
  test "비인증 /sales 접근은 영업 로그인 화면으로 리다이렉트된다 (SALES-7)" do
    get sales_root_path
    assert_redirected_to new_sales_session_path
    follow_redirect!
    assert_response :success
    assert_match(/받을돈 파트너스/, response.body, "영업 표면 전용 크롬(SALES-6)")
  end

  test "정상 로그인은 303으로 대시보드에 진입하고 세션·감사를 기록한다 (SALES-1·7)" do
    assert_difference -> { SalesRepSession.count }, +1 do
      assert_difference -> { AuditLog.where(action: "sales_rep_login_success").count }, +1 do
        sales_login(sales_reps(:sales_kim))
      end
    end

    get sales_root_path
    assert_response :success
    assert_select "h1", text: /김영업님의 실적/
  end

  test "잘못된 비밀번호는 422와 통일 문구로 거부되고 실패 감사가 기록된다 (SALES-7 열거 방지)" do
    assert_no_difference -> { SalesRepSession.count } do
      assert_difference -> { AuditLog.where(action: "sales_rep_login_failed").count }, +1 do
        post sales_session_path, params: { email: sales_reps(:sales_kim).email,
                                           password: "wrong-password" }
      end
    end
    assert_response :unprocessable_entity
    assert_select "p#alert", text: "이메일 또는 비밀번호가 올바르지 않습니다."
    assert_equal 1, sales_reps(:sales_kim).reload.failed_attempts
  end

  test "존재하지 않는 이메일도 동일 문구로 거부되며 감사는 기록하지 않는다 (SALES-7)" do
    assert_no_difference -> { AuditLog.where(action: "sales_rep_login_failed").count } do
      post sales_session_path, params: { email: "ghost@example.com", password: "whatever" }
    end
    assert_response :unprocessable_entity
    assert_select "p#alert", text: "이메일 또는 비밀번호가 올바르지 않습니다."
  end

  test "5회 실패 시 잠금되고 lockout 감사가 남으며 잠금 후 정확한 비밀번호도 거부된다 (AUTH-7.3 준용)" do
    rep = sales_reps(:sales_kim)
    4.times do
      post sales_session_path, params: { email: rep.email, password: "wrong-password" }
      assert_response :unprocessable_entity
      assert_not rep.reload.locked?
    end

    assert_difference -> { AuditLog.where(action: "sales_rep_lockout").count }, +1 do
      post sales_session_path, params: { email: rep.email, password: "wrong-password" }
    end
    assert rep.reload.locked?

    post sales_session_path, params: { email: rep.email, password: "password" }
    assert_response :unprocessable_entity, "잠금 계정은 정확한 비밀번호로도 로그인 불가"
    assert_empty SalesRepSession.where(sales_rep_id: rep.id)
  end

  test "정지 계정 로그인은 422로 거부되고 세션이 발급되지 않는다 (SALES-7)" do
    rep = sales_reps(:suspended_choi)
    post sales_session_path, params: { email: rep.email, password: "password" }

    assert_response :unprocessable_entity
    assert_select "p#alert", text: "이메일 또는 비밀번호가 올바르지 않습니다."
    assert_empty SalesRepSession.where(sales_rep_id: rep.id)
    assert AuditLog.exists?(action: "sales_rep_login_failed", target_type: "SalesRep",
                            target_id: rep.id)
  end

  test "로그인 시도는 3분에 10회로 제한된다 (SALES-7 rate limit)" do
    with_memory_rate_limit_store do
      rep = sales_reps(:sales_kim)
      10.times do
        post sales_session_path, params: { email: rep.email, password: "wrong-password" }
        assert_response :unprocessable_entity
      end

      post sales_session_path, params: { email: rep.email, password: "password" }
      assert_redirected_to new_sales_session_path
      follow_redirect!
      assert_select "p#alert", text: "너무 많은 시도가 있었습니다. 잠시 후 다시 시도해 주세요."
    end
  end

  test "로그아웃은 세션을 파기하고 로그인 화면으로 돌아간다 (SALES-7)" do
    sales_login(sales_reps(:sales_kim))

    assert_difference -> { SalesRepSession.count }, -1 do
      delete sales_session_path
    end
    assert_redirected_to new_sales_session_path

    get sales_root_path
    assert_redirected_to new_sales_session_path
  end
end
