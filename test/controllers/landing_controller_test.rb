require "test_helper"

# 표면 ① 랜딩 루트 — 컨트롤러 통합 테스트(정적 페이지, 시스템 테스트 불요)
# 검증 근거: PRD §7 SURF-1/3/4/6, LP-1, LP-12 / _workspace/05_review.md tester_focus
class LandingControllerTest < ActionDispatch::IntegrationTest
  test "GET /는 비로그인 200으로 landing/index 히어로를 렌더한다 (SURF-1, LP-1)" do
    # F-AUTH 미구현으로 세션 인프라 자체가 없음 — 요청은 정의상 비로그인 상태
    get root_url
    assert_response :success
    # 레이아웃에는 h1이 없으므로 h1 렌더는 landing/index 뷰 렌더의 증거
    assert_select "h1", count: 1
  end

  test "h1 헤드라인이 Q6 확정 문구와 일치한다 (LP-1)" do
    get root_url
    # <br> 개행과 작은따옴표 포함 정확 매칭 — 리뷰 05_review.md 제시 정규식
    assert_select "h1", text: /말하기 어려운 '돈 다오',\s*받을돈이 대신합니다/
  end

  test "LP-1 구성요소 4종이 모두 노출된다 (LP-1)" do
    get root_url
    # 서브카피 — 수금 루프 4단계 어휘(청구 링크 → 열람 추적 → 자동 리마인더 → 입금 약속 수집)
    assert_select "p", text: /청구 링크.*열람.*리마인더.*약속.*수금 루프/m
    # 주 CTA + 보조 문구 + 보조 CTA
    assert_select "button", text: /카카오로 시작하기/
    assert_select "p", text: /무료 · 카드등록 없음 · 3분/
    assert_select "button", text: /작동 방식 보기/
  end

  test "표면 ①은 noindex 없이 content_for :title을 렌더한다 (SURF-3)" do
    get root_url
    # 역방향: 색인 허용 표면 — noindex 부재
    assert_no_match(/noindex/, response.body)
    # content_for :title이 레이아웃 title 태그로 전달됨(Badeuldon 폴백 미사용)
    assert_select "title", text: /받을돈 — 말하기 어려운 '돈 다오', 받을돈이 대신합니다/
  end

  test "a 요소는 0개이고 모든 CTA는 disabled 버튼이다 (SURF-4)" do
    get root_url
    # ①→② 진입은 CTA 단일 — F-AUTH 전까지 링크 렌더 금지(비활성 button만)
    assert_select "a", count: 0
    assert_select "button[disabled][aria-disabled='true']", text: /카카오로 시작하기/, count: 1
    assert_select "button[disabled][aria-disabled='true']", text: /작동 방식 보기/, count: 1
  end

  test "LP-12 금지 표현이 응답에 없다 (LP-12)" do
    get root_url
    assert_no_match(/100%/, response.body)
    assert_no_match(/보장/, response.body)
  end
end
