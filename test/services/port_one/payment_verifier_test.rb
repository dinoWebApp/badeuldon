require "test_helper"
require_relative "../../test_helpers/fake_portone_client"

# PortOne::PaymentVerifier — 단건 결제 확정 검증기(PLAN-5) 단위 테스트. 이 파일은 재리뷰
# 2회차 R2-4(통화 검증) 중점 — 통화 불일치·누락이 VerificationError(:currency_mismatch)로
# 떨어지는지, 검증 순서(금액→채널→통화)와 fail-closed 기본을 검증한다(금액·채널 전수 행렬은
# Tester 단계 시나리오 — 재리뷰 2회차 §7-2). 포트원 호출 없음 — 순수 객체만 사용한다.
module PortOne
  class PaymentVerifierTest < ActiveSupport::TestCase
    def valid_payment(currency: "KRW", paid: 4_000, type: "TEST")
      { id: "payment-verify-1", status: "PAID", amount: { paid: paid },
        channel: { type: type }, currency: currency }
    end

    test "KRW·금액·채널이 모두 일치하면 payment를 그대로 돌려준다" do
      payment = valid_payment

      assert_same payment, PaymentVerifier.verify!(payment, order_amount: 4_000)
    end

    test "통화가 KRW가 아니면 currency_mismatch로 실패한다 (재리뷰 2회차 R2-4)" do
      error = assert_raises(PaymentVerifier::VerificationError) do
        PaymentVerifier.verify!(valid_payment(currency: "USD"), order_amount: 4_000)
      end

      assert_equal :currency_mismatch, error.reason
      assert_equal 'currency="USD" expected=KRW', error.detail
      assert_match(/통화 불일치/, error.message)
    end

    test "통화가 누락된 응답도 currency_mismatch로 실패한다 (fail-closed)" do
      payment = valid_payment
      payment.delete(:currency) # 공식 PaidPayment.currency는 required — 누락은 응답 이상

      error = assert_raises(PaymentVerifier::VerificationError) do
        PaymentVerifier.verify!(payment, order_amount: 4_000)
      end

      assert_equal :currency_mismatch, error.reason
      assert_equal "currency=nil expected=KRW", error.detail
    end

    test "검증은 금액→채널→통화 순서라 앞선 불일치가 먼저 떨어진다" do
      error = assert_raises(PaymentVerifier::VerificationError) do
        PaymentVerifier.verify!(valid_payment(currency: "USD", paid: 100), order_amount: 4_000)
      end
      assert_equal :amount_mismatch, error.reason

      error = assert_raises(PaymentVerifier::VerificationError) do
        PaymentVerifier.verify!(valid_payment(currency: "USD", type: "LIVE"), order_amount: 4_000)
      end
      assert_equal :channel_mismatch, error.reason
    end

    test "조립 헬퍼(paid_payment)의 기본 결제 건은 통화 KRW를 포함하고 검증을 통과한다 (대역 계약)" do
      payment = FakePortOneClient.paid_payment(id: "payment-verify-1", amount: 4_000)

      assert_equal "KRW", payment[:currency]
      assert_same payment, PaymentVerifier.verify!(payment, order_amount: 4_000)
    end

    # ── 이하 Tester 단계 고정(재리뷰 2회차 §7-2 — 금액·채널·통화 전수 행렬) ──
    # 모든 불일치는 VerificationError로 정규화돼야 한다(fail-closed) — TypeError·
    # NoMethodError·KeyError 같은 런타임 예외가 새면 웹훅 500→재시도 흡수·콜백 500이 된다.

    test "운영 기대(live: true)는 LIVE 채널 결제만 통과시키고 TEST는 channel_mismatch다" do
      payment = valid_payment(type: "LIVE")

      assert_same payment, PaymentVerifier.verify!(payment, order_amount: 4_000, live: true)

      error = assert_raises(PaymentVerifier::VerificationError) do
        PaymentVerifier.verify!(valid_payment(type: "TEST"), order_amount: 4_000, live: true)
      end
      assert_equal :channel_mismatch, error.reason
    end

    test "비운영 기대(live: false)는 TEST 채널 결제만 통과시키고 LIVE는 channel_mismatch다" do
      payment = valid_payment(type: "TEST")

      assert_same payment, PaymentVerifier.verify!(payment, order_amount: 4_000, live: false)

      error = assert_raises(PaymentVerifier::VerificationError) do
        PaymentVerifier.verify!(valid_payment(type: "LIVE"), order_amount: 4_000, live: false)
      end
      assert_equal :channel_mismatch, error.reason
      assert_includes error.detail, "expected=TEST"
    end

    test "amount.paid가 Float(4000.0) 형태도 통과한다 — JSON 소수 형태 호환" do
      payment = valid_payment(paid: 4_000.0)

      assert_same payment, PaymentVerifier.verify!(payment, order_amount: 4_000)
    end

    test "금액이 낮거나 높으면 amount_mismatch다 — 주문 원값과 정확히 같아야 한다" do
      [ 100, 5_000 ].each do |paid|
        error = assert_raises(PaymentVerifier::VerificationError) do
          PaymentVerifier.verify!(valid_payment(paid: paid), order_amount: 4_000)
        end

        assert_equal :amount_mismatch, error.reason
        assert_includes error.detail, "expected=4000"
      end
    end

    test "금액이 nil이거나 amount 키가 없으면 amount_mismatch다 (fail-closed)" do
      assert_amount_mismatch valid_payment(paid: nil)

      missing = valid_payment
      missing.delete(:amount)
      assert_amount_mismatch missing
    end

    test "금액이 문자열(\"4000\")이면 amount_mismatch다 — 협조적 변환 없이 거절한다" do
      assert_amount_mismatch valid_payment(paid: "4000")
    end

    test "amount가 Hash가 아니면(문자열·배열·숫자) amount_mismatch로 떨어진다 — TypeError 아님" do
      [ "4000", [ 4_000 ], 4_000 ].each do |amount|
        assert_amount_mismatch valid_payment.merge(amount: amount)
      end
    end

    test "payment가 nil이거나 Hash가 아니면 amount_mismatch로 떨어진다 — 응답 이상은 전부 실패다" do
      assert_amount_mismatch nil
      assert_amount_mismatch "PAID"
      assert_amount_mismatch [ valid_payment ]
    end

    test "channel.type 누락·공백 포함·소문자·심볼은 channel_mismatch다 — 공식 enum 외 값 거절" do
      [ nil, "TEST ", "test", :TEST ].each do |type|
        error = assert_raises(PaymentVerifier::VerificationError) do
          PaymentVerifier.verify!(valid_payment(type: type), order_amount: 4_000)
        end

        assert_equal :channel_mismatch, error.reason, "type=#{type.inspect}는 거절돼야 한다"
      end
    end

    test "channel이 Hash가 아니면 channel_mismatch로 떨어진다 — TypeError 아님" do
      [ "TEST", [ { type: "TEST" } ], 1 ].each do |channel|
        error = assert_raises(PaymentVerifier::VerificationError) do
          PaymentVerifier.verify!(valid_payment.merge(channel: channel), order_amount: 4_000)
        end

        assert_equal :channel_mismatch, error.reason
      end
    end

    test "통화가 USD·nil이거나 키가 없으면 currency_mismatch다 (R2-4)" do
      [ "USD", nil ].each do |currency|
        error = assert_raises(PaymentVerifier::VerificationError) do
          PaymentVerifier.verify!(valid_payment(currency: currency), order_amount: 4_000)
        end

        assert_equal :currency_mismatch, error.reason
        assert_includes error.detail, "expected=KRW"
      end

      missing = valid_payment
      missing.delete(:currency)
      error = assert_raises(PaymentVerifier::VerificationError) do
        PaymentVerifier.verify!(missing, order_amount: 4_000)
      end
      assert_equal :currency_mismatch, error.reason
    end

    test "문자열 키 해시는 관대하게 받지 않고 검증 실패로 처리한다 (심볼 키만 인정)" do
      payment = { "id" => "payment-verify-1", "status" => "PAID",
                  "amount" => { "paid" => 4_000 }, "channel" => { "type" => "TEST" },
                  "currency" => "KRW" }

      assert_amount_mismatch payment
    end

    test "live:에 nil·\"true\"·1이 오면 테스트 채널 기대로 해석한다 — 라이브로 해석하지 않는다" do
      [ nil, "true", 1, 0, "" ].each do |live|
        error = assert_raises(PaymentVerifier::VerificationError) do
          PaymentVerifier.verify!(valid_payment(type: "LIVE"), order_amount: 4_000, live: live)
        end

        assert_equal :channel_mismatch, error.reason, "live=#{live.inspect}는 TEST 기대로 본다"
        assert_includes error.detail, "expected=TEST"

        # 같은 live 값에서 TEST 결제는 통과한다 — false(테스트 채널) 해석의 증거
        payment = valid_payment(type: "TEST")
        assert_same payment, PaymentVerifier.verify!(payment, order_amount: 4_000, live: live)
      end
    end

    test "VerificationError는 reason·detail·메시지(라벨 포함)를 운반한다" do
      cases = { amount_mismatch: [ valid_payment(paid: 100), "금액 불일치" ],
                channel_mismatch: [ valid_payment(type: "LIVE"), "채널 불일치" ],
                currency_mismatch: [ valid_payment(currency: "USD"), "통화 불일치" ] }

      cases.each do |reason, (payment, label)|
        error = assert_raises(PaymentVerifier::VerificationError) do
          PaymentVerifier.verify!(payment, order_amount: 4_000)
        end

        assert_equal reason, error.reason
        assert_kind_of String, error.detail
        assert_includes error.message, label
        assert_includes error.message, "결제 확정 검증 실패"
      end
    end

    test "모든 비정상 응답은 VerificationError로 정규화된다 — TypeError·NoMethodError·KeyError가 아니다" do
      payments = [ nil, "PAID", 4_000, [ valid_payment ], valid_payment.merge(amount: "4000"),
                   valid_payment.merge(channel: "TEST"), valid_payment.merge(currency: 1),
                   { status: "PAID" }, {}, "" ]

      payments.each do |payment|
        error = assert_raises(PaymentVerifier::VerificationError) do
          PaymentVerifier.verify!(payment, order_amount: 4_000)
        end

        assert_includes PaymentVerifier::VerificationError::REASON_LABELS.keys, error.reason
      end
    end

    private

    def assert_amount_mismatch(payment)
      error = assert_raises(PaymentVerifier::VerificationError) do
        PaymentVerifier.verify!(payment, order_amount: 4_000)
      end

      assert_equal :amount_mismatch, error.reason
    end
  end
end
