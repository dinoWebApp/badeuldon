require "test_helper"

# 표면 ② /app 대시보드 셸 — DASH-1/2/4 빈 상태, ONB-1 준비 중 CTA, 사이드바·헤더 크롬,
# AUTH-1 비인증 가드, AUTH-1.3 미완료 프로필 가드(03 §4.1), SURF-3 noindex
# 시나리오 기준: _workspace/03_implementation.md §3·§4.1, 05_review.md 「Tester 중점 §2」
class App::DashboardsControllerTest < ActionDispatch::IntegrationTest
  test "비인증 /app 접근은 302로 로그인 화면에 리다이렉트된다 (AUTH-1)" do
    get app_root_path
    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "프로필 미완료 사용자의 /app 직접 접근은 프로필 설정 화면으로 안내된다 (AUTH-1.3 가드)" do
    sign_in_as users(:alpha)
    get app_root_path
    assert_response :redirect
    assert_redirected_to edit_app_profile_path
  end

  test "프로필 완료 사용자는 /app 대시보드 셸을 200으로 렌더한다 (DASH 셸 진입)" do
    sign_in_as users(:gamma)
    get app_root_path
    assert_response :success
    assert_select "h1", text: "대시보드"
    # 헤더 표시명 — gamma fixture(Phase 6 #2 완료 분기)
    assert_select "header span", text: "감마스튜디오", count: 1
    # /app은 noindex(SURF-3 — 상세 content 검증은 surf3_indexing_test)
    assert_select "meta[name=robots]", count: 1
  end

  test "DASH-1 요약 카드 3종은 빈 상태 문구와 대시 슬롯으로 렌더되고 0원을 표기하지 않는다" do
    sign_in_as users(:gamma)
    get app_root_path
    assert_response :success

    # 미수 총액 · 연체 건수·금액 · 7일 내 만기 — PRD §6.9 3요소 라벨
    assert_select "article h3", text: /미수 총액/, count: 1
    assert_select "article h3", text: /연체 건수·금액/, count: 1
    assert_select "article h3", text: /7일 내 만기/, count: 1
    # 빈 상태 — 카드 3종 공통 문구 + 수치 슬롯은 대시(—, aria-hidden)
    assert_select "p", text: "청구서를 발행하면 여기에 표시됩니다.", count: 3
    assert_select "p[aria-hidden='true']", text: "—", count: 3
    # 거짓 0원 금지(02_prd_update 결정) — 수치 미확보 상태에서 0원 표기 부재
    assert_no_match(/0원/, response.body)
  end

  test "DASH-2 오늘의 액션은 빈 상태 안내를 렌더한다" do
    sign_in_as users(:gamma)
    get app_root_path
    assert_response :success
    assert_select "p", text: "오늘 할 일이 없습니다", count: 1
    assert_select "p", text: /오늘 발송 예정·약속일 도래/, count: 1
  end

  test "ONB-1 첫 발행 CTA는 disabled이며 준비 중 배지를 노출한다" do
    sign_in_as users(:gamma)
    get app_root_path
    assert_response :success
    assert_select "h2", text: "3분이면 첫 청구서를 발행합니다", count: 1
    # F-INV 오픈 전까지 비활성 — disabled + aria-disabled 동시 보유
    assert_select "button[disabled][aria-disabled='true']", text: "첫 청구서 발행하기", count: 1
    assert_select "p", text: "준비 중 — 청구서 기능과 함께 열립니다", count: 1
  end

  test "DASH-4 청구서 목록은 정렬 기준 안내 문구를 렌더한다" do
    sign_in_as users(:gamma)
    get app_root_path
    assert_response :success
    assert_select "h2", text: "청구서", count: 1
    assert_select "p", text: "아직 발행된 청구서가 없습니다", count: 1
    # 기본 정렬 = 연체일 내림차순(PRD DASH-4) — 실제 정렬 구현은 F-INV 인계
    assert_select "p", text: "발행된 청구서는 연체일이 긴 순서부터 표시됩니다.", count: 1
  end

  test "사이드바는 대시보드 활성 표시·준비 중 메뉴·설정 실링크를 렌더한다" do
    sign_in_as users(:gamma)
    get app_root_path
    assert_response :success

    # 활성 내비 — 대시보드만 aria-current="page"(경로 기반 판정), 설정은 비활성
    assert_select "nav a[aria-current='page']", text: "대시보드", count: 1
    assert_select "nav a[aria-current='page'][href=?]", edit_app_profile_path, count: 0
    # 미구현 메뉴 — 링크 없이 aria-disabled + 준비 중 배지(플랜 결정 #2)
    assert_select "nav span[aria-disabled='true']", count: 2
    assert_select "nav span[aria-disabled='true']", text: /\A청구서/, count: 1
    assert_select "nav span[aria-disabled='true']", text: /\A거래처/, count: 1
    assert_select "nav span", text: "준비 중", count: 2
    # 설정 — AUTH-1.3 프로필 화면 실링크
    assert_select "nav a[href=?]", edit_app_profile_path, text: "설정", count: 1
  end

  test "헤더 로그아웃은 DELETE /session button_to와 확인 대화상자를 렌더한다" do
    sign_in_as users(:gamma)
    get app_root_path
    assert_response :success
    assert_select "form.button_to[action=?]", session_path do
      assert_select "input[name=_method][value=delete]", count: 1
      assert_select "button[data-turbo-confirm]", text: "로그아웃", count: 1
      assert_select "button[data-turbo-confirm='로그아웃하시겠습니까?']", count: 1
    end
  end
end
