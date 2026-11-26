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

    # 채널 키 미등록 전용 예외(PLAN-5 — 리뷰 W-2) — 설정 오류를 코드 오류(ArgumentError)와
    # 구분한다. 갱신·재시도 잡이 이 예외만 잡아 해당 구독을 건너뛰게 하고, 그 외 예외는
    # 기존대로 잡 밖으로 나가게 둔다.
    class MissingChannelKey < StandardError; end

    # api_secret·전송 계층을 주입 가능하게 둔다 — 테스트 stub과(기본값) 실측(주입)을 분리.
    def initialize(api_secret: Rails.application.credentials.dig(:portone, :api_secret),
                   store_id: Rails.application.credentials.dig(:portone, :store_id))
      @api_secret = api_secret
      @store_id = store_id
    end

    # 인증 결제 수동 승인 — 수금 패스 위젯(결제창) 완료 응답의 paymentToken을 최종 승인으로
    # 교환한다. totalAmount·isTest·currency는 포트원 검증용 파라미터(공식 OpenAPI v2
    # ConfirmPaymentBody — 결제 건 총 금액·테스트 여부·통화와 일치하지 않으면 포트원이 오류를
    # 반환하므로 값 전달 권장)로, 주문 레코드 원값·환경 기대값(운영 false·그 외 true)·KRW 단건
    # 고정을 그대로 보낸다. 승인 응답(ConfirmedPaymentSummary — pgTxId·paidAt만)에는 검증에 쓸
    # 필드가 없으므로 서버 쪽 2차 검증(금액·채널·통화)은 승인 뒤 재조회한 결제 건으로
    # PortOne::PaymentVerifier(확정점 FulfillPassService)가 담당한다(재리뷰 R-1·R-2·R2-4).
    def confirm_payment(payment_id:, payment_token:, total_amount:, is_test:, currency:,
                        store_id: default_store_id)
      request(method: :post, path: "/payments/#{escape(payment_id)}/confirm",
              body: { storeId: store_id, paymentToken: payment_token,
                      totalAmount: total_amount, isTest: is_test, currency: currency })
    end

    # 빌링키 발급 — 카드 인증 위젯이 발급한 토큰(billingIssueToken)을 빌링키로 교환한다.
    # 채널은 정기결제용(channel_key_billing), 고객 식별자는 구독의 pg_customer_key다.
    def issue_billing_key(issue_token:, channel_key:, customer_id:, store_id: default_store_id)
      ensure_channel_key!(channel_key)
      request(method: :post, path: "/billing-keys/confirm",
              body: { storeId: store_id, billingIssueToken: issue_token,
                      channelKey: channel_key, customer: { id: customer_id } })
    end

    # 자동결제 차감(정기결제) — Plus 월 구독 갱신. payment_id는 서버가 채번한 주문 번호
    # (pg_order_id)를 그대로 쓰며, 포트원이 이 ID로 중복 차감을 거부한다(멱등).
    # 응답은 결제 결과 스냅샷({ payment: {...} } — Order.metadata 보관).
    def charge_billing_key(payment_id:, billing_key:, channel_key:, amount:, customer_id:,
                           order_name:, store_id: default_store_id)
      ensure_channel_key!(channel_key)
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

    # 채널 키 미등록 가드(PLAN-5 — fail-closed) — 환경의 채널 키가 credentials에 없으면
    # (PortOne::ChannelKey가 nil) 결제 요청을 포트원으로 보내지 않고 여기서 실패한다.
    # 라이브 키로 대체하지 않으므로 키 부재는 즉시 가시적 오류가 된다.
    def ensure_channel_key!(channel_key)
      return if channel_key.present?

      raise MissingChannelKey, "포트원 채널 키가 등록되지 않았습니다 — credentials(:portone)에 환경에 맞는 채널 키를 등록해 주세요"
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
      # TEST 환경 실호출 원천 차단(2026-11-24 — 리뷰 중 운영 API 실호출 사고 계기) — test도
      # 운영과 같은 credentials를 로드하므로 stub 누락 시 실제 결제 API 호출이 나간다.
      # with_portone_client(생성자 교체) 또는 HTTP transport stub(client_service_test의
      # stub_start) 경유 시에만 통과한다(솔라피·이메일 perform 가드와 같은 방식).
      if Rails.env.test? && !Thread.current[:portone_http_stub]
        raise ApiError.new(status: nil, code: "TEST_GUARD",
                           message: "test 환경 실호출 차단 — with_portone_client 또는 HTTP transport stub 필요")
      end

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
