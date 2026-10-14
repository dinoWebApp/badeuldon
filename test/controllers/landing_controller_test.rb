require "test_helper"

# 표면 ① 랜딩 루트 — 컨트롤러 통합 테스트(정적 페이지, 시스템 테스트 불요)
# 검증 근거: PRD §7 SURF-1/3/4/6, LP-1, LP-12 / _workspace/05_review.md 재리뷰 §4
# AUTH-1 정책 반전(카카오 CTA 폐기 → 이메일/비밀번호 가입 CTA 활성화) 반영 — Phase 7 갱신
# PRD v0.19 Q6 헤드라인 번복·LP-5 버블 UI·LP-10 사업자 정보 반영 — 2026-10-14 갱신
class LandingControllerTest < ActionDispatch::IntegrationTest
  test "GET /는 비로그인 200으로 landing/index 히어로를 렌더한다 (SURF-1, LP-1)" do
    get root_url
    assert_response :success
    # 레이아웃에는 h1이 없으므로 h1 렌더는 landing/index 뷰 렌더의 증거
    assert_select "h1", count: 1
  end

  test "h1 헤드라인이 Q6 확정 문구와 일치한다 (LP-1)" do
    get root_url
    # <br> 개행 포함 매칭 — Q6 번복 확정 문구(2026-10-14, 리뷰 05_review.md 제시 정규식)
    assert_select "h1", text: /독촉하기 어려울 때,\s*받을돈이 대신합니다/
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

  test "주 CTA는 히어로·LP-10 최종에서 가입 화면 실링크다 (SURF-4, AUTH-1 반전)" do
    get root_url
    # 히어로 + LP-10 최종 CTA — 승인된 플랜 변경(03 §4.1): 동일 링크·동일 문구 유지
    assert_select "a[href=?]", new_registration_path, count: 2
    assert_select "a[href=?]", new_registration_path, text: /무료로 시작하기/, count: 2
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
    assert_select "title", text: /받을돈 — 독촉하기 어려울 때, 받을돈이 대신합니다/
  end

  test "LP-12 금지 표현이 응답에 없다 (LP-12)" do
    get root_url
    assert_no_match(/100%/, response.body)
    assert_no_match(/보장/, response.body)
    # 리뷰 제안 회귀 — PROMISE-3(약속일 리마인드)와 모순되는 '마지막 알림' 표현도 금지
    assert_no_match(/마지막 알림/, response.body)
  end

  test "랜딩 메타 description이 렌더된다 (SURF-3 — 색인 허용 표면)" do
    get root_url
    assert_select "meta[name=description]" do |metas|
      assert_equal 1, metas.size
      # 레이아웃 기본값이 아닌 랜딩 전용 description(content_for 전달 확인)
      assert_match(/수금 루프/, metas.first["content"])
      # 리뷰 제안 — description 선두 문장도 신규 헤드라인(Q6)으로 일관 갱신 확인
      assert_match(/\A독촉하기 어려울 때, 받을돈이 대신합니다\./, metas.first["content"])
    end
  end

  test "LP-2 공감 인용 3종이 PRD 원문으로 노출된다 (LP-2)" do
    get root_url
    # figure 내 인용 3종(LP-6 VIEW-5 고지문 blockquote와 구분)
    assert_select "figure blockquote", count: 3
    assert_select "figure blockquote", text: /청구서를 보냈는데 열어는 봤는지 알 수 없다/
    assert_select "figure blockquote", text: /만기가 지나도 독촉 문자를 못 쓰겠다/
    assert_select "figure blockquote", text: /독촉했다가 다음 프로젝트를 잃을까 겁난다/
  end

  test "LP-3 수금 루프 5단계가 한 줄 설명과 함께 노출된다 (LP-3)" do
    get root_url
    assert_select "ol li", count: 5
    %w[발행 전달·열람\ 추적 자동\ 리마인더 약속\ 수집 수금\ 마감].each do |title|
      assert_select "ol li span", text: /#{title}/
    end
  end

  test "LP-4 이점 문장 3종이 PRD 원문으로 노출된다 (LP-4)" do
    get root_url
    assert_select "p", text: /보냈는지, 언제 봤는지 알립니다/
    assert_select "p", text: /발신자는 ‘받을돈’, 문구는 4단계 톤/
    assert_select "p", text: /입금 예정일, 거래처가 클릭으로 답합니다/
  end

  test "LP-5 발신 문구 4단계가 라벨과 함께 노출된다 (LP-5, REM-2)" do
    get root_url
    %w[D-1 D+1 D+7 D+14].each { |stage| assert_select "span", text: stage }
    %w[예고 확인 재요청 최종\ 안내].each { |label| assert_select "span", text: /#{label}/ }
    # 4단계 모두 서비스 명의 인사로 시작(REM-1) — 버블 본문 p 기준
    assert_select "p", text: /^안녕하세요\. 받을돈입니다\./, count: 4
  end

  test "LP-5 D+14 문구는 시퀀스 종결 안내이며 법적 조치를 언급하지 않는다 (리뷰 이슈 #2, Q2)" do
    get root_url
    # Phase 6 채택 문구 — 정기 시퀀스(REM-12)의 종결 지칭
    assert_select "p", text: /이번 안내로 정기 리마인더를 마칩니다/
    # 리뷰 이슈 #2 회귀 — PROMISE-3(약속일 리마인드)와 모순되는 '마지막 알림' 표현 부재
    assert_no_match(/마지막 알림/, response.body)
    assert_select "p" do |paragraphs|
      d14 = paragraphs.find { |p| p.text.include?("정기 리마인더를 마칩니다") }
      assert d14, "D+14 최종 안내 문구가 노출되어야 한다"
      assert_no_match(/법적|내용증명|채권/, d14.text)
    end
  end

  test "LP-5 버블이 카톡 UI 구조(발신자·#FEE500·개행 3블록·수신 시간)를 따른다 (LP-5, REM-1/3)" do
    get root_url
    # 리뷰 제안 회귀 — 버블 컨테이너는 4단계 각 1개, 총 4개(bg + 꼬리 before:bg가 동일 클래스 속성)
    assert_select "div[class*='FEE500']" do |bubbles|
      assert_equal 4, bubbles.size, "카톡 버블은 4단계마다 1개씩 총 4개여야 한다"
      bubbles.each do |bubble|
        # 카톡 노란색 — 배경 클래스 정확 일치(#FEE500)
        assert_includes bubble["class"], "bg-[#FEE500]"
        # 개행 구조 — 인사말 → 본문 → 링크 3블록 분리(한 줄 나열 금지)
        blocks = bubble.css("p")
        assert_equal 3, blocks.size
        assert_match(/\A안녕하세요\. 받을돈입니다\./, blocks[0].text)
        assert_match(/\[발행인 표시명\]/, blocks[1].text)
        assert_match(%r{badeuldon\.kr/b/\[청구서 토큰\]}, blocks[2].text)
        # 링크는 표시 전용 텍스트 — 버블 내 앵커 금지(SURF-4)
        assert_empty bubble.css("a")
        # 발신자명 — REM-1 서비스 명의(개인 번호·이름 노출 아님)
        siblings = bubble.parent.xpath("./p")
        sender = siblings.find { |p| p.text == "받을돈" }
        assert sender, "버블 위에 발신자명 '받을돈'이 있어야 한다 (REM-1)"
        # 수신 시간 — REM-3 발송 창(09~18시) 내 표기
        time_text = siblings.find { |p| p.text.match?(/\A(오전|오후) \d{1,2}:\d{2}\z/) }&.text
        assert time_text, "버블 하단에 수신 시간이 있어야 한다 (REM-3)"
        meridiem, hour = time_text.match(/\A(오전|오후) (\d{1,2}):/).captures
        hour = hour.to_i
        hour += 12 if meridiem == "오후" && hour < 12
        assert hour.between?(9, 18), "수신 시간은 발송 창(09~18시) 안이어야 한다: #{time_text}"
      end
    end
  end

  test "LP-6 포지셔닝 헤드라인과 VIEW-5 고지문 원문이 노출된다 (LP-6, P5)" do
    get root_url
    assert_select "h2", text: /받을돈은 추심 서비스가 아닙니다/
    # VIEW-5 뷰어 하단 고지문 — PRD §6.11 원문
    assert_select "blockquote p",
      text: /본 청구서는 발행인이 직접 발행했습니다\. 본 서비스는 채권 추심 업무를 수행하지 않습니다\./
  end

  test "LP-7 요금 수치가 PLAN 원문대로 노출된다 (LP-7, PLAN-1/2/3/4)" do
    get root_url
    assert_select "li", text: /월 청구 3건 · 거래처 5개/
    assert_select "p", text: /9,900원/
    assert_select "p", text: /첫 14일 무료 체험/
    assert_select "p", text: /4,000원/
    assert_select "p", text: /90일 유효/
    assert_select "p", text: /청구 건당 최대 5통\(대체 SMS 포함\)/
    # 부가세 포함 여부 명시(PRD LP-7·결정 #4)
    assert_select "p", text: /부가세 포함/, minimum: 2
  end

  test "LP-8 FAQ 8항목의 질문이 모두 노출된다 (LP-8)" do
    get root_url
    assert_select "summary", count: 8
    %w[
      추심·법무 대행 서비스인가요?
      거래처가 불쾌해하지 않을까요?
      내 개인 번호·이름이 노출되나요?
      상대방도 앱을 깔거나 가입해야 하나요?
      알림톡 발송 비용은 별도인가요?
      계좌·거래처 정보는 안전하게 관리되나요?
      유료 구독은 어떻게 해지하나요?
      사업자가 아닌 프리랜서도 쓸 수 있나요?
    ].each do |question|
      assert_select "summary", text: /#{Regexp.escape(question)}/
    end
  end

  test "LP-10 푸터에 문의 채널이 표기된다 (LP-10, 결정 #5)" do
    get root_url
    assert_select "footer", text: /카카오톡 채널 ‘받을돈’/
    assert_select "footer", text: /© 2026 받을돈/
  end

  test "LP-10 푸터에 사업자 정보 4종이 노출된다 (LP-10)" do
    get root_url
    footer = css_select("footer").first
    assert footer, "랜딩 레이아웃 푸터가 렌더되어야 한다"
    text = footer.text
    # 법정 필수 4종 — 각각 렌더 확인(파이프 구분자는 장식)
    assert_match(/상호: 벨로루프/, text)
    assert_match(/대표: 김건준/, text)
    assert_match(/사업자등록번호: 539-14-03399/, text)
    assert_match(/주소: 경기도 김포시 김포한강8로 158, 6층 604-n112호\(마산동\)/, text)
    # 사업자 정보에 생년월일·개업일은 미노출(지시 기준)
    assert_no_match(/생년월일/, text)
    assert_no_match(/개업일/, text)
  end

  test "LP-10 최종 CTA는 신규 헤드라인을 반복 노출한다 (LP-10, LP-1)" do
    get root_url
    # 히어로 h1과 동일 문구를 closing h2에서 반복 — <br> 개행 포함 매칭
    assert_select "h1", text: /독촉하기 어려울 때,\s*받을돈이 대신합니다/
    assert_select "h2", text: /독촉하기 어려울 때,\s*받을돈이 대신합니다/
  end
end
