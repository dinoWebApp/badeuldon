# 솔라피 ClientService 테스트 대역 — SendService(client: 주입)·잡·스캔(with_solapi_client)이
# 공유한다. 실외부 호출이 절대 일어나지 않는다(REM-10 — 솔라피 API 실호출 금지).
# 성공 응답·예외를 주입하고, 호출 인자(템플릿 키·수신번호·변수)를 기록해 전달값을 검증한다.
class FakeSolapiClient
  attr_reader :calls

  # response — 성공 응답 Hash(또는 호출마다 평가되는 Proc). raise_on — template_key별 예외
  # (Solapi::ApiError 인스턴스 — 확정 실패 HTTP_400·모호 실패 TIMEOUT 시나리오용).
  def initialize(response: { messageId: "msg_fake_1" }, raise_on: {})
    @response = response
    @raise_on = raise_on
    @calls = []
  end

  def send_alimtalk(template_key:, to:, variables: {})
    @calls << { template_key: template_key.to_s, to: to.to_s, variables: variables }
    raise @raise_on[template_key.to_s] if @raise_on[template_key.to_s]

    response = @response
    response.respond_to?(:call) ? response.call : response
  end

  # 특정 템플릿의 호출 기록 — 스캔 경로에서 대상 스텝만 발송됐는지 검증에 쓴다.
  def calls_for(template_key)
    @calls.select { |call| call[:template_key] == template_key.to_s }
  end
end
