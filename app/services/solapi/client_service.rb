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
# 성공 응답은 운영 실측 성공으로 검증됐다(2026-11-06 — messageId 캡처 확인). [INFERENCE] 마킹
# 해소 — 단일 send 전 규격(엔드포인트·바디·variables 키·인증·응답 식별자)은 실측·공식 문서로
# 확정 상태다.
# 잔액 조회(ADMIN-5·REM-10 — 선불 크레딧 모니터링)는 읽기 전용 GET으로, 발송과 동일 HMAC
# Authorization 헤더를 공유한다. 응답 스키마는 2026-11-20·11-23 라이브 실측으로 확정(get_balance
# 주석 참조). 발송(write) 경로와 무관한 조회라 발송 멱등성(SEC-5)·상한(PLAN-3) 적용 대상이
# 아니다.
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
    # 잔액 조회 엔드포인트(ADMIN-5·REM-10) — 2026-11-20 라이브 실측으로 확정(get_balance 주석).
    BALANCE_PATH = "/cash/v1/balance"
    # 요청 메서드별 Net::HTTP 클래스 — 발송(POST)·조회(GET) 2종만 사용. 미지원 메서드는
    # KeyError로 fail-fast한다.
    NET_REQUEST_CLASSES = { get: Net::HTTP::Get, post: Net::HTTP::Post }.freeze
    # 2026-10-29 최초 승인 4종은 솔라피 등록 변수명이 "발행인명"이 아니라 "발행인"이다
    # (사용자 확인 2026-11-06 — 운영 실측 성공 조합). 나머지 14종은 "발행인명" 그대로다.
    # 도메인 계층은 순수 키 "발행인명"을 유지하고(ALIMTALK_TEMPLATES.md 공통 규칙) 이 래퍼가
    # 템플릿별로 치환한다 — 템플릿별 키 변환도 래퍼(스펙 계층)의 송신 직전 책임이다.
    LEGACY_ISSUER_KEY_TEMPLATES = %w[invoice_notice confirm_d1 requeue_d7 final_d14].freeze

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
      # YAML 작성 스타일(심벌 키 :phone_verification: / 문자열 키) 어느 쪽이든 조회가
      # 항상 문자열 키(@template_ids[template_key.to_s])로 이뤄지므로 주입분을 포함해
      # stringify_keys로 정규한다 — 심벌 키 credentials에서 MISSING_TEMPLATE 오동작 방지.
      @template_ids = (template_ids || {}).stringify_keys
    end

    # 등록 템플릿 키 맵(credentials solapi.template_ids) — 도메인 계층의 알림톡/SMS 분기
    # 판정용 접근자(AUTH-9 phone_verification — PhoneVerifications::SendService가 키 존재
    # 여부로 경로를 고른다). 읽기 전용 노출이며 @template_ids는 initialize에서 항상 Hash
    # 보장(nil → {}).
    def template_ids
      @template_ids
    end

    # SMS 단일 발송(AUTH-9 — 휴대폰 인증번호 등 템플릿 불요 문자). 알림톡과 동일 엔드포인트
    # (POST /messages/v4/send)·동일 인증(HMAC-SHA256)을 쓰며, message 객체에 type: "SMS"와
    # text 본문을 넣는다(kakaoOptions 대신). pf_id·템플릿이 필요 없으므로 credentials 검증도
    # api_key·api_secret·sender_number만 요구한다(ensure_credentials!의 require_pf_id 옵션).
    # [INFERENCE] 바디 스펙(type/text 키 배치)은 공식 문서 messages-v4/send 규격과 공식 SDK의
    # SMS 타입 필드에 근거한 실측 전 항목 — 첫 실발송 시 응답으로 확정한다(운영 노트에 기록).
    def send_sms(to:, body:, dry_run: false)
      ensure_credentials!(require_pf_id: false)

      payload = {
        message: {
          to: normalize_phone(to),
          from: @sender_number,
          text: body,
          type: "SMS"
        }
      }
      return dry_run_response(payload) if dry_run

      request(method: :post, path: SEND_PATH, body: payload)
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
                          variables: wrap_variables(variables, template_key) }
        }
      }
      return dry_run_response(body) if dry_run

      request(method: :post, path: SEND_PATH, body: body)
    end

    # 잔액 조회(ADMIN-5·REM-10 — 선불 크레딧 소진으로 인한 발송 중단 예방). GET
    # /cash/v1/balance로 단일 발송과 동일 HMAC-SHA256 Authorization 헤더를 쓴다(인증 체계는
    # 엔드포인트 무관 공통 — 공식 문서 authentication 규격). 읽기 전용이라 부작용이 없어
    # dry_run 개념이 필요 없다.
    #
    # 스키마(2026-11-20 첫 실측·2026-11-23 원본 응답으로 재확인 — 공식 문서 getBalance 일치):
    # 응답은 profit·accountId·autoRecharge·balance·deposit·lowBalanceAlert·minimumCash·point·
    # rechargeTo·rechargeTryCount·balanceOnly 11키이고, 금액은 원 단위 소수다(정수가 아니다 —
    # 11-20 기록의 "정수"는 to_i 정규화 뒤 값이다). 쓰는 키는 3개다.
    #   balance  잔액 + 예치금. 예치금은 부가세 10%를 뺀 금액으로 합산된다(공급가액 기준 —
    #            실측 deposit 8535.9에 balance 7682.31 = deposit × 0.9)
    #   deposit  예치금 그대로(부가세 포함 — 솔라피 콘솔에 보이는 기준)
    #   point    포인트
    # 두 기준을 모두 돌려준다 — 발송 단가가 "차감 단가(VAT미포함)"이라 잔여 발송량·경고 판정은
    # balance가 맞고 콘솔 대조는 deposit이 맞다. 한쪽만 표시하면 10% 차이로 콘솔과 다르게
    # 보인다(2026-11-23 사용자 지적). 반환형 { balance:, point:, deposit: } — 정수 원(소수 원은
    # 버림), deposit은 응답에 없으면 nil.
    def get_balance
      ensure_credentials!(require_pf_id: false)
      parse_balance(request(method: :get, path: BALANCE_PATH))
    end

    private

    # fail-fast — credentials 누락은 발송 시도 전에 구성 오류로 분류한다(반복 시도 방지).
    # send_sms는 카카오채널 발신 프로필(pf_id)이 필요 없다(require_pf_id: false).
    def ensure_credentials!(require_pf_id: true)
      required = [ :@api_key, :@api_secret, :@sender_number ]
      required << :@pf_id if require_pf_id
      missing = required.select { |name| instance_variable_get(name).blank? }
      return if missing.empty?

      raise ApiError.new(status: nil, code: "MISSING_CREDENTIALS",
                         message: "솔라피 credentials(:solapi) 설정이 누락되었습니다: #{missing.join(', ')}")
    end

    # 순수 변수명 키 → 솔라피 스펙 키 리터럴 "#{변수명}"으로 래핑한다. 래핑·템플릿별 키 변환
    # (LEGACY_ISSUER_KEY_TEMPLATES — 최초 승인 4종은 등록 변수명이 "발행인")은 이 래퍼의
    # 송신 직전 책임이다 — 도메인 계층(Reminders::SendService 조립·message_logs.variables
    # P4 스냅샷)은 순수 키를 유지해 스펙 변환을 한 곳에 둔다. "##{k}" 보간은 "#발행인명"이
    # 되는 함정이라(리터럴 #{를 소스에 직접 못 씀) format으로 조립한다.
    def wrap_variables(variables, template_key)
      variables.to_h do |key, value|
        key = "발행인" if legacy_issuer_template?(template_key) && key == "발행인명"
        [ format('#{%s}', key), value ]
      end
    end

    def legacy_issuer_template?(template_key)
      LEGACY_ISSUER_KEY_TEMPLATES.include?(template_key.to_s)
    end

    # 잔액 응답 정규화 — 방어적 파싱(스키마 이탈은 ApiError로 분류). balance 키 누락·null·
    # 비숫자는 fail-fast해 관리자 대시보드가 잘못된 잔액을 정상처럼 표시하는 것을 막는다.
    # point는 부여 크레딧이 없는 계정에서 0으로 관측될 수 있어 기본 0으로 관대하게 정규한다.
    # deposit(예치금 — 콘솔 표시 기준)은 보조값이라 누락·비숫자면 nil로 두고, 표시층이 부가세
    # 제외 금액에 기준을 명시해 그린다(경고 판정은 balance 하나로 한다).
    def parse_balance(payload)
      balance = parse_amount(payload[:balance])
      if balance.nil?
        raise ApiError.new(status: nil, code: "UNEXPECTED_BALANCE_RESPONSE",
                           message: "솔라피 잔액 응답 스키마가 예상과 다릅니다: #{payload.inspect}")
      end

      { balance: balance, point: parse_amount(payload[:point]) || 0,
        deposit: parse_amount(payload[:deposit]) }
    end

    # 금액 정규화 — Numeric은 정수화(소수 원은 버림 — 7682.31 → 7682), "12,345" 같은 콤마
    # 숫자형 문자열은 제거 후 정수화. 그 외(키 누락·null·비숫자 문자열)는 nil(스키마 이탈 신호).
    def parse_amount(value)
      if value.is_a?(Numeric)
        value.to_i
      elsif value.is_a?(String) && value.match?(/\A\d+(,\d+)*\z/)
        value.delete(",").to_i
      end
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
      net_request = NET_REQUEST_CLASSES.fetch(method).new(uri)
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
      # TEST 환경 실호출 원천 차단(2026-11-20) — credentials가 로드되므로 stub 누락 시
      # 실제 API 호출이 나간다(010-5555-1111 실발송 사고 계기). with_solapi_client(생성자
      # 교체) 또는 HTTP transport stub(client_service_test의 stub_start) 경유 시에만 통과.
      if Rails.env.test? && !Thread.current[:solapi_http_stub]
        raise ApiError.new(status: nil, code: "TEST_GUARD",
                           message: "test 환경 실호출 차단 — with_solapi_client 또는 HTTP transport stub 필요")
      end

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
