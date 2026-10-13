require "test_helper"

# 표면 ③ 응답 경로(F-PROMISE) 통합 테스트 — 뷰어 POST 접수 4종(PROMISE-1 원문 렌더·303 PRG·
# 감사 화면), 서버 재검증(결정 #3 과거 차단), 비인증 조작 파라미터 무시(PROMISE-2·Phase 6 #1),
# INV-4 전이·재응답 이력 보존, PROMISE-7 상태 불변, 무효 토큰 응답 경로 404(VIEW-6),
# 답변 표시(PROMISE-6). 시나리오 기준: _workspace/03_implementation.md §2,
# _workspace/05_review.md §Tester 2·3·7·8. KST 기준 주(2026-10-12~18)를 travel_to로 고정한다
# (TIME-1). 외부 API 호출 없음.
class ViewerPromisesTest < ActionDispatch::IntegrationTest
  fixtures :invoices, :promises

  test "뷰어는 응답 액션 4종 원문·P3 문구를 렌더하고 가입·개인정보 필드가 없다 (PROMISE-1·P3·VIEW-4)" do
    invoice = invoices(:delta_issued)

    travel_to(Time.zone.parse("2026-10-14 10:00")) do
      get viewer_path(invoice.token)
      assert_response :success

      assert_select "section[aria-label='응답 보내기']" do
        assert_select "h2", text: "이 청구서에 응답하기"
        # P3 — 가입·개인정보 입력 불요 문구
        assert_select "p", text: "응답은 바로 발행인에게 전달되며, 가입이나 개인정보 입력은 필요하지 않습니다."
        # PROMISE-1 원문 버튼 — 즉시 응답 2종(button_to)
        assert_select "form.button_to[action=?]", viewer_promises_path(invoice.token) do
          assert_select "button", text: "이번 주 내에 입금할게요", count: 1
          assert_select "button", text: "이미 입금했어요", count: 1
        end
        # 입력 2종 — <details> 네이티브 접기(VIEW-1 JS 불요)
        assert_select "summary", text: /입금 예정일 지정/
        assert_select "summary", text: /문의·이의 있어요/
        assert_select "input[type=hidden][name='promise[kind]'][value='date_selected']", count: 1
        assert_select "input[type=hidden][name='promise[kind]'][value='inquiry']", count: 1
        # date input — min=오늘(1차 방어, 서버가 재검증)·메모 상한 2,000자
        assert_select "input[type=date][name='promise[promised_on]'][min=?]", Date.current.iso8601
        assert_select "textarea[name='promise[memo]'][maxlength='2000']", count: 1
      end
      # P3 — 개인정보 입력 필드 전무
      assert_select "input[type=password]", count: 0
      assert_select "input[type=email]", count: 0
    end
  end

  test "답변 완료 문의가 있는 청구서는 발행인 답변을 표시한다 (PROMISE-6·P2)" do
    travel_to(Time.zone.parse("2026-10-14 10:00")) do
      get viewer_path(invoices(:delta_viewed).token)
      assert_response :success

      assert_select "section[aria-label='발행인 답변']", count: 1 do
        assert_select "h2", text: "발행인 답변"
        assert_select "p", text: "청구 총액에 부가세가 포함된 금액입니다."
        assert_select "p", text: /2026-10-14 10:00 답변/           # answered_at KST 표기(TIME-1)
      end
    end
  end

  test "this_week 등록은 303 PRG로 감사 화면을 보여주고 promised 전이를 기록한다 (PROMISE-1/2·INV-4)" do
    invoice = invoices(:delta_issued)

    travel_to(Time.zone.parse("2026-10-14 10:00")) do
      post viewer_promises_path(invoice.token), params: { promise: { kind: "this_week" } }
      assert_response :see_other
      assert_redirected_to viewer_promise_thanks_path(invoice.token)

      follow_redirect!
      assert_response :success
      assert_select "h1", text: "감사합니다. 발행인에게 전달했습니다."
      # 완료 화면은 폼이 없다 — PRG 재제출·이중 접수 방지(PROMISE-2)
      assert_select "form", count: 0
      # ③→③ 복귀 링크뿐(SURF-4)
      assert_select "a[href=?]", viewer_path(invoice.token), text: "청구서로 돌아가기", count: 1
      assert_select "a[href]" do |anchors|
        anchors.each { |anchor| assert_match(%r{\A/b/}, anchor[:href]) }
      end

      assert invoice.reload.promised?
      promise = invoice.promises.sole
      assert_equal "this_week", promise.kind
      assert_equal Date.new(2026, 10, 16), promise.promised_on    # 수요일 접수 → 이번 주 금
    end
  end

  test "date_selected는 당일·미래 등록을 303으로 접수하고 promised로 전이한다 (결정 #3·INV-4)" do
    invoice = invoices(:delta_issued)

    travel_to(Time.zone.parse("2026-10-16 10:00")) do
      post viewer_promises_path(invoice.token),
           params: { promise: { kind: "date_selected", promised_on: "2026-10-16" } }  # 당일 경계
      assert_response :see_other

      post viewer_promises_path(invoice.token),
           params: { promise: { kind: "date_selected", promised_on: "2026-10-30" } }  # 미래
      assert_response :see_other
    end

    assert invoice.reload.promised?
    assert_equal [ Date.new(2026, 10, 16), Date.new(2026, 10, 30) ],
                 invoice.promises.order(:id).pluck(:promised_on)
  end

  test "과거 예정일 등록은 422로 재렌더되고 잔재가 없다 (서버 재검증 — min 속성 우회 POST)" do
    invoice = invoices(:delta_issued)

    travel_to(Time.zone.parse("2026-10-16 10:00")) do
      post viewer_promises_path(invoice.token),
           params: { promise: { kind: "date_selected", promised_on: "2026-10-15" } }  # 어제
      assert_response :unprocessable_entity
      assert_select "p[role='alert']", text: /입금 예정일은 오늘 또는 그 이후 날짜로/
    end

    assert invoice.reload.issued?
    assert_empty invoice.reload.promises
  end

  test "paid_report 등록은 청구서 상태를 바꾸지 않는다 (PROMISE-7)" do
    invoice = invoices(:delta_issued)

    post viewer_promises_path(invoice.token), params: { promise: { kind: "paid_report" } }
    assert_response :see_other

    assert invoice.reload.issued?
    promise = invoice.promises.sole
    assert_equal "paid_report", promise.kind
    assert_nil promise.promised_on
  end

  test "inquiry 빈 메모는 422로 재렌더되고 잔재가 없다 (memo 필수)" do
    invoice = invoices(:delta_issued)

    post viewer_promises_path(invoice.token), params: { promise: { kind: "inquiry", memo: "" } }
    assert_response :unprocessable_entity
    assert_select "p[role='alert']", text: /문의 내용을 입력해 주세요/

    assert invoice.reload.issued?
    assert_empty invoice.reload.promises
  end

  test "inquiry 메모 등록은 303으로 접수되고 상태를 바꾸지 않는다 (PROMISE-7)" do
    invoice = invoices(:delta_issued)

    post viewer_promises_path(invoice.token), params: { promise: { kind: "inquiry", memo: "입금 계좌 문의드립니다" } }
    assert_response :see_other

    assert invoice.reload.issued?
    assert_equal "입금 계좌 문의드립니다", invoice.promises.sole.memo
  end

  test "위조 kind는 422 일반 문구로 거부된다 (enum 정보 누출 없음)" do
    invoice = invoices(:delta_issued)

    [ "hacker", "0" ].each do |kind|
      post viewer_promises_path(invoice.token), params: { promise: { kind: kind } }
      assert_response :unprocessable_entity
      assert_select "p[role='alert']", text: /응답을 처리할 수 없습니다/
    end

    assert invoice.reload.issued?
    assert_empty invoice.reload.promises
  end

  test "this_week의 조작 파라미터는 무시되고 서버 산정값으로 수렴한다 (PROMISE-2·Phase 6 #1)" do
    invoice = invoices(:delta_issued)

    travel_to(Time.zone.parse("2026-10-14 10:00")) do
      post viewer_promises_path(invoice.token), params: {
        promise: { kind: "this_week", promised_on: "1999-01-01", memo: "위조 메모",
                   answer: "위조 답변", invoice_id: invoices(:delta_paid).id }
      }
      assert_response :see_other
    end

    promise = invoice.promises.sole
    assert_equal Date.new(2026, 10, 16), promise.promised_on    # 클라이언트 값 무시 — 서버 금요일
    assert_nil promise.memo
    assert_nil promise.answer                                   # U1 전용 파라미터 주입 불가
    assert_equal invoice.id, promise.invoice_id                 # 청구서는 라우트 토큰으로만 결정
  end

  test "inquiry에 주입된 약속일은 무시되고 메모는 보존된다 (Phase 6 #1)" do
    invoice = invoices(:delta_issued)

    post viewer_promises_path(invoice.token),
         params: { promise: { kind: "inquiry", memo: "진짜 문의", promised_on: "2026-12-01" } }
    assert_response :see_other

    promise = invoice.promises.sole
    assert_nil promise.promised_on
    assert_equal "진짜 문의", promise.memo
  end

  test "paid_report에 주입된 약속일·메모는 모두 무시된다 (Phase 6 #1 — U1 타임라인 오염 차단)" do
    invoice = invoices(:delta_issued)

    post viewer_promises_path(invoice.token),
         params: { promise: { kind: "paid_report", promised_on: "2026-12-01", memo: "위조 메모" } }
    assert_response :see_other

    promise = invoice.promises.sole
    assert_nil promise.promised_on
    assert_nil promise.memo
  end

  test "재응답은 이력을 보존하고 최신 응답이 현재 기준이 된다 (P4·결정 #4)" do
    invoice = invoices(:delta_issued)

    travel_to(Time.zone.parse("2026-10-14 10:00")) do
      post viewer_promises_path(invoice.token), params: { promise: { kind: "this_week" } }
      assert_response :see_other
    end
    travel_to(Time.zone.parse("2026-10-15 10:00")) do
      post viewer_promises_path(invoice.token),
           params: { promise: { kind: "date_selected", promised_on: "2026-10-30" } }
      assert_response :see_other
    end

    assert invoice.reload.promised?                             # 재응답도 무변경 흡수
    latest = invoice.promises.order(created_at: :desc, id: :desc).first
    assert_equal "date_selected", latest.kind                   # 최신 응답 = 현재 약속 기준
    assert_equal 2, invoice.promises.count                      # 이력 전부 보존(P4)
  end

  test "동일 약속 이중 제출은 전이 1회·이력 2건으로 수렴한다 (원자 조건부 UPDATE)" do
    invoice = invoices(:delta_issued)

    travel_to(Time.zone.parse("2026-10-14 10:00")) do
      2.times do
        post viewer_promises_path(invoice.token), params: { promise: { kind: "this_week" } }
        assert_response :see_other
      end
    end

    assert invoice.reload.promised?
    assert_equal 2, invoice.promises.count
  end

  test "무효 토큰의 응답·완료 경로는 열람과 동일한 VIEW-6 404로 수렴한다 (VIEW-6)" do
    post viewer_promises_path("Z" * 43), params: { promise: { kind: "this_week" } }
    assert_response :not_found
    assert_select "h1", text: "링크가 만료되었거나 폐기되었습니다."

    get viewer_promise_thanks_path("Z" * 43)
    assert_response :not_found
    assert_select "h1", text: "링크가 만료되었거나 폐기되었습니다."
  end
end
