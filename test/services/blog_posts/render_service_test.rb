require "test_helper"

# BLOG-5(Q18) — 렌더 파이프라인: kramdown → sanitize allowlist → h2/h3 앵커·목차.
# XSS 차단(스크립트·이벤트 핸들러·위험 href)이 핵심 검증 대상.
class BlogPosts::RenderServiceTest < ActiveSupport::TestCase
  test "마크다운을 HTML로 렌더하고 h2/h3에 앵커를 부여해 목차를 반환한다" do
    result = BlogPosts::RenderService.call("## 서론\n내용\n\n### 세부\n내용2")
    assert_includes result.html, %(<h2 id="toc-서론-1">서론</h2>)
    assert_includes result.html, %(<h3 id="toc-세부-1">세부</h3>)
    assert_equal [ [ "서론", "toc-서론-1", 2 ], [ "세부", "toc-세부-1", 3 ] ], result.toc
  end

  test "동일 텍스트 헤딩은 앵커가 중복되지 않는다" do
    result = BlogPosts::RenderService.call("## 요약\na\n\n## 요약\nb")
    anchors = result.toc.map { |_, anchor, _| anchor }
    assert_equal anchors.uniq.size, anchors.size
  end

  test "script 태그·이벤트 핸들러·style 속성은 제거된다(XSS 차단)" do
    result = BlogPosts::RenderService.call(
      "<script>alert(1)</script>\n\n<p onclick=\"evil()\" style=\"x\">문단</p>"
    )
    assert result.html.exclude?("script")
    assert result.html.exclude?("onclick")
    assert result.html.exclude?("style")
    assert_includes result.html, "문단"
  end

  test "javascript: URL·위험 img src는 제거되고 https 링크·이미지는 유지된다" do
    result = BlogPosts::RenderService.call(
      "[링크](javascript:alert(1))\n\n![x](javascript:alert(2))\n\n[정상](https://example.com)\n\n![이미지](https://example.com/i.png)"
    )
    assert result.html.exclude?("javascript:")
    assert_includes result.html, %(href="https://example.com")
    assert_includes result.html, %(src="https://example.com/i.png")
    assert_includes result.html, %(alt="이미지")
  end

  test "테이블·blockquote 등 allowlist 태그는 유지된다" do
    result = BlogPosts::RenderService.call("| a | b |\n|---|---|\n| 1 | 2 |\n\n> 인용")
    assert_includes result.html, "<table>"
    assert_includes result.html, "<blockquote>"
  end

  test "parse_toc — 기존 body_html에서 목차만 재추출한다" do
    html = %(<h2 id="toc-서론-1">서론</h2><p>본문</p><h3 id="toc-세부-1">세부</h3>)
    assert_equal [ [ "서론", "toc-서론-1", 2 ], [ "세부", "toc-세부-1", 3 ] ],
                 BlogPosts::RenderService.parse_toc(html)
    assert_empty BlogPosts::RenderService.parse_toc("<p>헤딩 없음</p>")
  end
end
