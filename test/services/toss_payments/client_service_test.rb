require "test_helper"
require_relative "../../test_helpers/toss_stubbing"

# 토스페이먼츠 ClientService — 전송 계층(Net::HTTP)을 스텁해 요청 구성·응답 파싱·오류 정규화를
# 검증한다(PLAN-5·§6.19 EXT). 실외부 호출 0건 — 토스 API 실호출 금지 규약의 1차 방어선 검증.
# 시나리오 기준: _workspace/03_implementation.md §4 (토스 API 매핑 표).
class TossPayments::ClientServiceTest < ActiveSupport::TestCase
  include TossStubbing

  SECRET = "test_secret_key_skZZ"

  setup do
    @client = TossPayments::ClientService.new(secret_key: SECRET)
  end

  test "단건 승인은 /v1/payments/confirm에 orderId·paymentKey·amount를 POST한다" do
    transport = transport_returning(success_response(paymentKey: "pay_1", status: "DONE"))

    result = with_stubbed_transport(transport) do
      @client.confirm_payment(order_id: "order-1", payment_key: "pay_1", amount: 4_000)
    end

    assert_equal({ paymentKey: "pay_1", status: "DONE" }, result)
    request = transport.requests.sole
    assert_equal "POST", request.method
    assert_equal "/v1/payments/confirm", request.path
    assert_equal({ "orderId" => "order-1", "paymentKey" => "pay_1", "amount" => 4_000 },
                 JSON.parse(request.body))
  end

  test "빌링키 발급은 /v1/billing/authorizations/issue에 customerKey·authKey를 POST한다" do
    transport = transport_returning(success_response(billingKey: "tok_billing_1"))

    result = with_stubbed_transport(transport) do
      @client.issue_billing_key(customer_key: "cust_1", auth_key: "auth_1")
    end

    assert_equal({ billingKey: "tok_billing_1" }, result)
    request = transport.requests.sole
    assert_equal "POST", request.method
    assert_equal "/v1/billing/authorizations/issue", request.path
    assert_equal({ "customerKey" => "cust_1", "authKey" => "auth_1" }, JSON.parse(request.body))
  end

  test "정기 차감은 /v1/billing/{customerKey}에 빌링 결제 정보를 POST한다" do
    transport = transport_returning(success_response(paymentKey: "pay_2", status: "DONE"))

    result = with_stubbed_transport(transport) do
      @client.charge_billing_key(customer_key: "cust_1", billing_key: "tok_billing_1",
                                 order_id: "order-2", amount: 9_900)
    end

    assert_equal({ paymentKey: "pay_2", status: "DONE" }, result)
    request = transport.requests.sole
    assert_equal "POST", request.method
    assert_equal "/v1/billing/cust_1", request.path
    assert_equal({ "customerKey" => "cust_1", "billingKey" => "tok_billing_1",
                   "orderId" => "order-2", "amount" => 9_900 }, JSON.parse(request.body))
  end

  test "결제 조회는 /v1/payments/{paymentKey}를 GET한다 (웹훅 무결성 재조회)" do
    transport = transport_returning(success_response(status: "CANCELED"))

    result = with_stubbed_transport(transport) do
      @client.get_payment(payment_key: "pay_1")
    end

    assert_equal({ status: "CANCELED" }, result)
    request = transport.requests.sole
    assert_equal "GET", request.method
    assert_equal "/v1/payments/pay_1", request.path
    assert_nil request.body
  end

  test "인증은 secret_key Basic Auth(비밀번호 없음)다" do
    transport = transport_returning(success_response({}))

    with_stubbed_transport(transport) do
      @client.get_payment(payment_key: "pay_1")
    end

    request = transport.requests.sole
    assert_equal "Basic #{[ "#{SECRET}:" ].pack("m0")}", request["Authorization"]
  end

  test "비2xx 응답은 상태·코드·메시지를 운반하는 ApiError로 정규화된다" do
    transport = transport_returning(
      error_response(404, { code: "NOT_FOUND", message: "존재하지 않는 결제입니다" })
    )

    error = assert_raises(TossPayments::ApiError) do
      with_stubbed_transport(transport) { @client.get_payment(payment_key: "pay_x") }
    end

    assert_equal 404, error.status
    assert_equal "NOT_FOUND", error.code
    assert_equal "존재하지 않는 결제입니다", error.message
  end

  test "빈 본문 2xx 응답은 빈 Hash로 파싱된다" do
    transport = transport_returning(success_response(nil))

    result = with_stubbed_transport(transport) { @client.get_payment(payment_key: "pay_1") }

    assert_equal({}, result)
  end

  test "타임아웃은 code TIMEOUT인 ApiError로 정규화된다" do
    assert_error_normalized(Net::OpenTimeout.new("execution expired"), "TIMEOUT")
  end

  test "접속 실패는 code CONNECTION인 ApiError로 정규화된다" do
    assert_error_normalized(SocketError.new("Failed to open TCP connection"), "CONNECTION")
  end

  private

  # 응답(또는 예외)을 돌려주는 전송 계층 대역 — request 호출 인자를 기록한다.
  # Net::HTTPResponse는 start 블록 밖 읽기를 가정해 지연 본문 읽기를 강제하므로(IOError),
  # 본문을 즉시 돌려주는 하위 클래스로 만든다.
  def transport_returning(response, &request_block)
    transport = Struct.new(:response, :requests, keyword_init: true).new(response: nil, requests: [])
    fake_http = Object.new
    fake_http.define_singleton_method(:request) do |net_request|
      transport.requests << net_request
      request_block ? request_block.call(response) : response
    end
    transport.define_singleton_method(:stub_start) do |*_args, &block|
      raise response if response.is_a?(Exception)

      block.call(fake_http)
    end
    transport
  end

  def with_stubbed_transport(transport)
    with_http_transport(transport) { yield }
  end

  def success_response(payload)
    FakeSuccessResponse.new(payload)
  end

  def error_response(status, payload)
    FakeErrorResponse.new(status, payload)
  end

  # 본문 즉시 반환 대역 응답 — parse가 쓰는 is_a?(Net::HTTPSuccess)·body·code만 계약으로 삼는다.
  # Net::HTTPResponse 본체는 지연 본문 읽기(IOError) 때문에 그대로 쓸 수 없다.
  class FakeSuccessResponse < Net::HTTPSuccess
    def initialize(payload)
      super("1.1", "200", "OK")
      @payload = payload
    end

    def body
      @payload && JSON.generate(@payload)
    end
  end

  class FakeErrorResponse < Net::HTTPClientError
    def initialize(status, payload)
      super("1.1", status.to_s, "Error")
      @payload = payload
    end

    def body
      JSON.generate(@payload)
    end
  end

  def assert_error_normalized(network_error, expected_code)
    transport = transport_returning(network_error)

    error = assert_raises(TossPayments::ApiError) do
      with_stubbed_transport(transport) { @client.get_payment(payment_key: "pay_1") }
    end

    assert_nil error.status
    assert_equal expected_code, error.code
    assert_equal network_error.message, error.message
  end
end
