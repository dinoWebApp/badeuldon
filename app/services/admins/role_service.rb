# ADMIN-1·AUTH-7.2 — 관리자 롤·계정 콘솔 서비스(T-C1). 계정 생성·role 변경·잠금 해제.
# AUTH-7.2: 추가 계정은 최고 관리자(owner)만 콘솔에서 생성 — 공개 가입 경로는 없다.
# 감사 기록(ADMIN-2)은 MemberAdminService 선례대로 이 서비스 내부에서
# AuditLogs::RecordService 경유로 수행한다(§4.2 Service→Service 허용·컨트롤러 직접 create 금지).
# 모든 변경은 transaction으로 원자화하고, 규칙 위반은 예외 없이 Result로 반환한다.
module Admins
  class RoleService
    Result = Struct.new(:success, :errors, :message, keyword_init: true) do
      def success? = success
    end

    # role 승격/강등 — owner 전용. 최고 관리자 유일성 보장을 위해 owner가 자기 자신을
    # staff로 강등하는 것은 금지한다(모든 owner가 스스로 강등하면 콘솔 운영 불가).
    def self.change_role!(admin:, actor:, role:)
      new.change_role!(admin:, actor:, role:)
    end

    # 잠금 해제(AUTH-7.3) — owner 전용. locked_at/failed_attempts 초기화.
    def self.unlock!(admin:, actor:)
      new.unlock!(admin:, actor:)
    end

    # 신규 관리자 생성 — owner 전용. 중복·검증 실패는 Result로 반환.
    def self.create_admin!(actor:, email:, password:, role:)
      new.create_admin!(actor:, email:, password:, role:)
    end

    # 컨트롤러 가드(require_owner)가 staff 접근을 차단할 때의 감사 기록 전용 진입점.
    # ADMIN-2 — 컨트롤러 직접 AuditLog create 금지를 우회하지 않기 위한 경유점.
    # (수정: 클래스 메서드에서 private 인스턴스 record_denial을 암시적 호출하던 결함 —
    #  3-S 결선 후 staff 차단 경로 NoMethodError 3건. RecordService 직접 경유로 수정.)
    def self.record_denied!(actor:, action:, detail: nil)
      AuditLogs::RecordService.call(
        admin: actor, action: action,
        detail: detail || "owner 전용 작업에 staff가 시도했습니다: #{actor.email}"
      )
      Result.new(success: false, errors: [ "이 작업은 최고 관리자(owner)만 수행할 수 있습니다." ], message: nil)
    end

    def change_role!(admin:, actor:, role:)
      return denial(actor, "admin_role_denied") unless actor.owner?
      return failure("최고 관리자는 자기 자신을 staff로 강등할 수 없습니다.") if admin.id == actor.id && role.to_s == "staff"
      return failure("알 수 없는 롤입니다: #{role}") unless Admin.roles.key?(role.to_s)

      admin.transaction do
        admin.update!(role: role)
        AuditLogs::RecordService.call(
          admin: actor, action: "admin_role_change", target: admin,
          detail: "관리자 롤 변경: #{admin.email} → #{admin.role}"
        )
      end
      Result.new(success: true, errors: [], message: "#{admin.email}의 롤을 #{admin.role}로 변경했습니다.")
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.join(", "))
    end

    def unlock!(admin:, actor:)
      return denial(actor, "admin_unlock_denied") unless actor.owner?
      return failure("잠금 상태가 아닌 계정입니다.") unless admin.locked?

      admin.transaction do
        admin.unlock!
        AuditLogs::RecordService.call(
          admin: actor, action: "admin_unlock", target: admin,
          detail: "관리자 잠금 해제: #{admin.email}"
        )
      end
      Result.new(success: true, errors: [], message: "#{admin.email} 계정의 잠금을 해제했습니다.")
    end

    def create_admin!(actor:, email:, password:, role:)
      return denial(actor, "admin_create_denied") unless actor.owner?
      # C-1 — change_role!과 동일 기준(enum 사전 검사)으로 무효 롤은 Result 거부.
      # enum 할당 ArgumentError → 500 방지(감사 실패 미기록 정책 유지).
      return failure("알 수 없는 롤입니다: #{role}") unless Admin.roles.key?(role.to_s)

      # ProvisionService 선례 — otp_secret은 발급하지 않고 최초 로그인 시 2FA 등록 화면에서 발급.
      admin = Admin.new(email: email, password: password, role: role)
      admin.transaction do
        admin.save!
        AuditLogs::RecordService.call(
          admin: actor, action: "admin_create", target: admin,
          detail: "관리자 계정 생성: #{admin.email} (#{admin.role})"
        )
      end
      Result.new(success: true, errors: [], message: "관리자 계정을 생성했습니다: #{admin.email}")
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.join(", "))
    end

    private

    # staff 접근 — 거부 사유 Result 반환 + admin_*_denied 감사 기록.
    def denial(actor, action)
      record_denial(actor, action, "owner 전용 작업에 staff가 시도했습니다: #{actor.email}")
      failure("이 작업은 최고 관리자(owner)만 수행할 수 있습니다.")
    end

    def record_denial(actor, action, detail)
      AuditLogs::RecordService.call(admin: actor, action: action, detail: detail)
    end

    def failure(message)
      Result.new(success: false, errors: [ message ], message: nil)
    end
  end
end
