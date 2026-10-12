require "test_helper"

# SURF-3 색인 규칙 회귀 — 인증·뷰어·관리자 표면 noindex, 랜딩은 색인 허용
# 시나리오 기준: _workspace/05_review.md §5 Tester 중점 6번
class Surf3IndexingTest < ActionDispatch::IntegrationTest
  test "프로필 화면(/app)은 noindex 메타를 출력한다 (SURF-3)" do
    sign_in_as users(:alpha)
    get edit_app_profile_path
    assert_response :success
    assert_select "meta[name=robots]" do |metas|
      assert_equal 1, metas.size
      assert_match(/noindex/, metas.first["content"])
    end
  end

  test "welcome 화면도 noindex 메타를 출력한다 (SURF-3)" do
    sign_in_as users(:alpha)
    get welcome_path
    assert_response :success
    assert_select "meta[name=robots]" do |metas|
      assert_equal 1, metas.size
      assert_match(/noindex/, metas.first["content"])
    end
  end

  test "랜딩은 noindex 메타 없이 색인을 허용한다 (SURF-3 역방향)" do
    get root_url
    assert_select "meta[name=robots]", count: 0
  end

  test "robots.txt는 대시보드·뷰어·관리자·welcome 경로를 차단한다 (SURF-3)" do
    robots = File.read(Rails.root.join("public/robots.txt"))
    assert_includes robots, "Disallow: /app"
    assert_includes robots, "Disallow: /b/"
    assert_includes robots, "Disallow: /admin"
    assert_includes robots, "Disallow: /welcome"
  end
end
