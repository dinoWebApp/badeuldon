require "test_helper"

# 시스템 테스트 공통 케이스(첫 도입 — 플랜 결정 #3). 로컬 Chrome headless —
# selenium-webdriver 4.5+는 Selenium Manager로 드라이버를 자동 관리한다.
# 뷰어(표면 ③)는 모바일 우선 화면(VIEW-1·DESIGN-6)이므로 모바일 뷰포트로 고정한다.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 430, 932 ]

  private

  # Turbo 부트 대기 — data-turbo-confirm 확인 대화상자는 Turbo JS가 로드·연결된 뒤에만 뜬다.
  # CI(ubuntu·느린 부트)에서는 visit 직후 서버 렌더 HTML에 버튼이 이미 있어도(assert_text 통과)
  # Turbo 부트 전에 클릭하면 폼이 네이티브 제출로 진행되어 confirm이 아예 발생하지 않고
  # accept_confirm이 ModalNotFound로 실패한다(2026-11-06 GitHub Actions 실측 — 로컬 재현 없음).
  # accept_confirm 앞에서 호출해 부트 레이스를 제어한다. 타임아웃 초과 시 테스트 실패 처리.
  def wait_for_turbo(timeout: 5)
    deadline = Time.now + timeout
    until turbo_ready?
      if Time.now > deadline
        raise Minitest::Assertion,
          "Turbo가 #{timeout}초 내에 부트하지 못했습니다 " \
          "(window.Turbo 부재 또는 readyState != complete) — " \
          "data-turbo-confirm 대화상자가 발생하지 않아 accept_confirm이 실패할 상태"
      end
      sleep 0.05
    end
  end

  def turbo_ready?
    page.evaluate_script(
      "typeof window.Turbo !== 'undefined' && document.readyState === 'complete'"
    )
  rescue Selenium::WebDriver::Error::WebDriverError
    false # 내비게이션·평가 경합 — 폴링으로 재시도
  end
end
