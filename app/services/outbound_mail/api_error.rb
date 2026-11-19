# 자체 Outbound Mail API 오류(F-EMAIL — AUTH-8·AUTH-7.4/7.6·EXT-1 이메일 행 2026-11-20 지정) —
# HTTP 상태·OUTBOUND_MAIL_API.md §2 오류 표의 code·메시지를 운반한다. 네트워크 실패(타임아웃·
# 접속 실패)는 status nil + code TIMEOUT/CONNECTION으로 정규화하며(솔라피·포트원 래퍼와 동일
# 규약), credentials 미구성 같은 구성 오류도 코드로 fail-fast한다.
module OutboundMail
  class ApiError < StandardError
    # 잡 재시도 대상 코드 — 모호 실패(TIMEOUT·CONNECTION·MANUAL_REVIEW)와 일시 장애
    # (RATE_LIMITED·LOCAL_MTA_ERROR·MAIL_SERVICE_UNAVAILABLE). 4xx(구성·스펙 오류)와
    # IDEMPOTENCY_CONFLICT는 재시도해도 동일하게 실패하므로 제외한다. 같은 Idempotency-Key의
    # 재시도 자체는 항상 안전하다 — API가 기존 메시지를 반환한다(idempotent_replay).
    RETRYABLE_CODES = %w[ TIMEOUT CONNECTION RATE_LIMITED LOCAL_MTA_ERROR
                          MAIL_SERVICE_UNAVAILABLE MANUAL_REVIEW ].freeze

    attr_reader :status, :code

    def initialize(status:, code:, message: nil)
      @status = status
      @code = code
      super(message)
    end

    def retryable?
      RETRYABLE_CODES.include?(code)
    end
  end
end
