module Admins
  # ADMIN-5 — 가입 지표. 전체 집계(user 스코프 불요 — 관리자 콘솔 운영 지표).
  # "활성" 지표는 세션·활동 추적 컬럼이 없어 단순화한다: 최근 30일 가입수를 활성 후보로 함께 반환.
  # 규약 §3.2 — 집계는 Query Object, 뷰는 결과만 소비. TIME-1(KST) 기준 Date.current.
  class SignupStatsQuery
    Row = Struct.new(:total, :last_7d, :last_30d, keyword_init: true)

    def self.call
      Row.new(
        total: User.count,
        last_7d: User.where(created_at: 7.days.ago.beginning_of_day..).count,
        last_30d: User.where(created_at: 30.days.ago.beginning_of_day..).count
      )
    end
  end
end
