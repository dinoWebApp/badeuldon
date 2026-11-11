require "test_helper"

# BLOG-1~5 — BlogPost 모델(상태 전이·슬러그·리다이렉트 기록·렌더 저장·발행 필수 검증·공개 scope).
# 컨트롤러 경유 검증은 blog_controller_test / admin blog_posts 컨트롤러 테스트가 담당한다.
class BlogPostTest < ActiveSupport::TestCase
  setup do
    @admin = admins(:ops)
    @valid_attrs = {
      admin: @admin, title: "연청구서 대응 가이드", slug: "overdue-invoice-guide",
      body_md: "## 첫 절\n본문입니다.\n\n### 하위 절\n더"
    }
  end

  test "생성 시 body_html이 렌더·sanitize되어 저장된다 (BLOG-5·Q18)" do
    post = BlogPost.create!(@valid_attrs)
    assert_includes post.body_html, %(<h2 id="toc-)
    assert_includes post.body_html, "<p>본문입니다.</p>"
    assert post.body_html.exclude?("<script>")
  end

  test "slug는 형식 검증(소문자 영숫자+하이픈)·고유 (BLOG-1)" do
    assert BlogPost.create!(@valid_attrs)
    dup = BlogPost.new(@valid_attrs.merge(title: "다른 글"))
    assert_not dup.valid?
    assert dup.errors.key?(:slug)

    bad = BlogPost.new(@valid_attrs.merge(slug: "Bad_Slug!"))
    assert_not bad.valid?
    assert bad.errors.key?(:slug)
  end

  test "generate_slug! — 제목 파라미터화·한글 제목은 post-{epoch} 폴백·중복 접미 (BLOG-5)" do
    post = BlogPost.new(@valid_attrs.merge(slug: nil, title: "Overdue Invoice Guide"))
    post.generate_slug!
    assert_equal "overdue-invoice-guide", post.slug

    korean = BlogPost.new(@valid_attrs.merge(slug: nil, title: "독촉 방법"))
    korean.generate_slug!
    assert_match(/\Apost-\d+\z/, korean.slug)

    dup = BlogPost.new(@valid_attrs.merge(slug: nil, title: "Overdue Invoice Guide"))
    dup.slug = nil
    BlogPost.create!(@valid_attrs) # base 점유
    dup.generate_slug!
    assert_equal "overdue-invoice-guide-2", dup.slug
  end

  test "slug 변경 시 이전 slug가 리다이렉트 테이블에 기록된다 (BLOG-1)" do
    post = BlogPost.create!(@valid_attrs)
    post.update!(slug: "new-guide-slug")
    assert_equal [ "overdue-invoice-guide" ], post.slug_redirects.pluck(:old_slug)

    # 재변경·복귀 — old_slug 고유 제약으로 find_or_create(멱등)
    post.update!(slug: "overdue-invoice-guide")
    assert_equal 2, post.slug_redirects.count
  end

  test "publish! — 필수 필드(썸네일·OG·메타 2종) 미충족 시 거부 (BLOG-5)" do
    post = BlogPost.create!(@valid_attrs)
    assert_not post.publish!
    assert_equal "draft", post.status
    assert post.errors.key?(:thumbnail)
    assert post.errors.key?(:og_image)
    assert post.errors.key?(:meta_title)
    assert post.errors.key?(:meta_description)
    assert_nil post.published_at
  end

  test "publish! — 충족 시 published·published_at 기록, 재호출 멱등 (BLOG-5)" do
    post = BlogPost.create!(@valid_attrs.merge(meta_title: "메타 제목", meta_description: "메타 설명"))
    post.thumbnail.attach(io: StringIO.new("x"), filename: "t.png", content_type: "image/png")
    post.og_image.attach(io: StringIO.new("x"), filename: "o.png", content_type: "image/png")

    assert post.publish!
    assert_equal "published", post.status
    assert post.published_at.present?

    assert post.publish! # 멱등
    assert post.published_at
  end

  test "schedule! — publish_at 필수, 상태 scheduled (BLOG-5·Q20)" do
    post = BlogPost.create!(@valid_attrs)
    assert_not post.schedule!(nil)
    assert post.errors.added?(:publish_at, :blank)
    assert_equal "draft", post.status

    assert post.schedule!(1.day.from_now)
    assert_equal "scheduled", post.status
  end

  test "unpublish! — hidden 전환 후 공개 scope 제외 (BLOG-5)" do
    post = BlogPost.create!(@valid_attrs.merge(meta_title: "메타 제목", meta_description: "메타 설명"))
    post.thumbnail.attach(io: StringIO.new("x"), filename: "t.png", content_type: "image/png")
    post.og_image.attach(io: StringIO.new("x"), filename: "o.png", content_type: "image/png")
    post.publish!
    assert_includes BlogPost.published_now.ids, post.id

    assert post.unpublish!
    assert_equal "hidden", post.status
    assert_not_includes BlogPost.published_now.ids, post.id
  end

  test "published_now — draft·scheduled·예약 시각 미경과 제외, 경과 시 포함 (BLOG-3·Q20)" do
    draft = BlogPost.create!(@valid_attrs.merge(slug: "d-1"))
    sched = BlogPost.create!(@valid_attrs.merge(slug: "d-2", status: :scheduled, publish_at: 1.day.from_now))
    past_sched = BlogPost.create!(@valid_attrs.merge(slug: "d-3", status: :scheduled, publish_at: 1.hour.ago))
    manual = BlogPost.create!(@valid_attrs.merge(slug: "d-4", status: :published, published_at: Time.current))

    result = BlogPost.published_now.ids
    assert_not_includes result, draft.id
    assert_not_includes result, sched.id
    assert_not_includes result, past_sched.id # 스캔 전이라도 상태 scheduled는 미노출(전환 전용)
    assert_includes result, manual.id

    travel_to(2.hours.from_now) do
      past_sched.update!(status: :published) # 잡 전환 시나리오
      assert_includes BlogPost.published_now.ids, past_sched.id
    end
  end

  test "display_summary — summary 없으면 본문 기반(150자 상한), 있으면 그대로 (BLOG-3)" do
    post = BlogPost.new(@valid_attrs.merge(summary: nil))
    summary = post.display_summary
    assert summary.present?
    assert summary.length <= 151 # 150자 + 말줄임

    long = BlogPost.new(@valid_attrs.merge(body_md: "가" * 300))
    assert_equal 151, long.display_summary.length
    assert long.display_summary.end_with?("…")

    post.summary = "요약 텍스트"
    assert_equal "요약 텍스트", post.display_summary
  end

  test "삭제 시 slug 리다이렉트 연쇄 파기(cascade)" do
    post = BlogPost.create!(@valid_attrs)
    post.update!(slug: "moved")
    assert_difference -> { BlogSlugRedirect.count }, -1 do
      post.destroy
    end
  end
end
