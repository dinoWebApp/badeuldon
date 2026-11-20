# 입금 기록·마감(F-PAY) — U1의 원클릭 전액 마감(PAY-1)과 부분입금(PAY-2)의 단일 진입점.
# Payment 기록과 INV-4 전이(paid·partially_paid)를 한 트랜잭션으로 묶어 기록과 전이가 항상
# 함께 확정되게 한다. 청구서 행을 with_lock으로 직렬화하고 잠금 하에서 잔액을 재검증해
# 이중 클릭·동시 등록(두 탭)의 경합을 원자적으로 흡수한다(SEC 멱등 — 마감은 정확히 1회).
# 마감·기록은 U1만 수행하며 뷰어(③) 경로는 없다(PROMISE-7 — 채무자 paid_report는 상태를
# 바꾸지 않는다).
# Q22(2026-11-16 오기록 정책 확정):
# - 과다입금(금액 > 잔액) — 실제 입력 금액을 그대로 기록하고 잔액은 0 하한 처리
#   (Invoice#remaining_amount 클램프)로 수금 마감(paid). 초과분은 마감 기록 비고
#   (payments.note — 같은 트랜잭션에서 구조화 기록)과 감사 로그
#   (AuditLogs::RecordService — action "payment_over_recorded")에 병행 남기고
#   환불은 오프라인 안내(컨트롤러 플래시 문구)로 수렴한다. 자동 환불·차감 조정은 하지 않는다.
# - 마감(paid) 후 재입금 — payments 기록만 추가한다(상태 불변·알림 발화 없음·P4 기록 유지).
# 실패는 InvalidPayment로 예외화하고 실패 Payment(errors 포함)를 싣는다 — 컨트롤러가
# 422 응답을 조립하는 데 필요하다.
module Payments
  class RecordService
    class InvalidPayment < StandardError
      attr_reader :payment

      def initialize(payment)
        @payment = payment
        super(payment.errors.full_messages.first)
      end
    end

    # amount가 nil이면 PAY-1 원클릭 전액 마감 경로(폼에 금액 필드 부재 — 값이 아예 넘어오지
    # 않음)로, 남은 잔액 전체를 서버 기준값으로 계산한다. 빈 문자열은 전액으로 승격하지 않고
    # 모델 검증(입금 금액 미입력)으로 보낸다. 상한·미래 날짜 차단은 Payment 모델 담당이며
    # 기준 시각은 KST(Date.current — TIME-1)다. notify_thanks는 PAY-4 감사 알림 옵션(기본 켬).
    def initialize(invoice:, amount:, paid_on:, notify_thanks: true)
      @invoice = invoice
      @amount = amount
      @paid_on = paid_on
      @notify_thanks = notify_thanks
    end

    # 과다입금의 초과분(원). 마감 플래시 문구·감사 비고에 쓴다 — 정상·부분입금 경로는 0.
    def over_amount
      @over_amount || 0
    end

    # 마감(paid) 후 재입금 기록이었는지(Q22 — 상태 불변·알림 없음 경로).
    def post_paid_record?
      @post_paid_record == true
    end

    def call
      @invoice.with_lock do
        guard_recordable!
        @payment = record_payment!
        @post_paid_record = @invoice.paid?  # 전이 전 판정 — paid면 기록만 추가(전이·알림 없음)
        transition! unless post_paid_record?
      end
      audit_over_record if over_amount.positive?
      enqueue_reminder_notice  # 잠금 종료(커밋) 후 인큐
      @payment
    rescue ActiveRecord::RecordInvalid
      # save!/update! 실패 시 @payment는 record_payment!가 확보한 미저장 Payment(new 반환 후
      # 예외)다 — nil이 아님을 보장해 InvalidPayment가 errors를 읽을 수 있다(BUG-2 —
      # NoMethodError 방지).
      raise InvalidPayment, @payment || rejected_payment(nil)
    end

    private

    # 기록 가드 — 무효(void)·초안(draft)은 입금 기록 불가. paid는 Q22에 따라 "기록만 추가"
    # 경로로 통과시킨다(상태는 전이에서 건드리지 않는다).
    def guard_recordable!
      return if @invoice.unsettled? || @invoice.paid?

      raise InvalidPayment, rejected_payment("입금을 기록할 수 없는 상태의 청구서입니다")
    end

    # Q22 — 과다입금을 차단하지 않는다(구 결정 #3 폐기). 입력 금액을 원값 그대로 기록하고
    # 초과분은 over_amount로 보고한다(잔액은 Invoice#remaining_amount의 0 하한 클램프로
    # 0 처리). PAY-1 원클릭(nil)은 남은 잔액을 서버 기준값으로 계산한다. 기록은 with_lock
    # 직렬화 하에 있어 직전 트랜잭션의 등록이 반영된 최신 잔액 기준이다.
    def record_payment!
      remain = @invoice.total_amount - @invoice.payments.sum(:amount)
      # 원클릭(nil) 금액 미전송인데 잔액이 0이면(이중 클릭·마감 본 재클릭) 마감할 금액이
      # 없다 — "입금 금액 미입력" base 오류로 422 흡수한다(Q22 경계 — T8 고정 테스트).
      raise InvalidPayment, rejected_payment("입금 금액을 입력해 주세요") if @amount.nil? && remain <= 0
      # 금액은 원문자열을 그대로 Payment 검증에 통과시킨다 — 서비스에서 to_i로 선징제하면
      # "1.5"→1 같은 절삭이 only_integer 검증을 무력화한다(금액 무결성 — Phase 7 분기 수정).
      amount = @amount.nil? ? remain : @amount
      @payment = Payment.new(invoice_id: @invoice.id, amount: amount, paid_on: @paid_on)
      @payment.save!
      # 초과분 비고는 미수 계열 과다입금에 한정한다 — 마감 후 재입금(Q22)은 상태 불변 기록만
      # 추가하며 "초과분 마감" 개념이 성립하지 않는다. 저장 성공 후 캐스팅된 정수로 산정한다.
      @over_amount = @invoice.paid? ? 0 : [ @payment.amount - remain, 0 ].max
      # Q22 구조화 — 초과분을 마감 기록 자체(payments.note)에 남긴다. with_lock 트랜잭션
      # 안에서 함께 확정되므로 기록과 비고가 어긋나지 않는다(P4 — 마감 기록의 비고 무결성).
      @payment.update!(note: over_note) if @over_amount.positive?
      @payment
    end

    # 초과분 감사 기록(P4·Q22) — 마감 기록 비고(note)와 병행해 기존 감사 구조에도 남긴다.
    # 트랜잭션 확정 후 호출되며 target은 청구서(마감 기록의 소유체)다.
    def audit_over_record
      AuditLogs::RecordService.call(
        action: "payment_over_recorded", target: @invoice,
        detail: "과다입금 초과분 #{delimited(over_amount)}원 — 잔액 0 처리·수금 마감. 환불은 오프라인 안내"
      )
    end

    # 마감 기록 비고 문구(Q22) — U1 입금 이력에 표시되는 사용자 향 표기. 환불은 서비스가
    # 수행하지 않음을 명시한다(오프라인 협의 안내 — 자동 환불·차감 조정 없음).
    def over_note
      "입금액이 남은 잔액을 #{delimited(over_amount)}원 초과하여 마감 처리 — 초과분 환불은 거래처와 직접 협의"
    end

    # INV-4 전이 — 생성 직후 합계를 재조회해 기준을 확정한다: 총액 도달(과다입금 포함 —
    # 실제 금액 기록이므로 음수 도달) → 마감(PAY-1·Q22), 미달 → 부분입금(PAY-2).
    # with_lock 직렬화로 두 트랜잭션이 동시에 도달 판정에 성공할 수 없다.
    def transition!
      if @invoice.total_amount - @invoice.payments.sum(:amount) <= 0
        @invoice.mark_paid!
        @fully_paid = true
      else
        @invoice.mark_partially_paid!
        @fully_paid = false
      end
    end

    # F-REM 훅 — 채무자 향 1회성 발송(PLAN-3 상한 집계 밖). REM-3 창 밖이면 SendService가
    # 다음 평일 09시로 예약한다(확정 해석 3·4). 마감 후 재입금(Q22)은 발화하지 않는다.
    # - 전액 마감: paid_thanks(PAY-4 — 선택 옵션, 기본 켬)
    # - 부분입금: partial_paid(REM-4·PAY-2 — Q23: 추가 입금 건마다 재발송, SendService 참조)
    def enqueue_reminder_notice
      return if post_paid_record?

      if @fully_paid
        return unless @notify_thanks

        Reminders::DeliverJob.perform_later(@invoice.id, "paid_thanks", "debtor")
      else
        Reminders::DeliverJob.perform_later(@invoice.id, "partial_paid", "debtor")
      end
    end

    # 컨트롤러 422 조립용 실패 Payment — 입력한 입금일을 보존해 재렌더 폼에 되돌려주고,
    # base 오류는 플래시·필드 오류는 폼 인라인 표시에 쓴다(App::PromisesController 패턴).
    # 컬렉션에 붙이지 않는다(부모 저장 시 자동 저장 대상이 되는 것을 방지 — set_payments 주석).
    def rejected_payment(message)
      Payment.new(invoice_id: @invoice.id, paid_on: @paid_on).tap do |payment|
        payment.errors.add(:base, message) if message
      end
    end

    def delimited(amount)
      ActiveSupport::NumberHelper.number_to_delimited(amount)
    end
  end
end
