# 토스페이먼츠 API 오류(F-PLAN — PLAN-5) — HTTP 상태·토스 오류 코드·메시지를 함께 운반한다.
# 네트워크 실패(타임아웃·접속 실패)는 status nil + code TIMEOUT/CONNECTION으로 정규화한다.
module TossPayments
  class ApiError < StandardError
    # 모호 실패 코드 — 승인·차감 요청이 토스에 도달했을 수 있어(요청 도달 후 응답 유실)
    # 실패로 확정할 수 없다. 명확한 비즈니스 거부(카드 한도 초과 등)는 토스 응답 코드다.
    AMBIGUOUS_CODES = %w[ TIMEOUT CONNECTION ].freeze

    attr_reader :status, :code

    def initialize(status:, code:, message:)
      @status = status
      @code = code
      super(message)
    end

    # 이슈 #1·#4 — 모호 실패는 결제 확정(failed·expire) 대신 재확인·회복 대상으로 분류한다.
    def ambiguous?
      AMBIGUOUS_CODES.include?(code)
    end
  end
end
