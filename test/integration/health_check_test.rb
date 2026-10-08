require "test_helper"

# /up 헬스체크 회귀 방지 — root 라우트 추가가 기존 경로에 영향 없음을 검증
class HealthCheckTest < ActionDispatch::IntegrationTest
  test "GET /up는 200을 반환한다 (회귀 방지)" do
    get rails_health_check_url
    assert_response :success
  end
end
