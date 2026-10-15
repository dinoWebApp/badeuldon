# 포트원 외부 경계 스텁 헬퍼 — minitest 6에는 Object#stub이 없어(minitest-mock 별도 gem
# 미도입) 클래스 메서드를 임시 교체하는 최소 대역을 둔다. 블록 종료 시 원본을 반드시 복원한다.
# 포트원 API 실호출 금지(PLAN-5) 규약의 테스트 측 방어선이다.
module PortOneStubbing
  # 포트원 ClientService 인스턴스를 클래스 생성자 경로에 주입한다 — 컨트롤러가 기본 인자로
  # 만드는 클라이언트(UpgradeService·PurchaseService·웹훅 재조회)를 가로챈다.
  def with_portone_client(fake)
    original = PortOne::ClientService.method(:new)
    PortOne::ClientService.define_singleton_method(:new) { |*| fake }
    yield
  ensure
    PortOne::ClientService.define_singleton_method(:new, original)
  end

  # 전송 계층(Net::HTTP.start)을 대역으로 교체한다 — 요청 인자 기록·응답 주입·네트워크 예외
  # 시뮬레이션(ClientServiceTest 전용).
  def with_http_transport(transport)
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) do |*args, **kwargs, &block|
      transport.stub_start(*args, **kwargs, &block)
    end
    yield
  ensure
    Net::HTTP.define_singleton_method(:start, original)
  end
end
