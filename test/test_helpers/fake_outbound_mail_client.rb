# Outbound Mail API 테스트 대역(F-EMAIL — AUTH-8·AUTH-7.3/7.4/7.6·EXT-1) — FakeSolapiClient와
# 같은 구조. DeliveryMethod(settings[:client] 주입)와 DeliveryJob(생성자 교체 —
# OutboundMailStubbing.with_outbound_mail_client)이 공유한다. 자체 메일 API 실호출 금지
# (AGENTS.md 테스트 전략 "외부 API는 테스트에서 stub/wrapper 주입 — 실 호출 금지")의 테스트 측
# 방어선이다. 로컬 credentials에 outbound_mail.token이 없어도 이 대역으로 동작을 결정적으로 검증한다.
class FakeOutboundMailClient
  attr_reader :calls

  # 성공 202 스냅샷(OUTBOUND_MAIL_API.md §응답 — DeliveryMethod#deliver! 반환값 3키)·비구성
  # 여부(configured? — 폴백 분기)·raise_on — send_email마다 평가되는 callable(payload, 호출
  # 횟수) → 예외(OutboundMail::ApiError) 또는 nil. 재시도 시나리오(첫 호출 TIMEOUT → 두 번째
  # 성공)를 호출 횟수 기반으로 주입한다. response도 callable이면 호출마다 다른 스냅샷을 내보낸다.
  def initialize(configured: true,
                 response: { id: "mail_fake_1", message_id: "<fake@veloloop.kr>",
                             status: "accepted_by_postfix" },
                 raise_on: nil)
    @configured = configured
    @response = response
    @raise_on = raise_on
    @calls = []
  end

  def configured?
    @configured
  end

  # DeliveryMethod가 조립한 payload(:idempotency_key 포함 — ClientService가 헤더로 승격하는
  # 원시 상태)를 기록하고 성공 스냅샷 또는 주입된 예외를 돌려준다.
  def send_email(payload)
    @calls << payload
    error = @raise_on.respond_to?(:call) ? @raise_on.call(payload, @calls.size) : @raise_on
    raise error if error

    @response.respond_to?(:call) ? @response.call(payload, @calls.size) : @response
  end

  # 기록된 호출의 멱등 키들 — C-1 회귀(이벤트별 유일·재시도 동일) 단정에 쓴다.
  def idempotency_keys
    @calls.map { |payload| payload[:idempotency_key] }
  end
end
