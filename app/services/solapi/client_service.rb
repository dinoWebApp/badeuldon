# 솔라피 메시지 API 래퍼(F-REM — REM-10·§6.19 EXT) — 알림톡 발송의 단일 진입점. 외부 API는
# 도메인 wrapper로만 쓴다(아키텍처 규약). PortOne::ClientService와 같은 패턴의 ActiveRecord에
# 의존하지 않는 순수 Ruby 클래스라 테스트에서 응답 Hash를 stub할 수 있다.
# 대체문자(REM-5)는 솔라피 템플릿 등록 시 지정한 대체문자 필드로 처리되므로 별도 SMS 발송
# 경로가 없다(2026-11-03 확정). 발신자는 카카오채널 '받을돈' 발신 프로필(REM-1)이다.
# [INFERENCE] 인증·엔드포인트·응답 스펙은 solapi.com/developers 문서 기준 구현이며 라이브
# 실측 전까지 추정 마킹 상태다(테스트는 stub — 라이브 검증은 기술 부채).
require "net/http"
require "json"
require "openssl"
require "securerandom"

module Solapi
  class ClientService
    BASE_URL = "https://api.solapi.com"
    TIMEOUT_SECONDS = 10
    # [INFERENCE] 메시지 v4 단일 발송 엔드포인트
    SEND_PATH = "/messages/v4/send"

    # credentials·전송 계층을 주입 가능하게 둔다 — 테스트 stub과(기본값) 실측(주입)을 분리.
    def initialize(api_key: Rails.application.credentials.dig(:solapi, :api_key),
                   api_secret: Rails.application.credentials.dig(:solapi, :api_secret),
                   pf_id: Rails.application.credentials.dig(:solapi, :pf_id),
                   sender_number: Rails.application.credentials.dig(:solapi, :sender_number),
                   template_ids: Rails.application.credentials.dig(:solapi, :template_ids))
      @api_key = api_key
      @api_secret = api_secret
      @pf_id = pf_id
      @sender_number = sender_number
      @template_ids = template_ids || {}
    end

    # 알림톡 발송(REM-10) — template_key는 ALIMTALK_TEMPLATES.md·credentials template_ids의
    # 키와 동일 문자열이며, variables는 #{변수명}을 키로 하는 치환값 맵이다.
    def send_alimtalk(template_key:, to:, variables: {})
      template_id = @template_ids[template_key.to_s]
      unless template_id
        raise ApiError.new(status: nil, code: "MISSING_TEMPLATE",
                           message: "솔라피 템플릿 코드가 credentials에 없습니다: #{template_key}")
      end
      ensure_credentials!

      request(method: :post, path: SEND_PATH, body: {
        message: {
          to: normalize_phone(to),
          from: @sender_number,
          # [INFERENCE] 본문은 템플릿(kakaoOptions.templateId) + variables 치환으로 전달한다
          kakaoOptions: { pfId: @pf_id, templateId: template_id, variables: variables }
        }
      })
    end

    private

    # fail-fast — credentials 누락은 발송 시도 전에 구성 오류로 분류한다(반복 시도 방지).
    def ensure_credentials!
      missing = [ :@api_key, :@api_secret, :@pf_id, :@sender_number ]
        .select { |name| instance_variable_get(name).blank? }
      return if missing.empty?

      raise ApiError.new(status: nil, code: "MISSING_CREDENTIALS",
                         message: "솔라피 credentials(:solapi) 설정이 누락되었습니다: #{missing.join(', ')}")
    end

    # [INFERENCE] 하이픈 없는 숫자 형식만 허용되는 것으로 가정하고 비숫자를 제거한다.
    def normalize_phone(to)
      to.to_s.gsub(/\D/, "")
    end

    def request(method:, path:, body: nil)
      response = perform(build_request(method:, path:, body:))
      parse(response)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise ApiError.new(status: nil, code: "TIMEOUT", message: e.message)
    rescue SocketError, Errno::ECONNREFUSED => e
      raise ApiError.new(status: nil, code: "CONNECTION", message: e.message)
    end

    # [INFERENCE] 솔라피 인증 — HMAC-SHA256 시그니처 헤더.
    # signature = HMAC-SHA256(api_secret, "{date}.{salt}.{api_key}")의 hex 다이제스트.
    def build_request(method:, path:, body:)
      uri = URI.parse("#{BASE_URL}#{path}")
      net_request = Net::HTTP::Post.new(uri)
      date = Time.now.utc.iso8601
      salt = SecureRandom.uuid
      net_request["Authorization"] = hmac_authorization(date, salt)
      net_request["Date"] = date
      net_request["Content-Type"] = "application/json"
      net_request.body = JSON.generate(body) if body
      [ uri, net_request ]
    end

    def hmac_authorization(date, salt)
      signature = OpenSSL::HMAC.hexdigest("SHA256", @api_secret, "#{date}.#{salt}.#{@api_key}")
      "HMAC-SHA256 apiKey=#{@api_key}, date=#{date}, salt=#{salt}, signature=#{signature}"
    end

    def perform((uri, net_request))
      Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                      open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
        http.request(net_request)
      end
    end

    def parse(response)
      payload = response.body.to_s.empty? ? {} : JSON.parse(response.body, symbolize_names: true)

      return payload if response.is_a?(Net::HTTPSuccess)

      # [INFERENCE] 솔라피 오류 본문 — { code, message } 형태로 정규화를 가정한다.
      raise ApiError.new(status: response.code.to_i,
                         code: payload[:code] || "HTTP_#{response.code}",
                         message: payload[:message])
    end
  end
end
