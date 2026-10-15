# 토스페이먼츠 ClientService 테스트 대역 — 서비스(주입)·컨트롤러(TossPayments::ClientService.new
# 스텁) 테스트가 공유한다. 실외부 호출이 절대 일어나지 않는다(PLAN-5 — 토스 API 실호출 금지).
# 성공 응답·예외를 메서드별로 주입하고, 호출 인자를 기록해 서버 원값(orderId·amount) 전달을 검증한다.
class FakeTossClient
  attr_reader :calls

  # 메서드별 기본 성공 응답(Hash)과 raise_on 예외( Exception 인스턴스)를 주입한다.
  # 응답 자리에 Proc을 넣으면 호출 시 평가한다(동적 응답·서열 시나리오용).
  def initialize(confirm_payment: { paymentKey: "pay_fake_1", status: "DONE", method: "카드" },
                 issue_billing_key: { billingKey: "tok_billing_fake_1" },
                 charge_billing_key: { paymentKey: "pay_fake_1", status: "DONE" },
                 get_payment: { status: "DONE" },
                 raise_on: {})
    @responses = { confirm_payment:, issue_billing_key:, charge_billing_key:, get_payment: }
    @raise_on = raise_on
    @calls = Hash.new { |hash, key| hash[key] = [] }
  end

  def confirm_payment(order_id:, payment_key:, amount:)
    record(:confirm_payment, order_id:, payment_key:, amount:)
  end

  def issue_billing_key(customer_key:, auth_key:)
    record(:issue_billing_key, customer_key:, auth_key:)
  end

  def charge_billing_key(customer_key:, billing_key:, order_id:, amount:)
    record(:charge_billing_key, customer_key:, billing_key:, order_id:, amount:)
  end

  def get_payment(payment_key:)
    record(:get_payment, payment_key:)
  end

  private

  def record(method, kwargs)
    @calls[method] << kwargs
    raise @raise_on[method] if @raise_on[method]

    response = @responses[method]
    response.respond_to?(:call) ? response.call : response
  end
end
