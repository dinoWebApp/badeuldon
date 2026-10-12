require "test_helper"

# 회원가입 — AUTH-1(이메일/비밀번호), AUTH-1.4(중복·정규화), 가입 즉시 세션 시작
# 시나리오 기준: _workspace/05_review.md 재리뷰 「Phase 7 Tester 최종 중점 영역 §1」
class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "GET /registration/new은 가입 폼과 로그인 링크를 렌더한다 (SURF-4)" do
    get new_registration_path
    assert_response :success
    assert_select "form[action=?]", registration_path
    assert_select "a[href=?]", new_session_path, text: /로그인/
  end

  test "정상 가입은 303으로 세션을 시작하고 welcome으로 안내한다 (AUTH-1)" do
    assert_difference -> { User.count }, +1 do
      assert_difference -> { Session.count }, +1 do
        sign_up(email: "new-user@example.com")
      end
    end
    assert_response :see_other
    assert_redirected_to welcome_path
    assert cookies["session_id"]

    follow_redirect!
    assert_select "h1", text: "가입이 완료되었습니다"
    assert_select "p#notice", text: "회원가입이 완료되었습니다. 받을돈에 오신 것을 환영합니다!"
  end

  test "가입으로 시작한 세션으로 /welcome에 접근할 수 있다 (AUTH-1)" do
    sign_up(email: "new-user@example.com")
    follow_redirect!

    get welcome_path
    assert_response :success
    assert_select "h1", text: "가입이 완료되었습니다"
  end

  test "인증 없이 /welcome 접근은 로그인 화면으로 리다이렉트된다" do
    get welcome_path
    assert_redirected_to new_session_path
  end

  test "동일 이메일 재가입은 422와 중복 안내문으로 거부된다 (AUTH-1.4 — 리뷰 #1 회귀)" do
    assert_no_difference -> { User.count } do
      sign_up(email: users(:alpha).email)
    end
    assert_response 422
    assert_select "div[role=alert]", text: /이미 등록된 이메일입니다/
  end

  test "대소문자·공백 변형 이메일 재가입도 중복으로 거부된다 (AUTH-1.4 — 리뷰 #1 회귀)" do
    assert_no_difference -> { User.count } do
      sign_up(email: "  ALPHA@EXAMPLE.COM ")
    end
    assert_response 422
    assert_select "div[role=alert]", text: /이미 등록된 이메일입니다/
  end

  test "변형 이메일로 가입하면 정규화된 이메일로 로그인된다 (AUTH-1.4)" do
    sign_up(email: "  Mixed.Case@Example.COM ")
    assert_redirected_to welcome_path

    attempt_login(email: "mixed.case@example.com", password: "secret-123")
    assert_response :see_other
    assert_redirected_to root_url
  end

  test "빈 이메일 가입은 422와 한글 안내문으로 거부된다 (AUTH-1.4)" do
    assert_no_difference -> { User.count } do
      sign_up(email: "")
    end
    assert_response 422
    assert_select "div[role=alert]", text: /이메일을 입력해 주세요\./
  end

  test "빈 비밀번호 가입은 422와 한글 안내문으로 거부된다 (AUTH-1)" do
    assert_no_difference -> { User.count } do
      sign_up(email: "fresh@example.com", password: "")
    end
    assert_response 422
    assert_select "div[role=alert]", text: /비밀번호를 입력해 주세요\./
  end

  test "비밀번호 확인 불일치 가입은 422와 한글 안내문으로 거부된다 (AUTH-1)" do
    assert_no_difference -> { User.count } do
      sign_up(email: "fresh@example.com", password_confirmation: "different-123")
    end
    assert_response 422
    assert_select "div[role=alert]", text: /비밀번호 확인이 일치하지 않습니다\./
  end

  test "73자 비밀번호 가입은 422와 한글 안내문으로 거부된다 (AUTH-1)" do
    assert_no_difference -> { User.count } do
      sign_up(email: "fresh@example.com", password: "a" * 73)
    end
    assert_response 422
    assert_select "div[role=alert]", text: /비밀번호가 너무 깁니다\. 72자 이내로 입력해 주세요\./
  end

  test "가입 요청은 3분에 10회로 제한된다 (rate_limit)" do
    with_memory_rate_limit_store do
      10.times do
        sign_up(email: "")
        assert_response 422
      end

      sign_up(email: "")
      assert_redirected_to new_registration_path
      follow_redirect!
      assert_select "p#alert", text: "너무 많은 요청이 있었습니다. 잠시 후 다시 시도해 주세요."
    end
  end

  private
    def sign_up(email:, password: "secret-123", password_confirmation: password)
      post registration_path, params: { user: { email:, password:, password_confirmation: } }
    end

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
