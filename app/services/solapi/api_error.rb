# 솔라피 API 오류(REM-10) — HTTP 상태·솔라피 오류 코드·메시지를 운반한다. 네트워크 실패
# (타임아웃·접속 실패)는 status nil + code TIMEOUT/CONNECTION으로 정규화하며(포트원 래퍼와
# 동일 규약), credentials 누락·미승인 템플릿 같은 구성 오류도 코드로 fail-fast한다.
module Solapi
  class ApiError < StandardError
    # 모호 실패 코드 — 요청이 솔라피에 도달했을 수 있어(발송 후 응답 유실) 실패로 확정할 수
    # 없다. 잡 계층의 재시도(DeliverJob retry_on)는 이 코드들로 한정한다(§11.2 — 제한된 retry).
    RETRYABLE_CODES = %w[ TIMEOUT CONNECTION ].freeze

    attr_reader :status, :code

    def initialize(status:, code:, message: nil)
      @status = status
      @code = code
      super(message)
    end

    # 모호 실패 여부 — 확정 실패(4xx·설정 누락)는 기록 후 종료하고 재시도하지 않는다.
    def retryable?
      RETRYABLE_CODES.include?(code)
    end
  end
end
