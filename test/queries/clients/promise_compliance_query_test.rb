require "test_helper"

# CLIENT-3·PROMISE-5 — 거래처 약속 이행 이력 쿼리(Clients::PromiseComplianceQuery).
# 시나리오 기준: PRD v0.35 CLIENT-3·Q14 — ① 3상태 분류(이행 = 마감 입금일 ≤ 약속일·== 경계
# 포함 / 미이행 = 도과 후 미수 + 도과 후 입금 / 판정 중 = 유효·도과 전), ② 최신 약속순 정렬,
# ③ 재응답 시 최신 약속이 운영 약속(P4 — 약속 표시는 최신 기준), ④ 소유권 격리.
class Clients::PromiseComplianceQueryTest < ActiveSupport::TestCase
  test "3상태로 분류하고 최신 약속순으로 반환한다 (Q14·CLIENT-3)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      client = clients(:gamma_main)
      on_time = seed_invoice(gamma, client, "h-a", promised_on: Date.new(2026, 11, 5), status: :paid,
                             paid_on: Date.new(2026, 11, 5))                    # == 경계 → 이행
      late = seed_invoice(gamma, client, "h-b", promised_on: Date.new(2026, 11, 3), status: :paid,
                          paid_on: Date.new(2026, 11, 6))                       # +3 → 미이행
      open_past = seed_invoice(gamma, client, "h-c", promised_on: Date.new(2026, 11, 1))
      pending = seed_invoice(gamma, client, "h-d", promised_on: Date.new(2026, 11, 20))

      rows = Clients::PromiseComplianceQuery.call(client: client)

      assert_equal 4, rows.size
      # 약속일 내림차순 — 최신 약속이 첫 행(P4)
      assert_equal [ "2026-11-20", "2026-11-05", "2026-11-03", "2026-11-01" ],
                   rows.map { |r| r.promised_on.strftime("%Y-%m-%d") }
      assert_equal "pending", rows[0].status_key
      assert_equal "fulfilled", rows[1].status_key
      assert_equal "broken", rows[2].status_key
      assert_equal "broken", rows[3].status_key
      # 마감 입금일 병기 — paid 건만 존재
      assert_equal Date.new(2026, 11, 5), rows[1].closing_paid_on
      assert_nil rows[0].closing_paid_on
      assert_equal on_time.id, rows[1].invoice_id
      assert_equal late.total_amount, rows[2].total_amount
    end
  end

  test "재응답 시 최신 약속 1건이 운영 약속이다 (P4 — 이중 행 방지)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      client = clients(:gamma_main)
      invoice = seed_invoice(gamma, client, "h-re", promised_on: Date.new(2026, 11, 5))
      Promise.new(invoice: invoice, kind: :date_selected,
                  promised_on: Date.new(2026, 11, 12)).save(validate: false)

      rows = Clients::PromiseComplianceQuery.call(client: client)

      assert_equal 1, rows.size
      assert_equal Date.new(2026, 11, 12), rows.first.promised_on
      assert_equal "pending", rows.first.status_key
    end
  end

  test "무효·초안 청구의 약속은 목록에서 제외된다 (리뷰 C-1 — 성적표와 모집단 일치)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      client = clients(:gamma_main)
      # promised 상태에서 채권자가 void!한 시나리오 — 도과된 약속이라도 무효 건은 미이행 표기 금지(P1)
      voided = seed_invoice(gamma, client, "v-a", promised_on: Date.new(2026, 11, 1))
      voided.void!
      draft = seed_invoice(gamma, client, "v-d", promised_on: Date.new(2026, 11, 1), status: :draft)
      on_time = seed_invoice(gamma, client, "v-ok", promised_on: Date.new(2026, 11, 5), status: :paid,
                             paid_on: Date.new(2026, 11, 5))

      rows = Clients::PromiseComplianceQuery.call(client: client)

      # 목록 = 성적표(이행률·평균 지연일)와 동일 모집단 — voided·draft 행 미노출, 이행만 1행
      assert_equal 1, rows.size
      assert_equal on_time.id, rows.first.invoice_id
      assert_equal "fulfilled", rows.first.status_key
      assert_equal 0, rows.count { |r| r.status_key == "broken" }
    end
  end

  test "this_week 약속은 당일까지 판정 중이고 약속일 도과 후 미이행으로 전이된다 (Q14 시간 경과)" do
    invoice = nil
    # 접수 당일(금요일) — 약속일 == 오늘 경계: 유효 → 판정 중
    travel_to(Time.zone.parse("2026-11-06 14:00")) do
      invoice = seed_invoice(users(:gamma), clients(:gamma_main), "tw-a",
                             promised_on: Date.new(2026, 11, 6), kind: :this_week)
      rows = Clients::PromiseComplianceQuery.call(client: clients(:gamma_main))

      assert_equal "pending", rows.first.status_key
    end

    # 자정 경과 후(약속일 +1일) — 미수 상태 지속: 도과 → 미이행
    travel_to(Time.zone.parse("2026-11-07 09:00")) do
      rows = Clients::PromiseComplianceQuery.call(client: clients(:gamma_main))

      assert_equal "broken", rows.first.status_key
      assert_nil rows.first.closing_paid_on
    end
    assert invoice # 시드 성공 보장
  end

  test "다른 사용자의 거래처 약속은 포함되지 않는다 (소유권 격리)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      seed_invoice(users(:gamma), clients(:gamma_main), "h-g", promised_on: Date.new(2026, 11, 5))
      seed_invoice(users(:beta), clients(:beta_secret), "h-bt", promised_on: Date.new(2026, 11, 4))

      assert_equal 1, Clients::PromiseComplianceQuery.call(client: clients(:gamma_main)).size
      assert_equal 1, Clients::PromiseComplianceQuery.call(client: clients(:beta_secret)).size
    end
  end

  private

  # PaymentScorecardQueryTest와 동일 시드 규칙(약속은 과거일 허용 시드 — validate 우회).
  def seed_invoice(user, client, label, promised_on:, status: :promised, paid_on: Date.new(2026, 11, 4), kind: :date_selected)
    invoice = user.invoices.create!(
      client: client, due_on: Date.new(2026, 11, 30), status: status,
      tax_mode: :separate, withholding_enabled: false,
      issuer_display_name: "테스트발행자",
      bank_name: "국민은행", account_number: "123-45-678901", account_holder: "테스트",
      issue_number: "BD-20990101-#{label}",
      token: SecureRandom.urlsafe_base64(32),
      issued_at: Time.current,
      items_attributes: { "0" => { description: "시드 품목", quantity: "1", unit_price: "100000" } }
    ).reload

    Payment.create!(invoice: invoice, amount: 110_000, paid_on: paid_on) if status == :paid
    Promise.new(invoice: invoice, kind: kind,
                promised_on: promised_on).save(validate: false) if promised_on
    invoice
  end
end
