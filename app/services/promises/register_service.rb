# 응답(약속) 접수(F-PROMISE) — 뷰어(③) POST 경로의 단일 진입점. Promise 기록과 INV-4 상태
# 전이를 한 트랜잭션으로 묶어 기록과 전이가 항상 함께 확정되게 한다. 약속(this_week·
# date_selected) 접수 시 issued|viewed→promised 조건부 원자 전이를 수행하고(Invoice#
# mark_promised! — mark_viewed! 패턴), 입금 완료 회신·문의는 상태를 바꾸지 않는다(PROMISE-7 —
# 수금 마감은 U1 확인으로만). 시퀀스 중단·재스케줄(PROMISE-3)은 REM 도메인 부재로 이번
# 범위에서 N/A이며, U1 알림(PROMISE-4/7)은 채널 미계약으로 DASH-2 표시로 갈음한다
# (02_prd_update 승인 해석). 실패는 InvalidResponse로 예외화하고 실패 Promise(errors 포함)를
# 싣는다 — 컨트롤러가 422 응답을 조립하는 데 필요하다.
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
      end
      promise
    rescue ActiveRecord::RecordInvalid
      raise InvalidResponse, promise
    end

    private

    # 조작된 kind 등 이례 요청 — errors를 싣은 빈 Promise로 통일된 422 응답을 만든다.
    def invalid_promise(message)
      Promise.new(invoice: @invoice).tap { |blank| blank.errors.add(:kind, message) }
    end
  end
end
