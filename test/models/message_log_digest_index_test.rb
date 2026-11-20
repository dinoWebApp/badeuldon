require "test_helper"

# message_logs digest 부분 유니크 인덱스(2026-11-20 T3 — W-1 DB 방어선·SEC-5 준칙):
# idx_message_logs_digest_period_uniq [user_id, template_key, scheduled_at] where digest = 1.
# ① 같은 (user·template_key·scheduled_at) digest 2행째는 DB(RecordNotUnique)가 차단한다
# ② scheduled_at이 다르면 주 단위 복수 행이 허용된다 ③ 일반(digest=false) 기록은 동일
# 키 조합에 영향받지 않는다(부분 인덱스 범위 밖 — 기존 발송 이력 누적 불변).
# 키 조합은 Noti::WeeklyDigestService#already_sent_this_week?의 멱등 판정 쿼리와 1:1이다.
class MessageLogDigestIndexTest < ActiveSupport::TestCase
  fixtures :users, :clients, :invoices

  DIGEST_KEY = "noti2_weekly_digest" # Noti::WeeklyDigestService::TEMPLATE_KEY와 동일

  test "같은 (user·template_key·scheduled_at) digest 2행째는 DB에서 차단된다 (SEC-5 준칙)" do
    period = Time.zone.parse("2026-11-09 00:00")
    MessageLog.create!(user: users(:delta), digest: true, template_key: DIGEST_KEY,
                       scheduled_at: period, recipient_role: :user, origin: :auto)

    assert_raises ActiveRecord::RecordNotUnique do
      MessageLog.create!(user: users(:delta), digest: true, template_key: DIGEST_KEY,
                         scheduled_at: period, recipient_role: :user, origin: :auto)
    end
  end

  test "scheduled_at가 다르면 같은 사용자·템플릿도 복수 행이 허용된다 (주 단위 키)" do
    this_week = Time.zone.parse("2026-11-09 00:00")
    next_week = Time.zone.parse("2026-11-16 00:00")
    MessageLog.create!(user: users(:delta), digest: true, template_key: DIGEST_KEY,
                       scheduled_at: this_week, recipient_role: :user, origin: :auto)
    MessageLog.create!(user: users(:delta), digest: true, template_key: DIGEST_KEY,
                       scheduled_at: next_week, recipient_role: :user, origin: :auto)

    assert_equal 2, MessageLog.where(digest: true, user: users(:delta)).count
  end

  test "일반(digest=false) 기록은 동일 키 조합에 영향받지 않는다 (부분 인덱스 범위 밖)" do
    same_time = Time.zone.parse("2026-11-09 09:00")
    2.times do
      MessageLog.create!(user: users(:delta), invoice: invoices(:delta_issued),
                         template_key: "confirm_d1", scheduled_at: same_time,
                         recipient_role: :user, origin: :manual, status: :sent)
    end

    assert_equal 2, MessageLog.where(user: users(:delta), template_key: "confirm_d1",
                                     scheduled_at: same_time).count
  end
end
