# 솔라피 메시지 API 래퍼(F-REM — REM-10·§6.19 EXT) — 알림톡 발송의 단일 진입점. 외부 API는
# 도메인 wrapper로만 쓴다(아키텍처 규약). PortOne::ClientService와 같은 패턴의 ActiveRecord에
# 의존하지 않는 순수 Ruby 클래스라 테스트에서 응답 Hash를 stub할 수 있다.
# 대체문자(REM-5)는 솔라피 템플릿 등록 시 지정한 대체문자 필드로 처리되므로 별도 SMS 발송
# 경로가 없다(2026-11-03 확정). 발신자는 카카오채널 '받을돈' 발신 프로필(REM-1)이다.
# 스펙 근거(2026-11-06 확정): ① 인증 — signature = HMAC-SHA256(api_secret, date + salt)의
# hex 다이제스트(공식 문서 solapi.com/developers/api/authentication-api-key — 구분자 없는
# 단순 연결·apiKey 미포함. 운영 실측 "생성한 signature를 확인하세요" 거부의 원인 해소)
# ② 엔드포인트·바디 — POST /messages/v4/send에 최상위 message 단수 객체(단일 발송 규격.
# messages 배열은 다중·그룹 발송용 — 2026-11-06 3차 실측·공식 문서 확정) ③ variables 키는
# 리터럴 #{변수명} 형태(같은 문서 예시 — "#{고객명}": "홍길동") ④ 발신번호는 하이픈 제거
# 숫자만(공식 SDK solapi-nodejs phoneNumberSchema 소스 확인).
# [INFERENCE] 성공 응답 필드 구조(단일 send 응답의 messageId 위치)만 미실측 추정 상태다.
require "net/http"
require "json"
require "openssl"
require "securerandom"

module Solapi
  class ClientService
    BASE_URL = "https://api.solapi.com"
    TIMEOUT_SECONDS = 10
    # 메시지 v4 단일 발송 엔드포인트 — 실측·공식 문서로 확정(2026-11-06).
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
    # 키와 동일 문자열이며, variables는 순수 변수명("발행인명")을 키로 하는 치환값 맵이다.
    # dry_run: true는 실발송·네트워크 호출 없이 조립된 요청 스펙을 돌려준다(검증용 —
    # dry_run_response 주석 참조).
    def send_alimtalk(template_key:, to:, variables: {}, dry_run: false)
      template_id = @template_ids[template_key.to_s]
      unless template_id
        raise ApiError.new(status: nil, code: "MISSING_TEMPLATE",
                           message: "솔라피 템플릿 코드가 credentials에 없습니다: #{template_key}")
      end
      ensure_credentials!

      body = {
        # 단일 발송(POST /messages/v4/send)의 바디 최상위는 message 단수 객체다 — messages
        # 배열은 다중·그룹 발송(send-many·groups) 문맥의 규격이고, 공식 문서 messages-ata의
        # 배열 예시가 그룹 발송 예시를 재사용한 것이었다(2026-11-06 3차 실측 확정 — 오류
        # 본문 [["message" 필수입니다.], "messages" 사용할 수 없습니다.]). 1차 실패의 본체는
        # variables 키 #{} 누락이었던 것으로 수렴 — 이번 오류는 variables를 불평하지 않았다
        # (래핑 유효 재확인).
        message: {
          to: normalize_phone(to),
          from: @sender_number,
          # 본문은 템플릿(kakaoOptions.templateId) + variables 치환으로 전달한다(text 미포함).
          kakaoOptions: { pfId: @pf_id, templateId: template_id,
                          variables: wrap_variables(variables) }
        }
      }
      return dry_run_response(body) if dry_run

      request(method: :post, path: SEND_PATH, body: body)
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

    # 순수 변수명 키 → 솔라피 스펙 키 리터럴 "#{변수명}"으로 래핑한다. 래핑은 이 래퍼의 송신
    # 직전 책임이다 — 도메인 계층(Reminders::SendService 조립·message_logs.variables P4
    # 스냅샷)은 순수 키를 유지해 스펙 변환을 한 곳에 둔다. "##{k}" 보간은 "#발행인명"이 되는
    # 함정이라(리터럴 #{를 소스에 직접 못 씀) format으로 조립한다.
    def wrap_variables(variables)
      variables.to_h { |key, value| [ format('#{%s}', key), value ] }
    end

    # dry_run — 실발송 없는 스펙 검증용. 솔라피 API에 dryRun 파라미터(쿼리·바디 모두)는
    # 존재하지 않는다(2026-11-06 공식 문서 전수 확인 — solapi.com/developers/api/messages·
    # messages-ata·msg-groups-createMessageGroup·msg-groups-sendGroupMessage 어디에도 없고,
    # 공식 SDK solapi-nodejs·solapi-kotlin 요청 모델에도 부재. 문서화된 유일한 사전 검증
    # 옵션은 send-many의 바디 필드 strict). 따라서 래퍼 수준 실호출 스킵으로 구현한다 —
    # 요청은 조립하되 네트워크 연결 자체를 만들지 않는다.
    def dry_run_response(body)
      { dryRun: true, path: SEND_PATH, body: body }
    end

    # 하이픈 없는 숫자 형식 — 비숫자를 제거한다. 공식 SDK와 동일 규격(solapi-nodejs
    # phoneNumberSchema — 하이픈 제거 후 /^[0-9]+$/ 검증, 2026-11-06 소스 확인).
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

    # 솔라피 인증 — signature = HMAC-SHA256(api_secret, date + salt)의 hex 다이제스트.
    # 메시지는 date·salt의 구분자 없는 단순 연결이고 apiKey는 시그니처에 포함하지 않는다
    # (Authorization 헤더에만). 공식 문서 solapi.com/developers/api/authentication-api-key·
    # 공식 Node/Python 예시와 동일(2026-11-06 확정 — 운영 실측 "생성한 signature를
    # 확인하세요" 거부의 원인. 점 구분+apiKey 포함이던 구식 계산과 다르다).
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
      signature = OpenSSL::HMAC.hexdigest("SHA256", @api_secret, date + salt)
      "HMAC-SHA256 apiKey=#{@api_key}, date=#{date}, salt=#{salt}, signature=#{signature}"
    end

    def perform((uri, net_request))
      Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                      open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
        http.request(net_request)
      end
    end

    def parse(response)
      payload, raw_body = parse_body(response)

      return payload if response.is_a?(Net::HTTPSuccess)

      # 오류 본문은 {code, message} 가정과 다르게 온다(2026-11-06 실측 — message가 nil로
      # 누실돼 error_message가 "Solapi::ApiError"만 남음). errorMessage 키와 비JSON·비객체
      # raw 본문까지 fallback해 P4 진단 정보를 보존한다.
      raise ApiError.new(status: response.code.to_i,
                         code: payload[:code] || "HTTP_#{response.code}",
                         message: payload[:message] || payload[:errorMessage] ||
                                  raw_body.presence)
    end

    # 응답 본문 파싱 — payload는 해시(비해시 JSON·JSON 아님·빈 본문은 빈 해시), raw는
    # 원문 문자열. JSON::ParserError와 비객체 JSON이 ApiError 정규화를 우회하는 것을 막는다.
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
