require "test_helper"

# 표면 ① 랜딩 루트 — 컨트롤러 통합 테스트(정적 페이지, 시스템 테스트 불요)
# 검증 근거: PRD §7 SURF-1/3/4/6, LP-1, LP-12 / _workspace/05_review.md 재리뷰 §4
# AUTH-1 정책 반전(카카오 CTA 폐기 → 이메일/비밀번호 가입 CTA 활성화) 반영 — Phase 7 갱신
# PRD v0.19 Q6 헤드라인 번복·LP-5 버블 UI·LP-10 사업자 정보 반영 — 2026-10-14 갱신
# PG 심사 요건 — 푸터 법적 고지 링크(/terms·/privacy·/refund) 허용 반영 — 2026-10-15 갱신
# 법적 고지 링크는 ② 진입이 아니므로 SURF-4 위반이 아니다. ② 진입 링크는 가입 CTA 단일 유지.
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

  test "표면 ①의 a 요소는 가입 CTA와 헤더 로그인만 ②에 진입한다 (SURF-4 개정 — 법적 고지 링크 제외)" do
    get root_url
    # PG 심사 요건(2026-10-15) — 푸터 법적 고지 3종 링크는 ② 진입이 아니므로 허용된다.
    legal_hrefs = [ terms_path, privacy_path, refund_path ]
    assert_select "a" do |anchors|
      assert anchors.any?, "랜딩에 가입 CTA 링크가 존재해야 한다"
      assert anchors.all? { |anchor| anchor["href"] == new_registration_path || anchor["href"] == new_session_path || anchor["href"].in?(legal_hrefs) },
        "② 진입 링크는 가입·로그인만 허용 — 비밀번호 재설정 등 타 진입 금지(법적 고지 3종 제외)"
    end
    # 헤더 로그인 직행 링크 — 재방문 사용자 동선(SURF-4 개정 2026-10-16)
    assert_select "header a[href=?]", new_session_path, text: "로그인", count: 1
    # 비밀번호 재설정 직접 진입 없음(인증 화면 상호 링크만 존재)
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
    # Phase 6 채택 문구 — 정기 시퀀스(REM-12)의 종결 지칭(사용자 개정문 — 마무리 표현)
    assert_select "p", text: /이번 안내로 정기 리마인더를 마무리하겠습니다/
    # 리뷰 이슈 #2 회귀 — PROMISE-3(약속일 리마인드)와 모순되는 '마지막 알림' 표현 부재
    assert_no_match(/마지막 알림/, response.body)
    assert_select "p" do |paragraphs|
      d14 = paragraphs.find { |p| p.text.include?("정기 리마인더를 마무리하겠습니다") }
      assert d14, "D+14 최종 안내 문구가 노출되어야 한다"
      assert_no_match(/법적|내용증명|채권/, d14.text)
    end
  end

  test "LP-5 버블이 카톡 UI 구조(발신자·#FEE500·개행 본문·버튼 컴포넌트)를 따른다 (LP-5, REM-1/3)" do
    get root_url
    # 리뷰 제안 회귀 — 버블 컨테이너는 4단계 각 1개, 총 4개(bg + 꼬리 before:bg가 동일 클래스 속성)
    assert_select "div[class*='FEE500']" do |bubbles|
      assert_equal 4, bubbles.size, "카톡 버블은 4단계마다 1개씩 총 4개여야 한다"
      bubbles.each do |bubble|
        # 카톡 노란색 — 배경 클래스 정확 일치(#FEE500)
        assert_includes bubble["class"], "bg-[#FEE500]"
        # 개행 구조 — 인사말 p → 개행 본문 p(whitespace-pre-line) 2블록(한 줄 나열 금지)
        blocks = bubble.css("p")
        assert_equal 2, blocks.size
        assert_match(/\A안녕하세요\. 받을돈입니다\./, blocks[0].text)
        assert_match(/\[발행인 표시명\]/, blocks[1].text)
        assert_includes blocks[1].text, "\n", "본문은 알림톡 템플릿처럼 개행되어야 한다"
        # 링크는 버튼 컴포넌트로 표현 — URL 텍스트 노출 금지(사용자 개정)
        button = bubble.css("div[class*='border-t'] span").map(&:text).join
        assert_match(/금액 확인하기|입금 완료·예정일 알리기|입금 예정일 제안하기/, button)
        assert_no_match(%r{badeuldon\.kr/b/}, bubble.text)
        # 버튼은 표시 전용 — 버블 내 앵커 금지(SURF-4)
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

  test "LP-14 시나리오 섹션이 4개 카드와 식별 문구로 렌더된다 (LP-14 정상)" do
    get root_url
    # 섹션 헤딩 + 리드
    assert_select "h2", text: /모든 상황, 자동으로/
    assert_select "p", text: /시퀀스는 그에 맞춰 조용히 이어갑니다/
    # 4개 시나리오 카드 배지 — 약속 재조정(PROMISE-3)·열람 분기(REM-4·SHARE-5)·부분입금(PAY-2)·입금 회신(PROMISE-7)
    %w[약속 재조정 열람 분기 부분입금 입금 회신].each do |badge|
      assert_select "p", text: /#{badge}/
    end
    # 카드별 핵심 benefit 문구 1개씩
    assert_select "h3", text: /리마인더 일정이 그 약속에 맞춰 다시 짜입니다/
    assert_select "h3", text: /열어본 거래처와 아직 못 본 거래처, 받는 안내가 다릅니다/
    assert_select "h3", text: /일부만 받았어도, 잔액 기준으로 조용히 이어갑니다/
    assert_select "h3", text: /발송이 즉시 멈춥니다\. 마감은 당신의 확인으로만/
    # 미니 목업 라벨 4종 — 실제 알림톡 버블(LP-5)과의 혼동 방지 표기
    assert_select "p", text: /상황 미리보기/, count: 4
  end

  test "LP-14 시나리오 문구는 약속 시 리마인더가 완전히 멈춘다는 과장을 하지 않는다 (LP-14 사실성 — PROMISE-3)" do
    get root_url
    # 실제 동작은 재조정(약속일 D-1 안내 + 도과 시 D+1 재요청)이므로 '약속하면 멈춤' 서술은 과장
    assert_no_match(/약속하면.*멈춥/m, response.body)
    # 열람 여부와 무관하게 동일 안내라는 서술도 REM-4·SHARE-5 분기와 모순 — 부재 확인
    assert_no_match(/열어본 거래처와 아직 못 본 거래처, 받는 안내가 같습니다/, response.body)
  end

  test "LP-14 미니 목업 버블은 실제 알림톡 버블(#FEE500)로 렌더되지 않는다 (LP-5 혼동 방지)" do
    get root_url
    # LP-5 버블 테스트가 FEE500 총 4개를 검증하므로, 시나리오 미니 목업이 카톡 노란색이면 5개 이상으로 실패함
    assert_select "div[class*='FEE500']", count: 4
    # 시나리오 목업 본문은 실발신 문구 템플릿과 구분 — 미니 목업 전용 문구가 LP-5 버블 문구와 겹치지 않음
    assert_select "p", text: /약속해주신 입금 예정일이 내일입니다/
  end

  test "LP-15 통제 섹션이 사전 알림·발송 상한·기록 보존을 표기한다 (LP-15 정상)" do
    get root_url
    assert_select "h2", text: /자동이되, 통제는 사용자에게 있습니다/
    # 3항목 배지
    %w[사전 알림 발송 상한 기록 보존].each do |badge|
      assert_select "p", text: /#{badge}/
    end
    # ① REM-11 — 연체 단계 한정 사전 알림 + 원클릭 마감/보류
    assert_select "p", text: /연체 단계의 자동 발송이 예정된 날에는 당일 아침에 알려드립니다/
    assert_select "p", text: /원클릭으로 그날 발송을 마감하거나 보류할 수 있습니다/
    # ② REM-12·PLAN-3 — 5통 상한 + 만기일 기준 14일(리뷰 CRITICAL 회귀 방지)
    assert_select "h3", text: /청구 건당 최대 5통, 만기일로부터 14일 후 자동 종료/
    assert_select "p", text: /만기일로부터 14일 뒤인 최종 안내까지 발송된 뒤 자동으로 종료됩니다/
    # ③ P4 — 기록 보존(열람 범위 보장 문구 없이 사실만 서술)
    assert_select "h3", text: /모든 발송은 기록으로 남고 지워지지 않습니다/
  end

  test "LP-15 자동 종료 기준은 만기일 기준이며 '발행 후 14일' 오기재가 없다 (LP-15, REM-12 회귀 — 리뷰 이슈 #1)" do
    get root_url
    # REM-12·PLAN-3은 만기일 D+14 — '발행 후' 기준 표기는 규칙 오기재(리뷰 CRITICAL)이므로 부재를 검증
    assert_no_match(/발행 후 14일/, response.body)
    assert_no_match(/발행 후\s*14/, response.body)
    # 만기일 기준 표기 존재
    assert_match(/만기일로부터 14일/, response.body)
  end

  test "LP-12 '추심' 표현은 부정 문맥에서만 등장한다 (LP-12, P5 — 문맥 필터)" do
    get root_url
    # LP-6 고지문·FAQ의 부정 서술('~아닙니다', '수행하지 않습니다')과 의문문(FAQ 질문)은 허용,
    # 긍정 문맥의 추심 대행 서술은 금지
    contexts = response.body.scan(/[^<>]*추심[^<>]*/)
    assert contexts.any?, "뷰어 고지문(VIEW-5)·FAQ의 추심 부정 서술이 존재해야 한다"
    contexts.each do |context|
      assert context.match?(/아닙니다|수행하지 않|아닌|\?\s*\z/),
        "추심 표현은 부정·의문 문맥에서만 허용된다: #{context.strip}"
    end
  end

  test "LP-10 최종 CTA는 신규 헤드라인을 반복 노출한다 (LP-10, LP-1)" do
    get root_url
    # 히어로 h1과 동일 문구를 closing h2에서 반복 — <br> 개행 포함 매칭
    assert_select "h1", text: /독촉하기 어려울 때,\s*받을돈이 대신합니다/
    assert_select "h2", text: /독촉하기 어려울 때,\s*받을돈이 대신합니다/
  end
end
