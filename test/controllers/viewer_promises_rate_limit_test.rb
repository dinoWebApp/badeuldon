require "test_helper"

# rate_limit 회귀(F-PROMISE — 비인증 응답 경로 스팸 방지, 토큰당 10회/10분 :create 한정).
# 05_review.md Tester 제안 기법: rate_limit 기본 store는 **클래스 로드 시점에 캡처된 인스턴스**라
# 테스트 런타임의 Rails.cache 교체는 무효다(러너 실측 — ViewerController가 캡처한 스토어는
# Rails.cache와 동일 객체). 그래서 test 환경 스토어(NullStore — #increment가 nil 반환해 제한
# 미동작)의 #increment만 MemoryStore로 위임해 **원래 rate_limit 선언을 그대로 통과**시킨다.
# 파일 수정 없음, setup에서 주입·teardown에서 복원(같은 워커의 후속 테스트 영향 없음).
class ViewerPromisesRateLimitTest < ActionDispatch::IntegrationTest
  fixtures :invoices

  def setup
    super
    @rate_store = ActiveSupport::Cache::MemoryStore.new
    store = @rate_store
    Rails.cache.define_singleton_method(:increment) { |*args, **kwargs| store.increment(*args, **kwargs) }
  end

  def teardown
    Rails.cache.singleton_class.remove_method(:increment) if Rails.cache.singleton_class.method_defined?(:increment)
    super
  end

  test "유효 토큰 11회째 응답은 429로 차단되고 기록은 10건이다" do
    invoice = invoices(:delta_issued)

    travel_to(Time.zone.parse("2026-10-14 10:00")) do
      10.times do
        post viewer_promises_path(invoice.token), params: { promise: { kind: "paid_report" } }
        assert_response :see_other
      end

      post viewer_promises_path(invoice.token), params: { promise: { kind: "paid_report" } }
      assert_response :too_many_requests
    end

    assert_equal 10, invoice.promises.count
  end

  test "한도 카운터는 토큰별로 분리된다 (by: token)" do
    exhausted_token = invoices(:delta_issued).token
    other_token = invoices(:delta_overdue).token

    travel_to(Time.zone.parse("2026-10-14 10:00")) do
      10.times do
        post viewer_promises_path(exhausted_token), params: { promise: { kind: "paid_report" } }
        assert_response :see_other
      end

      post viewer_promises_path(other_token), params: { promise: { kind: "paid_report" } }
      assert_response :see_other                       # 타 토큰은 자기 카운터 — 차단 없음
    end

    assert_equal 1, invoices(:delta_overdue).promises.count
  end

  test "무효 토큰 요청도 토큰 문자열 기준으로 카운트된다 (404 가드 선행 확인)" do
    invalid_token = "Z" * 43

    travel_to(Time.zone.parse("2026-10-14 10:00")) do
      10.times do
        post viewer_promises_path(invalid_token), params: { promise: { kind: "this_week" } }
        assert_response :not_found
      end

      post viewer_promises_path(invalid_token), params: { promise: { kind: "this_week" } }
      assert_response :too_many_requests               # rate_limit이 set_invoice보다 먼저다
    end
  end

  test "열람(GET show)은 rate_limit 대상이 아니다 (only: :create)" do
    travel_to(Time.zone.parse("2026-10-14 10:00")) do
      12.times do
        get viewer_path(invoices(:delta_issued).token)
        assert_response :success
      end
    end
  end
end
