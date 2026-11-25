require "test_helper"
require_relative "test_helpers/capybara_chrome_compat"

# 시스템 테스트 공통 케이스(첫 도입 — 플랜 결정 #3). 로컬 Chrome headless —
# selenium-webdriver 4.5+는 Selenium Manager로 드라이버를 자동 관리한다.
# 뷰어(표면 ③)는 모바일 우선 화면(VIEW-1·DESIGN-6)이므로 모바일 뷰포트로 고정한다.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 430, 932 ]

  # fill_in 을 값 검증형으로 덮어쓴다(2026-11-25 실측). chromedriver 의 텍스트 입력은 CPU 부하·저사양
  # 환경에서 한 구간이 조용히 사라질 수 있다 — 로컬 CPU 부하 8회 중 2회: 본문 87자 중 84자만 들어가고
  # 뒤이은 필드 2개는 포커스만 받은 채 input 이벤트 0건·값 0자였다. fill_in 은 오류 없이 반환하므로
  # 필수값이 빠진 폼이 그대로 제출돼 검증에 걸리고, 테스트는 전혀 다른 오류(블로그 발행 테스트의
  # "undefined method 'title' for nil")로 보였다 — 원격 CI 플레이크의 근본 원인. 입력 뒤 값을 되읽어
  # 기댓값과 다르면 JS 로 값을 넣고 input·change 이벤트를 발생시킨다(프런트엔드 프레임워크 없는 일반
  # 폼 — 입력값을 JS 가 바꿔 쓰는 필드에는 쓰지 않는다. 현재 시스템 테스트의 fill_in 은 아이디·비밀번호·
  # 인증코드·제목·본문·사유뿐이다). 정상 환경에서는 한 번에 맞아 아무 일도 일어나지 않는다.
  def fill_in(locator = nil, with: nil, **options)
    super
    return if with.nil?

    expected = with.to_s
    field = find_field(locator, **options)
    return if field.value == expected

    page.execute_script(<<~JS, field, expected)
      const [field, value] = arguments;
      field.value = value;
      field.dispatchEvent(new Event("input", { bubbles: true }));
      field.dispatchEvent(new Event("change", { bubbles: true }));
    JS
    assert_equal expected, field.value, "#{locator} 입력값이 재입력 뒤에도 일치하지 않습니다"
  end

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
