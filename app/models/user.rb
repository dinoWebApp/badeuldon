# U1 사용자 — AUTH-1(이메일/비밀번호 인증만 제공), AUTH-1.4(이메일 = 로그인 아이디)
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  # AUTH-1.4 — 이메일 필수·고유(DB 고유 인덱스 위반을 500이 아닌 422 검증 실패로 처리)
  validates :email, presence: true, uniqueness: true

  # AUTH-1.4 — 이메일 대소문자·공백 정규화(로그인 아이디로서 동일 취급)
  normalizes :email, with: ->(e) { e.strip.downcase }
end
