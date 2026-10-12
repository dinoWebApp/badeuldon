require "test_helper"

# 시스템 테스트 공통 케이스(첫 도입 — 플랜 결정 #3). 로컬 Chrome headless —
# selenium-webdriver 4.5+는 Selenium Manager로 드라이버를 자동 관리한다.
# 뷰어(표면 ③)는 모바일 우선 화면(VIEW-1·DESIGN-6)이므로 모바일 뷰포트로 고정한다.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 430, 932 ]
end
