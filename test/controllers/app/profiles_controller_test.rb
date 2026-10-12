require "test_helper"
require "stringio"

# 프로필 설정(AUTH-1.3) — 표면 ② 첫 화면 통합 테스트
# 시나리오 기준: _workspace/05_review.md §5 Tester 중점 2·4번, 03_implementation.md §4.1
class App::ProfilesControllerTest < ActionDispatch::IntegrationTest
  test "비인증 프로필 화면 접근은 302로 로그인 화면에 리다이렉트된다 (require_authentication)" do
    get edit_app_profile_path
    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "비인증 프로필 저장 시도도 로그인 화면에 리다이렉트되고 저장되지 않는다 (기본 가드)" do
    assert_no_changes -> { users(:alpha).reload.display_name } do
      patch app_profile_path, params: { user: { display_name: "무단변경", business_type: "business" } }
    end
    assert_redirected_to new_session_path
  end

  test "프로필 화면은 필수 2필드와 선택 4필드 폼을 렌더한다 (AUTH-1.3)" do
    sign_in_as users(:alpha)
    get edit_app_profile_path
    assert_response :success
    assert_select "h1", text: "프로필 설정"
    assert_select "input[name='user[display_name]']"
    assert_select "input[type=radio][name='user[business_type]']", count: 2
    assert_select "input[name='user[phone]']"
    assert_select "select[name='user[bank_name]']"
    assert_select "input[name='user[account_number]'][data-controller='account-number']"
    assert_select "input[name='user[account_holder]']"
    # 자동 하이픈 보조 UX(리뷰 이슈 #8 placeholder 포맷 회귀)
    assert_select "input[name='user[account_number]'][placeholder='예) 1234-5678-9012']"
  end

  test "빈값 제출은 422와 필수 필드 한글 오류로 거부된다 (AUTH-1.3)" do
    sign_in_as users(:alpha)
    patch app_profile_path, params: { user: { display_name: "", business_type: "" } }
    assert_response :unprocessable_entity
    assert_select "div[role=alert]" do |alerts|
      text = alerts.first.text
      assert_includes text, "표시명(또는 상호)을 입력해 주세요."
      assert_includes text, "사업자 유형을 선택해 주세요."
    end
    assert_nil users(:alpha).reload.display_name
  end

  test "잘못된 형식의 연락처·계좌번호는 422와 한글 오류로 거부된다 (AUTH-1.3)" do
    sign_in_as users(:alpha)
    patch app_profile_path, params: { user: {
      display_name: "알파스튜디오", business_type: "business",
      phone: "abc", account_number: "12"
    } }
    assert_response :unprocessable_entity
    assert_select "div[role=alert]" do |alerts|
      text = alerts.first.text
      assert_includes text, "연락처 형식이 올바르지 않습니다. 예) 010-1234-5678"
      # 리뷰 이슈 #7 — 길이 안내 포함 문구 회귀
      assert_includes text, "계좌번호 형식을 확인해 주세요. 숫자와 하이픈(-)으로 5자 이상 입력해 주세요."
    end
  end

  test "필수 2필드만으로 저장하며 선택 4필드는 공백으로 남는다 (AUTH-1.3 — 선택 입력 허용)" do
    sign_in_as users(:alpha)
    patch app_profile_path, params: { user: { display_name: "  알파랩  ", business_type: "business" } }
    assert_response :see_other
    # 저장 완료 목적지 — welcome 임시 화면 소멸, /app 대시보드(03 §4.1)
    assert_redirected_to app_root_url

    user = users(:alpha).reload
    assert_equal "알파랩", user.display_name # normalizes — 앞뒤 공백 제거
    assert_equal "business", user.business_type
    assert_nil user.bank_name
    assert_nil user.account_number
    assert_nil user.account_holder
    assert_nil user.phone
  end

  test "6필드 저장은 303으로 /app에 안내하고 6컬럼 전부 DB에 반영된다 (AUTH-1.3, 03 §4.1)" do
    sign_in_as users(:alpha)
    patch app_profile_path, params: { user: {
      display_name: "알파스튜디오", business_type: "freelancer", bank_name: "우리은행",
      account_number: "1002-345-678901", account_holder: "김알파", phone: "010-1234-5678"
    } }
    assert_response :see_other
    assert_redirected_to app_root_url
    follow_redirect!
    assert_select "h1", text: "대시보드"
    assert_select "p#notice", text: "프로필 설정이 완료되었습니다."

    user = users(:alpha).reload
    assert_equal "알파스튜디오", user.display_name
    assert_equal "freelancer", user.business_type
    assert_equal "우리은행", user.bank_name
    assert_equal "1002-345-678901", user.account_number
    assert_equal "김알파", user.account_holder
    assert_equal "010-1234-5678", user.phone
  end

  test "프로필 완료 후 재로그인하면 /app으로 진입한다 (AUTH-1.3 분기, 03 §4.1)" do
    sign_in_as users(:alpha)
    patch app_profile_path, params: { user: { display_name: "알파스튜디오", business_type: "business" } }
    assert_redirected_to app_root_url

    sign_out
    post session_path, params: { email: users(:alpha).email, password: "password" }
    assert_response :see_other
    assert_redirected_to app_root_url
  end

  test "프로필 화면 헤더는 미완료 표시명에 플레이스홀더를 노출한다 (Phase 6 #2)" do
    sign_in_as users(:alpha)
    get edit_app_profile_path
    assert_response :success
    # 표시명 공백 사용자 — 빈 span 대신 플레이스홀더(app 레이아웃 헤더)
    assert_select "header span", text: "프로필 완성 중", count: 1
  end

  test "프로필 화면 헤더는 완료 사용자의 표시명을 노출한다 (Phase 6 #2 — 완료 분기)" do
    sign_in_as users(:gamma)
    get edit_app_profile_path
    assert_response :success
    assert_select "header span", text: "감마스튜디오", count: 1
  end

  test "프로필 업데이트는 로그인 사용자에게만 적용되고 타 사용자·인증 정보는 불변이다 (소유자 스코프)" do
    sign_in_as users(:alpha)
    patch app_profile_path, params: { user: {
      display_name: "알파스튜디오", business_type: "business",
      email: "hijack@example.com", password: "escalated-secret"
    } }
    assert_redirected_to app_root_url

    alpha = users(:alpha).reload
    assert_equal "알파스튜디오", alpha.display_name
    # 파라미터 화이트리스트 밖 — 권한 상향·계정 탈취 불가
    assert_equal "alpha@example.com", alpha.email
    assert alpha.authenticate("password")
    refute alpha.authenticate("escalated-secret")
    # 단일 자원(Current.user) 스코프 — 타 사용자 레코드 무영향
    assert_nil users(:beta).reload.display_name
    assert_equal "감마스튜디오", users(:gamma).reload.display_name
  end

  test "프로필 저장 로그에서 계좌번호·예금주·연락처는 [FILTERED]로 기록된다 (리뷰 이슈 #1 — CRITICAL 회귀)" do
    sign_in_as users(:alpha)
    io = StringIO.new
    captured = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(captured)
    begin
      patch app_profile_path, params: { user: {
        display_name: "알파스튜디오", business_type: "business", bank_name: "국민은행",
        account_number: "123-45-678901", account_holder: "김알파", phone: "010-1234-5678"
      } }
    ensure
      Rails.logger.stop_broadcasting_to(captured)
    end

    log = io.string
    assert_includes log, %q("account_number" => "[FILTERED]")
    assert_includes log, %q("account_holder" => "[FILTERED]")
    assert_includes log, %q("phone" => "[FILTERED]")
    assert_not_includes log, "123-45-678901"
    assert_not_includes log, "김알파"
    assert_not_includes log, "010-1234-5678"
    # 은행명·표시명은 민감정보가 아니므로 평문 유지(과잉 필터링 방지 회귀)
    assert_includes log, "국민은행"
    assert_includes log, "알파스튜디오"
  end
end
