# 바로빌 외부 경계 스텁 헬퍼 — 컨트롤러·Job이 기본 인자로 BaroBill::ClientService.new를
# 만드는 경로를 가로챈다(PortOneStubbing과 동일 패턴). 블록 종료 시 원본을 복원한다.
# 바로빌 SOAP 실호출 금지(TAX-1) 규약의 테스트 측 방어선이다.
module BaroBillStubbing
  def with_baro_bill_client(fake)
    original = BaroBill::ClientService.method(:new)
    BaroBill::ClientService.define_singleton_method(:new) { |*| fake }
    yield
  ensure
    BaroBill::ClientService.define_singleton_method(:new, original)
  end
end
