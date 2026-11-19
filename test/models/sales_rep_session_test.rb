require "test_helper"

# 영업 직원 세션 모델(SALES-7 — F-SALES). 12시간 절대 + 2시간 비활동 만료(AdminSession 준용)·
# 추측 불가 토큰. 시나리오 기준: PRD SALES-7·_workspace/05_review.md §4 Tester 중점 7번.
class SalesRepSessionTest < ActiveSupport::TestCase
  setup do
    travel_to(Time.zone.parse("2026-11-19 09:00"))
    @session = SalesRepSession.issue_for!(sales_reps(:sales_kim), ip: "127.0.0.1")
  end

  teardown do
    travel_back
  end

  test "issue_for!은 12시간 절대 만료와 추측 불가 토큰으로 발급한다 (SALES-7)" do
    assert_equal 32, Base64.urlsafe_decode64(@session.token).bytesize
    assert_equal Time.zone.parse("2026-11-19 21:00"), @session.expires_at
    assert_equal "127.0.0.1", @session.ip
  end

  test "절대 만료 경계 — 12시간 직전은 유효·12시간 경과는 활동 갱신과 무관하게 만료다 (SALES-7)" do
    travel_to(@session.expires_at - 1.second) do
      @session.touch_activity! # 비활동 만료 회피(활동 유지 시나리오)
      assert_not @session.reload.expired?
    end
    travel_to(@session.expires_at + 1.second) do
      @session.touch_activity! # 활동 갱신해도 절대 만료는 넘을 수 없다
      assert @session.reload.expired?
    end
  end

  test "비활동 만료 경계 — 2시간 비활동 시 만료다 (SALES-7)" do
    travel_to(Time.zone.parse("2026-11-19 10:59")) do
      assert_not @session.expired?
    end
    travel_to(Time.zone.parse("2026-11-19 11:01")) do
      assert @session.expired?
    end
  end

  test "touch_activity!는 비활동 기준점을 리셋하고 절대 만료는 건드리지 않는다 (SALES-7)" do
    travel_to(Time.zone.parse("2026-11-19 10:00")) do
      @session.touch_activity!
    end
    assert_equal Time.zone.parse("2026-11-19 10:00"), @session.reload.last_activity_at
    assert_equal Time.zone.parse("2026-11-19 21:00"), @session.expires_at, "절대 만료 불변"
  end

  test "usable은 만료되지 않은 세션만 반환한다 (SALES-7 before_action 재검증)" do
    assert_includes SalesRepSession.usable, @session

    travel_to(Time.zone.parse("2026-11-19 11:01")) do
      assert_not_includes SalesRepSession.usable, @session, "비활동 만료분 제외"
    end
  end
end
