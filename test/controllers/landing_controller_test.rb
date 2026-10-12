require "test_helper"

# 표면 ① 랜딩 루트 — 컨트롤러 통합 테스트(정적 페이지, 시스템 테스트 불요)
# 검증 근거: PRD §7 SURF-1/3/4/6, LP-1, LP-12 / _workspace/05_review.md 재리뷰 §4
# AUTH-1 정책 반전(카카오 CTA 폐기 → 이메일/비밀번호 가입 CTA 활성화) 반영 — Phase 7 갱신
class LandingControllerTest < ActionDispatch::IntegrationTest
  test "GET /는 비로그인 200으로 landing/index 히어로를 렌더한다 (SURF-1, LP-1)" do
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
    # 주 CTA — 가입 화면 실링크(AUTH-1 반전) + 보조 문구 + 보조 CTA
    assert_select "a[href=?]", new_registration_path, text: /무료로 시작하기/
    assert_select "p", text: /무료 · 카드등록 없음 · 3분/
    assert_select "button[disabled][aria-disabled='true']", text: /작동 방식 보기/, count: 1
  end

  test "주 CTA는 가입 화면 실링크다 (SURF-4, AUTH-1 반전)" do
    get root_url
    assert_select "a[href=?]", new_registration_path, count: 1
  end

  test "표면 ①의 a 요소는 가입 진입이 유일하다 (SURF-4 단일 진입점)" do
    get root_url
    assert_select "a" do |anchors|
      assert anchors.any?, "랜딩에 가입 CTA 링크가 존재해야 한다"
      assert anchors.all? { |anchor| anchor["href"] == new_registration_path },
        "①→② 진입은 가입 링크만 허용된다 — 로그인·재설정 등 타 링크 금지"
    end
    # 로그인·재설정 직접 진입 없음(인증 화면 상호 링크만 존재)
    assert_select "a[href=?]", new_session_path, count: 0
    assert_select "a[href=?]", new_password_path, count: 0
  end

  test "이전 카카오 CTA와 임시 안내문은 잔존하지 않는다 (AUTH-1 반전 회귀)" do
    get root_url
    assert_no_match(/카카오로 시작하기/, response.body)
    assert_no_match(/로그인은 곧 오픈됩니다/, response.body)
  end

  test "표면 ①은 noindex 없이 content_for :title을 렌더한다 (SURF-3)" do
    get root_url
    # 역방향: 색인 허용 표면 — noindex 부재
    assert_no_match(/noindex/, response.body)
    # content_for :title이 레이아웃 title 태그로 전달됨(Badeuldon 폴백 미사용)
    assert_select "title", text: /받을돈 — 말하기 어려운 '돈 다오', 받을돈이 대신합니다/
  end

  test "LP-12 금지 표현이 응답에 없다 (LP-12)" do
    get root_url
    assert_no_match(/100%/, response.body)
    assert_no_match(/보장/, response.body)
  end
end
