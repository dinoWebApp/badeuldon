require "test_helper"

# DASH-6 — 신고 주기 집계 쿼리(Reports::TaxPeriodQuery).
# 시나리오 기준: 05_review.md 「Tester 중점 테스트 제안」 2·3·4번 —
# 분기 경계일(3/31 vs 4/1 KST)·라벨 4종(익년 1월 포함)·draft/voided 매출 제외·
# 매출(issued_at)과 수금(paid_on) 기준 분리·부가세 별도·소유권 격리.
# 시간은 travel_to로 2026-11-09(KST) 고정(TIME-1) — 최근 4분기는 2026 Q1~Q4.
class Reports::TaxPeriodQueryTest < ActiveSupport::TestCase
  setup do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      @rows = Reports::TaxPeriodQuery.call(users(:gamma).id)
    end
  end

  # travel_to 블록 밖 어설션을 위해 rows를 다시 계산하지 않도록 setup에서 고정값을 캐시한다.
  # (분기 창은 Date.current로 파생되므로 travel 밖에서 재계산하면 실제 오늘 기준이 되어 어긋난다.)
  def rows
    @rows
  end

  test "최근 4개 분기(2026 Q1~Q4)를 오래된 순으로 반환한다 (DASH-6)" do
    assert_equal 4, rows.size
    assert_equal Date.new(2026, 1, 1), rows[0].start
    assert_equal Date.new(2026, 3, 31), rows[0].finish
    assert_equal Date.new(2026, 10, 1), rows[3].start
    assert_equal Date.new(2026, 12, 31), rows[3].finish
  end

  test "확정신고 라벨 4종 — 10~12월 분기는 익년 1월이다 (DASH-6)" do
    assert_equal "4월 확정신고", rows[0].label
    assert_equal "7월 확정신고", rows[1].label
    assert_equal "10월 확정신고", rows[2].label
    assert_equal "익년 1월 확정신고", rows[3].label
  end

  test "분기 경계일 발행은 각각 올바른 분기에 소속된다 — 3/31 vs 4/1 (TIME-1·DASH-6)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      client = clients(:gamma_main)
      seed_invoice(gamma, client, label: "q1-edge", due_on: Date.new(2026, 4, 30),
                   issued_at: Time.zone.parse("2026-03-31 23:59"))
      seed_invoice(gamma, client, label: "q2-edge", due_on: Date.new(2026, 5, 31),
                   issued_at: Time.zone.parse("2026-04-01 00:05"))
      seed_invoice(gamma, client, label: "q4-edge", due_on: Date.new(2026, 11, 30),
                   issued_at: Time.zone.parse("2026-10-01 00:05"))

      report_rows = Reports::TaxPeriodQuery.call(gamma.id)

      # 각 110,000(total) 중 공급가액 100,000씩 — 경계 청구가 인접 분기로 흘러가면 불일치로 검출된다
      assert_equal 100_000, report_rows[0].revenue  # Q1 — 3/31 23:59 KST
      assert_equal 100_000, report_rows[1].revenue  # Q2 — 4/1 00:05 KST
      assert_equal 100_000, report_rows[3].revenue  # Q4 — 10/1 00:05 KST
      assert_equal 0, report_rows[2].revenue        # Q3
    end
  end

  test "매출은 issued_at, 수금은 paid_on 기준으로 각각 소속 분기가 다를 수 있다 (DASH-6 기준 분리)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      invoice = seed_invoice(gamma, clients(:gamma_main), label: "split",
                             due_on: Date.new(2026, 7, 31), issued_at: Time.zone.parse("2026-04-15 10:00"))
      # Q2에 발행된 청구의 입금이 Q3(7월)에 발생 — 매출은 Q2, 수금은 Q3에 귀속되어야 한다
      Payment.create!(invoice: invoice, amount: 110_000, paid_on: Date.new(2026, 7, 20))

      report_rows = Reports::TaxPeriodQuery.call(gamma.id)

      assert_equal 100_000, report_rows[1].revenue  # Q2 — 발행 기준
      assert_equal 0, report_rows[1].collected
      assert_equal 110_000, report_rows[2].collected  # Q3 — 입금 기준
      assert_equal 0, report_rows[2].revenue
    end
  end

  test "부가세는 매출(공급가액)과 별도 집계된다 (INV-1·DASH-6)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      seed_invoice(gamma, clients(:gamma_main), label: "tax", due_on: Date.new(2026, 2, 28),
                   issued_at: Time.zone.parse("2026-02-10 10:00"))

      report_rows = Reports::TaxPeriodQuery.call(gamma.id)

      assert_equal 100_000, report_rows[0].revenue
      assert_equal 10_000, report_rows[0].tax_amount
    end
  end

  test "draft·voided 청구는 매출·부가세 집계에서 제외된다 (DASH-6·INV-1)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      seed_invoice(gamma, clients(:gamma_main), label: "voided", due_on: Date.new(2026, 2, 28),
                   status: :voided, issued_at: Time.zone.parse("2026-02-10 10:00"))
      # draft — issued_at 없음(초안은 발행 전이라 분기 소속 판정 대상 자체가 아니다)
      seed_invoice(gamma, clients(:gamma_main), label: "draft", due_on: Date.new(2026, 2, 28), status: :draft)

      report_rows = Reports::TaxPeriodQuery.call(gamma.id)

      assert_equal [ 0, 0, 0, 0 ], report_rows.map(&:revenue)
      assert_equal [ 0, 0, 0, 0 ], report_rows.map(&:tax_amount)
    end
  end

  test "다른 사용자의 매출·수금은 집계에 포함되지 않는다 (소유권 격리)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      beta = users(:beta)
      seed_invoice(gamma, clients(:gamma_main), label: "iso-g", due_on: Date.new(2026, 2, 28),
                   issued_at: Time.zone.parse("2026-02-10 10:00"))
      beta_invoice = seed_invoice(beta, clients(:beta_secret), label: "iso-b",
                                  due_on: Date.new(2026, 2, 28), issued_at: Time.zone.parse("2026-02-11 10:00"))
      Payment.create!(invoice: beta_invoice, amount: 550_000, paid_on: Date.new(2026, 3, 5))

      gamma_rows = Reports::TaxPeriodQuery.call(gamma.id)
      beta_rows = Reports::TaxPeriodQuery.call(beta.id)

      assert_equal 100_000, gamma_rows[0].revenue
      assert_equal 0, gamma_rows[0].collected  # beta 수금 550,000 미포함
      assert_equal 100_000, beta_rows[0].revenue
      assert_equal 550_000, beta_rows[0].collected
    end
  end

  private

  def seed_invoice(user, client, label:, due_on:, status: :issued, issued_at: nil, rows: [ [ 1, 100_000 ] ])
    issued_family = Invoice.new(status: status).unsettled? || status.to_s == "paid"
    user.invoices.create!(
      client: client, due_on: due_on, status: status,
      tax_mode: :separate, withholding_enabled: false,
      issuer_display_name: "테스트발행자",
      bank_name: "국민은행", account_number: "123-45-678901", account_holder: "테스트",
      issue_number: (issued_family ? "BD-20990101-#{label}" : nil),
      token: (issued_family ? SecureRandom.urlsafe_base64(32) : nil),
      issued_at: (issued_family ? (issued_at || Time.current) : nil),
      items_attributes: rows.each_with_index.to_h do |(quantity, unit_price), index|
        [ index.to_s, { description: "시드 품목#{index + 1}", quantity: quantity.to_s, unit_price: unit_price.to_s } ]
      end
    ).reload
  end
end
