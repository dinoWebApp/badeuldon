module Admins
  # ADMIN-5 — 메시지 발송 통계(솔라피 로컬 집계 — REM-10). 최근 30일 한정.
  # 실패율 분모 = sent + failed(pending·skipped 제외). skip 사유 = error_code 분포.
  # 솔라피 크레딧 잔액 API는 [INFERENCE] — 기술 부채로 로컬 집계만 제공한다.
  class MessageStatsQuery
    Row = Struct.new(:sent, :failed, :skipped, :failure_rate,
                     :skip_reasons, :by_recipient_role, keyword_init: true)

    def self.call
      scope = MessageLog.where(created_at: 30.days.ago.beginning_of_day..)
      sent = scope.sent.count
      failed = scope.failed.count
      attempted = sent + failed

      Row.new(
        sent: sent,
        failed: failed,
        skipped: scope.skipped.count,
        failure_rate: attempted.zero? ? nil : (failed * 100.0 / attempted).round(1),
        skip_reasons: scope.skipped.group(:error_code).order(Arel.sql("COUNT(*) DESC")).count,
        # enum 컬럼 group(:recipient_role) 키는 어댑터에 따라 정수 또는 enum 문자열 — 정규화.
        by_recipient_role: scope.sent.group(:recipient_role).count
                           .transform_keys { |k| k.is_a?(Integer) ? MessageLog.recipient_roles.key(k) : k.to_s }
      )
    end
  end
end
