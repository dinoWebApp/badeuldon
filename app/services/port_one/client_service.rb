# 포트원 V2 API 래퍼(F-PLAN — PLAN-5·§6.19 EXT) — 결제 승인·빌링키 발급·자동결제 차감·결제
# 조회·취소의 단일 진입점. 외부 API는 도메인 wrapper로만 쓴다(아키텍처 규약). ActiveRecord에
# 의존하지 않는 순수 Ruby 클래스라 테스트에서 응답 Hash를 stub할 수 있다.
# 인증은 V2 API Secret(`Authorization: PortOne {secret}` — 포트원 규격), 타임아웃 60초(포트원
# 권장 — PG 응답 지연 고려), POST에는 멱등 키(Idempotency-Key — UUID)를 보낸다.
require "net/http"
require "json"
require "securerandom"

module PortOne
  class ClientService
    BASE_URL = "https://api.portone.io"
    TIMEOUT_SECONDS = 60

    # api_secret·전송 계층을 주입 가능하게 둔다 — 테스트 stub과(기본값) 실측(주입)을 분리.
    def initialize(api_secret: Rails.application.credentials.dig(:portone, :api_secret),
                   store_id: Rails.application.credentials.dig(:portone, :store_id))
      @api_secret = api_secret
      @store_id = store_id
    end

    # 인증 결제 수동 승인 — 수금 패스 위젯(결제창) 완료 응답의 paymentToken을 최종 승인으로
    # 교환한다. 포트원이 결제 요청 당시 금액과 일치함을 검증하므로 amount는 위젯 호출에 쓴
    # 주문 레코드 원값 기준이다.
    def confirm_payment(payment_id:, payment_token:, store_id: default_store_id)
      request(method: :post, path: "/payments/#{escape(payment_id)}/confirm",
              body: { storeId: store_id, paymentToken: payment_token })
    end

    # 빌링키 발급 — 카드 인증 위젯이 발급한 토큰(billingIssueToken)을 빌링키로 교환한다.
    # 채널은 정기결제용(channel_key_billing), 고객 식별자는 구독의 pg_customer_key다.
    def issue_billing_key(issue_token:, channel_key:, customer_id:, store_id: default_store_id)
      request(method: :post, path: "/billing-keys/confirm",
              body: { storeId: store_id, billingIssueToken: issue_token,
                      channelKey: channel_key, customer: { id: customer_id } })
    end

    # 자동결제 차감(정기결제) — Plus 월 구독 갱신. payment_id는 서버가 채번한 주문 번호
    # (pg_order_id)를 그대로 쓰며, 포트원이 이 ID로 중복 차감을 거부한다(멱등).
    # 응답은 결제 결과 스냅샷({ payment: {...} } — Order.metadata 보관).
    def charge_billing_key(payment_id:, billing_key:, channel_key:, amount:, customer_id:,
                           order_name:, store_id: default_store_id)
      request(method: :post, path: "/payments/#{escape(payment_id)}/billing-key",
              body: { storeId: store_id, billingKey: billing_key, channelKey: channel_key,
                      orderName: order_name, amount: { total: amount }, currency: "KRW",
                      customer: { id: customer_id } })
    end

    # 결제 조회 — 웹훅 무결성 확인·모호 실패 재확인이 승인 응답 대신 이 조회를 신뢰한다
    # (위조 이벤트 차단 — 값은 포트원 서버 응답으로만 확정).
    def get_payment(payment_id:, store_id: default_store_id)
      request(method: :get,
              path: "/payments/#{escape(payment_id)}?storeId=#{escape(store_id)}")
    end

    # 결제 취소(전액 환불) — CS 절차용. 부분 취소·환불 처리는 정책상 콘솔 수동 절차(PLAN-6)다.
    def cancel_payment(payment_id:, reason:, store_id: default_store_id)
      request(method: :post, path: "/payments/#{escape(payment_id)}/cancel",
              body: { storeId: store_id, reason: reason })
    end

    private

    def default_store_id
      @store_id
    end

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
      net_request["Authorization"] = "PortOne #{@api_secret}"
      net_request["Content-Type"] = "application/json"
      net_request["Idempotency-Key"] = %("#{SecureRandom.uuid}") if net_request.is_a?(Net::HTTP::Post)
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

      # 포트원 오류 본문 — { type, message }가 표준이고 PG사 기인 오류는 pgCode·pgMessage를
      # 운반한다(최상위 또는 failure 객체). 코드·메시지는 ApiError로 정규화해 상위 계층이
      # PG사 세부 사유 없이도 분기할 수 있게 한다.
      raise ApiError.new(status: response.code.to_i,
                         code: payload[:code] || payload[:type],
                         message: payload[:message],
                         pg_code: pg_error_field(payload, :pgCode),
                         pg_message: pg_error_field(payload, :pgMessage))
    end

    def pg_error_field(payload, key)
      payload[key] || payload.dig(:failure, key)
    end

    def escape(value)
      URI.encode_www_form_component(value.to_s)
    end
  end
end
