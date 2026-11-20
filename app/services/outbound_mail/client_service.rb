# 자체 Outbound Mail API 래퍼(F-EMAIL — AUTH-8·AUTH-7.4/7.6·§6.19 EXT-1 이메일 행·2026-11-20
# 지정). 솔라피·포트원 래퍼와 같은 패턴 — credentials 기본값 + 초기화 인자 주입(테스트 stub과
# 실측을 분리) + fail-fast + ActiveRecord 비의존 순수 클래스. HTTP 호출은 포트원 래퍼 선례의
# Net::HTTP 방식을 재사용한다.
#
# 스펙 단일 소스는 루트 OUTBOUND_MAIL_API.md:
#   POST {base_url}/api/v1/emails · Authorization: Bearer <token> · Content-Type: application/json
#   · Idempotency-Key 헤더 필수(8~128자·[A-Za-z0-9._-] — 재시도는 같은 키 재사용)
#   · 성공 202 Accepted = 로컬 Postfix 접수(최종 배달은 메일 서버 쪽 추적 — 본 래퍼는 접수까지만
#     책임진다). 운영 한도: 분당 30(클라이언트별)·일 100(전체) — 429 RATE_LIMITED는 재시도 대상.
# 오류 본문 형식은 문서에 명시가 없어(오류 표는 HTTP 상태·code 값만 정의) code·message 키를
# 상위/중첩 양쪽에서 탐색한다 — [INFERENCE] 첫 실호출 응답으로 확정(03_implementation.md).
require "net/http"
require "json"

module OutboundMail
  class ClientService
    DEFAULT_BASE_URL = "https://mail-api.veloloop.kr"
    TIMEOUT_SECONDS = 10
    SEND_PATH = "/api/v1/emails"
    # OUTBOUND_MAIL_API.md Idempotency-Key 규칙 — 8~128자·[A-Za-z0-9._-]. DeliveryMethod가
    # 파생한 키를 송신 직전 한 번 더 검증한다(네트워크 왕복 없는 fail-fast).
    IDEMPOTENCY_KEY_PATTERN = /\A[A-Za-z0-9._-]{8,128}\z/

    # credentials(:outbound_mail base_url·token) 기본값 + 주입 — 포트원 래퍼 선례 방식.
    # base_url은 credentials가 없어도 문서 기본값이 있으므로 token 부재가 유일한 비구성 조건이다.
    def initialize(base_url: Rails.application.credentials.dig(:outbound_mail, :base_url),
                   token: Rails.application.credentials.dig(:outbound_mail, :token))
      @base_url = base_url.presence || DEFAULT_BASE_URL
      @token = token
    end

    # 폴백 판정용(DeliveryMethod가 credentials 등록 전 로그 폴백 여부를 이걸로 고른다).
    def configured?
      @base_url.present? && @token.present?
    end

    # 이메일 발송 — payload는 OutboundMail::DeliveryMethod가 조립한 스펙 해시(API 문서 §2
    # 요청 바디 규격). payload[:idempotency_key]는 JSON 바디에서 제외되고 Idempotency-Key
    # 헤더로 승격된다. 성공 시 202의 data에서 상위 계층이 필요로 하는 식별자 3개만 잘라
    # { id:, message_id:, status: }로 반환한다.
    def send_email(payload)
      unless configured?
        raise ApiError.new(status: nil, code: "MISSING_CREDENTIALS",
                           message: "Outbound Mail credentials(:outbound_mail token)이 누락되었습니다")
      end

      idempotency_key = payload[:idempotency_key].to_s
      unless idempotency_key.match?(IDEMPOTENCY_KEY_PATTERN)
        raise ApiError.new(status: nil, code: "INVALID_REQUEST",
                           message: "Idempotency-Key 규격 위반(8~128자·[A-Za-z0-9._-]): #{idempotency_key.inspect}")
      end

      request(path: SEND_PATH, body: payload.except(:idempotency_key).compact,
              idempotency_key: idempotency_key)
    end

    private

    def request(path:, body:, idempotency_key:)
      response = perform(build_request(path:, body:, idempotency_key:))
      parse(response)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise ApiError.new(status: nil, code: "TIMEOUT", message: e.message)
    rescue SocketError, Errno::ECONNREFUSED => e
      raise ApiError.new(status: nil, code: "CONNECTION", message: e.message)
    end

    def build_request(path:, body:, idempotency_key:)
      uri = URI.parse("#{@base_url}#{path}")
      net_request = Net::HTTP::Post.new(uri)
      net_request["Authorization"] = "Bearer #{@token}"
      net_request["Content-Type"] = "application/json"
      # 재시도 시 같은 키를 재사용해야 API 멱등(idempotent_replay)이 동작한다 — 키는
      # 렌더 결과로부터 결정적으로 파생된다(DeliveryMethod#idempotency_key 주석).
      net_request["Idempotency-Key"] = idempotency_key
      net_request.body = JSON.generate(body)
      [ uri, net_request ]
    end

    # base_url은 로컬 검증용 http(127.0.0.1:3001)를 허용하므로 스킴으로 SSL을 판정한다.
    def perform((uri, net_request))
      # TEST 환경 실호출 원천 차단(2026-11-20 — 솔라피 실발송 사고 계기). FakeOutboundMailClient
      # 주입 또는 HTTP transport stub 경유 시에만 통과.
      if Rails.env.test? && !Thread.current[:outbound_mail_http_stub]
        raise ApiError.new(status: nil, code: "TEST_GUARD",
                           message: "test 환경 실호출 차단 — FakeOutboundMailClient 또는 HTTP transport stub 필요")
      end

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
        http.request(net_request)
      end
    end

    def parse(response)
      payload, raw_body = parse_body(response)

      return success_snapshot(payload) if response.is_a?(Net::HTTPSuccess)

      raise ApiError.new(status: response.code.to_i,
                         code: error_field(payload, :code) || "HTTP_#{response.code}",
                         message: error_field(payload, :message) || raw_body.presence)
    end

    # 성공 202 — { success: true, data: { id, message_id, status, accepted_at, recipients } }.
    # 202는 Postfix 접수까지만 뜻한다 — status는 접수 상태(accepted_by_postfix)다.
    def success_snapshot(payload)
      data = payload[:data].is_a?(Hash) ? payload[:data] : {}
      { id: data[:id], message_id: data[:message_id], status: data[:status] }
    end

    # [INFERENCE] 오류 본문 탐색 — 성공이 {success, data} 래퍼이므로 오류도 중첩 가능성을
    # 포함해 {code,message} → {error:{code,message}} → {data:{code,message}} 순으로 본다.
    # 코드가 없으면 HTTP_<status>로 정규화하고, 메시지가 없으면 원문 본문을 보존한다(P4 진단).
    def error_field(payload, key)
      payload[key] || payload.dig(:error, key) || payload.dig(:data, key)
    end

    # 응답 본문 파싱 — payload는 해시(비해시 JSON·JSON 아님·빈 본문은 빈 해시), raw는 원문
    # 문자열(솔라피 래퍼와 동일 방어 — ApiError 정규화 우회 차단).
    def parse_body(response)
      raw = response.body.to_s
      return [ {}, raw ] if raw.empty?

      parsed = JSON.parse(raw, symbolize_names: true)
      [ parsed.is_a?(Hash) ? parsed : {}, raw ]
    rescue JSON::ParserError
      [ {}, raw ]
    end
  end
end
