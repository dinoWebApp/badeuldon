# AUTH-1.5 회원 자진 탈퇴(Q29) — 설정 화면 위험 구역에서 본인이 직접 실행한다.
# 관리자 콘솔의 계정 삭제(Admins::AccountPurgeService — Q13)와 의도적으로 다른 점:
# ① 미수 청구가 있어도 막지 않는다(본인 결정 — 건수·금액은 탈퇴 화면에서 미리 고지한다)
# ② 실행자가 회원 본인이므로 감사 로그의 admin은 nil이다(ADMIN-2 — detail에 이메일 스냅샷 기록).
#
# 실행 순서가 중요하다: 감사 기록은 삭제 트랜잭션 "내부에서 먼저" 남긴다 — user 삭제 후에는
# target_id 참조만 남으므로 detail 문자열에 이메일 스냅샷을 기록한다(Q13 감사 보존 선례).
# audit_logs는 admin 소유(admin_id FK · user 참조 없음 — db/schema.rb 실측)라 user 삭제로
# 소멸하지 않는다.
#
# detail에는 삭제 전에 계산한 탈퇴 시점 요약(미수 건수·잔액, Plus 이용 상태, 잔여 수금 패스 —
# ADMIN-2·PRD AUTH-1.5)도 함께 굳진다. 삭제 뒤에는 조인해 볼 원본이 없으므로 숫자·상태만
# 문자열로 남긴다(추가 개인정보 없음).
#
# 연쇄 삭제는 user.rb의 dependent: :destroy 선언(세션→recurring_invoices→invoices→
# clients→items→subscription·orders·payment_passes·notice_reads·tickets·tax_invoices)에
# 위임한다(선언 순서가 곧 파괴 순서 — B-1 주석 참조, 변경 금지). 삭제된 청구의 예약 발송 잡은
# Reminders::DeliverJob의 discard_on ActiveRecord::RecordNotFound로 버려진다(기존).
module Users
  class WithdrawalService
    Result = Struct.new(:success, :message, keyword_init: true) do
      def success? = success
    end

    def self.call(user:, confirm_email:, ip: nil)
      new.call(user:, confirm_email:, ip:)
    end

    def call(user:, confirm_email:, ip: nil)
      return failure("이메일이 일치하지 않습니다. 가입한 이메일을 다시 입력해 주세요.") unless email_confirmed?(user, confirm_email)

      user.transaction do
        AuditLogs::RecordService.call(
          admin: nil, action: "member_withdrawal", target: user,
          detail: withdrawal_detail(user), ip: ip
        )
        user.destroy!
      end
      Result.new(success: true, message: "탈퇴가 완료되었습니다. 그동안 이용해 주셔서 감사합니다.")
    rescue ActiveRecord::RecordNotDestroyed => e
      failure(e.record.errors.full_messages.join(", "))
    rescue ActiveRecord::InvalidForeignKey => e
      # 연쇄 순서(선언 순서)와 FK restrict가 어긋난 재발 시 500 대신 회원 안내 오류로 변환한다
      # (관리자 삭제 서비스와 같은 마지막 방어 — 재발 시 user.rb 선언 순서 점검).
      Rails.logger.warn(
        "[Users::WithdrawalService] 연쇄 삭제 참조 제약 — user_id=#{user.id} (#{e.class}: #{e.message})"
      )
      failure("탈퇴 처리 중 오류가 발생했습니다. 잠시 후 다시 시도하거나 문의해 주세요.")
    end

    private

    # AUTH-1.4 정규화(normalizes :email)와 동일 기준으로 비교 — 관리자 삭제 서비스와 같은 방식.
    def email_confirmed?(user, confirm_email)
      confirm_email.to_s.strip.downcase == user.email
    end

    # 탈퇴 시점 요약(ADMIN-2·AUTH-1.5) — 삭제 전에만 계산할 수 있으므로 감사 직전에 산출해
    # detail 문자열로 굳진다. 잔액은 DASH-1과 같은 계산식(Σ총액 − Σ입금액 — 부분입금 반영),
    # 수금 패스는 PaymentPass.usable의 잔여 합계(PLAN-4), Plus 상태는 구독 행의 plan+status다.
    def withdrawal_detail(user)
      unsettled = user.invoices.unsettled
      balance = unsettled.sum(:total_amount) -
                Payment.where(invoice_id: unsettled.select(:id)).sum(:amount)
      "회원 탈퇴 — 이메일 스냅샷: #{user.email} · " \
        "미수 #{unsettled.count}건(잔액 #{balance}원) · Plus: #{plus_state(user)} · " \
        "수금 패스 #{user.payment_passes.usable.sum(:remaining_uses)}건"
    end

    # Plus 이용 상태 — expire!가 plan을 free로 되돌리므로 plus?는 trialing·active·cancelled에서만
    # 참이다(cancelled = 해지 예약 — 자동 결제는 끝났고 기간 말까지 Plus인 상태, PLAN-5).
    def plus_state(user)
      subscription = user.subscription
      return "없음" unless subscription&.plus?
      return "체험" if subscription.trialing?
      return "유료(해지 예약)" if subscription.cancelled?
      return "유료" unless subscription.current_period_end

      "유료(종료 #{subscription.current_period_end.strftime('%-m-%-d')})"
    end

    def failure(message)
      Result.new(success: false, message:)
    end
  end
end
