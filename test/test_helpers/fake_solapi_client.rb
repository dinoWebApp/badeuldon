# 솔라피 ClientService 테스트 대역 — SendService(client: 주입)·잡·스캔(with_solapi_client)이
# 공유한다. 실외부 호출이 절대 일어나지 않는다(REM-10 — 솔라피 API 실호출 금지).
# 성공 응답·예외를 주입하고, 호출 인자(템플릿 키·수신번호·변수)를 기록해 전달값을 검증한다.
class FakeSolapiClient
  attr_reader :calls

  # response — 성공 응답 Hash(또는 호출마다 평가되는 Proc). raise_on — template_key별 예외
  # (Solapi::ApiError 인스턴스 — 확정 실패 HTTP_400·모호 실패 TIMEOUT 시나리오용).
  # sms_error — send_sms(AUTH-9 SMS 단일 발송) 실패 주입용 예외(발송 실패 → rate limit
  # 미소진 검증에 사용). 신규 확장(F-SALES) — 기존 호출부에는 영향 없다(키워드 기본값).
  def initialize(response: { messageId: "msg_fake_1" }, raise_on: {}, sms_error: nil)
    @response = response
    @raise_on = raise_on
    @sms_error = sms_error
    @calls = []
    @successful_calls = []
  end

  # SMS 단일 발송(AUTH-9) — send_sms(to:, body:) 호출을 기록한다. 성공 시 알림톡과 동일
  # 성공 응답을 돌리고, sms_error 주입 시 Solapi::ApiError를 raise한다(SendService의
  # 발송 실패 경로 — 행 destroy·rate limit 미소진 검증).
  def send_sms(to:, body:)
    call = { to: to.to_s, body: body.to_s }
    @calls << call
    raise @sms_error if @sms_error

    @successful_calls << call
    @response.respond_to?(:call) ? @response.call : @response
  end

  def send_alimtalk(template_key:, to:, variables: {})
    call = { template_key: template_key.to_s, to: to.to_s, variables: variables }
    @calls << call
    raise @raise_on[template_key.to_s] if @raise_on[template_key.to_s]

    @successful_calls << call
    response = @response
    response.respond_to?(:call) ? response.call : response
  end

  # 성공(예외 미발생) 호출만 — raise_on 경로는 기록되되 성공으로 세지 않는다
  # (calls는 실패 호출도 포함하는 기존 컨벤션 유지 — no_template_skip_test 참조).
  def successful_calls
    @successful_calls
  end

  # 특정 템플릿의 호출 기록 — 스캔 경로에서 대상 스텝만 발송됐는지 검증에 쓴다.
  def calls_for(template_key)
    @calls.select { |call| call[:template_key] == template_key.to_s }
  end
end
