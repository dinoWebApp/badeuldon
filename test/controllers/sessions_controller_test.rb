require "test_helper"

# 로그인/로그아웃 — AUTH-1, AUTH-1.6(세션 쿠키 30일), 계정 열거 방지
# 시나리오 기준: _workspace/05_review.md 재리뷰 「Phase 7 Tester 최종 중점 영역 §2」
class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "GET /session/new은 로그인 폼과 가입·재설정 링크를 렌더한다" do
    get new_session_path
    assert_response :success
    assert_select "form[action=?]", session_path
    assert_select "a[href=?]", new_registration_path, text: /무료로 시작하기/
    assert_select "a[href=?]", new_password_path, text: /비밀번호 찾기/
  end

  test "올바른 자격 증명은 303과 세션 발급으로 로그인한다 (AUTH-1)" do
    assert_difference -> { Session.count }, +1 do
      attempt_login(email: users(:alpha).email, password: "password")
    end
    assert_response :see_other
    assert_redirected_to root_url
    follow_redirect!
    assert_select "p#notice", text: "로그인되었습니다."
  end

  test "로그인 세션 쿠키는 30일 만료 속성으로 발급된다 (AUTH-1.6)" do
    attempt_login(email: users(:alpha).email, password: "password")
    assert_response :see_other

    set_cookies = Array(response.headers["Set-Cookie"]).flat_map { |value| value.to_s.split("\n") }
    cookie = set_cookies.find { |value| value.start_with?("session_id=") }
    assert cookie, "로그인 응답에 session_id 쿠키가 발급되어야 한다"

    expires_at = Time.httpdate(cookie[/expires=([^;]+)/, 1])
    assert_in_delta 30.days.from_now, expires_at, 5.minutes
  end

  test "미가입 이메일 로그인은 422와 안내문을 본문에 렌더한다 (AUTH-1 — 리뷰 #2 회귀)" do
    assert_no_difference -> { Session.count } do
      attempt_login(email: "ghost@example.com", password: "wrong-password")
    end
    assert_response 422
    assert_select "p#alert", text: "이메일 또는 비밀번호가 올바르지 않습니다."
  end

  test "오류 비밀번호 로그인은 422와 동일 안내문을 본문에 렌더한다 (AUTH-1 — 리뷰 #2 회귀)" do
    attempt_login(email: users(:alpha).email, password: "wrong-password")
    assert_response 422
    assert_select "p#alert", text: "이메일 또는 비밀번호가 올바르지 않습니다."
    assert_select "h1", text: "로그인"
  end

  test "계정 존재 여부와 무관하게 실패 응답 본문은 동일하다 (계정 열거 방지)" do
    attempt_login(email: users(:alpha).email, password: "wrong-password")
    assert_response 422
    existing_account_body = mask_per_request_values(response.body)

    users(:alpha).destroy!
    attempt_login(email: users(:alpha).email, password: "wrong-password")
    assert_response 422
    missing_account_body = mask_per_request_values(response.body)

    assert_equal existing_account_body, missing_account_body
  end

  test "로그아웃은 세션을 파기해 이전 쿠키로 재진입할 수 없다 (AUTH-1)" do
    sign_in_as(users(:alpha))
    stale_cookie = cookies["session_id"]
    get welcome_path
    assert_response :success

    delete session_path
    assert_response :see_other
    assert_redirected_to new_session_path
    follow_redirect!
    assert_select "p#notice", text: "로그아웃되었습니다."
    assert_equal 0, Session.count

    cookies.delete("session_id")
    cookies["session_id"] = stale_cookie
    get welcome_path
    assert_redirected_to new_session_path
  end

  test "로그인 시도는 3분에 10회로 제한된다 (rate_limit)" do
    with_memory_rate_limit_store do
      10.times do
        attempt_login(email: "ghost@example.com", password: "wrong-password")
        assert_response 422
      end

      attempt_login(email: "ghost@example.com", password: "wrong-password")
      assert_redirected_to new_session_path
      follow_redirect!
      assert_select "p#alert", text: "너무 많은 시도가 있었습니다. 잠시 후 다시 시도해 주세요."
    end
  end

  test "CSRF 토큰 없는 로그인 요청은 거부된다" do
    original_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    begin
      post session_path, params: { email: users(:alpha).email, password: "password" }
      assert_response 422
      assert_equal 0, Session.count
    ensure
      ActionController::Base.allow_forgery_protection = original_protection
    end
  end

  private
    def attempt_login(email:, password:)
      post session_path, params: { email:, password: }
    end

    # CSRF 토큰처럼 요청마다 무작위인 값(hidden input value·meta content)을 마스킹한다
    def mask_per_request_values(body)
      body.gsub(%r{(value|content)="[0-9A-Za-z+/=_-]{32,}"}, '\1="[MASKED]"')
    end

    # 테스트 환경 캐시(null_store)는 증분을 기억하지 못하므로, rate_limit이 부팅 시 캡처한
    # 캐시 스토어의 increment를 MemoryStore로 우회시킨다(요청 횟수 계수).
    def with_memory_rate_limit_store
      memory_store = ActiveSupport::Cache::MemoryStore.new
      cache_store = ActionController::Base.cache_store
      cache_store.define_singleton_method(:increment) do |name, amount = 1, **options|
        memory_store.increment(name, amount, **options)
      end
      yield
    ensure
      cache_store.singleton_class.remove_method(:increment) if cache_store.singleton_methods(false).include?(:increment)
    end
end
