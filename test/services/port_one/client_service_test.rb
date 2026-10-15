require "test_helper"
require_relative "../../test_helpers/portone_stubbing"

# PortOne::ClientService — 포트원 V2 래퍼 단위 테스트(PLAN-5·_workspace/03_implementation.md §1).
# 전송 계층(Net::HTTP.start)을 대역으로 교체해(with_http_transport — 실호출 금지 방어선) 요청
# 구성(경로·헤더·멱등 키·본문), 응답 파싱, 오류 정규화(type→code·pgCode/pgMessage), 타임아웃·
# 접속 실패의 모호 실패 분류를 5 엔드포인트(confirm·빌링키 발급·차감·조회·취소) 전수로 검증한다.
class FakePortOneTransport
  attr_reader :requests, :starts

  # response — 고정 응답 또는 호출마다 평가되는 Proc(응답 시퀀스용).
  # raise_on_request — request 시점에 발생시킬 예외(타임아웃·접속 실패 시뮬레이션).
  def initialize(response: nil, raise_on_request: nil)
    @response = response
    @raise_on_request = raise_on_request
    @requests = []
    @starts = []
  end

  def stub_start(host, port, **kwargs, &block)
    @starts << { host:, port:, **kwargs }
    block.call(self)
  end

  def request(net_request)
    @requests << net_request
    raise @raise_on_request if @raise_on_request

    @response.respond_to?(:call) ? @response.call : @response
  end
end

module PortOne
  class ClientServiceTest < ActiveSupport::TestCase
    include PortOneStubbing

    setup do
      @client = ClientService.new(api_secret: "test-secret", store_id: "store-test")
    end

    # ── confirm_payment (단건 승인 — 수동 승인 채널) ──

    test "confirm 성공은 승인 요청(paymentId 경로·멱등 키·토큰 본문)을 보내고 응답을 돌려준다" do
      transport = FakePortOneTransport.new(
        response: http_ok({ id: "payment-1", status: "PAID" }.to_json)
      )

      result = with_http_transport(transport) do
        @client.confirm_payment(payment_id: "payment-1", payment_token: "tok_widget_1")
      end

      assert_equal({ id: "payment-1", status: "PAID" }, result)
      request = transport.requests.sole
      assert_instance_of Net::HTTP::Post, request
      assert_equal "/payments/payment-1/confirm", request.path
      assert_equal "PortOne test-secret", request["Authorization"]
      assert_equal "application/json", request["Content-Type"]
      # 멱등 키 — POST 전용·RFC 8941 문자열 따옴표 포함 UUID
      assert_match(/\A"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"\z/,
                   request["Idempotency-Key"])
      assert_equal({ "storeId" => "store-test", "paymentToken" => "tok_widget_1" },
                   JSON.parse(request.body))
    end

    test "confirm 실패(404)는 포트원 오류 본문을 ApiError로 정규화한다" do
      transport = FakePortOneTransport.new(
        response: http_not_found({ type: "PAYMENT_NOT_FOUND",
                                   message: "결제건이 존재하지 않습니다" }.to_json)
      )

      error = with_http_transport(transport) do
        assert_raises(ApiError) { @client.confirm_payment(payment_id: "payment-x",
                                                          payment_token: "tok_1") }
      end

      assert_equal 404, error.status
      assert_equal "PAYMENT_NOT_FOUND", error.code
      assert_equal "결제건이 존재하지 않습니다", error.message
      assert_nil error.pg_code
      assert_not_predicate error, :ambiguous?               # 명확한 실패 — 재확인 대상 아님
    end

    # ── issue_billing_key (빌링키 발급 — 정기결제 채널) ──

    test "빌링키 발급 성공은 발급 토큰·정기결제 채널·고객 식별자 본문으로 요청한다" do
      transport = FakePortOneTransport.new(
        response: http_ok({ billingKey: "bk_issued_1",
                            channel: { key: "ch_billing" } }.to_json)
      )

      result = with_http_transport(transport) do
        @client.issue_billing_key(issue_token: "issue_1", channel_key: "ch_billing",
                                  customer_id: "cust_1")
      end

      assert_equal({ billingKey: "bk_issued_1", channel: { key: "ch_billing" } }, result)
      body = JSON.parse(transport.requests.sole.body)
      assert_equal({ "storeId" => "store-test", "billingIssueToken" => "issue_1",
                     "channelKey" => "ch_billing", "customer" => { "id" => "cust_1" } }, body)
    end

    test "빌링키 발급 실패는 PG 원문 오류(최상위 pgCode)를 ApiError에 운반한다" do
      transport = FakePortOneTransport.new(
        response: http_not_found({ type: "BILLING_KEY_NOT_FOUND",
                                   message: "빌링키가 존재하지 않습니다",
                                   pgCode: "F1001", pgMessage: "카드 정보 오류" }.to_json)
      )

      error = with_http_transport(transport) do
        assert_raises(ApiError) do
          @client.issue_billing_key(issue_token: "issue_bad", channel_key: "ch_billing",
                                    customer_id: "cust_1")
        end
      end

      assert_equal "BILLING_KEY_NOT_FOUND", error.code
      assert_equal "F1001", error.pg_code
      assert_equal "카드 정보 오류", error.pg_message
    end

    # ── charge_billing_key (자동결제 차감 — 정기결제) ──

    test "차감 성공은 빌링키·금액(total)·통화·고객 본문으로 요청하고 결과 스냅샷을 돌려준다" do
      transport = FakePortOneTransport.new(
        response: http_ok({ payment: { id: "payment-chg-1", status: "PAID" } }.to_json)
      )

      result = with_http_transport(transport) do
        @client.charge_billing_key(payment_id: "payment-chg-1", billing_key: "bk_1",
                                   channel_key: "ch_billing", amount: 9_900,
                                   customer_id: "cust_1", order_name: "받을돈 Plus 월 구독")
      end

      assert_equal({ payment: { id: "payment-chg-1", status: "PAID" } }, result)
      request = transport.requests.sole
      assert_equal "/payments/payment-chg-1/billing-key", request.path
      assert_equal({ "storeId" => "store-test", "billingKey" => "bk_1",
                     "channelKey" => "ch_billing", "orderName" => "받을돈 Plus 월 구독",
                     "amount" => { "total" => 9_900 }, "currency" => "KRW",
                     "customer" => { "id" => "cust_1" } }, JSON.parse(request.body))
    end

    test "차감 실패는 failure 객체의 PG 원문 오류를 ApiError에 운반한다" do
      transport = FakePortOneTransport.new(
        response: http_not_found({ type: "PG_PROVIDER_ERROR",
                                   message: "PG사 처리 중 오류가 발생했습니다",
                                   failure: { pgCode: "F1002", pgMessage: "한도초과" } }.to_json)
      )

      error = with_http_transport(transport) do
        assert_raises(ApiError) do
          @client.charge_billing_key(payment_id: "payment-chg-1", billing_key: "bk_1",
                                     channel_key: "ch_billing", amount: 9_900,
                                     customer_id: "cust_1", order_name: "받을돈 Plus 월 구독")
        end
      end

      assert_equal "PG_PROVIDER_ERROR", error.code
      assert_equal "F1002", error.pg_code                   # failure 객체에서 보완
      assert_equal "한도초과", error.pg_message
    end

    # ── get_payment (결제 조회 — 무결성 재확인) ──

    test "조회 성공은 storeId 질의 GET이며 멱등 키를 보내지 않는다" do
      transport = FakePortOneTransport.new(
        response: http_ok({ id: "payment-1", status: "PAID" }.to_json)
      )

      result = with_http_transport(transport) do
        @client.get_payment(payment_id: "payment-1")
      end

      assert_equal({ id: "payment-1", status: "PAID" }, result)
      request = transport.requests.sole
      assert_instance_of Net::HTTP::Get, request
      assert_equal "/payments/payment-1?storeId=store-test", request.path
      assert_nil request["Idempotency-Key"]                 # GET — 멱등 키 없음
      assert_nil request.body
    end

    test "조회 실패(404)도 ApiError로 정규화된다" do
      transport = FakePortOneTransport.new(
        response: http_not_found({ type: "PAYMENT_NOT_FOUND",
                                   message: "결제건이 존재하지 않습니다" }.to_json)
      )

      error = with_http_transport(transport) do
        assert_raises(ApiError) { @client.get_payment(payment_id: "payment-x") }
      end

      assert_equal 404, error.status
      assert_equal "PAYMENT_NOT_FOUND", error.code
    end

    # ── cancel_payment (결제 취소 — 전액 환불) ──

    test "취소 성공은 사유 본문으로 요청하고 취소 결과를 돌려준다" do
      transport = FakePortOneTransport.new(
        response: http_ok({ cancellation: { status: "SUCCEEDED" } }.to_json)
      )

      result = with_http_transport(transport) do
        @client.cancel_payment(payment_id: "payment-1", reason: "고객 요청 취소")
      end

      assert_equal({ cancellation: { status: "SUCCEEDED" } }, result)
      request = transport.requests.sole
      assert_equal "/payments/payment-1/cancel", request.path
      assert_equal({ "storeId" => "store-test", "reason" => "고객 요청 취소" },
                   JSON.parse(request.body))
    end

    test "취소 실패도 ApiError로 정규화된다" do
      transport = FakePortOneTransport.new(
        response: http_not_found({ type: "PAYMENT_NOT_FOUND",
                                   message: "결제건이 존재하지 않습니다" }.to_json)
      )

      error = with_http_transport(transport) do
        assert_raises(ApiError) { @client.cancel_payment(payment_id: "payment-x",
                                                         reason: "취소") }
      end

      assert_equal "PAYMENT_NOT_FOUND", error.code
    end

    # ── 전송 계층·네트워크 실패 (모호 실패 분류 — 이슈 #1·#4의 재확인 대상) ──

    test "전송 계층은 포트원 호스트·TLS·60초 타임아웃으로 열린다" do
      transport = FakePortOneTransport.new(response: http_ok({}.to_json))

      with_http_transport(transport) { @client.get_payment(payment_id: "payment-1") }

      start = transport.starts.sole
      assert_equal "api.portone.io", start[:host]
      assert_equal 443, start[:port]
      assert start[:use_ssl]
      assert_equal ClientService::TIMEOUT_SECONDS, start[:open_timeout]
      assert_equal ClientService::TIMEOUT_SECONDS, start[:read_timeout]
    end

    test "타임아웃은 모호 실패(TIMEOUT) ApiError로 분류된다" do
      transport = FakePortOneTransport.new(raise_on_request: Net::ReadTimeout.new("응답 시간 초과"))

      error = with_http_transport(transport) do
        assert_raises(ApiError) { @client.confirm_payment(payment_id: "payment-1",
                                                          payment_token: "tok_1") }
      end

      assert_nil error.status
      assert_equal "TIMEOUT", error.code
      assert_predicate error, :ambiguous?                   # 성공 여부 불명 — 재확인 대상
    end

    test "접속 실패는 모호 실패(CONNECTION) ApiError로 분류된다" do
      transport = FakePortOneTransport.new(raise_on_request: Errno::ECONNREFUSED.new("연결 거부"))

      error = with_http_transport(transport) do
        assert_raises(ApiError) { @client.charge_billing_key(payment_id: "payment-1",
                                                             billing_key: "bk_1",
                                                             channel_key: "ch_billing",
                                                             amount: 9_900,
                                                             customer_id: "cust_1",
                                                             order_name: "받을돈 Plus 월 구독") }
      end

      assert_equal "CONNECTION", error.code
      assert_predicate error, :ambiguous?
    end

    private

    def http_ok(body)
      Net::HTTPOK.new("1.1", "200", "OK").tap do |response|
        # 전송 계층 대역 — start 블록 밖에서 body 접근을 허용한다(읽기 완료 플래그)
        response.instance_variable_set(:@read, true)
        response.body = body
      end
    end

    def http_not_found(body)
      Net::HTTPNotFound.new("1.1", "404", "Not Found").tap do |response|
        response.instance_variable_set(:@read, true)
        response.body = body
      end
    end
  end
end
