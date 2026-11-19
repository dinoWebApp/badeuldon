# rate_limit 캐시 계수 헬퍼 — registrations_controller_test의 private 헬퍼를 공유 추출한
# 것(F-SALES Phase 7). 테스트 환경 캐시(null_store)는 증분을 기억하지 못하므로, rate_limit이
# 부팅 시 캡처한 캐시 스토어의 increment를 MemoryStore로 우회시킨다(요청 횟수 계수) —
# 가입(AUTH-9 IP 20회/1h)·/sales 로그인(10/3분) 등 컨트롤러 rate_limit 시나리오 공용.
module MemoryRateLimitHelper
  def with_memory_rate_limit_store
    memory_store = ActiveSupport::Cache::MemoryStore.new
    cache_store = ActionController::Base.cache_store
    cache_store.define_singleton_method(:increment) do |name, amount = 1, **options|
      memory_store.increment(name, amount, **options)
    end
    yield
  ensure
    cache_store.singleton_class.remove_method(:increment) if cache_store.singleton_methods(false).include?(:increment)
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include MemoryRateLimitHelper
end
