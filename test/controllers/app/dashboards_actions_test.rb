require "test_helper"
require_relative "../../test_helpers/reminder_factories"

# DASH-2 오늘의 액션 실데이터(F-PROMISE) — 마감 대기(PROMISE-7: 입금 완료 회신 ∩ unsettled),
# 답변 대기(PROMISE-6: 무답변 문의) 조건부 카드, 소멸 조건, 소유권 격리, 무액션 빈 상태 분기
# (기존 어설션 회귀). 시나리오 기준: _workspace/03_implementation.md §2,
# _workspace/05_review.md §Tester 4·9. KST 기준일 2026-10-12 고정(TIME-1). 외부 API 호출 없음.
# DASH-2·Q31(2026-11-26) — 나머지 세 종(오늘 발송 예정·약속일 도래·미열람 방치) 카드 검증을 추가한다:
# Free 자격(REM-8)에 따른 오늘 발송 예정 비표시·보류하기 액션(REM-11·REM-7 재사용)·빈 상태 조건 확장.
# 6차 리뷰 반영(2026-11-26) — 카드 문구는 실제 발송 예정 시각(기본 창 회원 = 오늘 14시)과
# 조사를 붙이지 않는 라벨 문형, 미열람은 "발행한 지 N일째" 문형으로 갱신(W-4).
class App::DashboardsActionsTest < ActionDispatch::IntegrationTest
  include ReminderFactories

  fixtures :users, :clients, :invoices, :promises

  test "입금 완료 회신이 있는 미마감 청구서는 마감 대기 카드로 표시된다 (PROMISE-7·DASH-2)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      get app_root_path
      assert_response :success

      assert_select "article", text: /마감 대기/ do |cards|
        assert_equal 1, cards.size
        assert_match(/델타파트너스 · 330,000원/, cards.first.text)
        assert_match(/거래처가 「이미 입금했어요」라고 회신했습니다\. 확인 후 마감해 주세요\./, cards.first.text)
      end
      assert_select "a[href=?]", app_invoice_path(invoices(:delta_partially_paid)),
                    text: "청구서 확인", count: 1
    end
  end

  test "무답변 문의는 답변 대기 카드로 표시되고 답변하면 카드가 소멸한다 (PROMISE-6·DASH-2)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      get app_root_path
      assert_response :success

      assert_select "article", text: /답변 대기/ do |cards|
        assert_equal 1, cards.size
        assert_match(/델타파트너스의 문의/, cards.first.text)
        assert_match(/입금 계좌가 변경되었는지/, cards.first.text)
      end
      assert_select "a[href=?]", app_invoice_path(invoices(:delta_due_soon)),
                    text: "문의에 답변하기", count: 1

      # 답변 등록 → 답변 대기 소멸(PROMISE-6 — 소멸 조건은 answered_at 기록)
      assert promises(:delta_unanswered_inquiry).answer!("계좌는 변경되지 않았습니다.")
      get app_root_path
      assert_select "article", text: /답변 대기/, count: 0
    end
  end

  test "마감 확정 후에는 마감 대기 카드가 소멸한다 (PROMISE-7 — 마감 자체는 PAY 도메인)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      # PAY 후속 도메인 부재 — U1 마감 확정 상태(paid)를 직접 세팅해 소멸 조건을 검증한다.
      invoices(:delta_partially_paid).update!(status: :paid)

      get app_root_path
      assert_select "article", text: /마감 대기/, count: 0     # settled 제외 — 소멸
      assert_select "article", text: /답변 대기/, count: 1     # 답변 대기는 유지
      assert_select "p", text: "오늘 할 일이 없습니다", count: 0
    end
  end

  test "타인 청구서의 응답은 대시보드에 표시되지 않는다 (소유권 격리 — Current.user 스코프)" do
    sign_in_as users(:gamma)                                   # 프로필 완료·청구서 0건
    get app_root_path
    assert_response :success

    assert_select "article", text: /마감 대기/, count: 0        # delta 소유 회신 비노출
    assert_select "article", text: /답변 대기/, count: 0        # delta 소유 문의 비노출
    assert_select "p", text: "오늘 할 일이 없습니다", count: 1   # 무액션 — 빈 상태 유지
  end

  test "청구서 0건·응답 0건이면 기존 빈 상태 문구만 렌더한다 (DASH-2 분기 회귀)" do
    sign_in_as users(:gamma)
    get app_root_path
    assert_response :success

    assert_select "p", text: "오늘 할 일이 없습니다", count: 1
    assert_select "p", text: /오늘 발송 예정·약속일 도래/, count: 1
    assert_select "article", text: /마감 대기/, count: 0
    assert_select "article", text: /답변 대기/, count: 0
  end

  # ── DASH-2·Q31(2026-11-26) — 나머지 세 종 ──

  test "오늘 발송 예정 카드는 만기 예고 대상 청구에 보류하기·청구서 확인 액션을 제공한다 (DASH-2·Q31·REM-11)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      # delta — 수금 패스 보유(자격 있음 — REM-8). fixtures 선언 집합 밖이라 테스트 내 생성.
      users(:delta).payment_passes.create!(total_uses: 10, remaining_uses: 10,
                                           expires_at: Time.zone.parse("2026-12-30 23:59:59 +0900"))
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.current + 1)   # 만기 예고(D-1)가 오늘 도래

      sign_in_as users(:delta)
      get app_root_path
      assert_response :success

      assert_select "span", text: "오늘 발송 예정", count: 1
      assert_select "article", text: /오늘 오후 2시에 다음 안내를 보냅니다: 「만기 예정 안내」\. 발송 전까지 보류할 수 있습니다\./ do |cards|
        assert_equal 1, cards.size
        assert_match(/델타파트너스 · 110,000원/, cards.first.text)
      end
      assert_select "form.button_to[action=?]", suspend_reminders_app_invoice_path(invoice) do
        assert_select "button[data-turbo-confirm='이 청구서의 자동 안내를 멈춥니다. 보류하시겠습니까?']",
                      text: "보류하기", count: 1
      end
      assert_select "a[href=?]", app_invoice_path(invoice), text: "청구서 확인", count: 1
    end
  end

  test "카드의 보류하기로 보류한 청구는 다음 대시보드 조회의 오늘 발송 예정에서 빠진다 (DASH-2·REM-11·리뷰 제안 6)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      users(:delta).payment_passes.create!(total_uses: 10, remaining_uses: 10,
                                           expires_at: Time.zone.parse("2026-12-30 23:59:59 +0900"))
      invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                        due_on: Date.current + 1)   # 만기 예고(D-1)가 오늘 도래
      sign_in_as users(:delta)

      get app_root_path
      assert_select "span", text: "오늘 발송 예정", count: 1

      patch suspend_reminders_app_invoice_path(invoice)             # 카드의 「보류하기」 경로 재사용(REM-7)
      assert_response :see_other

      get app_root_path
      assert_response :success
      # 보류 청구는 reminders_dispatchable에서 빠진다 — 보류하지 못하게 카드에 남으면 안 된다
      assert_select "span", text: "오늘 발송 예정", count: 0
    end
  end

  test "Free 회원에게는 오늘 발송 예정 카드가 없고 빈 상태가 유지된다 (DASH-2·Q31·REM-8)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      # 자격 없는 회원(Free)의 만기 전날 청구 — 후보는 있지만 자동 발송이 없어 카드도 없다
      create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                              due_on: Date.current + 1)

      sign_in_as users(:gamma)
      get app_root_path
      assert_response :success

      assert_select "span", text: "오늘 발송 예정", count: 0
      assert_select "p", text: "오늘 할 일이 없습니다", count: 1
    end
  end

  test "청구서가 있어도 다섯 종 모두 없으면 빈 상태를 유지한다 (DASH-2 — 조건 확장 회귀)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      invoice = create_reminder_invoice(user: users(:gamma), client: clients(:gamma_main),
                                        due_on: Date.current + 10)
      invoice.update_columns(issued_at: Time.current)   # 오늘 발행 — 미열람 방치 아님

      sign_in_as users(:gamma)
      get app_root_path
      assert_response :success

      assert_select "span", text: "오늘 발송 예정", count: 0
      assert_select "span", text: "약속일 도래", count: 0
      assert_select "span", text: "미열람", count: 0
      assert_select "span", text: "마감 대기", count: 0
      assert_select "span", text: "답변 대기", count: 0
      assert_select "p", text: "오늘 할 일이 없습니다", count: 1
    end
  end

  test "약속일 도래·미열람 방치 카드는 각 판정에 맞는 청구서로 렌더된다 (DASH-2·Q31)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      promise_invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                                due_on: Date.current + 18)
      promise_invoice.promises.create!(kind: :date_selected, promised_on: Date.current)
      unviewed_invoice = create_reminder_invoice(user: users(:delta), client: clients(:delta_main),
                                                 due_on: Date.current + 12)
      unviewed_invoice.update_columns(issued_at: Time.zone.parse("2026-10-07 10:00"))  # 5일 경과

      sign_in_as users(:delta)
      get app_root_path
      assert_response :success

      assert_select "span", text: "약속일 도래", count: 1
      assert_select "article", text: /오늘 입금하기로 한 약속이 있습니다\. 입금되었으면 마감해 주세요\./ do |cards|
        assert_match(/델타파트너스 · 110,000원/, cards.first.text)
      end
      # 미열람 — 신규 1건 + fixtures의 미열람 경과 건(delta_issued 41일·delta_due_soon 11일)까지 3장
      assert_select "span", text: "미열람", count: 3
      assert_select "article", text: /발행한 지 5일째인데 아직 열람 기록이 없습니다\./ do |cards|
        assert_equal 1, cards.size
        assert_match(/델타파트너스 · 110,000원/, cards.first.text)
      end
    end
  end
end
