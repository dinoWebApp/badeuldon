require "test_helper"

# BLOG-1~4 — 공개 /blog 표면(컨트롤러 경유 HTTP 수준 검증 — Run A/B 교훈).
# ① 목록(published만·카테고리 필터·페이지네이션) ② 상세(본문·목차·JSON-LD·메타·관련 글)
# ③ 구 슬러그 301 ④ 미발행·미존재 404 ⑤ 색인 허용(noindex 미출력 — SURF-3 예외).
class BlogControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = admins(:ops)
    @published = publish(BlogPost.create!(
      admin: @admin, title: "공개 글", slug: "public-post",
      body_md: "## 서론\n본문\n\n### 세부\n내용",
      meta_title: "공개 글 메타", meta_description: "공개 글 설명"
    ))
    @draft = BlogPost.create!(
      admin: @admin, title: "초안 글", slug: "draft-post", body_md: "내용"
    )
  end

  test "index는 published만 노출하고 초안은 숨긴다 (BLOG-3)" do
    get blog_path
    assert_response :success
    assert_match "공개 글", response.body
    assert_no_match "초안 글", response.body
  end

  test "index 카테고리 필터가 동작한다 (BLOG-3·Q19)" do
    publish(BlogPost.create!(
      admin: @admin, title: "세금 글", slug: "tax-post", body_md: "내용",
      category: :tax
    ))

    get blog_path(params: { category: "tax" })
    assert_response :success
    assert_match "세금 글", response.body
    assert_no_match "공개 글", response.body

    get blog_path(params: { category: "invalid" }) # 무효값은 필터 미적용(200 유지)
    assert_response :success
    assert_match "공개 글", response.body
  end

  test "index 페이지네이션 — 페이지당 12건·다음 페이지 링크 (BLOG-3)" do
    13.times do |i|
      publish(BlogPost.create!(
        admin: @admin, title: "글#{i}", slug: "bulk-#{i}", body_md: "내용",
        published_at: (i + 2).days.ago
      ))
    end

    get blog_path
    assert_response :success
    assert_match "다음 페이지", response.body

    get blog_path(params: { page: 2 })
    assert_response :success
    assert_match "글12", response.body # 가장 오래된 글 2건은 2페이지
    assert_match "글11", response.body
    assert_no_match "공개 글", response.body
    assert_no_match "글0", response.body # 최신 bulk는 1페이지
  end

  test "index는 LP-11 허브 레이어를 렌더한다 — 카테고리 카드 5·도구 카드 3·가입 CTA" do
    get blog_path
    assert_response :success
    assert_match "프리랜서 수금 콘텐츠", response.body
    assert_select "div.grid > a", 5 # 5클러스터 카드(필터 pill은 nav 요소 — 제외)
    BlogHelper::CATEGORY_KEYS.each do |key|
      assert_match blog_category_path(key), response.body # C-2 — path형 카테고리
    end
    %w[/tools/reminder-generator /tools/tax-calculator /tools/invoice-template].each do |path|
      assert_includes response.body, %(href="#{path}") # 3-S 결선 전 임시 하드코딩 경로
    end
    assert_match "무료로 시작하기", response.body
  end

  test "show는 본문·목차·JSON-LD·메타·관련 글을 렌더한다 (BLOG-2·4)" do
    publish(BlogPost.create!(
      admin: @admin, title: "관련 글", slug: "related-post", body_md: "내용", category: :scripts
    ))

    get blog_post_path(slug: "public-post")
    assert_response :success
    assert_includes response.body, %(<h2 id="toc-)
    assert_includes response.body, "#toc-서론-1" # 목차 앵커 링크
    assert_includes response.body, "application/ld+json"
    assert_includes response.body, "Article"
    assert_match %r{<meta name="description" content="공개 글 설명"/?>}, response.body
    assert_match %r{property="og:title"}, response.body
    assert_match %r{href="/tools"}, response.body          # CTA(3-Q 결선 대상 경로)
    assert_includes response.body, "관련 글"
    assert_no_match "초안 글", response.body
  end

  test "show는 noindex를 출력하지 않는다(색인 허용 — SURF-3 예외·BLOG-2)" do
    get blog_post_path(slug: "public-post")
    assert_response :success
    assert_no_match %r{name="robots"}, response.body
  end

  test "구 슬러그는 301로 신규 경로에 영구 리다이렉트된다 (BLOG-1)" do
    @published.update!(slug: "renamed-post")

    get blog_post_path(slug: "public-post")
    assert_response :moved_permanently
    assert_redirected_to blog_post_path(slug: "renamed-post")
  end

  test "미발행·미존재·리다이렉트 대상 비공개는 404 (BLOG-1·3)" do
    get blog_post_path(slug: "draft-post")
    assert_response :not_found

    get blog_post_path(slug: "no-such-post")
    assert_response :not_found

    @published.update!(slug: "renamed2-post", status: BlogPost.statuses[:hidden])
    get blog_post_path(slug: "public-post") # 리다이렉트 대상이 비공개면 404
    assert_response :not_found
  end

  test "sitemap.xml은 published 게시글과 카테고리를 반영한다 (BLOG-2)" do
    get sitemap_path
    assert_response :success
    assert_match "urlset", response.body
    assert_match blog_post_url(slug: "public-post"), response.body
    assert_match "lastmod", response.body
  end

  private

  def publish(post)
    post.thumbnail.attach(io: StringIO.new("x"), filename: "t.png", content_type: "image/png")
    post.og_image.attach(io: StringIO.new("x"), filename: "o.png", content_type: "image/png")
    post.meta_title = post.meta_title.presence || post.title
    post.meta_description = post.meta_description.presence || post.display_summary
    post.publish!
    assert post.reload.published?, "setup 발행 실패: #{post.errors.full_messages}"
    post
  end

  test "카테고리 경로형 /blog/category/:category로 필터된다 (C-2·BLOG-1)" do
    publish(BlogPost.create!(
      admin: @admin, title: "문서 글", slug: "docs-post", body_md: "내용", category: :docs
    ))

    get blog_category_path("docs")
    assert_response :success
    assert_match "문서 글", response.body
    assert_no_match "공개 글", response.body

    get blog_category_path("not-a-key")
    assert_response :success # 무효 키는 필터 없음(전체 목록) — 404 아님
    assert_match "공개 글", response.body
  end
end
