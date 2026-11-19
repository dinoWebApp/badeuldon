require "test_helper"

# 영업 직원 대시보드(SALES-6 — F-SALES). 본인 스코프 격리(SALES-7)·총원 표기(W-3)·
# 표시명 노출/이메일 미노출(W-4)·직전월 스냅샷·연도 누적·원천징수 고지(Q24)·noindex(SURF-3).
# 시나리오 기준: PRD §6.20 SALES-6·_workspace/05_review.md §4 Tester 중점 12번.
class Sales::DashboardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @rep = sales_reps(:sales_kim)
  end

  test "대시보드는 본인 타이틀·직함 배지·요율·역할 정책 문구를 표시한다 (SALES-6·1)" do
    sales_login(@rep)
    get sales_root_path

    assert_response :success
    assert_select "h1", text: /김영업님의 실적/
    assert_select "span", text: "CRO" # 직함 배지(표시용 자유 텍스트)
    assert_match(/수수료율 20%/, response.body)
    assert_match(/유치 후 12개월 내 결제분/, response.body, "sales 역할 12개월 캡 고지")
    assert_match(/받을돈 파트너스/, response.body, "SALES-6 자체 레이아웃")
  end

  test "officer 대시보드는 15%·무기한 문구를 표시한다 (Q24 역할 이원화)" do
    sales_login(sales_reps(:officer_park))
    get sales_root_path

    assert_response :success
    assert_match(/수수료율 15%/, response.body)
    assert_match(/기간 제한 없음/, response.body)
  end

  test "현재 추천 코드와 만료 예정일을 표시한다 (SALES-6·2)" do
    sales_login(@rep)
    get sales_root_path

    code = @rep.current_referral_code # fixture — ~Date.current+4까지 유효
    assert_select "input[value=?]", code.code
    assert_match(/#{code.valid_until.strftime("%Y-%m-%d")}까지 유효/, response.body)
    assert_match(/매주 월요일 새로 발급/, response.body)
  end

  test "이번 달 수령 예정(직전월 스냅샷)·상태 배지·연도 누적·원천징수 고지를 표시한다 (SALES-6·Q24)" do
    prev = 1.month.ago
    @rep.sales_commissions.create!(year: prev.year, month: prev.month,
                                   base_amount: 19_800, rate: 20, amount: 3_960, status: :pending)
    @rep.sales_commissions.create!(year: prev.year - 1, month: prev.month,
                                   base_amount: 9_900, rate: 20, amount: 1_980, status: :paid,
                                   paid_at: 1.year.ago)
    sales_login(@rep)
    get sales_root_path

    assert_match(/3,960/, response.body, "직전월 스냅샷 금액 — 이번 달 수령 예정 + 당해년 누적")
    assert_match(/지급 예정/, response.body, "pending 상태 배지")
    assert_match(/5,940/, response.body, "전체 누적(3,960 + 1,980) — 과거 연도 포함")
    assert_match(/원천징수 3\.3%/, response.body, "Q24 오프라인 원천징수 고지")
  end

  test "paid 스냅샷은 지급 완료 배지로 표시된다 (SALES-6)" do
    prev = 1.month.ago
    @rep.sales_commissions.create!(year: prev.year, month: prev.month,
                                   base_amount: 9_900, rate: 20, amount: 1_980,
                                   status: :paid, paid_at: Time.current)
    sales_login(@rep)
    get sales_root_path

    assert_match(/지급 완료/, response.body)
    assert_no_match(/지급 예정/, response.body)
  end

  test "내 사용자 목록은 표시명·가입일·요금제·상태만 노출하고 이메일은 노출하지 않는다 (SALES-6·W-4)" do
    referred = User.create!(email: "referred-visible@example.com", password: "password123",
                            display_name: "유치사용자A", referred_by_sales_rep_id: @rep.id)
    referred.subscription.update!(plan: :plus) # after_create Free 구독을 Plus로 전환
    User.create!(email: "referred-noname@example.com", password: "password123",
                 referred_by_sales_rep_id: @rep.id) # 표시명 미설정 — 폴백 표기 대상
    sales_login(@rep)
    get sales_root_path

    assert_response :success
    assert_match(/유치사용자A/, response.body, "표시명 노출(W-4 — SALES-6 명세)")
    assert_match(/미설정/, response.body, "표시명 미설정 유저 폴백")
    assert_match(/Plus/, response.body)
    users_section = css_select("section[aria-labelledby='users-heading']").first.to_s
    assert_not_includes users_section, referred.email, "이메일 미노출(W-4 — 개인정보 최소 수집)"
  end

  test "유치 사용자 총원은 count 기준으로 표기하고 목록은 최근 30명이다 (W-3)" do
    digest = BCrypt::Password.create("password")
    31.times do |i|
      User.create!(email: "bulk-referred-#{i}@example.com", password_digest: digest,
                   display_name: "벌크#{i}", referred_by_sales_rep_id: @rep.id,
                   created_at: (32 - i).days.ago)
    end
    sales_login(@rep)
    get sales_root_path

    assert_response :success
    assert_match(/총 31명/, response.body, "W-3 — limit(30).size 과소 표기 수정 검증")
    assert_match(/목록은 최근 30명 표시/, response.body)
    assert_select "section[aria-labelledby='users-heading'] tbody tr", count: 30
  end

  test "타 rep의 유치 사용자와 정산 스냅샷은 노출되지 않는다 (SALES-7 스코프 격리 — 2계정 교차)" do
    other = sales_reps(:officer_park)
    User.create!(email: "other-referred@example.com", password: "password123",
                 display_name: "타rep유치", referred_by_sales_rep_id: other.id)
    prev = 1.month.ago
    other.sales_commissions.create!(year: prev.year, month: prev.month,
                                    base_amount: 99_000, rate: 15, amount: 14_850)
    User.create!(email: "my-referred@example.com", password: "password123",
                 display_name: "내유치", referred_by_sales_rep_id: @rep.id)

    sales_login(@rep)
    get sales_root_path
    assert_response :success
    assert_match(/내유치/, response.body)
    assert_no_match(/타rep유치/, response.body, "타 rep 유치 사용자 미노출")
    assert_no_match(/14,850/, response.body, "타 rep 정산 스냅샷 미노출")
    assert_no_match(/99,000/, response.body)

    # 교차 — 상대 rep 시점에서도 동일하다
    sales_login(other)
    get sales_root_path
    assert_response :success
    assert_match(/타rep유치/, response.body)
    assert_match(/14,850/, response.body)
    assert_no_match(/내유치/, response.body)
  end

  test "/sales 응답은 noindex 메타를 출력하고 robots.txt는 /sales를 차단한다 (SURF-3)" do
    sales_login(@rep)
    get sales_root_path

    assert_response :success
    assert_select "meta[name=robots]" do |metas|
      assert_equal 1, metas.size
      assert_match(/noindex/, metas.first["content"])
    end

    robots = File.read(Rails.root.join("public/robots.txt"))
    assert_includes robots, "Disallow: /sales"
  end

  test "가입 폼(공개 표면)은 색인 허용을 유지한다 (SURF-3 역방향 — 리뷰 중점 11)" do
    get new_registration_path
    assert_response :success
    assert_select "meta[name=robots]", count: 0
  end
end
