# 포트원 API 오류(PLAN-5 — 포트원 V2) — HTTP 상태·포트원 오류 코드·메시지와 PG사(KG이니시스)
# 원문 오류 코드를 함께 운반한다. 포트원 오류 본문은 { type, message }(PG 기인 시 pgCode·pgMessage
# 확장) 형식이며, 네트워크 실패(타임아웃·접속 실패)는 status nil + code TIMEOUT/CONNECTION으로
# 정규화한다.
module PortOne
  class ApiError < StandardError
    # 모호 실패 코드 — 승인·차감 요청이 포트원에 도달했을 수 있어(요청 도달 후 응답 유실)
    # 실패로 확정할 수 없다. 명확한 비즈니스 거부(카드 한도 초과 등)는 포트원·PG 응답 코드다.
    AMBIGUOUS_CODES = %w[ TIMEOUT CONNECTION ].freeze

    attr_reader :status, :code, :pg_code, :pg_message

    def initialize(status:, code:, message:, pg_code: nil, pg_message: nil)
      @status = status
      @code = code
      @pg_code = pg_code
      @pg_message = pg_message
      super(message)
    end

    # 이슈 #1·#4 — 모호 실패는 결제 확정(failed·expire) 대신 재확인·회복 대상으로 분류한다.
    def ambiguous?
      AMBIGUOUS_CODES.include?(code)
    end

    # 이미 승인된 결제에 대한 재승인(confirm·차감 재시도) 거부 코드. 실패가 아니라 결제
    # 완료의 확정 신호다 — failed 확정 대신 결제 조회 합류 대상(C1: 결제됐는데 패스 누락 방지).
    def already_paid?
      code.to_s.upcase.include?("ALREADY_PAID")
    end
  end
end
