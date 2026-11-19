# 자체 메일 API 외부 경계 스텁 헬퍼(F-EMAIL) — PortOneStubbing·SolapiStubbing과 같은 구조.
# minitest 6에는 Object#stub이 없어(minitest-mock 별도 gem 미도입) 클래스 생성자·Rails.logger를
# 임시 교체하는 최소 대역을 둔다. 블록 종료 시 원본을 반드시 복원한다. 자체 메일 API 실호출
# 금지(AGENTS.md 테스트 전략)의 테스트 측 방어선이다.
# RAILS_ENV=test에서도 credentials의 유효 키가 로드될 수 있으므로, DeliveryJob→DeliveryMethod가
# 기본 생성하는 ClientService를 검증할 때는 반드시 with_outbound_mail_client으로 교체한다.
# (DeliveryMethod 단위는 settings[:client] 주입이 정규 경로 — 이 헬퍼는 잡 계층용.)
module OutboundMailStubbing
  # OutboundMail::ClientService 인스턴스를 클래스 생성자 경로에 주입한다 — DeliveryMethod의
  # 지연 기본 생성(@settings[:client] || ClientService.new)을 가로채 잡(DeliveryJob) 계층
  # 검증도 실호출 없이 수행하게 한다. fake는 configured?·send_email(payload) → 스냅샷을
  # 응답하는 객체면 충분하다(FakeOutboundMailClient).
  def with_outbound_mail_client(fake)
    original = OutboundMail::ClientService.method(:new)
    OutboundMail::ClientService.define_singleton_method(:new) { |*| fake }
    yield
  ensure
    OutboundMail::ClientService.define_singleton_method(:new, original)
  end

  # Rails.logger를 StringIO 기반 로거로 교체한다 — 폴백·성공·버림 로그([OUTBOUND_MAIL:*])의
  # 본문·수신자 미노출 단정(P4·W-3)에 쓴다. 블록 인자로 StringIO를 넘긴다.
  def with_outbound_mail_logger
    original = Rails.logger
    io = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(io)
    yield io
  ensure
    Rails.logger = original
  end

  # production 배달 환경 시뮬레이션 — DeliveryJob 계층 검증 전용. 잡 안의 메일은 렌더 시점에
  # wrap_delivery_behavior가 클래스 레벨 delivery_method·outbound_mail_api_settings·
  # raise_delivery_errors를 따라가므로(production.rb의 3가지 지정), 테스트 환경(:test·예외
  # 미상승)에서는 잡→배달 방식 체인이 :outbound_mail_api로 향하지 않는다. 블록 안에서만
  # production과 동일한 3가지를 세팅하고 종료 시 원복한다. 클라이언트는
  # with_outbound_mail_client(생성자 교체)로 주입한다.
  def with_outbound_mail_delivery(settings = {})
    original_method = ActionMailer::Base.delivery_method
    original_settings = ActionMailer::Base.outbound_mail_api_settings
    original_raise = ActionMailer::Base.raise_delivery_errors
    ActionMailer::Base.delivery_method = :outbound_mail_api
    ActionMailer::Base.outbound_mail_api_settings = settings
    ActionMailer::Base.raise_delivery_errors = true
    yield
  ensure
    ActionMailer::Base.delivery_method = original_method
    ActionMailer::Base.outbound_mail_api_settings = original_settings
    ActionMailer::Base.raise_delivery_errors = original_raise
  end

  # credentials를 부재 상태로 밀봉한다 — Rails.application.credentials.dig(:outbound_mail, ...)
  # 이 nil을 반환하게 해 로컬 credentials 등록 여부와 무관하게 "미구성" 분기를 검증한다.
  # DeliveryMethod#initialize·ApplicationMailer.mailer_from_header의 폴백이
  # `settings[:x] || credentials` 형태라 명시 nil 주입으로는 부재를 강제할 수 없어(nil이 ||를
  # 통과해 credentials로 떨어진다) 이 헬퍼가 유일한 밀봉 경로다. 2026-11-20 bin/ci — 운영자가
  # 로컬 credentials에 outbound_mail 블록을 등록해 "credentials 부재" 전제 단정 3건이 깨진
  # 환경 의존 결함의 밀봉 조치.
  def with_sealed_outbound_mail_credentials
    sealed = Object.new
    def sealed.dig(*_keys)
      nil
    end
    original = Rails.application.method(:credentials)
    Rails.application.define_singleton_method(:credentials) { sealed }
    yield
  ensure
    Rails.application.define_singleton_method(:credentials, original)
  end
end

# 전송 계층 대역 — Net::HTTP.start를 가로채 요청 기록·응답 주입·네트워크 예외 시뮬레이션.
# FakeSolapiTransport와 같은 구조 — ClientService·DeliveryMethod 체인 테스트가 공유한다.
class FakeOutboundMailTransport
  attr_reader :requests, :starts

  def initialize(response: nil, raise_on_request: nil)
    @response = response
    @raise_on_request = raise_on_request
    @requests = []
    @starts = []
  end

  def stub_start(host, port, **kwargs, &block)
    @starts << { host:, port:, **kwargs }
    block.call(self)
  end

  def request(net_request)
    @requests << net_request
    raise @raise_on_request if @raise_on_request

    @response.respond_to?(:call) ? @response.call : @response
  end
end
