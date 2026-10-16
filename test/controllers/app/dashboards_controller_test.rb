require "test_helper"

# 표면 ② /app 대시보드 — DASH-1 실데이터 요약 카드(미수 총액·연체 건수·금액·7일 내 만기),
# DASH-4 목록(연체일 내림차순 상위 5건), ONB-1 CTA 실링크·보유 전환, 사이드바·헤더 크롬,
# AUTH-1 비인증 가드, AUTH-1.3 미완료 프로필 가드(03 §4.1), SURF-3 noindex.
# 시나리오 기준: _workspace/03_implementation.md(ONB-1·DASH 전환), 05_review.md 「Tester 중점 §6」.
# 집계·경계일 검증은 travel_to로 2026-10-12(KST) 기준일을 고정한다(TIME-1).
class App::DashboardsControllerTest < ActionDispatch::IntegrationTest
  test "비인증 /app 접근은 302로 로그인 화면에 리다이렉트된다 (AUTH-1)" do
    get app_root_path
    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "프로필 미완료 사용자의 /app 접근은 플래시·배너·잠금 내비로 안내된다 (AUTH-1.3 가드)" do
    sign_in_as users(:alpha)
    get app_root_path
    assert_response :redirect
    assert_redirected_to edit_app_profile_path
    # 조용한 리다이렉트 금지 — 클릭이 반응한 이유를 플래시로 전달
    assert_equal "안전한 청구 발행을 위해 프로필을 먼저 완성해 주세요.", flash[:alert]

    follow_redirect!
    assert_response :success
    # 온보딩 배너 — '고장'이 아닌 '시작 단계'로 인식시킨다
    assert_select "div[role=status]", text: /받을돈 시작하기/
    assert_select "div[role=status]", text: /프로필을 완성하면/, count: 1
    # 잠금 내비 — 설정 제외 5개 메뉴는 자물쇠 스타일 링크(클릭 가능·가드가 안내)
    assert_select "nav a[aria-disabled='true']", count: 5
    assert_select "nav a[aria-disabled='true'][href=?]", app_invoices_path, text: "청구서", count: 1
    assert_select "nav a[aria-disabled='true'][href=?]", edit_app_profile_path, count: 0
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

  test "청구서 0건 사용자의 DASH-1 카드는 빈 상태 문구로 렌더되고 0원을 표기하지 않는다" do
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

  test "DASH-1 요약 카드는 실데이터 수치를 표시하고 초안·지급완료·무효를 제외한다 (DASH-1)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:gamma)
      seed_invoice(label: "a", due_on: Date.current - 5, rows: [ [ 1, 220_000 ] ])  # 연체(파생)
      seed_invoice(label: "b", due_on: Date.current, rows: [ [ 1, 110_000 ] ])      # 오늘 만기 — 7일 내
      seed_invoice(label: "c", due_on: Date.current + 3, rows: [ [ 1, 66_000 ] ])   # 7일 내
      seed_invoice(label: "d", due_on: Date.current + 20, rows: [ [ 1, 55_000 ] ])
      seed_invoice(label: "e", due_on: Date.current - 1, status: :paid)             # 미수 제외
      seed_invoice(label: "f", due_on: Date.current - 1, status: :voided)           # 미수 제외
      seed_invoice(label: "g", due_on: Date.current + 30, status: :draft, rows: [ [ 1, 999_000 ] ])  # 제외

      get app_root_path
      assert_response :success

      # 미수 총액 = 총액 기준(별도 10% 포함) 242,000 + 121,000 + 72,600 + 60,500
      # — 초안 999,000×1.1이 섞이면 불일치로 검출된다
      assert_select "article", text: /미수 총액/ do
        assert_select "p", text: "496,100원", count: 1
      end
      assert_select "article", text: /연체 건수·금액/ do
        assert_select "p", text: "1건", count: 1
        assert_select "span", text: "242,000원", count: 1
      end
      assert_select "article", text: /7일 내 만기/ do
        assert_select "p", text: "2건", count: 1
      end
      # 실데이터 전환 — 빈 상태 문구 소멸
      assert_select "p", text: "청구서를 발행하면 여기에 표시됩니다.", count: 0
    end
  end

  test "7일 내 만기는 오늘과 +7일을 포함하고 +8일부터 제외한다 (DASH-1 경계)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:gamma)
      seed_invoice(label: "a", due_on: Date.current)          # 오늘 — 포함
      seed_invoice(label: "b", due_on: Date.current + 7)      # +7 — 포함
      seed_invoice(label: "c", due_on: Date.current + 8)      # +8 — 제외
      seed_invoice(label: "d", due_on: Date.current - 1)      # 연체 — 범위 밖

      get app_root_path
      assert_response :success
      assert_select "article", text: /7일 내 만기/ do
        assert_select "p", text: "2건", count: 1
      end
      assert_select "article", text: /연체 건수·금액/ do
        assert_select "p", text: "1건", count: 1
      end
    end
  end

  test "초안만 보유한 사용자의 카드는 실측 0원을 표시한다 (DASH-1 — 빈 상태 아님)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:gamma)
      seed_invoice(label: "a", due_on: Date.current + 10, status: :draft, rows: [ [ 1, 300_000 ] ])

      get app_root_path
      assert_response :success
      assert_select "article", text: /미수 총액/ do
        assert_select "p", text: "0원", count: 1              # 초안은 미수 아님 — 실측 0원
      end
      assert_select "article", text: /연체 건수·금액/ do
        assert_select "p", text: "0건", count: 1
      end
      # @has_invoices는 초안 포함 — CTA는 관리 분기
      assert_select "h2", text: "발행한 청구서를 관리합니다", count: 1
    end
  end

  test "DASH-2 오늘의 액션은 빈 상태 안내를 렌더한다" do
    sign_in_as users(:gamma)
    get app_root_path
    assert_response :success
    assert_select "p", text: "오늘 할 일이 없습니다", count: 1
    assert_select "p", text: /오늘 발송 예정·약속일 도래/, count: 1
  end

  test "ONB-1 첫 발행 CTA는 신규 발행 화면 실링크로 활성화된다 (ONB-1)" do
    sign_in_as users(:gamma)
    get app_root_path
    assert_response :success
    assert_select "h2", text: "3분이면 첫 청구서를 발행합니다", count: 1
    # F-INV 오픈 — disabled 버튼·준비 중 배지 제거, 발행 화면 실링크
    assert_select "button[disabled]", count: 0
    assert_select "button[aria-disabled='true']", count: 0
    assert_select "p", text: "준비 중 — 청구서 기능과 함께 열립니다", count: 0
    assert_select "a[href=?]", new_app_invoice_path, text: "첫 청구서 발행하기", count: 1
  end

  test "ONB-1 CTA는 청구서 보유 시 목록 안내로 전환된다 (ONB-1)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:gamma)
      seed_invoice(label: "a", due_on: Date.current + 5)

      get app_root_path
      assert_response :success
      assert_select "h2", text: "발행한 청구서를 관리합니다", count: 1
      assert_select "a[href=?]", app_invoices_path, text: "청구서 전체 보기", count: 1
      assert_select "a[href=?]", new_app_invoice_path, text: "첫 청구서 발행하기", count: 0
      # DASH-4 목록이 실제 행을 렌더한다
      assert_select "section[aria-labelledby='dash-invoices'] tbody tr", count: 1
    end
  end

  test "DASH-4 목록은 연체일 내림차순 상위 5건만 표시한다 (DASH-4)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:gamma)
      seed_invoice(label: "a", due_on: Date.current - 3, rows: [ [ 1, 10_000 ] ])  # 연체 — 최상단
      seed_invoice(label: "b", due_on: Date.current + 15, rows: [ [ 1, 10_000 ] ])
      seed_invoice(label: "c", due_on: Date.current + 20, rows: [ [ 1, 10_000 ] ])
      seed_invoice(label: "d", due_on: Date.current + 25, rows: [ [ 1, 10_000 ] ])
      seed_invoice(label: "e", due_on: Date.current + 31, rows: [ [ 1, 10_000 ] ])
      seed_invoice(label: "f", due_on: Date.current + 40, rows: [ [ 1, 10_000 ] ])  # 6번째 — 탈락
      seed_invoice(label: "g", due_on: Date.current + 2, rows: [ [ 1, 10_000 ] ])

      get app_root_path
      assert_response :success
      # 만기일 오름차순 = 연체일 내림차순: -3, +2, +15, +20, +25 — +31·+40은 탈락
      numbers = css_select("section[aria-labelledby='dash-invoices'] tbody tr td:first-child a").map(&:text)
      assert_equal [ "BD-20990101-a", "BD-20990101-g", "BD-20990101-b", "BD-20990101-c",
                     "BD-20990101-d" ], numbers
    end
  end

  test "사이드바는 대시보드 활성 표시와 거래처·품목·청구서·설정 실링크를 렌더한다 (CLIENT-1·2·INV 전환)" do
    sign_in_as users(:gamma)
    get app_root_path
    assert_response :success

    # 활성 내비 — 대시보드만 aria-current="page"(경로 기반 판정)
    assert_select "nav a[aria-current='page']", text: "대시보드", count: 1
    assert_select "nav a[aria-current='page'][href=?]", app_clients_path, count: 0
    assert_select "nav a[aria-current='page'][href=?]", app_items_path, count: 0
    assert_select "nav a[aria-current='page'][href=?]", edit_app_profile_path, count: 0
    # 청구서 — 준비 중 배지에서 실링크로 전환(INV 오픈)
    assert_select "nav span[aria-disabled='true']", count: 0
    assert_select "nav span", text: "준비 중", count: 0
    assert_select "nav a[href=?]", app_invoices_path, text: "청구서", count: 1
    # 거래처·품목·설정 실링크
    assert_select "nav a[href=?]", app_clients_path, text: "거래처", count: 1
    assert_select "nav a[href=?]", app_items_path, text: "품목", count: 1
    assert_select "nav a[href=?]", edit_app_profile_path, text: "설정", count: 1
  end

  test "사이드바 활성 표시는 거래처·품목 화면에 따라 분기된다 (aria-current)" do
    sign_in_as users(:gamma)

    get app_clients_path
    assert_response :success
    assert_select "nav a[aria-current='page'][href=?]", app_clients_path, text: "거래처", count: 1
    assert_select "nav a[aria-current='page'][href=?]", app_root_path, count: 0
    assert_select "nav a[aria-current='page'][href=?]", app_items_path, count: 0

    get app_items_path
    assert_response :success
    assert_select "nav a[aria-current='page'][href=?]", app_items_path, text: "품목", count: 1
    assert_select "nav a[aria-current='page'][href=?]", app_clients_path, count: 0
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

  private

  # 집계 검증용 청구서 시드 — issue!를 쓰면 PLAN-1 월 3건 검증이 개입하므로 상태를 직접 세팅한다.
  # 검증 대상은 집계 스코프·카드 수치이며 발행 플로우 자체는 invoices_controller_test가 담당한다.
  def seed_invoice(label:, due_on:, status: :issued, rows: [ [ 1, 100_000 ] ])
    issued_family = Invoice.new(status: status).unsettled? || status.to_s == "paid"
    users(:gamma).invoices.create!(
      client: clients(:gamma_main), due_on: due_on, status: status,
      tax_mode: :separate, withholding_enabled: false,
      issuer_display_name: users(:gamma).display_name,
      bank_name: users(:gamma).bank_name, account_number: users(:gamma).account_number,
      account_holder: users(:gamma).account_holder,
      issue_number: (issued_family ? "BD-20990101-#{label}" : nil),
      token: (status.to_s == "voided" ? nil : (issued_family ? SecureRandom.urlsafe_base64(32) : nil)),
      issued_at: (issued_family ? Time.current : nil),
      items_attributes: rows.each_with_index.to_h do |(quantity, unit_price), index|
        [ index.to_s, { description: "시드 품목#{index + 1}", quantity: quantity.to_s, unit_price: unit_price.to_s } ]
      end
    ).reload
  end
end
