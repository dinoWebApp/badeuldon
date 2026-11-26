require "application_system_test_case"

# JS 컨트롤러 모듈이 브라우저에서 실제로 로드되는지 확인한다(2026-11-27 — 운영 결함 계기).
# 포트원 컨트롤러 2개가 "./portone_shared" 상대 경로 import 때문에 운영에서 로드되지 않아
# 결제하기·카드 등록 버튼이 무반응이었다(6bd374c 공통화 뒤 — 실결제 0건이라 드러나지 않았다).
# 컨트롤러·시스템 테스트는 data-controller 속성만 보므로 모듈 그래프가 깨져도 통과한다.
# 컨트롤러는 모든 화면에서 일괄 로드(eagerLoadControllersFrom — importmap의 *_controller 전부)
# 되므로, 대시보드 화면에서 같은 집합을 전부 import해 본다. 결제 버튼은 누르지 않는다 — 모듈을
# import만 하고 포트원 SDK는 호출하지 않는다. 소스·importmap 정적 대조는
# test/integration/javascript_importmap_test.rb가 담당한다.
class JavascriptControllersLoadTest < ApplicationSystemTestCase
  test "importmap의 모든 컨트롤러 모듈이 브라우저에서 로드된다 (포트원 결제·빌링 포함)" do
    log_in_as users(:delta)
    visit app_root_path

    # 여러 줄 스크립트는 execute_script로 보낸다 — evaluate_script는 "return <script>"로 감싸
    # 첫 줄에서 끝나므로(2026-11-27 실측) 아래 import가 아예 시작되지 않는다.
    page.execute_script <<~JS
      window.__controllerModuleCheck = "pending"
      const names = Object.keys(JSON.parse(document.querySelector('script[type="importmap"]').textContent).imports)
        .filter((name) => /^controllers\\/.*_controller$/.test(name))
      Promise.all(names.map((name) => import(name).then(
        () => null,
        (error) => name + " (" + error.message + ")"
      ))).then((failures) => {
        const failed = failures.filter(Boolean)
        window.__controllerModuleCheck = failed.length === 0
          ? "loaded " + names.length
          : "failed: " + failed.join(" | ")
      })
    JS

    result = await_js_result("window.__controllerModuleCheck")
    controller_files = Dir[Rails.root.join("app/javascript/controllers/**/*_controller.js")].count

    assert_equal "loaded #{controller_files}", result
  end

  private

    # 결과를 window에 남기고 폴링한다.
    def await_js_result(expression, timeout: 10)
      deadline = Time.now + timeout
      loop do
        result = page.evaluate_script(expression)
        return result unless result == "pending"
        raise Minitest::Assertion, "JS 결과가 #{timeout}초 내에 확정되지 않았다: #{expression}" if Time.now > deadline

        sleep 0.05
      end
    end
end
