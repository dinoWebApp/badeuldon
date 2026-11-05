# 솔라피 외부 경계 스텁 헬퍼 — PortOneStubbing과 같은 구조(F-REM W-7). minitest 6에는
# Object#stub이 없어(minitest-mock 별도 gem 미도입) 클래스 생성자를 임시 교체하는 최소 대역을
# 둔다. 블록 종료 시 원본을 반드시 복원한다. 솔라피 API 실호출 금지(REM-10·AGENTS.md 테스트
# 전략 "외부 API는 테스트에서 stub/wrapper 주입 — 실 호출 금지")의 테스트 측 방어선이다.
# RAILS_ENV=test에서도 credentials의 유효 키가 로드되므로 잡(DeliverJob.perform_now)·스캔
# (DispatchService.call·PrenoticeService.call)·U1 통보(NotifyUserService) 경로를 검증할 때는
# 반드시 이 헬퍼(또는 서비스 생성자 client: 직접 주입)로 래퍼를 교체한다.
module SolapiStubbing
  # 솔라피 ClientService 인스턴스를 클래스 생성자 경로에 주입한다 — 서비스의 지연 기본 생성
  # (SendService#client 등)과 잡이 감싸는 서비스 생성 경로를 가로채 잡 계층 검증도 실API
  # 호출 없이 수행하게 한다. fake는 send_alimtalk(template_key:, to:, variables:) → Hash를
  # 응답하는 객체면 충분하다.
  def with_solapi_client(fake)
    original = Solapi::ClientService.method(:new)
    Solapi::ClientService.define_singleton_method(:new) { |*| fake }
    yield
  ensure
    Solapi::ClientService.define_singleton_method(:new, original)
  end
end
