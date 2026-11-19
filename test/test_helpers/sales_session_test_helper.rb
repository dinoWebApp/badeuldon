# 영업 직원(/sales) 세션 헬퍼 — AdminSessionTestHelper와 같은 패턴(F-SALES — SALES-7).
# 2FA 없는 단일 단계 로그인이므로 POST 한 번으로 세션을 발급받는다. fixture rep의
# 비밀번호는 "password"(sales_reps.yml) 기준.
module SalesSessionTestHelper
  def sales_login(sales_rep, password: "password", ip: nil)
    headers = ip ? { "REMOTE_ADDR" => ip } : {}
    post sales_session_path, params: { email: sales_rep.email, password: }, headers: headers
    assert_response :see_other, "영업 직원 로그인이 통과해야 한다"
    assert_redirected_to sales_root_url
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SalesSessionTestHelper
end
