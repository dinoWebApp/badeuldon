require "test_helper"

# ADMIN-5 — 가입 지표 쿼리(Admins::SignupStatsQuery).
# 시나리오 기준: PRD v0.31 ADMIN-5·05_review.md §4 제안 6(빈 데이터 처리) —
# ① 전체·최근 7일·최근 30일 가입수가 기준 시각(TIME-1 KST) 대비 정확히 집계된다,
# ② 경계(7일·30일 자정 이전 가입은 포함, 그 이전은 제외),
# ③ 사용자가 전무해도 0으로 반환한다(nil 아님).
class Admins::SignupStatsQueryTest < ActiveSupport::TestCase
  test "전체·7일·30일 가입수를 기준 시각 대비 집계한다 (ADMIN-5·TIME-1)" do
    # 중첩 travel_to 블록 금지 — 순차 스텁으로 가입 시각을 흩뿌린다(fixtures 사용자 정리 후 시드)
    clear_domain_tables
    User.delete_all
    travel_to(Time.zone.parse("2026-10-05 09:00"))
    User.create!(email: "old@example.com", password: "password") # 30일 이전
    travel_back
    travel_to(Time.zone.parse("2026-11-02 12:00"))
    User.create!(email: "d30@example.com", password: "password") # 30일 창 내
    travel_back
    travel_to(Time.zone.parse("2026-11-09 08:00"))
    User.create!(email: "d7@example.com", password: "password") # 7일 창 내
    travel_back

    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      row = Admins::SignupStatsQuery.call

      assert_equal 3, row.total
      assert_equal 1, row.last_7d
      assert_equal 2, row.last_30d
    end
  end

  test "경계 — 30일 창 시작일 자정 이전 가입은 제외된다 (TIME-1)" do
    clear_domain_tables
    User.delete_all
    # 시간 의존 시딩 금지 — 실행일 기준 30.days.ago 시드는 창이 실행일마다 어긋나 깨진다.
    # 기준 시각을 고정하고 창 시작일을 그 시각에서 역산한다.
    base = Time.zone.parse("2026-11-10 09:00")
    boundary = (base - 30.days).beginning_of_day
    travel_to(boundary - 1.second)
    User.create!(email: "just-out@example.com", password: "password")
    travel_back
    travel_to(boundary)
    User.create!(email: "just-in@example.com", password: "password")
    travel_back

    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      row = Admins::SignupStatsQuery.call

      assert_equal 2, row.total
      assert_equal 1, row.last_30d, "창 시작 자정에 가입한 건만 포함"
    end
  end

  test "사용자가 없으면 0을 반환한다 (빈 데이터 — nil 아님)" do
    travel_to(Time.zone.parse("2026-11-10 09:00")) do
      clear_domain_tables
      User.delete_all

      row = Admins::SignupStatsQuery.call

      assert_equal({ total: 0, last_7d: 0, last_30d: 0 },
                   { total: row.total, last_7d: row.last_7d, last_30d: row.last_30d })
    end
  end
end
