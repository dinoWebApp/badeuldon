require "application_system_test_case"

# AUTH-1.5 회원 자진 탈퇴(Q29) — 브라우저 E2E. 설정 화면 위험 구역에서 확인용 이메일을
# 입력해 탈퇴하면 세션이 종료되고 랜딩으로 안내된다. 다시 /app에 접근하면 로그인 화면으로
# 되돌려진다(로그인 없음 — P3 표면 경계 유지). 로그인은 공용 log_in_as(ApplicationSystemTestCase —
# W-7 경화, dom_click_button 제출)를 쓴다.
class AppProfileWithdrawalTest < ApplicationSystemTestCase
  test "설정 화면에서 확인용 이메일을 입력해 탈퇴하면 랜딩으로 안내되고 로그인이 풀린다 (AUTH-1.5)" do
    user = users(:delta) # 미수 청구 6건 — 고지가 보이는 상태에서 진행한다
    # C-1 — 공용 픽스처 패스(delta_active_pass, 만료 2026-12-30)의 usable 의존 제거:
    # 만료일이 테스트 실행일과 무관하게 미래인 패스로 교체한다(시스템 테스트는 travel_to
    # 대신 상대 만료일을 쓴다 — Capybara 시간 동결 회피).
    user.payment_passes.destroy_all
    user.payment_passes.create!(total_uses: 10, remaining_uses: 10, expires_at: 90.days.from_now)

    log_in_as(user)
    visit edit_app_profile_path

    assert_text "회원 탈퇴"
    assert_text "탈퇴하면 계정과 데이터가 즉시 삭제되어 되돌릴 수 없습니다"
    assert_text "미수 청구 6건"
    assert_text "남은 수금 패스 10건"

    fill_in "확인용 이메일", with: user.email
    dom_click_button "탈퇴합니다"

    assert_text "탈퇴가 완료되었습니다. 그동안 이용해 주셔서 감사합니다."
    assert_equal root_path, current_path
    assert_not User.exists?(user.id)

    # 세션 종료 확인 — /app 재접근은 로그인 화면으로 되돌려진다
    visit app_root_path
    assert_selector "h1", text: "로그인"
    assert_text "이메일" # 로그인 폼이 렌더된다(비로그인 상태)
  end

  test "확인용 이메일이 불일치하면 설정 화면으로 되돌아가고 계정이 유지된다 (AUTH-1.5)" do
    user = users(:delta)

    log_in_as(user)
    visit edit_app_profile_path

    fill_in "확인용 이메일", with: "wrong@example.com"
    dom_click_button "탈퇴합니다"

    assert_text "이메일이 일치하지 않습니다. 가입한 이메일을 다시 입력해 주세요."
    assert_text "회원 탈퇴"
    # N-1 — 불일치 안내가 탈퇴 영역 안 role="alert"으로 실제 화면에 보인다(assert_selector는
    # 가시성을 기본 검사한다 — 앵커 복귀 시 상단 플래시가 화면 밖이어도 이 줄은 보인다).
    assert_selector "section#withdrawal [role='alert']",
                    text: "이메일이 일치하지 않습니다. 가입한 이메일을 다시 입력해 주세요."
    # 상단 플래시도 그대로 표시된다(기존 단언 유지 — 컨트롤러 테스트와 이중 고정)
    assert_selector "p#alert", text: "이메일이 일치하지 않습니다. 가입한 이메일을 다시 입력해 주세요."
    assert_predicate User.find_by(email: user.email), :present?
  end
end
