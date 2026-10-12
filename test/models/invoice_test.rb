require "test_helper"

# 청구서 도메인 모델 테스트 — 금액 산식(03 §2 명세)·INV-1 채번·INV-3 만기 재계산·INV-4 파생 연체·
# INV-5 발행본 본문 불변(모델 가드)·INV-6 무효 전이·PLAN-1 월 한도·품목 행 상한.
# 시나리오 기준: _workspace/03_implementation.md §2·§3·Phase 6 수정 이력, _workspace/05_review.md §2·§5.
# 시간 의존 검증은 travel_to로 KST(2026-10-12 기준)를 고정한다(TIME-1). 외부 API 호출 없음.
class InvoiceTest < ActiveSupport::TestCase
  # ── 금액 산식(Invoice.compute_amounts — 정수 원 단일 지점) ──

  test "금액 산식 — 별도 모드는 행 합계를 공급가액으로 부가세 10%를 더한다" do
    assert_equal(
      { subtotal: 100_000, tax_amount: 10_000, total_amount: 110_000,
        withholding_amount: 0, net_amount: 110_000 },
      Invoice.compute_amounts([ 100_000 ], tax_mode: :separate, withholding_enabled: false)
    )
  end

  test "금액 산식 — 부가세 사사오입 경계(104→10·105→11·정확반 15→2)" do
    assert_equal 10, Invoice.compute_amounts([ 104 ], tax_mode: :separate, withholding_enabled: false)[:tax_amount]
    assert_equal 11, Invoice.compute_amounts([ 105 ], tax_mode: :separate, withholding_enabled: false)[:tax_amount]
    assert_equal 2, Invoice.compute_amounts([ 15 ], tax_mode: :separate, withholding_enabled: false)[:tax_amount]
  end

  test "금액 산식 — 포함 모드는 총액을 1.1로 역분해하고 총액을 보존한다" do
    assert_equal(
      { subtotal: 1_000_000, tax_amount: 100_000, total_amount: 1_100_000,
        withholding_amount: 0, net_amount: 1_100_000 },
      Invoice.compute_amounts([ 1_100_000 ], tax_mode: :included, withholding_enabled: false)
    )
    # 극소 경계 — 109→공급 99·부가세 10, 11→공급 10·부가세 1, 1→공급 1·부가세 0
    assert_equal 99, Invoice.compute_amounts([ 109 ], tax_mode: :included, withholding_enabled: false)[:subtotal]
    assert_equal 109, Invoice.compute_amounts([ 109 ], tax_mode: :included, withholding_enabled: false)[:total_amount]
    assert_equal 10, Invoice.compute_amounts([ 11 ], tax_mode: :included, withholding_enabled: false)[:subtotal]
    assert_equal 1, Invoice.compute_amounts([ 11 ], tax_mode: :included, withholding_enabled: false)[:tax_amount]
    assert_equal({ subtotal: 1, tax_amount: 0, total_amount: 1 },
                 Invoice.compute_amounts([ 1 ], tax_mode: :included, withholding_enabled: false)
                        .slice(:subtotal, :tax_amount, :total_amount))
  end

  test "금액 산식 — 원천징수는 공급가액의 3.3%를 원 단위 내림한다(결정 #4)" do
    # 경계: 101→3 · 10,000→330 · 33→1 · 1,000→33 · 100→3 · 1→0
    { 101 => 3, 10_000 => 330, 33 => 1, 1_000 => 33, 100 => 3, 1 => 0 }.each do |subtotal, expected|
      amounts = Invoice.compute_amounts([ subtotal ], tax_mode: :separate, withholding_enabled: true)
      assert_equal expected, amounts[:withholding_amount],
                   "공급가액 #{subtotal}원의 원천징수 내림 불일치"
    end
  end

  test "금액 산식 — 별도·포함 × 원천징수 on/off 4조합(행 합계 110,000)" do
    separate_off = Invoice.compute_amounts([ 110_000 ], tax_mode: :separate, withholding_enabled: false)
    assert_equal({ subtotal: 110_000, tax_amount: 11_000, total_amount: 121_000,
                   withholding_amount: 0, net_amount: 121_000 }, separate_off)

    separate_on = Invoice.compute_amounts([ 110_000 ], tax_mode: :separate, withholding_enabled: true)
    assert_equal({ subtotal: 110_000, tax_amount: 11_000, total_amount: 121_000,
                   withholding_amount: 3_630, net_amount: 117_370 }, separate_on)

    included_off = Invoice.compute_amounts([ 110_000 ], tax_mode: :included, withholding_enabled: false)
    assert_equal({ subtotal: 100_000, tax_amount: 10_000, total_amount: 110_000,
                   withholding_amount: 0, net_amount: 110_000 }, included_off)

    # 03 §2 러너 실측값 — 포함+원천 110,000 → 실수령 106,700
    included_on = Invoice.compute_amounts([ 110_000 ], tax_mode: :included, withholding_enabled: true)
    assert_equal({ subtotal: 100_000, tax_amount: 10_000, total_amount: 110_000,
                   withholding_amount: 3_300, net_amount: 106_700 }, included_on)
  end

  test "금액 산식 — 0원 행은 전 컬럼 0원이다" do
    [ [ :separate, false ], [ :separate, true ], [ :included, false ], [ :included, true ] ].each do |tax_mode, withholding|
      amounts = Invoice.compute_amounts([ 0, 0 ], tax_mode: tax_mode, withholding_enabled: withholding)
      assert_equal({ subtotal: 0, tax_amount: 0, total_amount: 0,
                     withholding_amount: 0, net_amount: 0 }, amounts)
    end
  end

  test "금액 산식 — 복수 행 합계와 50행 원천징수 내림이 정확하다" do
    # 3행 Σ130,456 → 부가세 (130456+5)/10 = 13,046
    amounts = Invoice.compute_amounts([ 43_456, 50_000, 37_000 ], tax_mode: :separate, withholding_enabled: false)
    assert_equal 13_046, amounts[:tax_amount]
    assert_equal 143_502, amounts[:total_amount]

    # 50행 Σ1,275,000 → 원천 내림 42,075·실수령 = 총액 1,402,500 − 42,075 = 1,360,425
    rows = Array.new(50, 25_500)
    amounts = Invoice.compute_amounts(rows, tax_mode: :separate, withholding_enabled: true)
    assert_equal 1_275_000, amounts[:subtotal]
    assert_equal 42_075, amounts[:withholding_amount]
    assert_equal 1_360_425, amounts[:net_amount]
  end

  test "금액 산식 — 상한 조합(수량 10,000×단가 1e9)에서도 64bit 정수로 정확하다" do
    max_row = [ InvoiceItem::MAX_QUANTITY * InvoiceItem::MAX_UNIT_PRICE ]

    separate = Invoice.compute_amounts(max_row, tax_mode: :separate, withholding_enabled: false)
    assert_equal({ subtotal: 10_000_000_000_000, tax_amount: 1_000_000_000_000,
                   total_amount: 11_000_000_000_000, withholding_amount: 0,
                   net_amount: 11_000_000_000_000 }, separate)

    included_on = Invoice.compute_amounts(max_row, tax_mode: :included, withholding_enabled: true)
    assert_equal({ subtotal: 9_090_909_090_909, tax_amount: 909_090_909_091,
                   total_amount: 10_000_000_000_000, withholding_amount: 299_999_999_999,
                   net_amount: 9_700_000_000_001 }, included_on)
  end

  # ── 저장 스냅샷(before_validation :recalculate_amounts) — 컬럼 저장값 검증 ──

  test "저장 시 품목 행에서 금액 5컬럼이 재산정·스냅샷된다(포함+원천 조합)" do
    invoice = Invoice.create!(invoice_attributes(due_on: Date.current + 30,
                                                 tax_mode: :included,
                                                 withholding: true,
                                                 rows: [ [ 1, 55_000 ], [ 1, 55_000 ] ]))
    invoice.reload
    assert_equal({ subtotal: 100_000, tax_amount: 10_000, total_amount: 110_000,
                   withholding_amount: 3_300, net_amount: 106_700 },
                 invoice.slice(:subtotal, :tax_amount, :total_amount,
                               :withholding_amount, :net_amount).symbolize_keys)
  end

  test "삭제 예정 행은 금액 재산정에서 제외되고 행이 제거된다" do
    invoice = Invoice.create!(invoice_attributes(due_on: Date.current + 30,
                                                 rows: [ [ 1, 100_000 ], [ 2, 25_000 ] ]))
    assert_equal 165_000, invoice.reload.total_amount

    removed_id = invoice.items.order(:id).second.id
    invoice.update!(items_attributes: { removed_id.to_s => { id: removed_id, _destroy: "1" } })
    invoice.reload
    assert_equal 1, invoice.items.count
    assert_equal 100_000, invoice.subtotal
    assert_equal 110_000, invoice.total_amount
  end

  test "모든 행이 0원이면 총액 0원으로 저장된다" do
    invoice = Invoice.create!(invoice_attributes(due_on: Date.current + 30, rows: [ [ 3, 0 ] ]))
    assert_equal 0, invoice.reload.total_amount
  end

  # ── INV-1 채번 ──

  test "발행 시 BD-YYYYMMDD-NNN 형식으로 채번하고 토큰·발행 시각을 발급한다(INV-1·SHARE-1)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      invoice = create_and_issue!(due_on: Date.current + 30)
      assert_equal "BD-20261012-001", invoice.issue_number
      assert_match(/\ABD-\d{8}-\d{3,}\z/, invoice.issue_number)
      assert_equal 43, invoice.token.length                                   # ≈256bit
      assert_match(/\A[A-Za-z0-9_-]+\z/, invoice.token)                       # urlsafe
      assert invoice.issued?
      assert_equal Time.zone.parse("2026-10-12 09:00"), invoice.issued_at
      assert_equal Time.zone.local(2027, 1, 10).end_of_day.to_i, invoice.token_expires_at.to_i  # 만기+60일 end_of_day
    end
  end

  test "일별 순번은 같은 날 발행 건에 연속으로 매겨진다(INV-1)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      first = create_and_issue!(due_on: Date.current + 30)
      second = create_and_issue!(due_on: Date.current + 45)
      assert_equal "BD-20261012-001", first.issue_number
      assert_equal "BD-20261012-002", second.issue_number
    end
  end

  test "채번 순번은 사용자와 무관하게 서비스 전역으로 공유된다(INV-1)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      gamma_invoice = create_and_issue!(due_on: Date.current + 30)
      delta_invoice = create_and_issue!(due_on: Date.current + 30, user: users(:alpha),
                                        client: clients(:alpha_client_1))
      assert_equal "BD-20261012-001", gamma_invoice.issue_number
      assert_equal "BD-20261012-002", delta_invoice.issue_number
    end
  end

  test "채번 일자는 KST 기준 — 자정 경계에서 다음 일자로 채번된다(INV-1·TIME-1)" do
    travel_to(Time.zone.parse("2026-10-12 23:59:59")) do
      assert_equal "BD-20261012-001", create_and_issue!(due_on: Date.current + 30).issue_number
    end
    # KST 10-13 00:30 = UTC 10-12 15:30 — UTC 기준이면 BD-20261012-가 나오므로 KST 판정 근거가 된다
    travel_to(Time.zone.parse("2026-10-13 00:30:00")) do
      assert_equal "BD-20261013-001", create_and_issue!(due_on: Date.current + 30).issue_number
    end
  end

  # ── INV-3 만기일 — 미수정 프리필은 발행일+30으로 재계산(Phase 6 #2) ──

  test "10일 경과한 프리필 초안 발행 시 만기일은 발행일+30일로 재계산된다(INV-3)" do
    invoice = nil
    travel_to(Time.zone.parse("2026-10-02 10:00")) do
      invoice = Invoice.create!(invoice_attributes(due_on: Date.current + 30))  # 프리필 원값 11-01
    end
    travel_to(Time.zone.parse("2026-10-12 10:00")) do
      assert invoice.issue!, -> { invoice.errors.full_messages.join(", ") }
      invoice.reload
      assert_equal Date.new(2026, 11, 11), invoice.due_on                     # 발행일(10-12)+30
      assert_equal Time.zone.local(2027, 1, 10).end_of_day.to_i, invoice.token_expires_at.to_i
    end
  end

  test "명시적으로 수정한 만기일은 발행 시 존중된다(INV-3)" do
    invoice = nil
    travel_to(Time.zone.parse("2026-10-02 10:00")) do
      invoice = Invoice.create!(invoice_attributes(due_on: Date.current + 45))  # 11-16 ≠ 프리필 11-01
    end
    travel_to(Time.zone.parse("2026-10-12 10:00")) do
      assert invoice.issue!, -> { invoice.errors.full_messages.join(", ") }
      assert_equal Date.new(2026, 11, 16), invoice.reload.due_on
    end
  end

  test "당일 작성·당일 발행 초안의 만기일은 발행일+30일이다(INV-3)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      invoice = create_and_issue!(due_on: Date.current + 30)
      assert_equal Date.current + 30, invoice.due_on
    end
  end

  # ── INV-4 파생 연체 판정·스코프 ──

  test "만기 당일은 연체가 아니고 익일부터 연체로 판정된다(INV-4 파생)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      due_today = create_and_issue!(due_on: Date.current)
      due_yesterday = create_and_issue!(due_on: Date.current - 1)

      assert_not due_today.overdue?
      assert_equal 0, due_today.days_overdue
      assert due_yesterday.overdue?
      assert_equal 1, due_yesterday.days_overdue
    end
  end

  test "unsettled·overdue·due_within·voidable 스코프는 상태·만기일 기준으로 집계된다" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      invoices_scope = users(:delta).invoices
      # 미수 = 발행 계열 6건 — 초안 2·수금완료·무효 제외
      assert_equal 6, invoices_scope.unsettled.count
      # 연체(파생) = 발행 계열 && 만기일 < 오늘 — issued(10-01)·overdue enum(09-01)
      assert_equal [ invoices(:delta_issued).id, invoices(:delta_overdue).id ].sort,
                   invoices_scope.overdue.order(:id).ids
      # 7일 내 만기 — due_soon(10-15)만 해당, 연체 건(10-01 이전) 제외
      assert_equal [ invoices(:delta_due_soon).id ],
                   invoices_scope.due_within(Date.current..Date.current + 7).ids
      # 무효 가능 = 발행 계열 6건
      assert_equal 6, invoices_scope.voidable.count
    end
  end

  test "sorted_by_due는 만기일 오름차순(연체일 내림차순)으로 정렬된다(DASH-4)" do
    expected = %i[delta_overdue delta_voided delta_paid delta_issued delta_due_soon
                  delta_viewed delta_promised delta_partially_paid].map { |fixture| invoices(fixture).id }
    expected += [ invoices(:delta_draft).id, invoices(:delta_draft_two_rows).id ].sort  # 같은 만기일 — id순(병렬 PK는 YAML 순서 비보장)
    assert_equal expected, users(:delta).invoices.sorted_by_due.ids
  end

  # ── INV-5 발행본 본문 불변(모델 레벨 가드 — Phase 6 #5) ──

  test "발행본 update! 본문 변경은 RecordNotSaved로 차단된다(INV-5·기술 노트 5)" do
    invoice = invoices(:delta_issued)
    assert_raises(ActiveRecord::RecordNotSaved) do
      invoice.update!(bank_name: "국민은행")
    end
    assert_equal "신한은행", invoice.reload.bank_name
  end

  test "발행본 update 본문 변경은 false와 base 오류로 차단된다(INV-5)" do
    invoice = invoices(:delta_issued)
    assert_not invoice.update(due_on: Date.new(2026, 12, 1))
    assert_includes invoice.errors[:base], "발행된 청구서는 내용을 수정할 수 없습니다"
    assert_equal Date.new(2026, 10, 1), invoice.reload.due_on
  end

  test "발행본 품목 행 변경도 모델 가드로 차단된다(INV-5)" do
    invoice = invoices(:delta_issued)
    item_id = invoice.items.first.id
    assert_raises(ActiveRecord::RecordNotSaved) do
      invoice.update!(items_attributes: { item_id.to_s => { id: item_id, quantity: "99" } })
    end
    assert_equal 1, invoice.reload.items.first.quantity
  end

  test "발행본 무변경 저장은 통과하고 무효 전이도 허용된다(INV-5 가드 예외 경로)" do
    invoice = invoices(:delta_issued)
    assert_no_changes -> { invoice.reload.updated_at } do
      assert invoice.save!
    end
    assert invoice.void!
  end

  # ── INV-6 무효 전이 ──

  test "voidable 판정은 발행 계열만 true다 — enum 예약 상태 fixtures 직접 세팅 검증(INV-6)" do
    assert_not invoices(:delta_draft).voidable?
    assert invoices(:delta_issued).voidable?
    assert invoices(:delta_overdue).voidable?            # 연체 enum 예약값
    assert invoices(:delta_due_soon).voidable?
    assert invoices(:delta_viewed).voidable?
    assert invoices(:delta_promised).voidable?
    assert invoices(:delta_partially_paid).voidable?
    assert_not invoices(:delta_paid).voidable?           # 수금완료는 종결
    assert_not invoices(:delta_voided).voidable?
  end

  test "무효 처리는 voided로 전이하고 토큰을 즉시 폐기한다(INV-6)" do
    invoice = invoices(:delta_viewed)
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      assert invoice.void!
    end
    invoice.reload
    assert invoice.voided?
    assert_nil invoice.token
    assert_equal Time.zone.parse("2026-10-12 09:00"), invoice.voided_at
    assert_equal "BD-20260905-001", invoice.issue_number                  # 채번 보존(P4 발행 이력)
    assert_equal 55_000, invoice.total_amount                             # 금액 동결
  end

  test "무효 본·초안·수금완료 본의 무효 처리는 거부된다(INV-6)" do
    { delta_voided: invoices(:delta_voided),
      delta_draft: invoices(:delta_draft),
      delta_paid: invoices(:delta_paid) }.each_value do |invoice|
      assert_not invoice.void!
      assert_includes invoice.errors[:base], "발행된 청구서만 무효 처리할 수 있습니다"
    end
    assert invoices(:delta_voided).reload.voided?
    assert invoices(:delta_draft).reload.draft?
    assert invoices(:delta_paid).reload.paid?
  end

  test "재발행은 거부된다 — 발행본·무효본 모두(INV-4)" do
    issued = invoices(:delta_issued)
    assert_not issued.draft?
    assert_not issued.issue!
    assert issued.reload.issued?

    voided = invoices(:delta_viewed)
    assert voided.void!
    assert_not voided.reload.issue!
  end

  # ── PLAN-1 월 3건 발행 한도 ──

  test "Free는 월 3건까지 발행하고 4번째는 한도 문구로 거부된다(PLAN-1)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      3.times { create_and_issue!(due_on: Date.current + 30) }
      fourth = Invoice.new(invoice_attributes(due_on: Date.current + 30))
      assert_not fourth.issue!
      assert_includes fourth.errors[:base],
                     "Free 플랜은 매월 3건까지 발행할 수 있습니다. Plus로 무제한 이용할 수 있습니다"
      assert_equal 3, users(:gamma).invoices.issued.count
    end
  end

  test "무효 처리된 발행도 당월 한도 카운트에 포함된다(PLAN-1 — 문서화된 해석)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      invoices_this_month = 3.times.map { create_and_issue!(due_on: Date.current + 30) }
      invoices_this_month.first.void!

      fourth = Invoice.new(invoice_attributes(due_on: Date.current + 30))
      assert_not fourth.issue!
      assert_includes fourth.errors[:base],
                     "Free 플랜은 매월 3건까지 발행할 수 있습니다. Plus로 무제한 이용할 수 있습니다"
    end
  end

  test "다음 달에는 발행 한도가 초기화된다(PLAN-1·TIME-1)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      3.times { create_and_issue!(due_on: Date.current + 30) }
    end
    travel_to(Time.zone.parse("2026-11-01 09:00")) do
      invoice = create_and_issue!(due_on: Date.current + 30)
      assert_equal "BD-20261101-001", invoice.issue_number
    end
  end

  test "초안은 월 건수와 무관하게 저장된다(PLAN-1 — 초안 무제한)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      5.times do |index|
        invoice = Invoice.create!(invoice_attributes(due_on: Date.current + 30 + index))
        assert invoice.draft?
      end
      assert_equal 5, users(:gamma).invoices.draft.count
    end
  end

  # ── INV-1 품목 행 수 상한(Phase 6 #6) ──

  test "품목 행은 100개까지 저장할 수 있다(INV-1·Phase 6 #6)" do
    invoice = Invoice.new(invoice_attributes(due_on: Date.current + 30, rows: Array.new(100, [ 1, 1_000 ])))
    assert invoice.valid?
    assert invoice.save
    assert_equal 100, invoice.reload.items.count
  end

  test "품목 행 101개는 저장이 거부된다(INV-1·Phase 6 #6)" do
    invoice = Invoice.new(invoice_attributes(due_on: Date.current + 30, rows: Array.new(101, [ 1, 1_000 ])))
    assert_not invoice.valid?
    assert_includes invoice.errors[:base], "품목 행은 최대 100개까지 입력할 수 있습니다"
    assert_raises(ActiveRecord::RecordInvalid) { invoice.save! }
  end

  private

  # 발행 가능한 최소 속성 — user·client·만기일·품목 행(수량·단가). due_on은 명시값(프리필 재계산과 구분).
  def invoice_attributes(due_on:, rows: [ [ 1, 100_000 ] ], tax_mode: :separate,
                         withholding: false, user: users(:gamma), client: clients(:gamma_main))
    {
      user: user, client: client, due_on: due_on, tax_mode: tax_mode,
      withholding_enabled: withholding,
      issuer_display_name: user.display_name.presence || "테스트발행자",
      bank_name: "국민은행", account_number: "123-45-678901", account_holder: "테스트예금주",
      items_attributes: rows.each_with_index.to_h do |(quantity, unit_price), index|
        [ index.to_s, { description: "품목#{index + 1}", quantity: quantity.to_s, unit_price: unit_price.to_s } ]
      end
    }
  end

  def create_and_issue!(**options)
    invoice = Invoice.create!(invoice_attributes(**options))
    assert invoice.issue!, -> { invoice.errors.full_messages.join(", ") }
    invoice.reload
  end
end
