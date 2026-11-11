# ADMIN-10·BLOG-5·Q20 — 예약 발행 스캔 잡(매분 KST). scheduled + publish_at 경과 건을
# publish!로 published 전환한다. publish!가 이미 published면 nop, 대상 스캔도 published를
# 배제하므로 멱등. 개별 게시글 발행 실패(필수 검증 미충족 — BLOG-5)는 skip하고 나머지를
# 계속 처리한다(부분 실패 격리 — 1건 실패가 배치 전체를 중단하지 않는다).
module BlogPosts
  class PublishScheduledJob < ApplicationJob
    queue_as :default

    def perform
      # publish_at: ...Time.current — 무한 시작 범위로 예약 시각 <= 현재(KST, TIME-1)만 대상
      BlogPost.where(status: :scheduled).where(publish_at: ...Time.current).find_each do |post|
        next if post.publish!

        Rails.logger.warn("[BlogPosts::PublishScheduledJob] publish failed — " \
                          "blog_post_id=#{post.id} errors=#{post.errors.full_messages.join(', ')}")
      end
    end
  end
end
