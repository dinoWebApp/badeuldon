require "test_helper"
require_relative "../../test_helpers/portone_stubbing"

# Solapi::ClientService — 솔라피 메시지 API 래퍼 단위 테스트(REM-10).
# 전송 계층(Net::HTTP.start)을 대역으로 교체해(PortOneStubbing.with_http_transport 준용 —
# 실호출 금지 방어선) 요청 구성(경로·HMAC 인증·message 단수 바디·kakaoOptions·#{변수명} 키
# 래핑·번호 정규화), 응답 파싱, fail-fast(템플릿 코드·credentials 누락), 오류 정규화
# (HTTP·TIMEOUT·CONNECTION·오류 본문 fallback), dry_run(실호출 스킵)을 검증한다.
# 스펙(엔드포인트·바디·variables 키)은 2026-11-06 운영 실측·공식 문서로 확정됐다 —
# 성공 응답 필드 구조만 미실측([INFERENCE] 유지).
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
      # perform 가드 통과 플래그(2026-11-20) — 이 파일은 with_http_transport로 HTTP 계층을
      # 교체하므로 실호출이 아님. 가드는 stub 없는 다른 경로의 실호출만 차단한다.
      Thread.current[:solapi_http_stub] = true
      @client = ClientService.new(
        api_key: "test-api-key", api_secret: "test-api-secret", pf_id: "pf_badeuldon",
        sender_number: "01000000000", template_ids: { "confirm_d1" => "tmpl_confirm_1" }
      )
    end

    teardown do
      Thread.current[:solapi_http_stub] = nil
    end

    test "send_alimtalk 성공은 v4 단일 발송 요청(HMAC 인증·message 단수·\#{변수명} 키)을 보내고 응답을 돌려준다" do
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
      # 시그니처 계산 검증 — HMAC-SHA256(api_secret, date + salt)의 hex 다이제스트(공식
      # 인증 문서 규격: 구분자 없는 단순 연결·apiKey 미포함). 헤더의 date·salt로 재계산해
      # 일치를 확인한다(2026-11-06 실측 — 점 구분+apiKey 포함 계산이 서명 불일치 거부됨).
      header = request["Authorization"]
      date = header[/date=([^,]+)/, 1]
      salt = header[/salt=([^,]+)/, 1]
      expected_signature = OpenSSL::HMAC.hexdigest("SHA256", "test-api-secret", date + salt)
      assert_equal "signature=#{expected_signature}", header[/signature=[0-9a-f]{64}\z/]
      # 바디 최상위는 message 단수 객체다 — messages 배열은 다중·그룹 발송(send-many·groups)
      # 규격(2026-11-06 3차 실측 확정). "#\{거래처명}"는 리터럴 #{거래처명}이다(솔라피 스펙 —
      # 치환 변수 키에 #{} 포함).
      body = JSON.parse(request.body)
      message = body["message"]
      assert_equal "01033337777", message["to"]                      # 하이픈 제거 정규화
      assert_equal "01000000000", message["from"]                    # 서비스 명의 발신번호(REM-1)
      assert_equal({ "pfId" => "pf_badeuldon", "templateId" => "tmpl_confirm_1",
                     "variables" => { "#\{거래처명}" => "델타파트너스" } },
                   message["kakaoOptions"])
      assert_equal [ { host: "api.solapi.com", port: 443, use_ssl: true,
                      open_timeout: 10, read_timeout: 10 } ], transport.starts
    end

    test "dry_run: true는 네트워크 호출 없이 조립된 요청 스펙(message 단수·\#{변수명} 키)을 돌려준다" do
      transport = FakeSolapiTransport.new(response: http_ok("{}".to_json))

      result = with_http_transport(transport) do
        @client.send_alimtalk(template_key: "confirm_d1", to: "010-3333-7777",
                              variables: { "거래처명" => "델타파트너스" }, dry_run: true)
      end

      assert_empty transport.starts                                  # 연결 자체가 없다
      assert_empty transport.requests                                # 발송 시도도 없다
      assert_predicate result[:dryRun], :present?
      assert_equal "/messages/v4/send", result[:path]
      message = result[:body][:message]
      assert_equal({ "#\{거래처명}" => "델타파트너스" }, message[:kakaoOptions][:variables])
    end

    test "최초 승인 4종은 \#{발행인} 키로 송신하고 그 외 템플릿은 \#{발행인명}을 유지한다 (래퍼 스펙 계층)" do
      client = ClientService.new(
        api_key: "test-api-key", api_secret: "test-api-secret", pf_id: "pf_badeuldon",
        sender_number: "01000000000",
        template_ids: { "invoice_notice" => "t1", "confirm_d1" => "t2", "requeue_d7" => "t3",
                        "final_d14" => "t4", "paid_thanks" => "t5" }
      )
      transport = FakeSolapiTransport.new(response: http_ok("{}".to_json))
      variables = { "발행인명" => "김발행" }

      with_http_transport(transport) do
        ClientService::LEGACY_ISSUER_KEY_TEMPLATES.each do |key|
          client.send_alimtalk(template_key: key, to: "010-3333-7777", variables: variables)
        end
        client.send_alimtalk(template_key: "paid_thanks", to: "010-3333-7777", variables: variables)
      end

      # 2026-10-29 최초 승인 4종 — 솔라피 등록 변수명이 "발행인"(사용자 확인 2026-11-06)
      legacy_keys = transport.requests.first(4).map do |request|
        JSON.parse(request.body)["message"]["kakaoOptions"]["variables"].keys.sole
      end
      assert_equal [ "#\{발행인}" ] * 4, legacy_keys
      # 그 외 14종 — 발행인명 원키 유지
      paid_variables = JSON.parse(transport.requests.last.body)["message"]["kakaoOptions"]["variables"]
      assert_equal({ "#\{발행인명}" => "김발행" }, paid_variables)
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

    test "template_ids 심벌 키 주입은 stringify_keys 정규화로 문자열 조회에 성공한다 (YAML 스타일 무관)" do
      # credentials solapi.template_ids는 심벌 키 YAML(:phone_verification:)로 작성돼도 조회는
      # 항상 문자열 키(@template_ids[template_key.to_s]) — 주입분(stub 포함)까지 정규해야
      # MISSING_TEMPLATE 오동작이 없다(2026-11-19 결함 수정).
      client = ClientService.new(
        api_key: "test-api-key", api_secret: "test-api-secret", pf_id: "pf_badeuldon",
        sender_number: "01000000000",
        template_ids: { phone_verification: "TPH01", "confirm_d1" => "t2" } # 혼합 — 심벌+문자열
      )
      transport = FakeSolapiTransport.new(response: http_ok({ messageId: "m1" }.to_json))

      result = with_http_transport(transport) do
        client.send_alimtalk(template_key: :phone_verification, to: "010-3333-7777",
                             variables: { "인증번호" => "123456" })
      end

      assert_equal({ messageId: "m1" }, result)
      template_id = JSON.parse(transport.requests.sole.body)["message"]["kakaoOptions"]["templateId"]
      assert_equal "TPH01", template_id
      assert_equal({ "phone_verification" => "TPH01", "confirm_d1" => "t2" },
                   client.template_ids, "접근자는 문자열 키 Hash를 돌려준다")
    end

    test "template_ids가 nil이면 빈 Hash로 정규되고 미등록 키는 MISSING_TEMPLATE이다 (nil 안전)" do
      client = ClientService.new(api_key: "k", api_secret: "s", pf_id: "pf",
                                 sender_number: "01000000000", template_ids: nil)
      assert_equal({}, client.template_ids)

      transport = FakeSolapiTransport.new(response: http_ok("{}".to_json))
      error = with_http_transport(transport) do
        assert_raises(ApiError) { client.send_alimtalk(template_key: "phone_verification",
                                                       to: "010-3333-7777") }
      end
      assert_equal "MISSING_TEMPLATE", error.code
      assert_empty transport.requests
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

    test "본문에 code가 없는 HTTP 오류는 HTTP_<status>로 정규화된다 (폴백)" do
      transport = FakeSolapiTransport.new(response: http_error(500, { message: "internal" }.to_json))

      error = with_http_transport(transport) do
        assert_raises(ApiError) { @client.send_alimtalk(template_key: "confirm_d1",
                                                        to: "010-3333-7777") }
      end

      assert_equal 500, error.status
      assert_equal "HTTP_500", error.code
    end

    test "오류 본문에 message가 없으면 errorMessage 키로 fallback한다 (P4 진단 보존)" do
      # 솔라피 오류 본문 규격은 {code, message} 가정과 다르게 실측됐다(2026-11-06 —
      # message 누실로 error_message가 "Solapi::ApiError"만 남은 케이스).
      transport = FakeSolapiTransport.new(
        response: http_error(400, { errorCode: "InvalidTemplate",
                                    errorMessage: "템플릿 변수 불일치" }.to_json)
      )

      error = with_http_transport(transport) do
        assert_raises(ApiError) { @client.send_alimtalk(template_key: "confirm_d1",
                                                        to: "010-3333-7777") }
      end

      assert_equal 400, error.status
      assert_equal "HTTP_400", error.code
      assert_equal "템플릿 변수 불일치", error.message
    end

    test "비JSON 오류 본문은 raw 본문을 error_message로 보존한다 (JSON 파서 우회 방지)" do
      transport = FakeSolapiTransport.new(response: http_error(400, "Invalid template request"))

      error = with_http_transport(transport) do
        assert_raises(ApiError) { @client.send_alimtalk(template_key: "confirm_d1",
                                                        to: "010-3333-7777") }
      end

      assert_equal 400, error.status
      assert_equal "HTTP_400", error.code
      assert_equal "Invalid template request", error.message
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

    # ── 잔액 조회 get_balance(T4 — ADMIN-5·REM-10, 2026-11-20 실측·2026-11-23 원본 재확인 스키마) ──

    test "get_balance는 GET /cash/v1/balance에 HMAC 인증으로 조회하고 정수 잔액을 정규화해 돌려준다" do
      transport = FakeSolapiTransport.new(
        response: http_ok({ balance: 123_456, point: 100, deposit: 135_802 }.to_json)
      )

      result = with_http_transport(transport) { @client.get_balance }

      assert_equal({ balance: 123_456, point: 100, deposit: 135_802 }, result)
      request = transport.requests.sole
      assert_instance_of Net::HTTP::Get, request          # GET 전용 — 발송(write) API 무호출
      assert_equal "/cash/v1/balance", request.path
      assert_nil request.body                             # 조회 바디 없음
      # 발송과 동일 인증 체계(HMAC-SHA256 apiKey·date·salt·signature)를 공유한다
      assert_match(/\AHMAC-SHA256 apiKey=test-api-key, date=.*, salt=.*, signature=[0-9a-f]{64}\z/,
                   request["Authorization"])
    end

    test "get_balance는 콤마 숫자형 문자열 잔액을 정수로 정규화한다 (방어적 파싱)" do
      transport = FakeSolapiTransport.new(
        response: http_ok({ balance: "12,345", point: "1,000", deposit: "13,717" }.to_json)
      )

      result = with_http_transport(transport) { @client.get_balance }

      assert_equal({ balance: 12_345, point: 1_000, deposit: 13_717 }, result)
    end

    test "get_balance는 point 누락은 0, deposit 누락은 nil로 정규한다 (보조값은 관대한 정규화)" do
      transport = FakeSolapiTransport.new(response: http_ok({ balance: 500 }.to_json))

      result = with_http_transport(transport) { @client.get_balance }

      assert_equal({ balance: 500, point: 0, deposit: nil }, result)
    end

    test "get_balance는 실측 응답(11키·소수 금액)에서 부가세 제외 잔액과 예치금을 버림 정수로 함께 돌려준다" do
      # 2026-11-23 운영 원본 응답 형태(계정 식별자만 가공) — balance = deposit × 0.9
      # (예치금에서 부가세 10%를 뺀 값). 한쪽만 쓰면 콘솔(deposit 기준)과 10% 달라 보인다.
      transport = FakeSolapiTransport.new(response: http_ok({
        profit: 0, accountId: "account-id-1", autoRecharge: 0,
        balance: 7682.31, deposit: 8535.9,
        lowBalanceAlert: { notificationBalance: "0", currentBalance: "190",
                           balances: [ 200 ], channels: [ "SMS" ], enabled: true },
        minimumCash: 0, point: 0, rechargeTo: 0, rechargeTryCount: 0, balanceOnly: 0
      }.to_json))

      result = with_http_transport(transport) { @client.get_balance }

      assert_equal({ balance: 7682, point: 0, deposit: 8535 }, result)
    end

    test "get_balance는 deposit 비숫자를 nil로 둔다 (balance와 달리 보조값이라 fail-fast하지 않는다)" do
      transport = FakeSolapiTransport.new(response: http_ok({ balance: 500, deposit: "abc" }.to_json))

      result = with_http_transport(transport) { @client.get_balance }

      assert_equal 500, result[:balance]
      assert_nil result[:deposit]
    end

    test "get_balance 응답 스키마 이탈은 UNEXPECTED_BALANCE_RESPONSE로 fail-fast한다" do
      # balance 키 누락·null·비숫자 — 잘못된 잔액을 정상처럼 표시하는 것을 차단한다
      [ {}, { balance: nil, point: 0 }, { balance: "abc" } ].each do |payload|
        transport = FakeSolapiTransport.new(response: http_ok(payload.to_json))

        error = with_http_transport(transport) do
          assert_raises(ApiError) { @client.get_balance }
        end

        assert_nil error.status
        assert_equal "UNEXPECTED_BALANCE_RESPONSE", error.code
      end
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
