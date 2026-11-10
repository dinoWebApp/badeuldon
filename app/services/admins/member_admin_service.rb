# ADMIN-3 회원 관리 서비스(Run B) — 플랜 수동 변경·계정 정지/해제.
# 감사 기록(ADMIN-2)은 이 서비스 내부에서 AuditLogs::RecordService로 수행한다.
# §4.2 의존 방향: Service→Service는 허용되며 컨트롤러는 얇게 유지한다(02 확정 해석 4의
# "RecordService 경유"를 만족 — 컨트롤러 직접 AuditLog create는 여전히 금지).
# 모든 변경은 transaction으로 원자화하고, 검증 실패는 예외 없이 result 해시(errors)로 반환한다.
module Admins
  class MemberAdminService
    Result = Struct.new(:success, :errors, :message, keyword_init: true) do
      def success? = success
    end

    # 플랜 수동 변경 규칙(PRD v0.31 ADMIN-3 확정):
    # - grant_trial    : 체험 전환 — 활성(Plus) 구독 보유 시 금지, used_trial이면 1회 가드
    # - extend_trial   : 체험 연장 — current_period_end를 months개월 연장(trialing이면 trial_ends_at 동기화)
    # - cancel_subscription : 구독 해지 — Subscription#cancel!(기간 말까지 유효 — PLAN-5)
    def self.change_plan!(admin:, user:, plan_params:)
      new.change_plan!(admin:, user:, plan_params:)
    end

    # 정지/해제 토글 — 정지 시 user.sessions 전부 파기(02 확정 해석 5).
    def self.toggle_suspension!(admin:, user:)
      new.toggle_suspension!(admin:, user:)
    end

    def change_plan!(admin:, user:, plan_params:)
      action = plan_params[:action].to_s
      months = plan_params[:months].presence&.to_i || 1
      case action
      when "grant_trial" then grant_trial!(admin, user)
      when "extend_trial" then extend_trial!(admin, user, months)
      when "cancel_subscription" then cancel_subscription!(admin, user)
      else failure("알 수 없는 플랜 변경 요청입니다: #{action}")
      end
    end

    def toggle_suspension!(admin:, user:)
      suspending = user.active?
      user.transaction do
        if suspending
          user.update!(status: :suspended)
          user.sessions.destroy_all # 정지 계정의 기존 세션 전부 파기 — 재로그인 차단과 짝
        else
          user.update!(status: :active)
        end
        AuditLogs::RecordService.call(
          admin:, action: suspending ? "member_suspend" : "member_unsuspend", target: user
        )
      end
      Result.new(success: true, errors: [], message: suspending ? "회원을 정지했습니다. 기존 세션도 종료되었습니다." : "정지를 해제했습니다.")
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.join(", "))
    end

    private

    def grant_trial!(admin, user)
      subscription = user.subscription
      return failure("구독 행이 없어 체험을 시작할 수 없습니다.") unless subscription
      return failure("활성 Plus 구독이 있어 체험으로 전환할 수 없습니다.") if active_plus?(subscription)
      return failure("무료 체험은 계정당 1회입니다.") if subscription.used_trial?

      subscription.start_trial!
      record_plan_change(admin, user, "플랜 수동 변경: 체험 전환(14일)")
      Result.new(success: true, errors: [], message: "무료 체험을 시작했습니다(14일).")
    rescue Subscription::TrialAlreadyUsedError
      failure("무료 체험은 계정당 1회입니다.")
    end

    def extend_trial!(admin, user, months)
      return failure("연장 개월은 1~12개월 사이로 입력해 주세요.") unless (1..12).cover?(months) # W-5

      subscription = user.subscription
      return failure("구독 행이 없어 체험을 연장할 수 없습니다.") unless subscription
      return failure("활성 Plus 구독이 있어 체험 연장을 적용할 수 없습니다.") if active_plus?(subscription)

      base = [ subscription.current_period_end, subscription.trial_ends_at, Time.current ].compact.max
      subscription.update!(current_period_end: base + months.months)
      subscription.update!(trial_ends_at: subscription.current_period_end) if subscription.trialing?
      record_plan_change(admin, user, "플랜 수동 변경: 체험 연장 #{months}개월")
      Result.new(success: true, errors: [], message: "이용 기간을 #{months}개월 연장했습니다.")
    end

    def cancel_subscription!(admin, user)
      subscription = user.subscription
      return failure("구독 행이 없어 해지할 수 없습니다.") unless subscription
      return failure("이미 해지 상태입니다.") if subscription.cancelled?

      subscription.cancel!
      record_plan_change(admin, user, "플랜 수동 변경: 구독 해지(기간 말까지 유효 — PLAN-5)")
      Result.new(success: true, errors: [], message: "구독을 해지했습니다. 현재 기간 종료까지 유효합니다.")
    end

    def active_plus?(subscription)
      subscription.plus? && subscription.active?
    end

    def record_plan_change(admin, user, detail)
      AuditLogs::RecordService.call(admin:, action: "member_plan_change", target: user, detail:)
    end

    def failure(message)
      Result.new(success: false, errors: [ message ], message: nil)
    end
  end
end
