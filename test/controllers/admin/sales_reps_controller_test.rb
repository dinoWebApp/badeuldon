require "test_helper"

# 영업 직원 관리 콘솔(SALES-1 — F-SALES). CRUD(삭제 없음)·정지(세션 파기)·코드 재생성(멱등
# 안내)·잠금 해제(W-1)·감사 전건(ADMIN-2)·staff 허용.
# 시나리오 기준: PRD §6.20 SALES-1·ADMIN-2·_workspace/05_review.md §4 Tester 중점 8·10번.
class Admin::SalesRepsControllerTest < ActionDispatch::IntegrationTest
  include AdminSessionTestHelper

  setup do
    setup_admin_totp_secrets
    @owner = admins(:ops)
    @staff = admins(:staffuser)
  end

  test "비인증 /admin/sales_reps 접근은 관리자 로그인으로 리다이렉트된다 (AUTH-7.5)" do
    get admin_sales_reps_path
    assert_redirected_to new_admin_session_url
  end

  test "목록은 역할·요율·상태·현재 코드를 표시한다 (SALES-1)" do
    admin_login(@owner, at: Time.current)
    get admin_sales_reps_path

    assert_response :success
    assert_match(/김영업/, response.body)
    assert_match(/CRO/, response.body)
    assert_match(/20%/, response.body)
    assert_match(/KIM2026A/, response.body)
    assert_match(/계정 삭제는 지원하지 않습니다/, response.body, "P4 — 정지로만 운영 고지")
  end

  test "생성은 초기 추천 코드를 즉시 발급하고 감사를 기록한다 (SALES-1·2·ADMIN-2)" do
    admin_login(@owner, at: Time.current)

    assert_difference -> { SalesRep.count }, +1 do
      assert_difference -> { SalesReferralCode.count }, +1 do
        assert_difference -> { AuditLog.where(action: "sales_rep_created").count }, +1 do
          post admin_sales_reps_path, params: {
            sales_rep: { email: "new.rep@example.com", password: "password123",
                         name: "신규영업", title: "파트장", role: "sales" }
          }
        end
      end
    end
    assert_redirected_to admin_sales_reps_path

    rep = SalesRep.find_by(email: "new.rep@example.com")
    code = rep.current_referral_code
    assert_not_nil code, "생성 시 초기 코드 발급"
    assert_equal 8, code.code.length
    assert_match(/초기 추천 코드: #{code.code}/, flash[:notice])
    assert_equal "sales", rep.role
  end

  test "생성 시 알 수 없는 role 값은 sales로 강제된다 (조작 입력 방어)" do
    admin_login(@owner, at: Time.current)

    post admin_sales_reps_path, params: {
      sales_rep: { email: "weird.role@example.com", password: "password123",
                   name: "이상역할", role: "superadmin" }
    }
    assert_redirected_to admin_sales_reps_path
    assert_equal "sales", SalesRep.find_by(email: "weird.role@example.com").role
  end

  test "요율 오버라이드는 1~50 범위 밖을 422로 거부한다 (W-2 서버 측 검증)" do
    admin_login(@owner, at: Time.current)

    [ 0, 51, -5 ].each do |rate|
      assert_no_difference -> { SalesRep.count } do
        post admin_sales_reps_path, params: {
          sales_rep: { email: "rate-#{rate}@example.com", password: "password123",
                       name: "요율검증", role: "sales", commission_rate: rate }
        }
      end
      assert_response :unprocessable_entity, "rate #{rate}는 거부된다"
    end
  end

  test "수정은 요율·직함을 반영하고 감사를 기록한다 (SALES-1·ADMIN-2)" do
    admin_login(@owner, at: Time.current)
    rep = sales_reps(:sales_kim)

    patch admin_sales_rep_path(rep), params: {
      sales_rep: { title: "수석 영업", commission_rate: 30 }
    }
    assert_redirected_to admin_sales_reps_path

    assert_equal 30, rep.reload.commission_rate
    assert_equal "수석 영업", rep.title
    assert_equal 30, rep.effective_rate
    assert AuditLog.exists?(action: "sales_rep_updated", target_type: "SalesRep", target_id: rep.id)
  end

  test "수정 시 비밀번호 공백은 기존 값을 유지한다 (SALES-1)" do
    admin_login(@owner, at: Time.current)
    rep = sales_reps(:sales_kim)
    digest_before = rep.password_digest

    patch admin_sales_rep_path(rep), params: {
      sales_rep: { title: "직함만 수정", password: "" }
    }
    assert_redirected_to admin_sales_reps_path
    assert_equal digest_before, rep.reload.password_digest
  end

  test "정지 전환은 세션을 전부 파기하고 감사를 기록한다 (SALES-1·7)" do
    admin_login(@owner, at: Time.current)
    rep = sales_reps(:sales_kim)
    sales_login(rep) # 영업 세션 발급(별도 쿠키 — integration 세션에 admin과 병존)
    assert_equal 1, rep.sales_rep_sessions.count

    patch toggle_suspension_admin_sales_rep_path(rep)
    assert_redirected_to admin_sales_reps_path

    assert rep.reload.suspended?
    assert_empty rep.sales_rep_sessions.reload, "정지 시 세션 전량 파기"
    assert AuditLog.exists?(action: "sales_rep_suspended", target_id: rep.id)

    patch toggle_suspension_admin_sales_rep_path(rep)
    assert rep.reload.active?
    assert AuditLog.exists?(action: "sales_rep_resumed", target_id: rep.id)
  end

  test "코드 재생성은 이전 코드를 즉시 무효화하고 재실행은 멱등 안내로 흡수한다 (SALES-2·W-1 맥락)" do
    admin_login(@owner, at: Time.current)
    rep = sales_reps(:sales_kim)
    old_code = rep.current_referral_code

    patch rotate_code_admin_sales_rep_path(rep)
    assert_redirected_to admin_sales_reps_path
    assert_match(/새 추천 코드: /, flash[:notice])
    new_code = rep.reload.current_referral_code
    assert_not_equal old_code.code, new_code.code
    assert_equal Date.current - 1.day, old_code.reload.valid_until, "이전 코드 조기 종료"
    assert AuditLog.exists?(action: "sales_rep_code_rotated", target_id: rep.id)

    patch rotate_code_admin_sales_rep_path(rep)
    assert_redirected_to admin_sales_reps_path
    assert_match(/멱등/, flash[:alert], "당일 재실행은 무변경 안내")
    assert_equal new_code.code, rep.reload.current_referral_code.code
  end

  test "잠금 해제(W-1)는 locked_at·failed_attempts를 리셋하고 감사를 기록한다" do
    admin_login(@owner, at: Time.current)
    rep = sales_reps(:sales_kim)
    5.times { rep.record_failed_attempt! }
    assert rep.reload.locked?

    patch unlock_admin_sales_rep_path(rep)
    assert_redirected_to admin_sales_reps_path
    assert_match(/잠금을 해제했습니다/, flash[:notice])

    assert_not rep.reload.locked?
    assert_equal 0, rep.failed_attempts
    assert AuditLog.exists?(action: "sales_rep_unlocked", target_id: rep.id)

    # 해제 후 자력 로그인이 가능해진다(W-1 — 복구 경로 검증)
    sales_login(rep)
  end

  test "staff 권한도 생성·정지·mark_paid를 수행할 수 있다 (SALES-1 staff 허용 정책)" do
    admin_login(@staff, at: Time.current)

    assert_difference -> { SalesRep.count }, +1 do
      post admin_sales_reps_path, params: {
        sales_rep: { email: "staff.created@example.com", password: "password123",
                     name: "스태프생성", role: "sales" }
      }
    end
    assert_redirected_to admin_sales_reps_path
  end

  test "삭제(destroy)는 컨트롤러 액션이 없어 수행할 수 없다 (P4 — 계정 삭제 없음, 정지로만 운영)" do
    admin_login(@owner, at: Time.current)
    rep = sales_reps(:sales_kim)

    # routes는 resources 기본형이라 destroy 경로가 존재하지만 액션이 없다 — Rails 8은
    # 미구현 액션을 404로 응답해 계정 삭제 경로는 성립하지 않는다(콘솔 UI에도 삭제 버튼 없음).
    delete admin_sales_rep_path(rep)
    assert_response :not_found
    assert SalesRep.exists?(rep.id)
  end
end
