require "test_helper"

# ADMIN-5 — 메시지 발송 통계 쿼리(Admins::MessageStatsQuery — 솔라피 로컬 집계, REM-10).
# 시나리오 기준: PRD v0.31 ADMIN-5·05_review.md §4 제안 6 —
# ① 최근 30일 한정 집계(그 이전 발송 제외), ② 실패율 분모 = sent + failed(pending·skipped 제외),
# ③ 발송이 하나도 없으면 실패율 nil(분모 0), ④ skip 사유 분포 = error_code,
# ⑤ recipient_role 키 정규화(enum 어댑터 차이 대응 — 문자열 키 보장).
class Admins::MessageStatsQueryTest < ActiveSupport::TestCase
  setup do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      @invoice = invoices(:delta_issued)
      @user = users(:delta)
      MessageLog.delete_all
      @sent = MessageLog.create!(invoice: @invoice, user: @user, template_key: "d1",
                                 status: :sent, sent_at: Time.current)
      @failed = MessageLog.create!(invoice: @invoice, user: @user, template_key: "d1",
                                   status: :failed, error_code: "1023")
      MessageLog.create!(invoice: @invoice, user: @user, template_key: "d1", status: :pending)
      MessageLog.create!(invoice: @invoice, user: @user, template_key: "d1",
                         status: :skipped, error_code: "상한 도달")
    end
  end

  test "sent·failed·skipped·실패율을 집계한다 — 실패율 분모는 sent+failed (ADMIN-5)" do
    row = Admins::MessageStatsQuery.call

    assert_equal 1, row.sent
    assert_equal 1, row.failed
    assert_equal 1, row.skipped
    assert_equal 50.0, row.failure_rate, "pending·skipped는 분모 제외 — 1/2"
    assert_equal({ "상한 도달" => 1 }, row.skip_reasons, "skip 사유 분포는 error_code 기준")
  end

  test "발송이 하나도 없으면 실패율은 nil이다 (분모 0 — 뷰 '-')" do
    MessageLog.delete_all

    row = Admins::MessageStatsQuery.call

    assert_nil row.failure_rate
    assert_equal 0, row.sent
  end

  test "30일 이전 발송은 집계에서 제외된다 (최근 30일 한정)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      invoice = invoices(:delta_issued)
      user = users(:delta)
      MessageLog.delete_all
      MessageLog.create!(invoice: invoice, user: user, template_key: "d1", status: :sent,
                         created_at: 40.days.ago)

      row = Admins::MessageStatsQuery.call

      assert_equal 0, row.sent, "40일 전 발송은 창 밖"
    end
  end

  test "recipient_role 키는 문자열로 정규화된다 (enum 어댑터 차이 대응)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      MessageLog.create!(invoice: @invoice, user: @user, template_key: "d1",
                         status: :sent, recipient_role: :user)

      row = Admins::MessageStatsQuery.call

      assert row.by_recipient_role.key?("debtor"), "채무자 발송 1건이 문자열 키로 집계되어야 한다"
      assert row.by_recipient_role.key?("user")
      assert_equal 1, row.by_recipient_role["debtor"]
      assert_equal 1, row.by_recipient_role["user"]
    end
  end
end
