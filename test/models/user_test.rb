require "test_helper"

# U1 사용자 모델 — AUTH-1(이메일/비밀번호), AUTH-1.4(이메일 필수·고유·정규화)
# 오류 문구는 가입 폼에 노출되는 en.yml 한글 문구 그대로 검증한다(리뷰 이슈 #3 회귀).
class UserTest < ActiveSupport::TestCase
  test "이메일은 대소문자와 앞뒤 공백을 정규화한다 (AUTH-1.4)" do
    user = User.new(email: " DOWNCASED@EXAMPLE.COM ")
    assert_equal "downcased@example.com", user.email
  end

  test "이메일이 비면 유효하지 않다 (AUTH-1.4)" do
    user = User.new(email: "", password: "secret-123", password_confirmation: "secret-123")
    assert_predicate user, :invalid?
    assert_includes user.errors[:email], "이메일을 입력해 주세요."
  end

  test "동일 이메일은 유효하지 않다 (AUTH-1.4)" do
    user = User.new(email: users(:alpha).email, password: "secret-123", password_confirmation: "secret-123")
    assert_predicate user, :invalid?
    assert_includes user.errors[:email], "이미 등록된 이메일입니다"
  end

  test "대소문자·공백 변형 이메일도 중복으로 유효하지 않다 (AUTH-1.4)" do
    user = User.new(email: "  Alpha@Example.COM ")
    assert_equal "alpha@example.com", user.email
    assert_predicate user, :invalid?
    assert_includes user.errors[:email], "이미 등록된 이메일입니다"
  end

  test "새 레코드에 비밀번호가 없으면 유효하지 않다 (has_secure_password 기본)" do
    user = User.new(email: "fresh@example.com")
    assert_predicate user, :invalid?
    assert_includes user.errors[:password], "비밀번호를 입력해 주세요."
  end

  test "72바이트를 초과하는 비밀번호는 유효하지 않다 (has_secure_password 기본)" do
    user = User.new(email: "fresh@example.com", password: "a" * 73, password_confirmation: "a" * 73)
    assert_predicate user, :invalid?
    assert_includes user.errors[:password], "비밀번호가 너무 깁니다. 72자 이내로 입력해 주세요."
  end

  test "비밀번호 확인이 일치하지 않으면 유효하지 않다 (has_secure_password 기본)" do
    user = User.new(email: "fresh@example.com", password: "secret-123", password_confirmation: "different-123")
    assert_predicate user, :invalid?
    assert_includes user.errors[:password_confirmation], "비밀번호 확인이 일치하지 않습니다."
  end

  test "올바른 비밀번호로 인증하고 틀린 비밀번호는 거부한다 (AUTH-1)" do
    assert users(:alpha).authenticate("password")
    refute users(:alpha).authenticate("wrong-password")
  end
end
