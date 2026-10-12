require "test_helper"

# 비밀번호 재설정 메일 — AUTH-8(수신자 = 가입 이메일, 15분 만료·1회용 고정 한글 안내 — 리뷰 #5 회귀)
class PasswordsMailerTest < ActionMailer::TestCase
  test "reset은 가입 이메일로 15분 만료 안내를 보낸다 (AUTH-8)" do
    mail = PasswordsMailer.reset(users(:alpha))

    assert_equal "[받을돈] 비밀번호 재설정 안내", mail.subject
    assert_equal [ users(:alpha).email ], mail.to

    assert_includes mail.html_part.body.to_s, "이 링크는 15분 후 만료되며,"
    assert_includes mail.text_part.body.to_s, "이 링크는 15분 후 만료되며,"
    assert_match %r{/passwords/}, mail.html_part.body.to_s
    assert_match %r{/passwords/}, mail.text_part.body.to_s
  end
end
