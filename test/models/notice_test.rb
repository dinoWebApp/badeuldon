require "test_helper"

# ADMIN-6 — Notice 모델. 중요도 enum·검증(title/body 필수·만료>시작)·게시 중 스코프
# (초안 제외·만료 제외·무기한 포함 — KST Time.current, TIME-1).
class NoticeTest < ActiveSupport::TestCase
  test "title·body 필수 검증 (ADMIN-6)" do
    notice = Notice.new
    assert notice.invalid?
    assert_not_nil notice.errors[:title]
    assert_not_nil notice.errors[:body]
  end

  test "expires_at은 published_at보다 이후여야 한다 — 둘 다 있을 때 (ADMIN-6)" do
    notice = notices(:general_active)
    notice.update(published_at: Time.current, expires_at: Time.current - 1.hour)
    assert notice.invalid?
    assert_not_nil notice.errors[:expires_at]

    notice.update(expires_at: Time.current + 1.hour)
    assert notice.valid?
  end

  test "expires_at 단독(초안·만료 예정)은 검증 통과 — 둘 다 있을 때만 비교 (ADMIN-6)" do
    notice = Notice.new(title: "t", body: "b", published_at: nil, expires_at: Time.current - 1.day)
    assert notice.valid?
  end

  test "importance enum — general 기본·important 전환 (ADMIN-6)" do
    assert notices(:general_active).general?
    assert notices(:important_active).important?
    assert_equal "general", Notice.new.importance
  end

  # ── published_now 스코프(ADMIN-7 노출 대상) ──

  test "published_now는 초안(발행 전)을 제외한다" do
    Notice.create!(title: "초안", body: "b", importance: :general) # published_at nil
    assert_not_includes Notice.published_now, Notice.find_by(title: "초안")
  end

  test "published_now는 미래 발행을 제외한다" do
    assert_not_includes Notice.published_now, notices(:future_notice)
  end

  test "published_now는 만료 공지를 제외한다" do
    assert_not_includes Notice.published_now, notices(:expired_notice)
  end

  test "published_now는 게시 중 공지를 포함한다 — 만료 nil(무기한) 포함" do
    assert_includes Notice.published_now, notices(:general_active)
    assert_includes Notice.published_now, notices(:important_active)
  end

  test "live?·draft?·ended? 상태 술어 (ADMIN-6 목록 배지)" do
    assert notices(:general_active).live?
    assert_not notices(:general_active).ended?
    draft = Notice.create!(title: "초안2", body: "b")
    assert draft.draft?
    assert_not draft.live?
    assert notices(:expired_notice).ended?
    assert_not notices(:expired_notice).live?
  end
end
