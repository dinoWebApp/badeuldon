# 영업 직원 세션(SALES-7 — SALES-1 AUTH-7.5 준용). U1 Session(30일)·AdminSession과 완전
# 분리: 12시간 절대 만료 + 2시간 비활동 만료. 토큰은 추측 불가(SecureRandom.urlsafe_base64(32)).
# 세션 키는 sales 표면 전용(session[:sales_session_token]) — U1·관리자 쿠키와 격리된다.
class SalesRepSession < ApplicationRecord
  ABSOLUTE_TTL = 12.hours
  IDLE_TTL = 2.hours

  belongs_to :sales_rep

  # 사용 가능(만료 아님) 세션 — before_action 재검증에서 사용(AdminSession 동일 패턴).
  scope :usable, -> {
    where(expires_at: Time.current..)
      .where(last_activity_at: IDLE_TTL.ago..)
  }

  def self.issue_for!(sales_rep, ip:)
    create!(sales_rep:, token: SecureRandom.urlsafe_base64(32),
            expires_at: ABSOLUTE_TTL.from_now, last_activity_at: Time.current, ip:)
  end

  def expired?
    expires_at <= Time.current || last_activity_at <= IDLE_TTL.ago
  end

  # 요청마다 활동 시각 갱신(비활동 만료 기준점 리셋 — 절대 만료는 건드리지 않음).
  def touch_activity!
    update_column(:last_activity_at, Time.current)
  end
end
