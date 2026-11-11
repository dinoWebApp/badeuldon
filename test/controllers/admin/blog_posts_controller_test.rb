require "test_helper"

# ADMIN-10·BLOG-5 — 블로그 콘텐츠 관리(컨트롤러 경유 HTTP 수준 검증).
# ① 목록·필터 ② 생성(슬러그 자동)·수정·삭제 ③ publish(필수 검증 실패 alert)·schedule·
# unpublish ④ 비인증·U1 세션 차단(Run A/B 교훈).
class Admin::BlogPostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_admin_totp_secrets
    @admin = admins(:ops)
  end

  test "index는 목록·상태 배지·필터를 렌더한다 (ADMIN-10·BLOG-5)" do
    admin_login(@admin)
    BlogPost.create!(admin: @admin, title: "초안 글", slug: "draft-post", body_md: "내용")

    get admin_blog_posts_path
    assert_response :success
    assert_match "초안 글", response.body
    assert_match "초안", response.body

    get admin_blog_posts_path, params: { status: "draft", category: "scripts" }
    assert_response :success
    assert_match "초안 글", response.body
  end

  test "생성은 303으로 반영되고 slug 비우면 자동 생성된다 (BLOG-5)" do
    admin_login(@admin)
    assert_difference -> { BlogPost.count }, 1 do
      post admin_blog_posts_path, params: {
        blog_post: { title: "신규 글", body_md: "내용", slug: "", category: "scripts" }
      }
    end
    assert_response :see_other
    assert_redirected_to admin_blog_posts_path
    created = BlogPost.order(:id).last
    assert_equal "신규 글", created.title
    assert_match(/\A[a-z0-9-]+\z/, created.slug)
    assert_equal @admin.id, created.admin_id
  end

  test "필수값 누락 생성은 422로 재렌더된다 (ADMIN-10)" do
    admin_login(@admin)
    assert_no_difference -> { BlogPost.count } do
      post admin_blog_posts_path, params: { blog_post: { title: "", body_md: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "수정·삭제가 동작하고 slug 변경 시 리다이렉트가 기록된다 (BLOG-1·5)" do
    admin_login(@admin)
    post_record = BlogPost.create!(admin: @admin, title: "원래 글", slug: "old-slug", body_md: "내용")

    patch admin_blog_post_path(post_record), params: {
      blog_post: { title: "수정 글", slug: "new-slug", body_md: "수정 내용" }
    }
    assert_response :see_other
    post_record.reload
    assert_equal "수정 글", post_record.title
    assert_equal [ "old-slug" ], post_record.slug_redirects.pluck(:old_slug)

    assert_difference -> { BlogPost.count }, -1 do
      delete admin_blog_post_path(post_record)
    end
    assert_response :see_other
  end

  test "publish는 필수 필드 미충족 시 실패 안내, 충족 시 발행된다 (BLOG-5)" do
    admin_login(@admin)
    post_record = BlogPost.create!(admin: @admin, title: "발행 대상", slug: "pub-1", body_md: "내용",
                                   meta_title: "메타 제목", meta_description: "메타 설명")

    patch publish_admin_blog_post_path(post_record)
    assert_response :see_other
    assert_equal "draft", post_record.reload.status # 썸네일·OG·메타 부족 — 거부

    post_record.thumbnail.attach(io: StringIO.new("x"), filename: "t.png", content_type: "image/png")
    post_record.og_image.attach(io: StringIO.new("x"), filename: "o.png", content_type: "image/png")
    patch publish_admin_blog_post_path(post_record)
    assert_response :see_other
    assert_equal "published", post_record.reload.status
    assert post_record.published_at.present?

    patch publish_admin_blog_post_path(post_record) # 재호출 멱등
    assert_response :see_other
    assert_equal "published", post_record.reload.status
  end

  test "schedule은 publish_at 필수·상태 전환, unpublish는 hidden 전환 (BLOG-5·Q20)" do
    admin_login(@admin)
    post_record = BlogPost.create!(admin: @admin, title: "예약 대상", slug: "sch-1", body_md: "내용")

    patch schedule_admin_blog_post_path(post_record), params: { blog_post: { publish_at: "" } }
    assert_response :see_other
    assert_equal "draft", post_record.reload.status

    patch schedule_admin_blog_post_path(post_record),
          params: { blog_post: { publish_at: 1.day.from_now.strftime("%Y-%m-%dT%H:%M") } }
    assert_response :see_other
    assert_equal "scheduled", post_record.reload.status
    assert post_record.publish_at.present?

    patch unpublish_admin_blog_post_path(post_record)
    assert_response :see_other
    assert_equal "hidden", post_record.reload.status
  end

  test "비인증 접근은 로그인 화면으로 유도되고 U1 세션도 차단된다 (AUTH-7)" do
    get admin_blog_posts_path
    assert_redirected_to new_admin_session_path

    user = users(:alpha)
    post session_path, params: { email: user.email, password: "password" }
    patch publish_admin_blog_post_path(BlogPost.create!(admin: @admin, title: "t", slug: "x-1", body_md: "b"))
    assert_redirected_to new_admin_session_path
  end

  test "폼은 multipart(enctype)로 렌더되고 edit엔 예약 발행 트리거가 있다 (B-1·C-1)" do
    admin_login(@admin)

    get new_admin_blog_post_path
    assert_response :success
    assert_match %r{enctype="multipart/form-data"}, response.body

    post_record = BlogPost.create!(admin: @admin, title: "트리거 글", slug: "trigger-1", body_md: "내용")
    get edit_admin_blog_post_path(post_record)
    assert_response :success
    assert_match schedule_admin_blog_post_path(post_record), response.body
    assert_match "예약 발행", response.body
  end

  test "multipart 업로드로 썸네일·OG가 실제 첨부되고 발행된다 (B-1·BLOG-5)" do
    admin_login(@admin)

    post admin_blog_posts_path, params: {
      blog_post: {
        title: "멀티파트 글", body_md: "내용과 [도구](/tools) 링크", category: "docs",
        meta_title: "멀티파트 메타", meta_description: "멀티파트 설명",
        thumbnail: fixture_file_upload("sample.png", "image/png"),
        og_image: fixture_file_upload("sample.png", "image/png")
      }
    }
    assert_response :see_other
    created = BlogPost.order(:id).last
    assert created.thumbnail.attached?, "multipart 폼 전송으로 썸네일이 첨부되어야 한다"
    assert created.og_image.attached?, "multipart 폼 전송으로 OG 이미지가 첨부되어야 한다"

    patch publish_admin_blog_post_path(created)
    assert_response :see_other
    assert_equal "published", created.reload.status
  end

  test "schedule에 파싱 불가 시각은 좀비 예약 없이 거부된다 (W-2·BLOG-5)" do
    admin_login(@admin)
    post_record = BlogPost.create!(admin: @admin, title: "좀비 방지", slug: "zombie-1", body_md: "내용")

    patch schedule_admin_blog_post_path(post_record), params: { blog_post: { publish_at: "not-a-date" } }
    assert_response :see_other
    assert_redirected_to edit_admin_blog_post_path(post_record)
    record = post_record.reload
    assert_equal "draft", record.status
    assert_nil record.publish_at
  end

  test "publish는 내부 링크 부재 시 경고를 덧붙이고 있으면 없다 (C-4·BLOG-6)" do
    admin_login(@admin)

    no_link = BlogPost.create!(admin: @admin, title: "링크 없음", slug: "no-link-1", body_md: "내용",
                               meta_title: "메타", meta_description: "설명")
    attach_publish_assets(no_link)
    patch publish_admin_blog_post_path(no_link)
    assert_response :see_other
    assert flash[:notice].to_s.include?("내부 링크가 없습니다")

    with_link = BlogPost.create!(admin: @admin, title: "링크 있음", slug: "with-link-1",
                                 body_md: "내용과 [도구](/tools) 참고", meta_title: "메타", meta_description: "설명")
    attach_publish_assets(with_link)
    patch publish_admin_blog_post_path(with_link)
    assert_response :see_other
    refute flash[:notice].to_s.include?("내부 링크가 없습니다")
  end

  private

  def attach_publish_assets(record)
    record.thumbnail.attach(io: StringIO.new("x"), filename: "t.png", content_type: "image/png")
    record.og_image.attach(io: StringIO.new("x"), filename: "o.png", content_type: "image/png")
  end
end
