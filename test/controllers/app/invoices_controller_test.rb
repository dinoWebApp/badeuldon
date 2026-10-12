require "test_helper"

# 청구서 화면(표면 ② — INV) 통합 테스트 — 초안 CRUD·발행(INV-4)·무효(INV-6)·채번·스냅샷·
# 소유권 격리·위조 품목 id 방어(Phase 6 #4)·행 수 상한(#6)·월 3건 한도(PLAN-1)·UI 뱃지·INV-2 표기.
# 시나리오 기준: _workspace/03_implementation.md §3·Phase 6 수정 이력, _workspace/05_review.md §5.
# 날짜 파생 어설션(연체·뱃지·만기)은 travel_to로 2026-10-12(KST) 기준일을 고정한다(TIME-1).
# fixtures 청구서는 전부 delta 소유 — gamma·alpha·beta는 0건(대시보드 빈 상태·삭제 검증용).
class App::InvoicesControllerTest < ActionDispatch::IntegrationTest
  # fixtures 청구서는 전부 delta 소유(프로필 완료 상태). alpha·beta는 기존 테스트가 사용자·거래처
  # 삭제(FK 연쇄)를 검증하므로 청구서 fixtures를 두면 안 되고, gamma는 대시보드 빈 상태 검증용으로 0건을 유지한다.

  # ── 인증·프로필 가드 ──

  test "비인증 청구서 목록 접근은 로그인 화면으로 리다이렉트된다 (AUTH-1)" do
    get app_invoices_path
    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "프로필 미완료 사용자의 청구서 화면 접근은 프로필 설정으로 안내된다 (AUTH-1.3)" do
    sign_in_as users(:beta)
    get app_invoices_path
    assert_response :redirect
    assert_redirected_to edit_app_profile_path
  end

  # ── 목록·상세 렌더 ──

  test "목록은 소유 청구서만 연체일 내림차순으로 렌더한다 (DASH-4 정렬·소유권)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      get app_invoices_path
    end
    assert_response :success

    numbers = css_select("tbody tr td:first-child a").map(&:text)
    assert_equal [ "BD-20260801-001", "BD-20260815-001", "BD-20260820-001", "BD-20260901-001",
                   "BD-20261001-001", "BD-20260905-001", "BD-20260910-001", "BD-20260915-001",
                   "초안", "초안" ], numbers
    assert_match(/델타파트너스/, response.body)
    assert_no_match(/베타비밀거래처/, response.body)          # 타 사용자 데이터 비노출
  end

  test "상세는 청구 정보·계좌·품목·금액 내역을 렌더하고 토큰을 노출하지 않는다 (INV-1·SHARE-1)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      get app_invoice_path(invoices(:delta_issued))
    end
    assert_response :success

    assert_select "h1", text: "BD-20260901-001"
    assert_select "p", text: "2026-09-01에 발행했습니다."
    assert_select "dd", text: "델타파트너스"
    assert_select "dd", text: "델팀장 님"
    assert_select "dd", text: /2026-10-01/                      # 만기일
    assert_select "dd", text: /연체 11일/                        # 파생 연체 표기(기준일 실측)
    assert_select "dd", text: "테스트발행자"
    assert_select "dd", text: "별도"
    assert_select "dd", text: "110-234-567890"
    assert_select "td", text: "웹 개발"
    assert_select "dd", text: "200,000원"                       # 공급가액
    assert_select "dd", text: "220,000원"                       # 청구 총액
    assert_select "dt", text: "실수령액", count: 0              # 원천징수 미적용 — 실수령액 미표기
    assert_no_match(/#{invoices(:delta_issued).token}/, response.body)  # 링크 미노출(플랜 결정 #1)
  end

  test "원천징수 청구서 상세는 공급가액·원천징수·실수령액 내역을 표기한다 (INV-2)" do
    sign_in_as users(:delta)
    get app_invoice_path(invoices(:delta_viewed))
    assert_response :success

    assert_select "dt", text: "원천징수 (공급가액의 3.3%)"
    assert_select "dd", text: "−1,650원"
    assert_select "dt", text: "실수령액"
    assert_select "dd", text: "53,350원"
    assert_select "p", text: "공급가액의 3.3% 원천징수 후 실수령액 기준으로 안내됩니다."
  end

  test "포함 모드 상세는 부가세 역산 표기를 렌더한다 (INV-1)" do
    sign_in_as users(:delta)
    get app_invoice_path(invoices(:delta_promised))
    assert_response :success
    assert_select "dt", text: "부가세 (총액 포함 — 역산)"
    assert_select "dd", text: "10,000원"
  end

  test "초안 상세는 발행·수정·삭제 액션과 확인 대화상자를 렌더한다 (INV-5)" do
    sign_in_as users(:delta)
    get app_invoice_path(invoices(:delta_draft))
    assert_response :success

    assert_select "p", text: "초안입니다. 발행 전까지 언제든 수정할 수 있습니다."
    assert_select "form.button_to[action=?]", issue_app_invoice_path(invoices(:delta_draft)) do
      assert_select "input[name=_method][value=patch]", count: 1
      assert_select "button[data-turbo-confirm='발행 후에는 내용을 수정할 수 없습니다. 발행하시겠습니까?']",
                    text: "발행하기", count: 1
    end
    assert_select "a[href=?]", edit_app_invoice_path(invoices(:delta_draft)), text: "수정", count: 1
    assert_select "button[data-turbo-confirm='이 초안을 삭제하시겠습니까?']", text: "삭제", count: 1
  end

  test "발행 본 상세는 무효 처리 액션만 렌더한다 (INV-6)" do
    sign_in_as users(:delta)
    get app_invoice_path(invoices(:delta_due_soon))
    assert_response :success

    assert_select "p", text: "2026-10-01에 발행했습니다."
    assert_select "button[data-turbo-confirm='무효 처리한 청구서는 되돌릴 수 없습니다. 무효 처리하시겠습니까?']",
                  text: "무효 처리", count: 1
    assert_select "main button", text: "발행하기", count: 0
    assert_select "main a", text: "수정", count: 0
  end

  test "무효 본 상세는 무효 일자를 안내하고 전환 액션이 없다 (INV-6·Phase 6 #1)" do
    sign_in_as users(:delta)
    get app_invoice_path(invoices(:delta_voided))
    assert_response :success

    # 무효 건은 issued_at이 있어도 무효 일자를 먼저 안내한다(데드 브랜치 수정 검증)
    assert_select "p", text: "2026-09-01에 무효 처리했습니다."
    assert_no_match(/에 발행했습니다/, response.body)
    assert_select "p", text: "무효 처리된 청구서입니다. 필요하면 새 초안을 만들어 다시 발행하세요."
    assert_select "main form.button_to", count: 0
  end

  # ── 초안 CRUD ──

  test "초안 생성은 303으로 상세에 안내되고 발행자 표시명을 서버 기준으로 저장한다 (INV-1)" do
    sign_in_as users(:gamma)
    post app_invoices_path, params: draft_params(
      client_id: clients(:gamma_main).id,
      due_on: (Date.current + 30).to_s,
      rows: [ row ],
      extra: { issuer_display_name: "위조발행자" }
    )
    assert_response :see_other

    invoice = Invoice.order(:id).last
    assert_redirected_to app_invoice_path(invoice)
    assert invoice.draft?
    assert_equal "감마스튜디오", invoice.issuer_display_name     # 파라미터 주입 불가 — 스냅샷
    assert_equal 1, invoice.items.count
  end

  test "포함+원천 조합 초안 저장은 스냅샷 컬럼에 산식값을 저장한다 (금액 통합)" do
    sign_in_as users(:gamma)
    post app_invoices_path, params: draft_params(
      client_id: clients(:gamma_main).id, due_on: (Date.current + 30).to_s,
      tax_mode: "included", withholding: "1",
      rows: [ row(description: "랜딩 제작", unit_price: "55000"),
              row(description: "아이콘 세트", unit_price: "55000") ]
    )
    assert_response :see_other

    invoice = Invoice.order(:id).last.reload
    assert_equal({ subtotal: 100_000, tax_amount: 10_000, total_amount: 110_000,
                   withholding_amount: 3_300, net_amount: 106_700 },
                 invoice.slice(:subtotal, :tax_amount, :total_amount,
                               :withholding_amount, :net_amount).symbolize_keys)
  end

  test "필수 누락 생성은 422와 한글 오류로 거부된다 (Turbo 규약)" do
    sign_in_as users(:gamma)
    post app_invoices_path, params: draft_params(
      client_id: "",
      due_on: (Date.current + 30).to_s,
      rows: [ row(description: "", quantity: "1", unit_price: "100000") ]
    )
    assert_response :unprocessable_entity
    assert_match(/거래처를 선택해 주세요\./, response.body)
    assert_match(/품목 설명을 입력해 주세요\./, response.body)
  end

  test "초안 수정은 303으로 반영하고 금액을 재산정한다 (INV-5 — 초안만 수정)" do
    sign_in_as users(:delta)
    draft = invoices(:delta_draft_two_rows)
    items = draft.items.order(:id)

    patch app_invoice_path(draft), params: draft_params(
      client_id: clients(:delta_main).id,
      due_on: "2026-11-11",
      rows: [ row(id: items.first.id, description: "웹 유지보수", quantity: "1", unit_price: "100000"),
              row(id: items.second.id, description: "디자인 수정", quantity: "3", unit_price: "30000") ]
    )
    assert_response :see_other
    assert_redirected_to app_invoice_path(draft)

    assert_equal "디자인 수정", items.second.reload.description
    assert_equal 3, items.second.quantity
    assert_equal 190_000, draft.reload.subtotal                 # 100,000 + 3×30,000
    assert_equal 209_000, draft.total_amount

    # 수정 화면 거래처 select는 본인 거래처만(소유권 격리)
    get edit_app_invoice_path(draft)
    assert_response :success
    assert_no_match(/감마파트너스/, response.body)
  end

  test "초안 삭제는 303으로 목록에 안내되고 레코드가 제거된다 (INV-5)" do
    sign_in_as users(:delta)
    draft = invoices(:delta_draft_two_rows)

    assert_difference -> { Invoice.count }, -1 do
      delete app_invoice_path(draft)
    end
    assert_response :see_other
    assert_redirected_to app_invoices_path
    assert_equal "청구서 초안이 삭제되었습니다.", flash[:notice]
  end

  test "발행본은 삭제할 수 없다 (INV-5·P4 발행 이력 보존)" do
    sign_in_as users(:delta)
    assert_no_difference -> { Invoice.count } do
      delete app_invoice_path(invoices(:delta_issued))
    end
    assert_response :not_found
  end

  # ── 발행 전환(INV-4) ──

  test "초안 발행은 303으로 전환되고 채번·토큰·만기 재계산을 반영한다 (INV-1·3·SHARE-1/2·Phase 6 #2)" do
    travel_to(Time.zone.parse("2026-10-12 09:00"))
    sign_in_as users(:gamma)
    invoice = create_gamma_draft                              # 만기 프리필 = 작성일+30
    assert invoice.draft?

    # 10일 경과 후 발행 — 미수정 프리필 만기일은 발행일+30으로 재계산된다(Phase 6 #2)
    travel_to(Time.zone.parse("2026-10-22 10:00"))
    patch issue_app_invoice_path(invoice)
    assert_response :see_other
    assert_redirected_to app_invoice_path(invoice)
    assert_equal "청구서가 발행되었습니다.", flash[:notice]
    travel_back

    invoice.reload
    assert invoice.issued?
    assert_equal "BD-20261022-001", invoice.issue_number      # 발행일 기준 채번
    assert_equal 43, invoice.token.length
    assert_equal Date.new(2026, 11, 21), invoice.due_on       # 발행일(10-22)+30 재계산
    assert_equal Time.zone.local(2027, 1, 20).end_of_day.to_i, invoice.token_expires_at.to_i  # 만기+60일
    assert_not_nil invoice.issued_at
  end

  test "발행본 edit·update·destroy·issue 접근은 모두 404다 (INV-5 draft 스코프)" do
    sign_in_as users(:delta)
    invoice = invoices(:delta_issued)

    get edit_app_invoice_path(invoice)
    assert_response :not_found
    patch app_invoice_path(invoice), params: draft_params(client_id: clients(:delta_main).id, rows: [ row ])
    assert_response :not_found
    delete app_invoice_path(invoice)
    assert_response :not_found
    patch issue_app_invoice_path(invoice)
    assert_response :not_found

    assert invoice.reload.issued?
    assert_equal Date.new(2026, 10, 1), invoice.due_on          # 본문 무변경
  end

  # ── 무효 전환(INV-6) ──

  test "발행 본 무효 처리는 303으로 전환되고 토큰을 즉시 폐기한다 (INV-6)" do
    sign_in_as users(:delta)
    invoice = invoices(:delta_issued)

    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      patch void_app_invoice_path(invoice)
    end
    assert_response :see_other
    assert_equal "청구서가 무효 처리되었습니다.", flash[:notice]

    invoice.reload
    assert invoice.voided?
    assert_nil invoice.token                                    # 링크 즉시 폐기
    assert_equal Time.zone.parse("2026-10-12 09:00"), invoice.voided_at
    assert_equal "BD-20260901-001", invoice.issue_number        # 채번 보존(P4)
    assert_equal 220_000, invoice.total_amount                  # 발행 후 금액 동결(무효 후에도)
  end

  test "초안·수금완료·무효 본 무효 요청은 404다 (INV-6 voidable 스코프)" do
    sign_in_as users(:delta)
    [ invoices(:delta_draft), invoices(:delta_paid), invoices(:delta_voided) ].each do |invoice|
      patch void_app_invoice_path(invoice)
      assert_response :not_found
    end

    assert invoices(:delta_draft).reload.draft?
    assert invoices(:delta_paid).reload.paid?
    assert invoices(:delta_voided).reload.voided?
  end

  # ── PLAN-1 월 3건 발행 한도 ──

  test "Free 월 3건 발행 후 4번째 발행은 422 한도 문구로 차단된다 (PLAN-1)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:gamma)
      3.times do
        invoice = create_gamma_draft
        patch issue_app_invoice_path(invoice)
        assert_response :see_other
      end

      fourth = create_gamma_draft
      patch issue_app_invoice_path(fourth)
      assert_response :unprocessable_entity
      assert_select "#alert",
                    text: "Free 플랜은 매월 3건까지 발행할 수 있습니다. Plus로 무제한 이용할 수 있습니다"
      assert fourth.reload.draft?
    end
  end

  test "초안은 한도와 무관하게 생성된다 (PLAN-1 — 초안 무제한)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:gamma)
      4.times do
        post app_invoices_path,
             params: draft_params(client_id: clients(:gamma_main).id, due_on: (Date.current + 30).to_s, rows: [ row ])
        assert_response :see_other
      end
      assert_equal 4, users(:gamma).invoices.draft.count
    end
  end

  # ── 소유권 격리 ──

  test "타 사용자 청구서 전 액션은 404로 거부된다 (소유권 격리)" do
    sign_in_as users(:gamma)
    invoice = invoices(:delta_issued)

    get app_invoice_path(invoice)
    assert_response :not_found
    get edit_app_invoice_path(invoice)
    assert_response :not_found
    patch app_invoice_path(invoice), params: draft_params(client_id: clients(:gamma_main).id, rows: [ row ])
    assert_response :not_found
    delete app_invoice_path(invoice)
    assert_response :not_found
    patch issue_app_invoice_path(invoice)
    assert_response :not_found
    patch void_app_invoice_path(invoice)
    assert_response :not_found

    assert invoice.reload.issued?
    assert_equal "신한은행", invoice.bank_name                   # 값 무변경
  end

  test "타 사용자 거래처로 생성은 422로 거부된다 (client_must_be_owned)" do
    sign_in_as users(:gamma)
    assert_no_difference -> { Invoice.count } do
      post app_invoices_path, params: draft_params(
        client_id: clients(:delta_main).id,
        due_on: (Date.current + 30).to_s,
        rows: [ row ]
      )
    end
    assert_response :unprocessable_entity
    assert_match(/본인의 거래처만 선택할 수 있습니다/, response.body)
  end

  test "목록은 청구서 0건 사용자에게 빈 상태를 렌더한다 (소유권·ONB-1)" do
    sign_in_as users(:gamma)
    get app_invoices_path
    assert_response :success
    assert_select "p", text: "첫 청구서를 발행하세요", count: 1
    assert_no_match(/BD-20260901-001/, response.body)
  end

  # ── 위조 품목 id 방어(Phase 6 #4) ──

  test "위조 품목 id 수정 요청은 500이 아닌 422로 거부된다 (무결성·Phase 6 #4)" do
    sign_in_as users(:delta)
    draft = invoices(:delta_draft_two_rows)
    forged_id = invoices(:delta_issued).items.first.id          # 타 청구서 품목

    assert_no_difference -> { InvoiceItem.count } do
      patch app_invoice_path(draft), params: draft_params(
        client_id: clients(:delta_main).id,
        rows: [ row(id: forged_id, destroy: "1") ]
      )
    end
    assert_response :unprocessable_entity
    assert_match(/유효하지 않은 품목 요청입니다/, response.body)
    assert InvoiceItem.exists?(forged_id)                       # 타 청구서 품목 무영향
    assert_equal 2, draft.reload.items.count                    # 초안 품목 무영향
  end

  test "위조 품목 id 생성 요청은 레코드 없이 422로 거부된다 (무결성·Phase 6 #4)" do
    sign_in_as users(:gamma)
    forged_id = invoice_items(:delta_draft_item).id             # 타인 품목 — 신규엔 보유 항목이 없다

    assert_no_difference -> { Invoice.count } do
      post app_invoices_path, params: draft_params(
        client_id: clients(:gamma_main).id,
        due_on: (Date.current + 30).to_s,
        rows: [ row(id: forged_id) ]
      )
    end
    assert_response :unprocessable_entity
    assert_match(/유효하지 않은 품목 요청입니다/, response.body)
    assert InvoiceItem.exists?(forged_id)
  end

  test "타 사용자 품목 id를 섞은 초안 수정도 422로 거부된다 (소유권·무결성)" do
    sign_in_as users(:gamma)
    draft = create_gamma_draft
    delta_item_id = invoice_items(:delta_draft_item).id

    patch app_invoice_path(draft), params: draft_params(
      client_id: clients(:gamma_main).id,
      rows: [ row(id: delta_item_id, destroy: "1") ]
    )
    assert_response :unprocessable_entity
    assert_match(/유효하지 않은 품목 요청입니다/, response.body)
    assert_equal 1, draft.reload.items.count
  end

  # ── 품목 행 수 상한(Phase 6 #6) ──

  test "품목 100행 초안은 저장되고 101행은 422로 거부된다 (INV-1·Phase 6 #6)" do
    sign_in_as users(:gamma)
    hundred_rows = Array.new(100) { |index| row(description: "품목#{index + 1}", unit_price: "1000") }

    assert_difference -> { InvoiceItem.count }, 100 do
      post app_invoices_path, params: draft_params(
        client_id: clients(:gamma_main).id, due_on: (Date.current + 30).to_s, rows: hundred_rows
      )
    end
    assert_response :see_other

    assert_no_difference -> { Invoice.count } do
      post app_invoices_path, params: draft_params(
        client_id: clients(:gamma_main).id, due_on: (Date.current + 30).to_s, rows: hundred_rows + [ row ]
      )
    end
    assert_response :unprocessable_entity
    assert_match(/품목 행은 최대 100개까지 입력할 수 있습니다/, response.body)
  end

  # ── 상태 뱃지·표기(DESIGN-2·5) ──

  test "목록 상태 뱃지는 상태색과 연체일·tabular 금액을 표기한다 (DESIGN-2·5)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      sign_in_as users(:delta)
      get app_invoices_path
    end
    assert_response :success

    # 상태색 — 연체 주황(파생 1건 + enum 예약값 1건)·수금 완료 녹색·나머지 중립
    assert_select "span.bg-orange-50", text: "연체", count: 2
    assert_select "span", text: "대기 중", count: 2
    assert_select "span", text: "약속 대기", count: 1
    assert_select "span", text: "부분입금", count: 1
    assert_select "span.bg-green-50", text: "수금 완료", count: 1
    assert_select "span", text: "무효", count: 1
    assert_select "span", text: "초안", count: 2
    # 연체일 수치 — 2026-09-01 만기 41일·2026-10-01 만기 11일(주황 강조)
    assert_select "td span.text-orange-600", text: "41일", count: 1
    assert_select "td span.text-orange-600", text: "11일", count: 1
    # 금액 tabular 표기
    assert_select "td.tabular-nums", text: "220,000원", count: 1
  end

  private

  # 폼 전송 형태(인덱스 키 해시)의 품목 행 1개 — 필수값 기본 제공
  def row(description: "웹 개발", quantity: "1", unit_price: "100000", id: nil, destroy: nil)
    attributes = { description: description, quantity: quantity, unit_price: unit_price }
    attributes[:id] = id.to_s if id
    attributes[:_destroy] = destroy if destroy
    attributes
  end

  # 초안 생성·수정 요청 본문 — 품목 행은 인덱스 키 해시(params.expect 문서형 배열 수신 형태)
  def draft_params(client_id:, rows:, due_on: nil, tax_mode: "separate", withholding: "0", extra: {})
    {
      invoice: {
        client_id: client_id, due_on: due_on, tax_mode: tax_mode, withholding_enabled: withholding,
        bank_name: "국민은행", account_number: "123-45-678901", account_holder: "테스트예금주",
        items_attributes: rows.each_with_index.to_h { |attributes, index| [ index.to_s, attributes ] }
      }.merge(extra)
    }
  end

  # gamma 초안 생성 헬퍼 — 303 검증 후 마지막 생성 레코드 반환
  def create_gamma_draft(due_on: (Date.current + 30).to_s)
    post app_invoices_path, params: draft_params(client_id: clients(:gamma_main).id, due_on: due_on, rows: [ row ])
    assert_response :see_other
    Invoice.order(:id).last
  end
end
