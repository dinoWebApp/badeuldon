require "test_helper"
require_relative "../../test_helpers/portone_stubbing"
require_relative "../../test_helpers/outbound_mail_stubbing"

# OutboundMail::ClientService — 자체 메일 API 래퍼 단위 테스트(F-EMAIL — EXT-1 이메일 행·SEC-5).
# 전송 계층(Net::HTTP.start)을 대역으로 교체해(PortOneStubbing.with_http_transport 준용 —
# 실호출 금지 방어선) 요청 구성(경로·Bearer·Idempotency-Key 헤더 승격·null 제거), 202 스냅샷
# 파싱, 오류 정규화(본문 3형식 탐색·빈 본문/비JSON 방어), fail-fast(credentials·키 규격),
# 네트워크 예외 정규화(TIMEOUT·CONNECTION), retryable? 분류를 검증한다.
# 스펙 단일 소스: 루트 OUTBOUND_MAIL_API.md. 오류 본문 형식은 [INFERENCE](03 §3 I-1).
class OutboundMail::ClientServiceTest < ActiveSupport::TestCase
  include PortOneStubbing

  BASE_URL = "https://mail-api.example.test"
  TOKEN = "bd-test-token"

  def setup
    @client = OutboundMail::ClientService.new(base_url: BASE_URL, token: TOKEN)
  end

  # ── 요청 구성·202 파싱 ─────────────────────────────────────────────────

  test "send_email은 POST /api/v1/emails에 Bearer·Idempotency-Key 헤더로 보내고 202 스냅샷 3키를 돌려준다 (EXT-1)" do
    transport = FakeOutboundMailTransport.new(response: http_ok(
      { success: true,
        data: { id: "mail_ulid_1", message_id: "<m1@veloloop.kr>",
                status: "accepted_by_postfix", accepted_at: "2026-11-20T09:00:00+09:00",
                recipients: { to: 1, cc: 0, bcc: 0 } } }.to_json
    ))
    payload = {
      idempotency_key: "bd.#{"a" * 64}",
      from: { email: "badeuldon@veloloop.kr", name: "받을돈" },
      to: [ { email: "user@example.com" } ],
      cc: [], bcc: [],
      subject: "제목",
      text_body: "본문"
    }

    result = with_http_transport(transport) { @client.send_email(payload) }

    assert_equal({ id: "mail_ulid_1", message_id: "<m1@veloloop.kr>",
                   status: "accepted_by_postfix" }, result)
    request = transport.requests.sole
    assert_instance_of Net::HTTP::Post, request
    assert_equal "/api/v1/emails", request.path
    assert_equal "Bearer #{TOKEN}", request["Authorization"]
    assert_equal "application/json", request["Content-Type"]
    assert_equal payload[:idempotency_key], request["Idempotency-Key"]
    assert_equal [ { host: "mail-api.example.test", port: 443, use_ssl: true,
                     open_timeout: 10, read_timeout: 10 } ], transport.starts
  end

  test "idempotency_key는 JSON 바디에서 제외되고 nil 필드도 송신되지 않는다 (헤더 승격·compact)" do
    transport = FakeOutboundMailTransport.new(response: http_ok(
      { success: true, data: { id: "mail_2", message_id: "<m2@veloloop.kr>",
                               status: "accepted_by_postfix" } }.to_json
    ))
    payload = {
      idempotency_key: "job.#{"b" * 36}",
      from: { email: "badeuldon@veloloop.kr", name: nil },
      to: [ { email: "user@example.com" } ],
      cc: [], bcc: [],
      reply_to: nil,
      subject: "제목",
      text_body: "본문",
      html_body: nil
    }

    with_http_transport(transport) { @client.send_email(payload) }

    body = JSON.parse(transport.requests.sole.body)
    assert_not_includes body.keys, "idempotency_key", "멱등 키는 헤더로만 전달된다(SEC-5)"
    assert_not_includes body.keys, "html_body", "최상위 null 필드는 JSON null로 나가지 않는다"
    assert_not_includes body.keys, "reply_to"
  end

  # ── fail-fast — credentials·키 규격(네트워크 왕복 없음) ─────────────────

  test "token 부재는 configured? false이고 send_email은 MISSING_CREDENTIALS로 fail-fast한다" do
    client = OutboundMail::ClientService.new(base_url: nil, token: nil)

    assert_not_predicate client, :configured?

    transport = FakeOutboundMailTransport.new(response: http_ok("{}".to_json))
    error = with_http_transport(transport) do
      assert_raises(OutboundMail::ApiError) { client.send_email(minimal_payload) }
    end
    assert_nil error.status
    assert_equal "MISSING_CREDENTIALS", error.code
    assert_empty transport.requests, "실호출 없이 차단된다"
  end

  test "token이 있으면 configured? true이고 base_url 생략 시 문서 기본값을 쓴다" do
    client = OutboundMail::ClientService.new(base_url: nil, token: TOKEN)

    assert_predicate client, :configured?
    assert_equal OutboundMail::ClientService::DEFAULT_BASE_URL, "https://mail-api.veloloop.kr"
  end

  test "Idempotency-Key 규격 위반은 네트워크 왕복 없이 INVALID_REQUEST로 fail-fast한다 (SEC-5·T-3)" do
    transport = FakeOutboundMailTransport.new(response: http_ok("{}".to_json))

    [ "short", "bd.with space", "bd.슬래시/불가", "", "bd." + ("z" * 130) ].each do |bad_key|
      error = with_http_transport(transport) do
        assert_raises(OutboundMail::ApiError) { @client.send_email(minimal_payload.merge(idempotency_key: bad_key)) }
      end
      assert_nil error.status
      assert_equal "INVALID_REQUEST", error.code, "키=#{bad_key.inspect}"
    end
    assert_empty transport.requests, "규격 위반 키로는 HTTP 요청 자체를 보내지 않는다"
  end

  # ── 오류 정규화 — 본문 3형식 탐색·방어 ──────────────────────────────────

  test "4xx 오류는 상태·code를 정규화하고 재시도 대상이 아니다 (OUTBOUND_MAIL_API.md §2)" do
    transport = FakeOutboundMailTransport.new(response: http_response(
      403, { code: "SENDER_NOT_ALLOWED", message: "허용되지 않은 발신 주소" }.to_json,
      Net::HTTPForbidden
    ))

    error = with_http_transport(transport) { assert_raises(OutboundMail::ApiError) { @client.send_email(minimal_payload) } }

    assert_equal 403, error.status
    assert_equal "SENDER_NOT_ALLOWED", error.code
    assert_equal "허용되지 않은 발신 주소", error.message
    assert_not_predicate error, :retryable?
  end

  test "오류 본문은 {error:{code,message}}·{data:{code,message}} 중첩 형식도 탐색한다 ([INFERENCE] I-1)" do
    transport = FakeOutboundMailTransport.new(response: http_response(
      400, { error: { code: "INVALID_REQUEST", message: "필드 오류" } }.to_json, Net::HTTPBadRequest
    ))
    error = with_http_transport(transport) { assert_raises(OutboundMail::ApiError) { @client.send_email(minimal_payload) } }
    assert_equal "INVALID_REQUEST", error.code

    transport = FakeOutboundMailTransport.new(response: http_response(
      422, { data: { code: "INVALID_RECIPIENT", message: "수신자 오류" } }.to_json, Net::HTTPUnprocessableEntity
    ))
    error = with_http_transport(transport) { assert_raises(OutboundMail::ApiError) { @client.send_email(minimal_payload) } }
    assert_equal "INVALID_RECIPIENT", error.code
    assert_not_predicate error, :retryable?
  end

  test "코드 없는 빈 본문·비JSON 본문은 HTTP_<status> 정규화·원문 보존으로 방어한다 (P4 진단)" do
    transport = FakeOutboundMailTransport.new(response: http_response(400, "", Net::HTTPBadRequest))
    error = with_http_transport(transport) { assert_raises(OutboundMail::ApiError) { @client.send_email(minimal_payload) } }
    assert_equal "HTTP_400", error.code
    assert_equal "OutboundMail::ApiError", error.message, "코드·원문 모두 없으면 운반할 메시지가 없다(예외 기본 문구)"

    transport = FakeOutboundMailTransport.new(response: http_response(
      500, "<html>boom</html>", Net::HTTPInternalServerError
    ))
    error = with_http_transport(transport) { assert_raises(OutboundMail::ApiError) { @client.send_email(minimal_payload) } }
    assert_equal "HTTP_500", error.code
    assert_equal "<html>boom</html>", error.message, "비JSON 본문은 원문을 보존한다"
  end

  # ── retryable? 분류(W-5 — DeliveryJob retry_on의 분기 근거) ──────────────

  test "429·5xx(일시 장애·모호 실패)는 재시도 대상으로 분류된다" do
    assert_retryable 429, "RATE_LIMITED", Net::HTTPTooManyRequests
    assert_retryable 502, "LOCAL_MTA_ERROR", Net::HTTPBadGateway
    assert_retryable 503, "MAIL_SERVICE_UNAVAILABLE", Net::HTTPServiceUnavailable
    assert_retryable 503, "MANUAL_REVIEW", Net::HTTPServiceUnavailable
  end

  test "409·400·401은 재시도 대상에서 제외된다 (구성·스펙 오류·멱등 충돌)" do
    transport = FakeOutboundMailTransport.new(response: http_response(
      409, { code: "IDEMPOTENCY_CONFLICT", message: "같은 키+다른 payload" }.to_json, Net::HTTPConflict
    ))
    error = with_http_transport(transport) { assert_raises(OutboundMail::ApiError) { @client.send_email(minimal_payload) } }
    assert_equal 409, error.status
    assert_not_predicate error, :retryable?
    assert_not_predicate OutboundMail::ApiError.new(status: 400, code: "INVALID_REQUEST"), :retryable?
    assert_not_predicate OutboundMail::ApiError.new(status: 401, code: "UNAUTHORIZED"), :retryable?
    assert_not_predicate OutboundMail::ApiError.new(status: nil, code: "MISSING_CREDENTIALS"), :retryable?
  end

  # ── 네트워크 예외 정규화 ────────────────────────────────────────────────

  test "타임아웃·접속 실패는 TIMEOUT·CONNECTION으로 정규화하고 재시도 대상이다" do
    transport = FakeOutboundMailTransport.new(raise_on_request: Net::OpenTimeout.new("execution expired"))
    error = with_http_transport(transport) { assert_raises(OutboundMail::ApiError) { @client.send_email(minimal_payload) } }
    assert_nil error.status
    assert_equal "TIMEOUT", error.code
    assert_predicate error, :retryable?

    transport = FakeOutboundMailTransport.new(raise_on_request: Errno::ECONNREFUSED.new("Connection refused"))
    error = with_http_transport(transport) { assert_raises(OutboundMail::ApiError) { @client.send_email(minimal_payload) } }
    assert_equal "CONNECTION", error.code
    assert_predicate error, :retryable?
  end

  private

  def minimal_payload
    {
      idempotency_key: "bd.#{"a" * 64}",
      from: { email: "badeuldon@veloloop.kr" },
      to: [ { email: "user@example.com" } ],
      subject: "제목",
      text_body: "본문"
    }
  end

  def assert_retryable(status, code, response_class)
    transport = FakeOutboundMailTransport.new(
      response: http_response(status, { code: code }.to_json, response_class)
    )
    error = with_http_transport(transport) { assert_raises(OutboundMail::ApiError) { @client.send_email(minimal_payload) } }
    assert_equal status, error.status
    assert_equal code, error.code
    assert_predicate error, :retryable?
  end

  # Net::HTTP 응답 대역 — 생성자 인자 순서 주의(httpv·code·message. 첫 인자에 상태코드를 넣으면
  # code가 오염된다 — 03 §6.1 실측). @read 플래그로 start 블록 밖 body 접근을 허용한다(솔라피 선례).
  def http_ok(body)
    Net::HTTPAccepted.new("1.1", "202", "Accepted").tap do |response|
      response.instance_variable_set(:@read, true)
      response.body = body
    end
  end

  def http_response(status, body, response_class)
    response_class.new("1.1", status.to_s, "Error").tap do |response|
      response.instance_variable_set(:@read, true)
      response.body = body
    end
  end
end
