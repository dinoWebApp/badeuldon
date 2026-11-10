# 운영 감사 로그 단일 기록 진입점(ADMIN-2 — 컨트롤러에서 AuditLog 직접 create 금지).
# action 확정값: login_success · login_failed · lockout · new_ip_login · password_reset(+unlock)
# · coupon_redeemed(ADMIN-4 — U1 쿠폰 적용 추적, admin 부재라 nil).
module AuditLogs
  class RecordService
    def self.call(admin: nil, action:, target: nil, detail: nil, ip: nil)
      AuditLog.create!(
        admin:, action:,
        target_type: target&.class&.name, target_id: target&.id,
        detail:, ip:
      )
    end
  end
end
