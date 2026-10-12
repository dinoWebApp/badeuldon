require "test_helper"

# 비밀번호 재설정 — AUTH-8(1회성·15분 만료·기존 세션 무효화·열거 방지)
# 시나리오 기준: _workspace/05_review.md 재리뷰 「Phase 7 Tester 최종 중점 영역 §3」
class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:alpha) }

  test "GET /passwords/new은 재설정 요청 폼을 렌더한다" do
    get new_password_path
    assert_response :success
    assert_select "form[action=?]", passwords_path
    assert_select "a[href=?]", new_session_path, text: /로그인으로 돌아가기/
  end

  test "가입 이메일 요청은 재설정 메일을 발송하고 안내 리다이렉트한다 (AUTH-8)" do
    post passwords_path, params: { email: @user.email }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_session_path

    perform_enqueued_jobs
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_equal [ @user.email ], ActionMailer::Base.deliveries.last.to

    follow_redirect!
    assert_select "p#notice", text: "비밀번호 재설정 안내를 이메일로 보냈습니다. (가입된 이메일인 경우)"
  end

  test "미가입 이메일 요청은 메일 없이 동일하게 응답한다 (AUTH-8 열거 방지)" do
    post passwords_path, params: { email: "ghost@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to new_session_path
    ghost_notice = flash[:notice]

    post passwords_path, params: { email: @user.email }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_session_path
    assert_equal ghost_notice, flash[:notice]
  end

  test "재설정 요청은 3분에 10회로 제한된다 (rate_limit)" do
    with_memory_rate_limit_store do
      10.times do
        post passwords_path, params: { email: "ghost@example.com" }
        assert_response :see_other
      end

      post passwords_path, params: { email: "ghost@example.com" }
      assert_redirected_to new_password_path
      follow_redirect!
      assert_select "p#alert", text: "너무 많은 요청이 있었습니다. 잠시 후 다시 시도해 주세요."
    end
  end

  test "유효한 토큰으로 새 비밀번호 설정 화면에 진입한다 (AUTH-8)" do
    token = @user.password_reset_token
    get edit_password_path(token)
    assert_response :success
    assert_select "form[action=?]", password_path(token)
  end

  test "변조된 토큰 진입은 만료 안내와 함께 거부된다 (AUTH-8)" do
    get edit_password_path("tampered-token")
    assert_redirected_to new_password_path
    follow_redirect!
    assert_select "p#alert", text: "비밀번호 재설정 링크가 만료되었거나 잘못되었습니다."
  end

  test "15분이 지난 토큰 진입은 거부된다 (AUTH-8 만료)" do
    token = @user.password_reset_token
    travel 16.minutes do
      get edit_password_path(token)
      assert_redirected_to new_password_path
      follow_redirect!
      assert_select "p#alert", text: "비밀번호 재설정 링크가 만료되었거나 잘못되었습니다."
    end
  end

  test "재설정 완료는 새 비밀번호 로그인으로 전환한다 (AUTH-8)" do
    token = @user.password_reset_token
    assert_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "brand-new-123", password_confirmation: "brand-new-123" }
      assert_redirected_to new_session_path
    end
    follow_redirect!
    assert_select "p#notice", text: "비밀번호가 변경되었습니다. 새 비밀번호로 로그인해 주세요."

    attempt_login(email: @user.email, password: "brand-new-123")
    assert_response :see_other

    attempt_login(email: @user.email, password: "password")
    assert_response 422
  end

  test "사용된 토큰은 1회성으로 재사용이 거부된다 (AUTH-8)" do
    token = @user.password_reset_token
    put password_path(token), params: { password: "brand-new-123", password_confirmation: "brand-new-123" }
    assert_redirected_to new_session_path

    get edit_password_path(token)
    assert_redirected_to new_password_path
  end

  test "확인 불일치 재설정은 422와 안내문을 본문에 렌더한다 (AUTH-8 — 리뷰 #2 회귀)" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "no-match-1", password_confirmation: "no-match-2" }
      assert_response 422
    end
    assert_select "p#alert", text: "비밀번호를 확인해 주세요."
  end

  test "재설정 완료 시 기존 세션은 전부 무효화된다 (AUTH-8)" do
    sign_in_as(@user)
    stale_cookie = cookies["session_id"]
    get welcome_path
    assert_response :success

    put password_path(@user.password_reset_token), params: { password: "brand-new-123", password_confirmation: "brand-new-123" }
    assert_redirected_to new_session_path
    assert_equal 0, @user.reload.sessions.count

    cookies.delete("session_id")
    cookies["session_id"] = stale_cookie
    get welcome_path
    assert_redirected_to new_session_path
  end

  private
    def attempt_login(email:, password:)
      post session_path, params: { email:, password: }
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
