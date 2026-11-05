# 응답(약속) 접수(F-PROMISE) — 뷰어(③) POST 경로의 단일 진입점. Promise 기록과 INV-4 상태
# 전이를 한 트랜잭션으로 묶어 기록과 전이가 항상 함께 확정되게 한다. 약속(this_week·
# date_selected) 접수 시 issued|viewed→promised 조건부 원자 전이를 수행하고(Invoice#
# mark_promised! — mark_viewed! 패턴), 입금 완료 회신·문의는 상태를 바꾸지 않는다(PROMISE-7 —
# 수금 마감은 U1 확인으로만). 발송 중단 계열 응답은 같은 트랜잭션에서 즉시 마킹한다 —
# paid_report는 해당 청구 일시정지(REM-7·PROMISE-7), refusal은 거래처 번호 단위 수신거부 +
# 해당 청구 시퀀스 종결(VIEW-7 즉시 중단). 약속 재스케줄(PROMISE-3)의 발송은 DispatchService가
# 최신 약속 기준으로 무상태 재계산한다. U1 향 알림(noti_promise·noti_deposit_reply·
# noti_inquiry·noti_refusal)은 커밋 후 인큐하며 REM-3 창 없이 즉시 발송된다(확정 해석 3).
# 실패는 InvalidResponse로 예외화하고 실패 Promise(errors 포함)를 싣는다 — 컨트롤러가 422
# 응답을 조립하는 데 필요하다.
module Promises
  class RegisterService
    class InvalidResponse < StandardError
      attr_reader :promise

      def initialize(promise)
        @promise = promise
        super(promise.errors.full_messages.first)
      end
    end

    def initialize(invoice:, kind:, promised_on: nil, memo: nil)
      @invoice = invoice
      @kind = kind
      @promised_on = promised_on
      @memo = memo
    end

    def call
      unless Promise.kinds.key?(@kind.to_s)
        raise InvalidResponse, invalid_promise("응답을 처리할 수 없습니다. 다시 시도해 주세요")
      end

      promise = @invoice.promises.build(kind: @kind, promised_on: @promised_on, memo: @memo)
      ActiveRecord::Base.transaction do
        promise.save!
        # INV-4 — 약속 접수의 조건부 전이. 이미 promised인 재응답은 무변경으로 흡수된다.
        @invoice.mark_promised! if promise.this_week? || promise.date_selected?
        apply_reminder_state(promise)
      end
      enqueue_reminder_notice(promise)  # 커밋(트랜잭션 종료) 후 인큐
      promise
    rescue ActiveRecord::RecordInvalid
      raise InvalidResponse, promise
    end

    private

    # 발송 중단 계열 응답의 상태 마킹 — 응답 기록과 중단이 항상 함께 확정되게 같은 트랜잭션에
    # 둔다. update_column은 타임스탬프 마킹만 수행하는 의도된 우회다(본문 불변·검증 재실행 불필요).
    # - paid_report(PROMISE-7): 해당 청구 즉시 일시정지 — 마감은 U1 확인으로만 확정된다.
    # - refusal(VIEW-7): 거래처 번호 단위 수신거부(전 청구 즉시 중단) + 해당 청구 시퀀스 종결.
    def apply_reminder_state(promise)
      if promise.paid_report?
        @invoice.update_column(:reminders_suspended_at, Time.current) unless @invoice.reminders_suspended?
      elsif promise.refusal?
        @invoice.client.update_column(:refused_at, Time.current) unless @invoice.client.refused?
        @invoice.finish_sequence!
      end
    end

    # U1 향 즉시 알림(PERF-1·NOTI-1) — 트랜잭션 커밋 후 인큐한다. U1 향이므로 REM-3 창을
    # 적용하지 않는다(SendService가 recipient_role로 분기 — 확정 해석 3).
    def enqueue_reminder_notice(promise)
      template_key =
        if promise.this_week? || promise.date_selected?
          "noti_promise"       # PROMISE-4 — this_week는 "이번 주 내" 치환(SendService 변수 조립)
        elsif promise.paid_report?
          "noti_deposit_reply" # PROMISE-7
        elsif promise.inquiry?
          "noti_inquiry"       # PROMISE-6
        elsif promise.refusal?
          "noti_refusal"       # VIEW-7 — 발송 즉시 중단 사실 포함
        end
      return unless template_key

      Reminders::DeliverJob.perform_later(@invoice.id, template_key, "user")
    end

    # 조작된 kind 등 이례 요청 — errors를 싣은 빈 Promise로 통일된 422 응답을 만든다.
    def invalid_promise(message)
      Promise.new(invoice: @invoice).tap { |blank| blank.errors.add(:kind, message) }
    end
  end
end
