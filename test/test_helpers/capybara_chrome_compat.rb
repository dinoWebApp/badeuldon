# Chrome 158 호환 — Capybara 세션 초기화(reset!)의 와일드카드 저장소 삭제 대체(2026-11-24 실측).
#
# Capybara 3.40.0(현재 최신)은 매 reset! 마다 CDP Storage.clearDataForOrigin 을 origin '*' 로
# 호출해 쿠키를 지운다. Chrome 158 부터 이 와일드카드를 받지 않아
# Selenium::WebDriver::Error::InvalidArgumentError("* is not a valid URL")로 깨진다 — 로컬
# 시스템 테스트 13건 중 10건이 테스트 본문은 통과한 뒤 정리 단계에서 에러였다(Ruby 4.0.7에서도
# 동일 — Ruby 버전과 무관). 테스트 지원 코드로만 우회하며 운영 코드는 건드리지 않는다.
#
# 대체 규칙 — 의도(모든 origin 의 쿠키 삭제)를 같은 역할의 CDP 명령으로 유지한다.
#   - 저장소 종류가 쿠키뿐이면 Network.clearBrowserCookies(브라우저의 전체 쿠키 삭제)
#   - 그 외(local_storage 등)면 테스트 서버 origin 에 대해 원래 명령을 그대로 호출
# Capybara 가 와일드카드 없이 동작하는 버전을 내놓으면 이 파일을 걷는다 — 걷은 뒤 Chrome 158
# 에서 bin/rails test:system 이 그대로 통과해야 한다.
require "capybara/selenium/driver"

module CapybaraChromeCompat
  STORAGE_CLEAR = "Storage.clearDataForOrigin"
  WILDCARD_ORIGIN = "*"
  COOKIES_ONLY = "cookies"

  # Capybara::Selenium::Driver::ChromeDriver#execute_cdp(cmd, params = {}) 과 같은 시그니처.
  def execute_cdp(cmd, params = {})
    if cmd == STORAGE_CLEAR && params[:origin] == WILDCARD_ORIGIN
      return super("Network.clearBrowserCookies") if params[:storageTypes] == COOKIES_ONLY

      params = params.merge(origin: server_origin)
    end
    super(cmd, params)
  end

  private

  def server_origin
    Capybara.current_session.server&.base_url || "http://127.0.0.1"
  end
end

Capybara::Selenium::Driver::ChromeDriver.prepend(CapybaraChromeCompat)
