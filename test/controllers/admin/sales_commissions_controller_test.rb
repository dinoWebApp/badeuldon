require "test_helper"

# 수수료 정산 콘솔(SALES-5 — F-SALES). 연월 필터 목록·pending/paid 합계·mark paid(감사)·
# 중복 지급 방지·staff 허용.
# 시나리오 기준: PRD §6.20 SALES-5·Q24(지급 M+1·오프라인)·_workspace/05_review.md §2 ADMIN-2.
class Admin::SalesCommissionsControllerTest < ActionDispatch::IntegrationTest
  include AdminSessionTestHelper

  setup do
    setup_admin_totp_secrets
    @owner = admins(:ops)
    @rep = sales_reps(:sales_kim)
    @commission = @rep.sales_commissions.create!(year: 2026, month: 9,
                                                 base_amount: 19_800, rate: 20, amount: 3_960)
  end

  test "목록은 스냅샷과 pending·paid 합계를 표시한다 (SALES-5)" do
    @rep.sales_commissions.create!(year: 2026, month: 10, base_amount: 9_900, rate: 20,
                                   amount: 1_980, status: :paid, paid_at: Time.current)
    admin_login(@owner, at: Time.current)

    get admin_sales_commissions_path(year: 2026)
    assert_response :success
    assert_match(/3,960/, response.body)
    assert_match(/1,980/, response.body)
    assert_match(/3,960/, response.body) # pending 합계 — 상태 배지와 별도 표기
    assert_match(/1,980/, response.body) # paid 합계
  end

  test "월 필터는 해당 연월 스냅샷만 표시한다 (SALES-5)" do
    @rep.sales_commissions.create!(year: 2026, month: 10, base_amount: 9_900, rate: 20, amount: 1_980)
    admin_login(@owner, at: Time.current)

    get admin_sales_commissions_path(year: 2026, month: 9)
    assert_response :success
    assert_match(/3,960/, response.body)
    assert_no_match(/1,980/, response.body, "10월 스냅샷은 9월 필터에서 제외")
  end

  test "mark paid는 상태를 paid로 전환하고 감사를 기록한다 (SALES-5·ADMIN-2)" do
    admin_login(@owner, at: Time.current)

    patch mark_paid_admin_sales_commission_path(@commission)
    assert_redirected_to admin_sales_commissions_path(year: @commission.year, month: @commission.month)
    assert_match(/지급 처리했습니다/, flash[:notice])

    assert @commission.reload.paid?
    assert_not_nil @commission.paid_at
    audit = AuditLog.find_by(action: "commission_marked_paid", target_type: "SalesCommission",
                             target_id: @commission.id)
    assert_not_nil audit
    assert_includes audit.detail, "2026.09"
    assert_includes audit.detail, "3960원"
  end

  test "이미 지급된 정산의 재 mark paid는 안내로 흡수된다 (SEC-5 — 지급 확정 보존)" do
    admin_login(@owner, at: Time.current)
    @commission.mark_paid!
    paid_at_before = @commission.paid_at

    patch mark_paid_admin_sales_commission_path(@commission)
    assert_redirected_to admin_sales_commissions_path(year: @commission.year, month: @commission.month)
    assert_match(/이미 지급 처리된 정산입니다/, flash[:alert])
    assert_equal paid_at_before, @commission.reload.paid_at
  end

  test "staff 권한도 mark paid를 수행할 수 있다 (SALES-5 staff 허용)" do
    admin_login(admins(:staffuser), at: Time.current)

    patch mark_paid_admin_sales_commission_path(@commission)
    assert_redirected_to admin_sales_commissions_path(year: @commission.year, month: @commission.month)
    assert @commission.reload.paid?
  end

  test "비인증 접근은 관리자 로그인으로 리다이렉트된다 (AUTH-7.5)" do
    get admin_sales_commissions_path
    assert_redirected_to new_admin_session_url
  end
end
