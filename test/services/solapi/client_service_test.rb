require "test_helper"
require_relative "../../test_helpers/portone_stubbing"

# Solapi::ClientService — 솔라피 메시지 API 래퍼 단위 테스트(REM-10).
# 전송 계층(Net::HTTP.start)을 대역으로 교체해(PortOneStubbing.with_http_transport 준용 —
# 실호출 금지 방어선) 요청 구성(경로·HMAC 인증·kakaoOptions 본문·번호 정규화), 응답 파싱,
# fail-fast(템플릿 코드·credentials 누락), 오류 정규화(HTTP·TIMEOUT·CONNECTION)를 검증한다.
# [INFERENCE] 스펙(엔드포인트·인증·응답)은 라이브 실측 전 추정 상태 — 테스트는 구현 계약을
# 고정하는 역할이며 실측 후 갱신 대상이다(_workspace/03_implementation.md §[INFERENCE]).
class FakeSolapiTransport
  attr_reader :requests, :starts

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

module Solapi
  class ClientServiceTest < ActiveSupport::TestCase
    include PortOneStubbing

    def setup
      @client = ClientService.new(
        api_key: "test-api-key", api_secret: "test-api-secret", pf_id: "pf_badeuldon",
        sender_number: "01000000000", template_ids: { "confirm_d1" => "tmpl_confirm_1" }
      )
    end

    test "send_alimtalk 성공은 v4 단일 발송 요청(HMAC 인증·kakaoOptions)을 보내고 응답을 돌려준다" do
      transport = FakeSolapiTransport.new(
        response: http_ok({ messageId: "msg_solapi_1" }.to_json)
      )

      result = with_http_transport(transport) do
        @client.send_alimtalk(template_key: "confirm_d1", to: "010-3333-7777",
                              variables: { "거래처명" => "델타파트너스" })
      end

      assert_equal({ messageId: "msg_solapi_1" }, result)
      request = transport.requests.sole
      assert_instance_of Net::HTTP::Post, request
      assert_equal "/messages/v4/send", request.path
      assert_equal "application/json", request["Content-Type"]
      # HMAC-SHA256 인증 헤더 — apiKey·date·salt·signature 4요소
      assert_match(/\AHMAC-SHA256 apiKey=test-api-key, date=.*, salt=.*, signature=[0-9a-f]{64}\z/,
                   request["Authorization"])
      assert_match(/\A\d{4}-\d\d-\d\dT/, request["Date"])
      body = JSON.parse(request.body)
      assert_equal "01033337777", body["message"]["to"]              # 하이픈 제거 정규화
      assert_equal "01000000000", body["message"]["from"]            # 서비스 명의 발신번호(REM-1)
      assert_equal({ "pfId" => "pf_badeuldon", "templateId" => "tmpl_confirm_1",
                     "variables" => { "거래처명" => "델타파트너스" } },
                   body["message"]["kakaoOptions"])
      assert_equal [ { host: "api.solapi.com", port: 443, use_ssl: true,
                      open_timeout: 10, read_timeout: 10 } ], transport.starts
    end

    test "credentials에 없는 템플릿 키는 요청 없이 MISSING_TEMPLATE로 fail-fast한다 (REM-10)" do
      transport = FakeSolapiTransport.new(response: http_ok("{}".to_json))

      error = with_http_transport(transport) do
        assert_raises(ApiError) { @client.send_alimtalk(template_key: "unknown_key",
                                                        to: "010-3333-7777") }
      end

      assert_nil error.status
      assert_equal "MISSING_TEMPLATE", error.code
      assert_match(/unknown_key/, error.message)
      assert_empty transport.requests                                # 발송 시도 전 구성 오류 분류
    end

    test "credentials 누락은 요청 없이 MISSING_CREDENTIALS로 fail-fast한다 (반복 시도 방지)" do
      client = ClientService.new(api_key: "", api_secret: "s", pf_id: "pf",
                                 sender_number: "01000000000",
                                 template_ids: { "confirm_d1" => "tmpl_1" })
      transport = FakeSolapiTransport.new(response: http_ok("{}".to_json))

      error = with_http_transport(transport) do
        assert_raises(ApiError) { client.send_alimtalk(template_key: "confirm_d1",
                                                       to: "010-3333-7777") }
      end

      assert_equal "MISSING_CREDENTIALS", error.code
      assert_match(/@api_key/, error.message)
      assert_empty transport.requests
    end

    test "HTTP 오류 응답은 본문 code·message로 ApiError를 만들고 재시도 대상이 아니다" do
      transport = FakeSolapiTransport.new(
        response: http_error(400, { code: "BadPhone", message: "유효하지 않은 번호" }.to_json)
      )

      error = with_http_transport(transport) do
        assert_raises(ApiError) { @client.send_alimtalk(template_key: "confirm_d1",
                                                        to: "010-3333-7777") }
      end

      assert_equal 400, error.status
      assert_equal "BadPhone", error.code
      assert_equal "유효하지 않은 번호", error.message
      assert_not_predicate error, :retryable?                        # 확정 실패 — 재시도 안 함
    end

    test "본문에 code가 없는 HTTP 오류는 HTTP_<status>로 정규화된다 ([INFERENCE] 폴백)" do
      # 오류 본문은 code 키 없는 객체로 온다고 가정한다(비객체 본문은 정규화 밖 — 보고서 참조)
      transport = FakeSolapiTransport.new(response: http_error(500, { message: "internal" }.to_json))

      error = with_http_transport(transport) do
        assert_raises(ApiError) { @client.send_alimtalk(template_key: "confirm_d1",
                                                        to: "010-3333-7777") }
      end

      assert_equal 500, error.status
      assert_equal "HTTP_500", error.code
    end

    test "타임아웃은 TIMEOUT으로 정규화되고 재시도 대상이다 (모호 실패 — 잡 재시도 한정)" do
      transport = FakeSolapiTransport.new(raise_on_request: Net::ReadTimeout.new("read timeout"))

      error = with_http_transport(transport) do
        assert_raises(ApiError) { @client.send_alimtalk(template_key: "confirm_d1",
                                                        to: "010-3333-7777") }
      end

      assert_nil error.status
      assert_equal "TIMEOUT", error.code
      assert_predicate error, :retryable?
    end

    test "접속 실패는 CONNECTION으로 정규화되고 재시도 대상이다" do
      transport = FakeSolapiTransport.new(raise_on_request: SocketError.new("connection refused"))

      error = with_http_transport(transport) do
        assert_raises(ApiError) { @client.send_alimtalk(template_key: "confirm_d1",
                                                        to: "010-3333-7777") }
      end

      assert_equal "CONNECTION", error.code
      assert_predicate error, :retryable?
    end

    private

    def http_ok(body)
      Net::HTTPOK.new("1.1", "200", "OK").tap do |response|
        # 전송 계층 대역 — start 블록 밖에서 body 접근을 허용한다(읽기 완료 플래그)
        response.instance_variable_set(:@read, true)
        response.body = body
      end
    end

    def http_error(status, body)
      Net::HTTPServerError.new("1.1", status.to_s, "Error").tap do |response|
        response.instance_variable_set(:@read, true)
        response.body = body
      end
    end
  end
end
