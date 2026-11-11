require "test_helper"

module BlogPosts
  # ADMIN-10·BLOG-5·Q20 — 예약 발행 스캔 잡(매분 KST). scheduled + publish_at 경과 건을
  # publish!로 published 전환한다. publish!의 필수 검증(BLOG-5) 미충족 건은 skip·나머지 계속
  # (부분 실패 격리), published는 대상 스캔에서 배제되어 재실행 멱등.
  class PublishScheduledJobTest < ActiveSupport::TestCase
    setup do
      @admin = admins(:ops)
      @valid_attrs = {
        admin: @admin, title: "예약 발행 가이드", slug: "scheduled-publish-guide",
        body_md: "## 본문\n예약 발행 테스트",
        meta_title: "예약 발행 가이드", meta_description: "예약 발행 테스트 요약"
      }
    end

    def create_scheduled(attrs = {})
      post = BlogPost.create!(@valid_attrs.merge(slug: "scheduled-#{BlogPost.count + 1}-#{Time.current.to_i}",
                                                 publish_at: 1.hour.ago, status: :scheduled, **attrs))
      post.thumbnail.attach(io: StringIO.new("x"), filename: "t.png", content_type: "image/png")
      post.og_image.attach(io: StringIO.new("x"), filename: "o.png", content_type: "image/png")
      post
    end

    test "publish_at이 경과한 scheduled 건을 published로 전환한다 (Q20 — 도과 시 전환)" do
      post = create_scheduled
      assert post.scheduled?

      BlogPosts::PublishScheduledJob.perform_now
      assert post.reload.published?
      assert_not_nil post.published_at
    end

    test "publish_at이 미래인 scheduled 건은 유지한다" do
      post = BlogPost.create!(@valid_attrs.merge(slug: "future-scheduled", publish_at: 1.hour.from_now,
                                                 status: :scheduled))

      BlogPosts::PublishScheduledJob.perform_now
      assert post.reload.scheduled?
      assert_nil post.published_at
    end

    test "필수 검증 실패 건은 scheduled 유지·나머지는 전환한다 (부분 실패 격리 — BLOG-5)" do
      ok = create_scheduled
      # 썸네일 미첨부 → publishable? 실패. AS 첨부 없이 scheduled로 생성.
      broken = BlogPost.create!(title: "미완성 초안", slug: "broken-scheduled", admin: @admin,
                                body_md: "본문", meta_title: "미완성", meta_description: "미완성 요약",
                                publish_at: 1.hour.ago, status: :scheduled)
      assert broken.scheduled?

      BlogPosts::PublishScheduledJob.perform_now
      assert ok.reload.published?, "발행 가능 건은 실패 건과 무관하게 전환된다"
      assert broken.reload.scheduled?, "필수 검증 미충족 건은 skip된다"
    end

    test "재실행해도 멱등이다 (이미 published는 대상 아님)" do
      post = create_scheduled
      BlogPosts::PublishScheduledJob.perform_now
      first_published_at = post.reload.published_at

      BlogPosts::PublishScheduledJob.perform_now
      assert post.reload.published?
      assert_equal first_published_at, post.reload.published_at
    end
  end
end
