# 단건 결제 확정 검증기(PLAN-5 — 2026-11-25 재리뷰 R-1·R-2 반영) — 포트원에서 재조회
# (get_payment)한 전체 결제 건을 주문과 대조해 어긋나면 paid 확정을 막는다(fail-closed).
# 승인(confirm) 응답(ConfirmedPaymentSummary)에는 pgTxId·paidAt만 있어 검증 대상이 아니다 —
# 검증 입력은 항상 재조회 결과다(2026-11-25 콜백 경로 정정). ActiveRecord에 의존하지 않는
# 순수 Ruby 클래스다(ClientService와 같은 테스트 전략).
#
# 근거(포트원 공식 OpenAPI v2 1.16.0) — 결제 객체(PaidPayment)의 amount는 PaymentAmount로
# paid("실제 결제금액")가 required이고, channel은 SelectedChannel로 type이 LIVE·TEST enum(required),
# currency도 required(enum에 KRW 포함)다. 승인 요청의 totalAmount·isTest·currency는
# "검증용 파라미터로, 결제 건 총 금액·테스트 여부·통화와 일치하지 않을 경우 오류가 반환됩니다"
# (값 전달 권장)일 뿐 — 서버가 재조회 결제 건을 대조하지 않으면 금액·채널·통화는 여전히 무검증이다.
#
# 왜(fail-closed): 확정점이 상태(PAID)만 보면, 로그인 사용자가 자기 대기 주문의 paymentId로
# 낮은 금액을 넣거나 테스트 채널로 결제해 정가 상품(수금 패스·내용증명·세금계산서)을 받을 수
# 있다. 통화(currency)도 KRW 단건 고정으로 검증한다(R2-4 — 금액 숫자만 맞으면 통과하는 우회
# 차단). 금액 비교는 정확히 같은 숫자로 판정한다(0원 주문은 없어 paid 누락·비숫자는 실패로
# 떨어진다). 채널 기대값은 환경 분리(PLAN-5)와 동일한 판정 — 운영은 LIVE, 그 외 환경은 TEST만
# 수용한다(양방향 격리).
#
# 사용처: 단건 결제의 유일한 paid 확정점 Orders::FulfillPassService(콜백 PurchaseService·웹훅
# Webhooks::PortOneController 공통). Plus 갱신은 서버가 금액·채널을 지정하는 빌링키 차감이라
# 검증 대상이 아니다. ClientService는 심볼 키로 파싱하므로 payment의 키는 심볼이다(문자열 키 해시는
# 검증 실패로 처리 — 관대하게 받지 않는다). amount·channel이 Hash 외 형태(문자열·배열·숫자 등)여도
# dig의 TypeError가 아니라 검증 실패로 떨어진다 — 모르는 응답 형태는 전부 실패다(fail-closed).
module PortOne
  class PaymentVerifier
    # 검증 실패(재리뷰 R-1·R-2) — 결제가 주문과 일치하지 않는다. 모호 실패가 아니라 결정적
    # 불일치라 상위 계층은 pending 회복이 아니라 주문 실패 확정으로 처리한다(규약 §3.5-5 —
    # 전용 예외. UpgradeService::UpgradeError 선례).
    class VerificationError < StandardError
      REASON_LABELS = { amount_mismatch: "금액 불일치", channel_mismatch: "채널 불일치",
                        currency_mismatch: "통화 불일치" }.freeze

      attr_reader :reason, :detail

      def initialize(reason:, detail:)
        @reason = reason
        @detail = detail
        super("결제 확정 검증 실패(#{REASON_LABELS.fetch(reason)}): #{detail}")
      end
    end

    # 채널 종류 기대값(공식 enum) — live가 true일 때만 LIVE, 그 외(nil 포함)는 TEST(fail-closed).
    EXPECTED_CHANNEL_TYPES = { true => "LIVE", false => "TEST" }.freeze
    # 통화 기대값 — KRW 단건 고정(R2-4. 공식 PaidPayment.currency required — enum에 KRW 포함).
    EXPECTED_CURRENCY = "KRW".freeze

    # payment — ClientService 응답(심볼 키 Hash·nil 허용). 통과하면 payment를 그대로 돌려준다.
    def self.verify!(payment, order_amount:, live: PortOne::ChannelKey.live_channel?)
      new(order_amount:, live:).verify!(payment)
    end

    def initialize(order_amount:, live:)
      @order_amount = order_amount.to_i
      # live는 ChannelKey.live_channel?(항상 true/false)로만 전달되지만, nil 등 다른 값이 와도
      # 테스트 쪽(false)으로 해석한다(fail-closed — 라이브로 해석하지 않는다).
      @expected_channel_type = EXPECTED_CHANNEL_TYPES.fetch(live == true)
    end

    def verify!(payment)
      verify_amount!(payment)
      verify_channel!(payment)
      verify_currency!(payment)
      payment
    end

    private

    # ① 금액 — 실제 결제금액(amount.paid)이 주문 금액과 정확히 같은 숫자인가. JSON 정수·소수
    # (4000.0) 형태 모두 통과시키기 위해 Numeric이면서 == 비교다. 값이 없거나(nil) 숫자가 아니면
    # 실패 — payment가 nil인 경우(응답 부재)도 여기서 실패로 떨어진다. 중첩 값은 Hash일 때만
    # 읽는다(amount가 문자열·배열 등이면 dig의 TypeError 대신 nil로 떨어져 실패 — fail-closed).
    def verify_amount!(payment)
      amount = payment.is_a?(Hash) ? payment[:amount] : nil
      paid = amount.is_a?(Hash) ? amount[:paid] : nil
      return if paid.is_a?(Numeric) && paid == @order_amount

      raise VerificationError.new(reason: :amount_mismatch,
                                  detail: "paid=#{paid.inspect} expected=#{@order_amount}")
    end

    # ② 채널 종류 — 결제가 만들어진 채널(channel.type)이 환경 기대값(LIVE/TEST)과 같은가.
    # 공식 enum 외 값·누락은 실패다. 금액 검사가 통과한 시점에 payment는 Hash지만 형태 방어를
    # 유지한다(channel이 Hash 외 형태면 nil로 떨어져 실패).
    def verify_channel!(payment)
      channel = payment.is_a?(Hash) ? payment[:channel] : nil
      type = channel.is_a?(Hash) ? channel[:type] : nil
      return if type == @expected_channel_type

      raise VerificationError.new(reason: :channel_mismatch,
                                  detail: "type=#{type.inspect} expected=#{@expected_channel_type}")
    end

    # ③ 통화(R2-4) — 결제 통화(currency)가 KRW인가. 금액 숫자만 맞으면 통과하던 우회를 막는
    # 방어다. 누락·그 외 통화는 실패다(공식 Payment.currency는 required — 누락은 응답 이상).
    def verify_currency!(payment)
      currency = payment.is_a?(Hash) ? payment[:currency] : nil
      return if currency == EXPECTED_CURRENCY

      raise VerificationError.new(reason: :currency_mismatch,
                                  detail: "currency=#{currency.inspect} expected=#{EXPECTED_CURRENCY}")
    end
  end
end
