require "test_helper"

# 시스템 테스트 공통 케이스(첫 도입 — 플랜 결정 #3). 로컬 Chrome headless —
# selenium-webdriver 4.5+는 Selenium Manager로 드라이버를 자동 관리한다.
# 뷰어(표면 ③)는 모바일 우선 화면(VIEW-1·DESIGN-6)이므로 모바일 뷰포트로 고정한다.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 430, 932 ]

  private

  # Turbo 부트 대기(2026-11-06 CI 안정화 — 경위는 _workspace/07_test_report.md §7 참조).
  # data-turbo-confirm 폼은 Turbo가 부트된 뒤에만 window.confirm을 거쳐 결정적으로 동작하므로:
  # (1) readyState complete를 보장해 execute_script로 window.confirm stub을 안전히 주입할
  #     시점을 만들고,
  # (2) window.Turbo 존재를 보장해 클릭이 네이티브 제출이 아닌 Turbo 제출 경로로 진행하게 한다
  # (부트 전 클릭이면 stub이 무의미해진다). 타임아웃 초과 시 테스트 실패로 명시한다.
  def wait_for_turbo(timeout: 5)
    deadline = Time.now + timeout
    until turbo_ready?
      if Time.now > deadline
        raise Minitest::Assertion,
          "Turbo가 #{timeout}초 내에 부트하지 못했습니다 " \
          "(window.Turbo 부재 또는 readyState != complete) — " \
          "confirm stub 주입·Turbo 제출 경로가 보장되지 않는 상태"
      end
      sleep 0.05
    end
  end

  # button_to 제출 버튼의 DOM 레벨 클릭(2026-11-06 CI 안정화 — 실측 근거는 §7 참조).
  # selenium-webdriver 4.50 + Chrome 156 조합에서 chromedriver의 합성 클릭이 세션 상태에
  # 따라 pointerdown 이하 이벤트 전체를 통째로 드롭해 폼이 아예 제출되지 않는다(실측:
  # selenium 클릭 8/8 유실·ev=[] vs DOM 클릭 8/8 성공 — submit→Turbo 제출 체인 정상).
  # DOM 클릭은 실제 클릭과 동일한 click→submit→Turbo(fetch) 체인을 타므로 흐름 검증
  # 목적에는 동등하다. 버튼 발견은 find(:button)로 Capybara 대기·부재 실패 규칙을 유지한다.
  def dom_click_button(label)
    button = find(:button, label)
    page.execute_script("arguments[0].click()", button)
  end

  def turbo_ready?
    page.evaluate_script(
      "typeof window.Turbo !== 'undefined' && document.readyState === 'complete'"
    )
  rescue Selenium::WebDriver::Error::WebDriverError
    false # 내비게이션·평가 경합 — 폴링으로 재시도
  end
end
