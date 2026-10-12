# 비밀번호 재설정 안내 메일(AUTH-8) — 1회성 만료 링크 전달
class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    mail subject: "[받을돈] 비밀번호 재설정 안내", to: user.email
  end
end
