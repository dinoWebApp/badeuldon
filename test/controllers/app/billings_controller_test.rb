require "test_helper"

# 요금제 페이지(F-PLAN 표면 ② — /app/billing) — 플랜 배지·상태 문구·플랜 비교·수금 패스 목록·
# 체크아웃 전환·PLAN-6 환불 불가 고지. AUTH-1 비인증 가드.
# 시나리오 기준: PRD §6.10 PLAN-1·2·4·6, _workspace/03_implementation.md §1(신규 뷰). 외부 API 호출 없음.
class App::BillingsControllerTest < ActionDispatch::IntegrationTest
  test "비인증 요금제 페이지 접근은 302로 로그인 화면에 리다이렉트된다 (AUTH-1)" do
    get app_billing_path

    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "Free 사용자는 200으로 플랜 카드·한도 문구·체험 CTA를 렌더한다 (PLAN-1)" do
    sign_in_as users(:gamma)  # 구독 행 없음 — 컨트롤러가 즉석 Free 행 생성(레거시 폴백)

    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      get app_billing_path

      assert_response :success
      assert_select "h1", text: "요금제"
      assert_select "span", text: "Free 이용 중", count: 1
      assert_select "p", text: /월 청구 3건 · 거래처 5개 한도로 이용 중입니다/, count: 1
      assert_select "button[type=submit]", text: "Plus 14일 무료 체험 시작", count: 1
      # 플랜 비교 카드 — PLAN-2 수치 원문. 카드 등록 안내문(월 9,900원 자동 결제)과 구분해
      # 비교 카드 문단으로 정확히 매칭한다(테스트 키 credentials 구성 시 안내문도 렌더됨).
      assert_select "p", text: /9,900원 \/ 월 · 부가세 포함/, count: 1
      assert_select "li", text: /무제한 청구·거래처/, count: 1
    end
  end

  test "체험 중 배지는 체험 종료일까지의 무료 안내를 렌더한다 (PLAN-2)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      users(:gamma).create_subscription!(plan: :plus, status: :trialing,
                                         trial_ends_at: Time.zone.parse("2026-10-29 09:00"))
      sign_in_as users(:gamma)
      get app_billing_path

      assert_response :success
      assert_select "span", text: "Plus 체험 중", count: 1
      assert_select "p", text: /까지 무료입니다/, count: 1
      assert_select "button[type=submit]", text: "Plus 14일 무료 체험 시작", count: 0  # 이중 체험 CTA 없음
    end
  end

  test "Plus 이용 중은 해지 버튼과 결제 주기를 렌더하고 체험 CTA가 없다 (PLAN-5)" do
    sign_in_as users(:epsilon)  # subscriptions.yml — plus/active·빌링키 보유

    get app_billing_path

    assert_response :success
    assert_select "span", text: "Plus 이용 중", count: 1
    assert_select "button[type=submit]", text: "Plus 해지", count: 1
    assert_select "p", text: /결제 주기:/, count: 1
    assert_select "button[type=submit]", text: "Plus 14일 무료 체험 시작", count: 0
  end

  test "해지 예정 배지와 만료 배지가 생명주기 상태별로 렌더된다" do
    users(:gamma).create_subscription!(plan: :plus, status: :cancelled,
                                       current_period_end: 5.days.from_now)
    sign_in_as users(:gamma)
    get app_billing_path

    assert_select "span", text: "Plus 해지 예정", count: 1
    assert_select "p", text: /까지 Plus로 이용할 수 있습니다/, count: 1
  end

  test "환불 불가 고지가 렌더된다 (PLAN-6)" do
    sign_in_as users(:gamma)

    get app_billing_path

    assert_response :success
    assert_select "p", text: /구독료·이용권·패스권은 환불되지 않습니다/, count: 1
  end

  test "보유 수금 패스는 잔여·유효기간 요약으로 렌더되고 만료 패스는 제외된다 (PLAN-4)" do
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      users(:delta).payment_passes.create!(total_uses: 10, remaining_uses: 7,
                                           expires_at: 30.days.from_now)
      users(:delta).payment_passes.create!(total_uses: 10, remaining_uses: 10,
                                           expires_at: 1.second.ago)  # 만료 — 목록 제외
      sign_in_as users(:delta)
      get app_billing_path

      assert_response :success
      assert_select "li", text: /잔여 7\/10 · .*까지/, count: 1
      assert_select "li", text: /잔여 10\/10 · 2026-12-30까지/, count: 1  # fixture 패스
      assert_select "p", text: "보유한 수금 패스가 없습니다.", count: 0
    end
  end

  test "본인 대기 주문의 체크아웃은 결제 위젯 파셜을 주문 원값으로 렌더한다 (PLAN-5)" do
    order = users(:delta).orders.create!(product: :collection_pass, amount: 4_000,
                                         toss_order_id: "order-checkout-1")
    sign_in_as users(:delta)

    get app_billing_path(checkout: order.toss_order_id)

    assert_response :success
    assert_select "[data-controller=toss-payment]", count: 1
    assert_select "div[data-toss-payment-order-id-value='order-checkout-1']", count: 1
    assert_select "[data-toss-payment-amount-value='4000']", count: 1
  end

  test "타인의 주문·이미 처리된 주문의 체크아웃 파라미터는 파셜을 렌더하지 않는다 (위조 차단)" do
    other_order = users(:epsilon).orders.create!(product: :collection_pass, amount: 4_000,
                                                 toss_order_id: "order-other-1")
    sign_in_as users(:delta)

    get app_billing_path(checkout: other_order.toss_order_id)     # 타인 주문
    assert_response :success
    assert_select "[data-controller=toss-payment]", count: 0

    get app_billing_path(checkout: orders(:delta_pass_order).toss_order_id)  # 이미 paid
    assert_response :success
    assert_select "[data-controller=toss-payment]", count: 0
  end
end
