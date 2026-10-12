require "test_helper"

# 표면 ③ 청구서 뷰어(/b/:token) 통합 테스트 — 토큰 매트릭스 5종+초안·최초/재열람 추적
# (SHARE-3·INV-4)·device 판별·VIEW-1 구형·인앱 브라우저 406 회귀·VIEW-6 응답 통일(무효 4종 본문
# 무차이)·VIEW-8 화이트리스트·noindex(SURF-3). 시나리오 기준: _workspace/03_implementation.md §2·§4,
# _workspace/05_review.md §3·§8-a. 시간 의존 검증(만료 경계·viewed_at)은 travel_to로
# KST를 고정한다(TIME-1). 외부 API 호출 없음.
class ViewerControllerTest < ActionDispatch::IntegrationTest
  fixtures :invoices, :view_events

  MOBILE_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 " \
              "(KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1"
  DESKTOP_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
               "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  # VIEW-1 회귀 — 카카오톡 인앱 실측 패턴(actionpack 8.1.4 BrowserBlocker 기준 :modern 차단
  # 확인 UA)과 링크 미리보기 크롤러.
  INAPP_IOS_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 " \
                 "(KHTML, like Gecko) Mobile/15E148 Safari/604.1"
  INAPP_ANDROID_UA = "Mozilla/5.0 (Linux; Android 13; SM-S918N Build/TP1A.220624.014; wv) " \
                     "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/111.0.5563.116 " \
                     "Mobile Safari/537.36"
  CRAWLER_UA = "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"

  # ── 토큰 매트릭스 — ① 정상 ──

  test "발행건 토큰은 뷰어를 200으로 렌더한다 (SHARE-1·VIEW-2/3/5)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      get viewer_path(invoices(:delta_issued).token), headers: { "User-Agent" => DESKTOP_UA }
    end
    assert_response :success

    # VIEW-2 — 발행인 표시명 헤더
    assert_select "h1", text: "받을돈을 통해 테스트발행자님이 보낸 청구서입니다"
    # VIEW-3 — 청구번호·만기일·품목·금액 분해·총액
    assert_select "dd", text: "BD-20260901-001"
    assert_select "dd", text: "2026-10-01"
    assert_select "td", text: "웹 개발"
    assert_select "dd", text: "200,000원"
    assert_select "dd", text: "220,000원"
    # 계좌 카드 + PAY-3 입금자명 안내
    assert_select "section[aria-label='입금 계좌']", count: 1
    assert_select "p", text: "입금 시 입금자명을 '델타파트너스'으로 입력해 주세요."
    # VIEW-5 — 하단 고지(P5, 두 문장이 <br>로 구분된 단락)
    assert_select "p", text: /본 서비스는 채권 추심 업무를 수행하지 않습니다\./
  end

  test "초안은 토큰이 발급되지 않아 뷰어에 노출될 수 없다 (INV-4 발행 계열 한정)" do
    assert_nil invoices(:delta_draft).token
    assert_nil invoices(:delta_draft).token_expires_at
  end

  # ── 최초 열람·재열람 추적(SHARE-3·INV-4) ──

  test "최초 열람은 viewed 전이와 first 이벤트를 기록한다 (INV-4·SHARE-3)" do
    invoice = invoices(:delta_issued)
    assert invoice.issued?

    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      get viewer_path(invoice.token), headers: { "User-Agent" => DESKTOP_UA }
      assert_response :success

      assert invoice.reload.viewed?                                  # INV-4 issued→viewed 1회 전이
      event = invoice.view_events.sole
      assert event.first?                                            # 최초 열람 플래그
      assert_equal "pc", event.device
      assert_equal "127.0.0.1", event.ip
      assert_equal Time.zone.parse("2026-10-12 09:00"), event.viewed_at  # KST 고정(TIME-1)
    end
  end

  test "재열람은 이벤트만 추가하고 상태를 유지한다 (SHARE-3)" do
    invoice = invoices(:delta_issued)

    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      get viewer_path(invoice.token), headers: { "User-Agent" => MOBILE_UA }
      assert_response :success
    end
    travel_to(Time.zone.parse("2026-10-13 10:30")) do
      get viewer_path(invoice.token), headers: { "User-Agent" => DESKTOP_UA }
      assert_response :success
    end

    assert invoice.reload.viewed?                                    # 중복 전이 없음
    events = invoice.view_events.order(:viewed_at, :id)
    assert_equal 2, events.size
    assert events.first.first?
    assert_not events.last.first?
    assert_equal "mobile", events.first.device
    assert_equal "pc", events.last.device
  end

  test "viewed 상태 재방문도 이벤트를 기록한다 (SHARE-3)" do
    invoice = invoices(:delta_viewed)
    assert invoice.viewed?
    assert_equal 2, invoice.view_events.count                        # fixtures — 최초(mobile)·재열람(pc)

    get viewer_path(invoice.token), headers: { "User-Agent" => DESKTOP_UA }
    assert_response :success

    assert invoice.reload.viewed?
    events = invoice.view_events.order(:viewed_at, :id)
    assert_equal 3, events.size
    assert_not events.last.first?
    assert_equal "pc", events.last.device
  end

  # ── device 판별(SHARE-3 — UA 대략 판별) ──

  test "모바일 UA는 mobile·데스크톱 UA는 pc로 기록된다 (SHARE-3)" do
    invoice = invoices(:delta_issued)

    get viewer_path(invoice.token), headers: { "User-Agent" => MOBILE_UA }
    assert_response :success
    assert_equal "mobile", invoice.view_events.order(:id).last.device

    get viewer_path(invoice.token), headers: { "User-Agent" => DESKTOP_UA }
    assert_response :success
    assert_equal "pc", invoice.view_events.order(:id).last.device
  end

  # ── VIEW-1 구형·인앱 브라우저 — 406 차단 회귀(05_review WARNING #1·#3) ──

  test "구형·인앱 브라우저 UA로도 뷰어가 200으로 렌더된다 (VIEW-1 카카오톡 인앱)" do
    invoice = invoices(:delta_issued)

    [ INAPP_IOS_UA, INAPP_ANDROID_UA ].each do |user_agent|
      get viewer_path(invoice.token), headers: { "User-Agent" => user_agent }
      assert_response :success                                    # :modern 정책이었다면 406
      assert_select "h1", text: "받을돈을 통해 테스트발행자님이 보낸 청구서입니다"
      assert_select "dd", text: "220,000원"
      assert_select "p", text: /본 서비스는 채권 추심 업무를 수행하지 않습니다\./
    end
  end

  test "facebookexternalhit 크롤러 UA로도 뷰어가 200으로 렌더된다 (VIEW-1·링크 미리보기)" do
    get viewer_path(invoices(:delta_issued).token), headers: { "User-Agent" => CRAWLER_UA }
    assert_response :success
    assert_select "h1", text: "받을돈을 통해 테스트발행자님이 보낸 청구서입니다"
    assert_no_match(/로그인/, response.body)                       # P3 — 가입 유도 없음
  end

  # ── 토큰 매트릭스 — ②~⑤ 무효(VIEW-6 통일) ──

  test "만료된 토큰은 VIEW-6 안내와 404로 응답한다 (SHARE-2·VIEW-6)" do
    invoice = invoices(:delta_issued)                                # 만료 2026-11-30 23:59:59

    travel_to(Time.zone.parse("2026-12-01 09:00")) do
      get viewer_path(invoice.token)
      assert_response :not_found
      assert_select "h1", text: "링크가 만료되었거나 폐기되었습니다."
      assert_select "p", text: "발행인에게 직접 연락해 주세요."
    end

    assert invoice.reload.issued?                                    # 무효 접근은 전이·기록 없음
    assert_empty invoice.view_events
  end

  test "폐기된 건의 이전 토큰은 동일한 VIEW-6 404로 응답한다 (INV-6)" do
    invoice = invoices(:delta_due_soon)
    old_token = invoice.token
    assert invoice.void!                                             # 토큰 즉시 폐기(nil)

    get viewer_path(old_token)
    assert_response :not_found
    assert_select "h1", text: "링크가 만료되었거나 폐기되었습니다."
    assert invoice.reload.voided?
    assert_empty invoice.view_events
  end

  test "재발급 이전 토큰은 동일한 VIEW-6 404로 응답한다 (SHARE-2)" do
    invoice = invoices(:delta_promised)
    old_token = invoice.token
    assert invoice.regenerate_token!

    get viewer_path(old_token)
    assert_response :not_found
    assert_select "h1", text: "링크가 만료되었거나 폐기되었습니다."
    assert_empty invoice.reload.view_events
  end

  test "존재하지 않는 토큰은 동일한 VIEW-6 404로 응답한다 (VIEW-6)" do
    assert_no_difference -> { ViewEvent.count } do
      get viewer_path("Z" * 43)
    end
    assert_response :not_found
    assert_select "h1", text: "링크가 만료되었거나 폐기되었습니다."
    assert_select "p", text: "발행인에게 직접 연락해 주세요."
  end

  test "무효 토큰 4종은 상태코드·본문이 동일하다 — 존재 여부 누설 금지 (VIEW-6)" do
    # 본문 비교 기준: <main> 영역(CSRF 메타 등 요청별 랜덤 요소 제외 — 03 §4 러너 실측 기준)
    expired = invoices(:delta_issued)
    voided_token = invoices(:delta_due_soon).token
    invoices(:delta_due_soon).void!
    reissued_old = invoices(:delta_promised).token
    invoices(:delta_promised).regenerate_token!

    travel_to(Time.zone.parse("2026-12-01 09:00")) do                # expired 만료 경과
      bodies = [ expired.token, voided_token, reissued_old, "Z" * 43 ].map do |token|
        get viewer_path(token)
        assert_response :not_found
        response.body[/<main\b.*<\/main>/m]
      end

      assert_equal 1, bodies.uniq.size
      assert_match(/링크가 만료되었거나 폐기되었습니다/, bodies.first)
    end
  end

  # ── VIEW-8 화이트리스트·SURF-3 noindex ──

  test "뷰어 본문에는 링크 앵커·내비가 없다 (VIEW-8·SURF-4)" do
    get viewer_path(invoices(:delta_issued).token), headers: { "User-Agent" => DESKTOP_UA }
    assert_response :success
    assert_select "a[href]", count: 0                                # ③→① 유출 차단
    assert_select "nav", count: 0
    assert_no_match(/로그인/, response.body)

    get viewer_path("Z" * 43)
    assert_response :not_found
    assert_select "a[href]", count: 0                                # VIEW-6 화면에도 링크 없음
    assert_select "nav", count: 0
  end

  test "뷰어 응답은 정상·무효 모두 noindex 메타를 출력한다 (SURF-3)" do
    get viewer_path(invoices(:delta_issued).token), headers: { "User-Agent" => DESKTOP_UA }
    assert_response :success
    assert_select "meta[name=robots]" do |metas|
      assert_equal 1, metas.size
      assert_match(/noindex/, metas.first["content"])
    end

    get viewer_path("Z" * 43)
    assert_response :not_found
    assert_select "meta[name=robots]" do |metas|
      assert_equal 1, metas.size
      assert_match(/noindex/, metas.first["content"])
    end
  end

  test "원천징수 건 뷰어는 입금하실 금액 관점으로 안내한다 (INV-2·P1)" do
    get viewer_path(invoices(:delta_viewed).token), headers: { "User-Agent" => DESKTOP_UA }
    assert_response :success

    assert_select "dt", text: "원천징수 (공급가액의 3.3%)"
    assert_select "dd", text: "−1,650원"
    assert_select "dt", text: "입금하실 금액"
    assert_select "dd", text: "53,350원"
    assert_select "p", text: "원천징수 3.3%는 제외한 「입금하실 금액」만 입금해 주세요."
  end
end
