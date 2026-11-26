require "test_helper"

# JS 모듈 import 경로 가드(2026-11-27 — 운영 결함 계기). 포트원 컨트롤러 2개가 공통 헬퍼를
# "./portone_shared" 상대 경로로 불러오면서(6bd374c 공통화) 운영에서 모듈이 404가 나고
# 결제하기·카드 등록 버튼이 무반응이었다. 상대 경로는 importmap으로 해석되지 않고 그대로
# URL이 되는데, Propshaft는 JS 안의 import문을 다이제스트 경로로 바꿔 주지 않는다. 화면의
# data-controller 속성만 보는 기존 테스트는 모듈 그래프가 깨져도 통과하므로 소스와 실제
# 렌더되는 importmap을 직접 대조한다(브라우저 로드 확인은 javascript_controllers_load_test).
class JavascriptImportmapTest < ActionDispatch::IntegrationTest
  JS_ROOT = Rails.root.join("app/javascript")
  RELATIVE_IMPORT = /\b(?:from|import)\s*\(?\s*["']\.{1,2}\//

  test "JS 모듈은 상대 경로로 import하지 않는다 — 다이제스트 경로에서 404가 된다" do
    offenders = javascript_sources.filter_map do |path|
      path.relative_path_from(Rails.root).to_s if path.read.match?(RELATIVE_IMPORT)
    end

    assert_empty offenders, "상대 경로 import 대신 importmap 이름(controllers/…)을 쓴다: #{offenders.join(", ")}"
  end

  test "controllers/… 로 import하는 이름은 화면에 렌더되는 importmap에 다이제스트 핀으로 있다" do
    names = javascript_sources.flat_map { |path| path.read.scan(/\bfrom\s+["'](controllers\/[^"']+)["']/).flatten }.uniq
    assert_includes names, "controllers/portone_shared", "포트원 공통 헬퍼는 importmap 이름으로 불러온다"

    imports = rendered_imports

    names.each do |name|
      assert File.exist?(JS_ROOT.join("#{name}.js")), "소스 파일이 없다: #{name}"
      assert_match(%r{\A/assets/#{Regexp.escape(name)}-[0-9a-f]{8}\.js\z}, imports[name].to_s,
                   "importmap 핀이 다이제스트 에셋 경로가 아니다: #{name} -> #{imports[name].inspect}")
    end
  end

  private

    def javascript_sources
      Dir[JS_ROOT.join("**/*.js")].sort.map { |path| Pathname(path) }
    end

    # 브라우저가 실제로 받는 importmap — 공개 화면에 다이제스트 경로로 렌더된다.
    def rendered_imports
      get "/session/new"
      assert_response :success

      json = response.body[/<script type="importmap"[^>]*>(.*?)<\/script>/m, 1]
      assert json, "화면에 importmap 스크립트가 없다"

      JSON.parse(json).fetch("imports")
    end
end
