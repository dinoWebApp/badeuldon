# 포트원 ClientService 테스트 대역 — 서비스(주입)·컨트롤러(PortOne::ClientService.new 스텁)
# 테스트가 공유한다. 실외부 호출이 절대 일어나지 않는다(PLAN-5 — 포트원 API 실호출 금지).
# 성공 응답·예외를 메서드별로 주입하고, 호출 인자를 기록해 서버 원값(paymentId·amount·채널 키)
# 전달을 검증한다.
class FakePortOneClient
  attr_reader :calls

  # 메서드별 기본 성공 응답(Hash)과 raise_on 예외(Exception 인스턴스)를 주입한다.
  # 응답 자리에 Proc을 넣으면 호출 시 평가한다(동적 응답·서열 시나리오용).
  def initialize(confirm_payment: { pgTxId: "pg_tx_fake_1", paidAt: "2026-10-15T09:00:00.000Z" },
                 issue_billing_key: { billingKey: "billing_key_fake_1" },
                 charge_billing_key: { payment: { id: "payment_fake_1", status: "PAID" } },
                 get_payment: { id: "payment_fake_1", status: "PAID" },
                 cancel_payment: { cancellation: { status: "SUCCEEDED" } },
                 raise_on: {})
    @responses = { confirm_payment:, issue_billing_key:, charge_billing_key:,
                   get_payment:, cancel_payment: }
    @raise_on = raise_on
    @calls = Hash.new { |hash, key| hash[key] = [] }
  end

  def confirm_payment(payment_id:, payment_token:, store_id: nil)
    record(:confirm_payment, payment_id:, payment_token:, store_id:)
  end

  def issue_billing_key(issue_token:, channel_key:, customer_id:, store_id: nil)
    record(:issue_billing_key, issue_token:, channel_key:, customer_id:, store_id:)
  end

  def charge_billing_key(payment_id:, billing_key:, channel_key:, amount:, customer_id:,
                         order_name:, store_id: nil)
    record(:charge_billing_key, payment_id:, billing_key:, channel_key:, amount:,
                                customer_id:, order_name:, store_id:)
  end

  def get_payment(payment_id:, store_id: nil)
    record(:get_payment, payment_id:, store_id:)
  end

  def cancel_payment(payment_id:, reason:, store_id: nil)
    record(:cancel_payment, payment_id:, reason:, store_id:)
  end

  private

  def record(method, kwargs)
    @calls[method] << kwargs
    raise @raise_on[method] if @raise_on[method]

    response = @responses[method]
    response.respond_to?(:call) ? response.call : response
  end
end
