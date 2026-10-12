# U1 사용자 — AUTH-1(이메일/비밀번호 인증만 제공), AUTH-1.4(이메일 = 로그인 아이디), AUTH-1.3(프로필)
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :clients, dependent: :destroy  # CLIENT-1 — 탈퇴 시 거래처 데이터 삭제(AUTH-1.5)
  has_many :items, dependent: :destroy    # CLIENT-2 — 탈퇴 시 품목 데이터 삭제(AUTH-1.5)

  # AUTH-1.3 사업자 유형 — 사업자(business)·프리랜서(freelancer, 3.3% 원천징수 해당).
  # 미선택 허용: 가입 시점엔 결정하지 않고, 프로필 설정(:profile 컨텍스트)에서 필수가 된다.
  enum :business_type, { business: 0, freelancer: 1 }

  # AUTH-1.4 — 이메일 필수·고유(DB 고유 인덱스 위반을 500이 아닌 422 검증 실패로 처리)
  validates :email, presence: true, uniqueness: true

  # AUTH-1.3 — 프로필 저장 시 표시명·사업자 유형은 필수, 계좌 3종·연락처는 선택 입력(이후 수정 가능).
  # 가입(register/save)에는 적용되지 않는 컨텍스트 검증 — 미설정은 "프로필 미완료" 판정 근거.
  validates :display_name, presence: true, on: :profile
  validates :business_type, presence: true, on: :profile
  validates :phone, allow_blank: true, format: { with: /\A\d{2,3}-?\d{3,4}-?\d{4}\z/ }, on: :profile
  validates :account_number, allow_blank: true, format: { with: /\A\d[\d-]{4,19}\z/ }, on: :profile

  # AUTH-1.4 — 이메일 대소문자·공백 정규화(로그인 아이디로서 동일 취급)
  normalizes :email, with: ->(e) { e.strip.downcase }
  # AUTH-1.3 — 표시명 앞뒤 공백 제거
  normalizes :display_name, with: ->(d) { d.strip }
end
