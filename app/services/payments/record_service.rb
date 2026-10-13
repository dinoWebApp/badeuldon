# 입금 기록·마감(F-PAY) — U1의 원클릭 전액 마감(PAY-1)과 부분입금(PAY-2)의 단일 진입점.
# Payment 기록과 INV-4 전이(paid·partially_paid)를 한 트랜잭션으로 묶어 기록과 전이가 항상
# 함께 확정되게 한다. 청구서 행을 with_lock으로 직렬화하고 잠금 하에서 잔액을 재검증해
# 이중 클릭·동시 등록(두 탭)으로 잔액이 초과되는 경로를 원자적으로 차단한다(SEC 멱등 —
# 마감은 정확히 1회). 마감은 U1만 수행하며 뷰어(③) 경로는 없다(PROMISE-7 — 채무자
# paid_report는 상태를 바꾸지 않는다). 실패는 InvalidPayment로 예외화하고 실패
# Payment(errors 포함)를 싣는다 — 컨트롤러가 422 응답을 조립하는 데 필요하다.
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
    # 기준 시각은 KST(Date.current — TIME-1)다.
    def initialize(invoice:, amount:, paid_on:)
      @invoice = invoice
      @amount = amount
      @paid_on = paid_on
    end

    def call
      payment = nil
      @invoice.with_lock do
        guard_payable!
        remain = @invoice.total_amount - @invoice.payments.sum(:amount)
        amount = @amount.nil? ? remain : guard_within_remain(@amount, remain)
        # 컬렉션 분리형 생성 — 실패 시 검증 오류를 지닌 레코드를 그대로 422 조립에 넘긴다.
        payment = Payment.new(invoice_id: @invoice.id, amount: amount, paid_on: @paid_on)
        payment.save!
        transition!
      end
      payment
    rescue ActiveRecord::RecordInvalid
      raise InvalidPayment, payment
    end

    private

    # 전이 가드(INV-4) — 초안·무효·이미 마감된 건은 입금 기록 불가(422 회귀). with_lock이
    # 최신 상태를 보장하므로 이중 클릭의 두 번째 요청은 정확히 이 가드에서 흡수된다.
    def guard_payable!
      return if @invoice.unsettled?

      message = @invoice.paid? ? "이미 수금이 마감된 청구서입니다" : "입금을 기록할 수 없는 상태의 청구서입니다"
      raise InvalidPayment, rejected_payment(message)
    end

    # 잔액 초과 차단(결정 #3 — 초과 입금 기록 불가, 정확한 마감만 허용). remain은 잠금 하
    # 재조회값이므로 직전 트랜잭션의 등록이 반영된 최신 잔액이다. 금액은 원값을 그대로
    # create!로 넘겨 모델 검증이 최종 판정한다(to_i 승격에 의한 값 왜곡 방지).
    def guard_within_remain(amount, remain)
      return amount if amount.to_i <= remain

      # do...end가 raise에 묶이는 것을 피하기 위해 선대입한다(raise 인자 우선순위 함정).
      failed = rejected_payment(nil)
      failed.errors.add(:amount, "입금 금액이 남은 잔액(#{delimited(remain)}원)보다 큽니다. 잔액 이하로 입력해 주세요")
      raise InvalidPayment, failed
    end

    # INV-4 전이 — 생성 직후 합계를 재조회해 기준을 확정한다: 총액 도달 → 마감(PAY-1),
    # 미달 → 부분입금(PAY-2, 잔액은 Invoice#remaining_amount 기준). with_lock 직렬화로
    # 두 트랜잭션이 동시에 도달 판정에 성공할 수 없다.
    def transition!
      if @invoice.total_amount - @invoice.payments.sum(:amount) <= 0
        @invoice.mark_paid!
      else
        @invoice.mark_partially_paid!
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
