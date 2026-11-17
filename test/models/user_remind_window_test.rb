require "test_helper"

# REM-3 발송 요일·시간대 세부 지정(T6 — 2026-11-16 확정) 모델 테스트 — 고정 경계(평일 09~18)
# 내에서만 축소 가능(확장 3중 차단의 1중: 모델 검증), next_remind_slot 이월 9시나리오,
# remind_window_open? 판정. SendService·PrenoticeService가 이 판정점을 공유한다(단일 출처).
# 시나리오 기준: _workspace/parallel/T6/03_implementation.md §3·05_review.md Tester 지시 3번.
class UserRemindWindowTest < ActiveSupport::TestCase
  fixtures :users

  def build_user(remind_allowed_wdays: "1,2,3,4,5", remind_start_hour: 9, remind_end_hour: 18)
    users(:gamma).dup.tap do |user|
      user.email = "remind-window-#{SecureRandom.hex(4)}@example.com"
      user.remind_allowed_wdays = remind_allowed_wdays
      user.remind_start_hour = remind_start_hour
      user.remind_end_hour = remind_end_hour
    end
  end

  # ── 검증(REM-3 고정 경계 — 확장 차단) ──

  test "기본 설정(평일 9~18)은 유효하다" do
    assert build_user.valid?
  end

  test "주말(0·6) 포함은 검증 실패다 (REM-3 고정 경계 — 확장 불가)" do
    assert_not build_user(remind_allowed_wdays: "0,1,2,3,4,5").valid?
    assert_not build_user(remind_allowed_wdays: "6").valid?
    assert_not build_user(remind_allowed_wdays: "").valid? # 빈값 — 최소 1일 강제
  end

  test "09시 미만 시작·18시 초과 종료는 검증 실패다 (REM-3 고정 경계)" do
    assert_not build_user(remind_start_hour: 8).valid?
    assert_not build_user(remind_end_hour: 19).valid?
    assert_not build_user(remind_start_hour: 17, remind_end_hour: 17).valid? # 시작 < 종료 위반
  end

  test "경계값(09·18·11~17 시작)은 유효하다" do
    assert build_user(remind_start_hour: 9, remind_end_hour: 10).valid?
    assert build_user(remind_start_hour: 17, remind_end_hour: 18).valid?
    assert build_user(remind_start_hour: 9, remind_end_hour: 18).valid?
  end

  test "remind_allowed_wday_list는 1~5 이외를 제거하고 정렬·중복 제거한다" do
    user = build_user
    user.remind_allowed_wdays = "5,3,3,9,0"
    assert_equal [ 3, 5 ], user.remind_allowed_wday_list
  end

  # ── remind_window_open? 판정 ──

  test "창 판정은 요일·start 이상·end 미만이다" do
    user = build_user # 평일 9~18
    monday_10 = Time.zone.parse("2026-11-16 10:00") # 월
    assert user.remind_window_open?(monday_10)
    assert_not user.remind_window_open?(Time.zone.parse("2026-11-16 08:59")) # 개방 전
    assert_not user.remind_window_open?(Time.zone.parse("2026-11-16 18:00")) # 종료 경계
    assert_not user.remind_window_open?(Time.zone.parse("2026-11-15 10:00")) # 일요일
  end

  # ── next_remind_slot 이월(9시나리오 — 리뷰 지시 3번) ──
  # 2026-11-16 = 월요일 기준(TIME-1 KST).

  test "이월 시나리오 9종이 명세와 일치한다 (REM-3 세부 지정)" do
    default = build_user                       # 평일 9~18
    tue_thu = build_user(remind_allowed_wdays: "2,4", remind_start_hour: 13, remind_end_hour: 16)

    scenarios = [
      # [설정, 기준 시각, 기대 슬롯]
      [ default, "2026-11-13 18:00", "2026-11-16 09:00" ],  # 금 18:00(종료 경계) → 다음 주 월 09:00
      [ default, "2026-11-14 10:00", "2026-11-16 09:00" ],  # 토 → 월 09:00
      [ default, "2026-11-16 07:30", "2026-11-16 09:00" ],  # 월 개방 전 → 당일 09:00
      [ default, "2026-11-16 17:59", "2026-11-16 17:59" ],  # 경계 직전 → 그대로
      [ default, "2026-11-16 18:00", "2026-11-17 09:00" ],  # 월 18:00(종료 경계) → 화 09:00
      [ tue_thu, "2026-11-16 14:00", "2026-11-17 13:00" ],  # 월(비허용) → 화 13:00
      [ tue_thu, "2026-11-17 16:00", "2026-11-19 13:00" ],  # 화 종료 경계 → 목 13:00(당일 start 회귀 금지)
      [ tue_thu, "2026-11-17 12:00", "2026-11-17 13:00" ],  # 허용 요일 개방 전 → 당일 start
      [ tue_thu, "2026-11-17 14:00", "2026-11-17 14:00" ]   # 창 내 → 그대로
    ]

    scenarios.each do |user, from, expected|
      slot = user.next_remind_slot(Time.zone.parse(from))
      assert_equal Time.zone.parse(expected), slot,
                   "#{from} 시각의 이월 슬롯 불일치 (설정: #{user.remind_allowed_wdays} " \
                   "#{user.remind_start_hour}~#{user.remind_end_hour})"
    end
  end

  test "허용 요일이 최소 1개 보장되어 이월 루프는 종료한다 (최악 이월 7일)" do
    monday_only = build_user(remind_allowed_wdays: "1")
    slot = monday_only.next_remind_slot(Time.zone.parse("2026-11-17 10:00")) # 화 → 다음 주 월
    assert_equal Time.zone.parse("2026-11-23 09:00"), slot
  end
end
