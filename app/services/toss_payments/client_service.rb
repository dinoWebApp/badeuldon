# 토스페이먼츠 코어 API 래퍼(F-PLAN — PLAN-5·§6.19 EXT) — 결제 승인·빌링키 발급·자동결제
# 차감·결제 조회의 단일 진입점. 외부 API는 도메인 wrapper로만 쓴다(아키텍처 규약). ActiveRecord에
# 의존하지 않는 순수 Ruby 클래스라 시스템 테스트에서 응답 Hash를 stub할 수 있다.
# 인증은 secret_key Basic Auth(사용자명=secret_key, 비밀번호 없음 — 토스 규격), 타임아웃 10초.
require "net/http"
require "json"

module TossPayments
  class ClientService
    BASE_URL = "https://api.tosspayments.com/v1"
    TIMEOUT_SECONDS = 10

    # secret_key·전송 계층을 주입 가능하게 둔다 — 테스트 stub과(기본값) 실측(주입)을 분리.
    def initialize(secret_key: Rails.application.credentials.dig(:toss, :secret_key))
      @secret_key = secret_key
    end

    # 단건 결제 승인 — 수금 패스 구매 리다이렉트 콜백(paymentKey)의 승인. 토스가 위젯 요청
    # 당시 금액과 일치함을 검증하므로 amount는 반드시 주문 레코드의 원값을 넘긴다.
    def confirm_payment(order_id:, payment_key:, amount:)
      request(method: :post, path: "/payments/confirm",
              body: { orderId: order_id, paymentKey: payment_key, amount: amount })
    end

    # 빌링키 발급 — 카드 인증 위젯이 발급한 authKey를 자동결제 키로 교환한다.
    def issue_billing_key(customer_key:, auth_key:)
      request(method: :post, path: "/billing/authorizations/issue",
              body: { customerKey: customer_key, authKey: auth_key })
    end

    # 자동결제 차감(정기결제) — Plus 월 구독 갱신. 응답은 결제 결과 스냅샷(Order.metadata 보관).
    def charge_billing_key(customer_key:, billing_key:, order_id:, amount:)
      request(method: :post, path: "/billing/#{customer_key}",
              body: { customerKey: customer_key, billingKey: billing_key,
                      orderId: order_id, amount: amount })
    end

    # 결제 조회 — 웹훅(paymentStatusChanged) 무결성 확인이 승인 응답 대신 이 조회를
    # 신뢰한다(위조 이벤트 차단 — 값은 토스 서버 응답으로만 확정).
    def get_payment(payment_key:)
      request(method: :get, path: "/payments/#{payment_key}")
    end

    private

    def request(method:, path:, body: nil)
      response = perform(build_request(method:, path:, body:))
      parse(response)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise ApiError.new(status: nil, code: "TIMEOUT", message: e.message)
    rescue SocketError, Errno::ECONNREFUSED => e
      raise ApiError.new(status: nil, code: "CONNECTION", message: e.message)
    end

    def build_request(method:, path:, body:)
      uri = URI.parse("#{BASE_URL}#{path}")
      net_request = net_class(method).new(uri)
      net_request.basic_auth(@secret_key, "")
      net_request["Content-Type"] = "application/json"
      net_request.body = JSON.generate(body) if body
      [ uri, net_request ]
    end

    def net_class(method)
      case method
      when :post then Net::HTTP::Post
      else Net::HTTP::Get
      end
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

      raise ApiError.new(status: response.code.to_i,
                         code: payload[:code], message: payload[:message])
    end
  end
end
