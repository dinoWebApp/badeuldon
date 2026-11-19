# 추천 코드 이력(SALES-2 — F-SALES). 로테이션(Sales::RotateReferralCodesService)이 매주
# 새 행을 발급하고 기존 행의 valid_until을 조기 종료한다 — 과거 어트리뷰션 감사는 이력 행으로
# 추적한다(P4). 가입 폼은 current_valid 스코프(현재 유효 창)만 수용한다(SALES-3).
class SalesReferralCode < ApplicationRecord
  # 코드 길이(SALES-2 — 8자 안전 문자열). 혼동 문자(O/0·I/1/L)를 뺀 알파벳 대문자+숫자.
  CODE_LENGTH = 8
  SAFE_ALPHABET = (("A".."Z").to_a - %w[O I L] + ("2".."9").to_a).freeze

  belongs_to :sales_rep

  normalizes :code, with: ->(code) { code.strip.upcase }

  validates :code, presence: true, uniqueness: true, length: { is: CODE_LENGTH }
  validates :valid_from, :valid_until, presence: true
  validate :valid_until_after_valid_from

  # 현재 유효 창(가입 수용 판정) — 오늘(KST·TIME-1)이 valid_from 이상 valid_until 이하.
  # 만료 코드는 거부·안내 대상이다(가입 폼 — 코드 재발급은 월요일 자동 로테이션).
  scope :current_valid, -> {
    where(valid_from: ..Date.current).where(valid_until: Date.current..)
  }

  def expired?
    valid_until < Date.current
  end

  # 8자 안전 문자열 생성 — 혼동 문자 제외 알파벳에서 무작위 추출. 유니크 재시도는
  # 서비스(RotateReferralCodesService)가 유니크 인덱스 충돌을 흡수하는 방식으로 담당.
  def self.generate_code
    Array.new(CODE_LENGTH) { SAFE_ALPHABET.sample }.join
  end

  private

  def valid_until_after_valid_from
    return if valid_until.blank? || valid_from.blank?
    return if valid_until >= valid_from

    errors.add(:valid_until, "은(는) 유효 시작일보다 이전일 수 없습니다")
  end
end
