require "test_helper"

# REM-3 발송 요일·시간대 설정 UI(T6) 통합 테스트 — 프로필 폼 저장(303)·고정 경계 밖 제출 422·
# 서버 필터(주말 0·6 제거 — 이중 보장). REM-9 금지 표현과 무관·U1 전용 경로(AUTH 가드).
class App::ProfilesRemindSettingsTest < ActionDispatch::IntegrationTest
  fixtures :users

  test "고정 경계 내 설정(화·목 13~16)은 저장되고 303으로 리다이렉트된다 (REM-3)" do
    sign_in_as users(:delta)

    patch app_profile_path, params: { user: {
      display_name: "델타디자인", business_type: "freelancer",
      remind_allowed_wdays: [ "2", "4" ], remind_start_hour: "13", remind_end_hour: "16"
    } }
    assert_response :see_other

    user = users(:delta).reload
    assert_equal [ 2, 4 ], user.remind_allowed_wday_list
    assert_equal 13, user.remind_start_hour
    assert_equal 16, user.remind_end_hour
  end

  test "주말(0·6) 포함 제출은 검증 실패 422이고 저장되지 않는다 (REM-3 고정 경계)" do
    sign_in_as users(:delta)

    patch app_profile_path, params: { user: {
      display_name: "델타디자인", business_type: "freelancer",
      remind_allowed_wdays: [ "0", "6" ], remind_start_hour: "9", remind_end_hour: "18"
    } }
    assert_response :unprocessable_entity
    assert_equal "1,2,3,4,5", users(:delta).reload.remind_allowed_wdays # 기본값 유지
  end

  test "야간 시간대(08시 시작·19시 종료) 제출은 422다 (REM-3 고정 경계)" do
    sign_in_as users(:delta)

    patch app_profile_path, params: { user: {
      display_name: "델타디자인", business_type: "freelancer",
      remind_allowed_wdays: [ "1" ], remind_start_hour: "8", remind_end_hour: "18"
    } }
    assert_response :unprocessable_entity

    patch app_profile_path, params: { user: {
      display_name: "델타디자인", business_type: "freelancer",
      remind_allowed_wdays: [ "1" ], remind_start_hour: "9", remind_end_hour: "19"
    } }
    assert_response :unprocessable_entity
    assert_equal 9, users(:delta).reload.remind_start_hour
  end

  test "서버 필터는 요일 배열에서 0·6·공백을 제거한다 (이중 보장 — 검증 전 단계)" do
    sign_in_as users(:delta)

    patch app_profile_path, params: { user: {
      display_name: "델타디자인", business_type: "freelancer",
      remind_allowed_wdays: [ "0", "2", " ", "4", "6" ],
      remind_start_hour: "9", remind_end_hour: "18"
    } }
    assert_response :see_other
    assert_equal "2,4", users(:delta).reload.remind_allowed_wdays # 주말이 서버에서 제거됨
  end
end
