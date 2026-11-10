# ADMIN-3 ④ 계정 삭제·데이터 파기(Q13) — AUTH-1.5 준용.
# 가드: ① 이메일 타이핑 2중 확인 ② 미수 청구서 존재 시 차단(Q13 — 완납·무효·초안만 허용).
# 권한: staff도 실행 가능(ADMIN-3 회원 관리 권한 선임 — 운영 안전은 2중 확인·미수 차단·
# 감사 기록으로 담보하며 별도 owner 전용 가드를 두지 않는다).
# 실행 순서가 중요하다: 감사 기록은 삭제 트랜잭션 "내부에서 먼저" 남긴다 — user 삭제 후에는
# target_id 참조만 남으므로 detail 문자열에 이메일 스냅샷을 기록한다(Q13 감사 보존).
# audit_logs는 admin 소유(admin_id FK · user 참조 없음 — db/schema.rb 실측)라 user 삭제로
# 소멸하지 않는다.
#
# 연쇄 삭제는 user.rb의 dependent: :destroy 선언(user.sessions→recurring_invoices→
# invoices→clients→items→subscription·orders·payment_passes·notice_reads·tickets)에 위임한다
# — recurring_invoices가 invoices보다 먼저 선언돼야 last_invoice FK restrict(B-1)가 해소된다.
# message_logs는 user에 직접 선언되지 않지만 invoices의 DB FK on_delete: :cascade로
# invoices 삭제 시 함께 소멸한다. 미수 차단 가드 덕분에 발행(비초안) 이력 있는 계정은
# 원천 차단되므로 발송 기록(P4) 소실은 초안 전용 계정(발송 이력 자체가 없음)에서만 발생한다.
module Admins
  class AccountPurgeService
    Result = Struct.new(:success, :errors, :message, keyword_init: true) do
      def success? = success
    end

    def self.call(admin:, user:, confirm_email:)
      new.call(admin:, user:, confirm_email:)
    end

    def call(admin:, user:, confirm_email:)
      return failure("확인용 이메일이 일치하지 않습니다.") unless email_confirmed?(user, confirm_email)

      unsettled = user.invoices.unsettled
      if unsettled.exists?
        return failure(
          "미수 청구가 있는 계정은 삭제할 수 없습니다. " \
          "(미수 #{unsettled.count}건 · 합계 #{unsettled.sum(:total_amount)}원)"
        )
      end

      user.transaction do
        AuditLogs::RecordService.call(
          admin:, action: "account_purge", target: user,
          detail: "계정 삭제·데이터 파기 — 이메일 스냅샷: #{user.email}"
        )
        user.destroy!
      end
      Result.new(success: true, errors: [], message: "회원 계정과 데이터를 삭제했습니다. (#{user.email})")
    rescue ActiveRecord::RecordNotDestroyed => e
      failure(e.record.errors.full_messages.join(", "))
    rescue ActiveRecord::InvalidForeignKey => e
      # B-1 방어선 — 연쇄 순서(선언 순서)와 FK restrict가 어긋난 재발 시 500 대신 관리자 안내
      # 오류로 변환한다(연쇄 삭제 위임 구조의 마지막 방어 — 재발 시 user.rb 선언 순서 점검).
      failure("연쇄 삭제 중 참조 제약에 걸렸습니다. 관리자에게 문의해 주세요. (#{e.class})")
    end

    private

    # AUTH-1.4 정규화(normalizes :email)와 동일 기준으로 비교 — 대소문자·공백 차이 허용 안 함.
    def email_confirmed?(user, confirm_email)
      confirm_email.to_s.strip.downcase == user.email
    end

    def failure(message)
      Result.new(success: false, errors: [ message ], message: nil)
    end
  end
end
