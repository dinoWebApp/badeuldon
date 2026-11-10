require "test_helper"

# CLIENT-3/4·PROMISE-5 — 거래처 지급 성적표 쿼리(Clients::PaymentScorecardQuery).
# 시나리오 기준: PRD v0.35 CLIENT-4·결정 기록 Q14·02_prd_update 확정 해석 —
# ① 이행 = paid && 마감 입금일 ≤ 약속일(== 경계 포함) / 미이행 = 도과 후 미수 + 도과 후 입금 /
#   판정 중 = 유효·도과 전, ② 평균 지급 지연일 = 약속 있던 마감 건만(약속 없는 청구 제외)·
#   부분입금은 최종 입금일 기준(행 가중 금지 — DASH-5 리뷰 C-1 선례), ③ 약속 없는 거래처 nil,
#   ④ 비교 배지용 사용자 전체 평균·거래처 수, ⑤ 소유권 격리. 시간은 travel_to 2026-11-09 KST(TIME-1).
class Clients::PaymentScorecardQueryTest < ActiveSupport::TestCase
  test "판정 3상태·약속 없는 마감 제외·부분입금 최종 입금일 기준으로 지표가 집계된다 (Q14)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      client = clients(:gamma_main)
      # A — 부분입금 후 완납: 최종 입금일 == 약속일 → 이행(지연 0)
      fulfilled = seed_invoice(gamma, client, "q-a", promised_on: Date.new(2026, 11, 5), status: :paid)
      Payment.create!(invoice: fulfilled, amount: 10_000, paid_on: Date.new(2026, 11, 1))
      Payment.create!(invoice: fulfilled, amount: 100_000, paid_on: Date.new(2026, 11, 5))
      # B — 도과 후 입금(paid): 미이행(지연 +3)
      seed_invoice(gamma, client, "q-b", promised_on: Date.new(2026, 11, 3), status: :paid,
                   paid_on: Date.new(2026, 11, 6))
      # C — 도과 후 미수(unsettled): 미이행
      seed_invoice(gamma, client, "q-c", promised_on: Date.new(2026, 11, 1))
      # D — 약속 유효(도과 전): 판정 중
      seed_invoice(gamma, client, "q-d", promised_on: Date.new(2026, 11, 20))
      # E — 약속 없는 마감: 지연·이행률 집계 제외
      seed_invoice(gamma, client, "q-e", promised_on: nil, status: :paid)
      # F — 조기 입금(지연 −2): 이행
      seed_invoice(gamma, client, "q-f", promised_on: Date.new(2026, 11, 8), status: :paid,
                   paid_on: Date.new(2026, 11, 6))

      scorecard = Clients::PaymentScorecardQuery.call(client: client)

      assert_equal 660_000, scorecard.total_invoiced_amount  # 발행 계열 6건
      assert_equal 2, scorecard.unsettled_count              # C·D
      # (0 + 3 − 2) / 3 — 약속 없던 E는 제외된다. 입금 행 가중으로 A의 조기 입금 −4가 섞이면 반전 검출
      assert_equal 0, scorecard.avg_delay_days
      assert_equal 50, scorecard.compliance_rate             # 이행 2(A·F) / 확정 4(A·B·C·F)
      assert_equal 1, scorecard.clients_count                # gamma 거래처 1개 — 배지 비대상
    end
  end

  test "6개월 경향은 마감 입금월 기준이고 창 밖 마감은 버린다 (CLIENT-4)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      client = clients(:gamma_main)
      seed_invoice(gamma, client, "t-nov", promised_on: Date.new(2026, 11, 3), status: :paid,
                   paid_on: Date.new(2026, 11, 6))                          # 당월 +3
      seed_invoice(gamma, client, "t-oct", promised_on: Date.new(2026, 10, 1), status: :paid,
                   paid_on: Date.new(2026, 10, 3))                          # 전월 +2
      seed_invoice(gamma, client, "t-old", promised_on: Date.new(2026, 4, 1), status: :paid,
                   paid_on: Date.new(2026, 4, 6))                           # 7개월 전 — 창 밖

      trend = Clients::PaymentScorecardQuery.call(client: client).monthly_trend

      assert_equal 6, trend.size
      assert_equal "2026-06", trend.first.first
      assert_equal "2026-11", trend.last.first
      assert_nil trend.first.last
      assert_equal 2, trend.reverse.assoc("2026-10").last
      assert_equal 3, trend.reverse.assoc("2026-11").last
    end
  end

  test "약속 없는 거래처는 지연일·이행률이 nil이다 (CLIENT-4 null 처리)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      seed_invoice(gamma, clients(:gamma_main), "np-a", promised_on: nil, status: :paid)
      seed_invoice(gamma, clients(:gamma_main), "np-b", promised_on: nil, status: :paid)

      scorecard = Clients::PaymentScorecardQuery.call(client: clients(:gamma_main))

      assert_nil scorecard.avg_delay_days
      assert_nil scorecard.compliance_rate
      assert_equal 220_000, scorecard.total_invoiced_amount
    end
  end

  test "비교 배지용 사용자 전체 평균은 모든 거래처 마감 건을 포함한다 (CLIENT-4)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      main = clients(:gamma_main)
      other = gamma.clients.create!(name: "감마제2", contact_name: "감책임", phone: "010-0000-0000")
      seed_invoice(gamma, main, "cmp-a", promised_on: Date.new(2026, 11, 3), status: :paid,
                   paid_on: Date.new(2026, 11, 6))                          # +3
      seed_invoice(gamma, other, "cmp-b", promised_on: Date.new(2026, 11, 2), status: :paid,
                   paid_on: Date.new(2026, 11, 6))                          # +4

      scorecard = Clients::PaymentScorecardQuery.call(client: main)

      assert_equal 2, scorecard.clients_count
      assert_equal 3, scorecard.avg_delay_days
      assert_equal 4, scorecard.all_clients_avg_delay  # (3 + 4) / 2 = 3.5 → 4
    end
  end

  test "다른 사용자의 거래처·청구·약속은 집계에 포함되지 않는다 (소유권 격리)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      seed_invoice(users(:gamma), clients(:gamma_main), "iso-g",
                   promised_on: Date.new(2026, 11, 3), status: :paid,
                   paid_on: Date.new(2026, 11, 4))                          # +1
      seed_invoice(users(:beta), clients(:beta_secret), "iso-b",
                   promised_on: Date.new(2026, 11, 1), status: :paid,
                   paid_on: Date.new(2026, 11, 6))                          # +5

      gamma_score = Clients::PaymentScorecardQuery.call(client: clients(:gamma_main))
      beta_score = Clients::PaymentScorecardQuery.call(client: clients(:beta_secret))

      assert_equal 1, gamma_score.clients_count
      assert_equal 1, gamma_score.avg_delay_days
      assert_equal 110_000, gamma_score.total_invoiced_amount
      assert_equal 5, beta_score.avg_delay_days
    end
  end

  test "연말을 넘는 6개월 창은 연도 경계에서 월 라벨·창 밖 버림이 정확하다 (CLIENT-4·TIME-1)" do
    travel_to(Time.zone.parse("2027-01-15 09:00")) do
      gamma = users(:gamma)
      client = clients(:gamma_main)
      seed_invoice(gamma, client, "y-jan", promised_on: Date.new(2027, 1, 3), status: :paid,
                   paid_on: Date.new(2027, 1, 6))                                       # 당월 +3
      seed_invoice(gamma, client, "y-dec", promised_on: Date.new(2026, 12, 10), status: :paid,
                   paid_on: Date.new(2026, 12, 13))                                     # 연말 직전 +3
      seed_invoice(gamma, client, "y-old", promised_on: Date.new(2026, 7, 1), status: :paid,
                   paid_on: Date.new(2026, 7, 6))                                       # 창 밖(2026-07)

      trend = Clients::PaymentScorecardQuery.call(client: client).monthly_trend

      assert_equal 6, trend.size
      assert_equal "2026-08", trend.first.first   # 2027-01 기준 6개월 뒤 — 연 롤오버 정확
      assert_equal "2027-01", trend.last.first
      assert_nil trend.first.last                 # 빈 달은 nil(뷰 "-"·중립 바)
      assert_equal 3, trend.reverse.assoc("2026-12").last
      assert_equal 3, trend.reverse.assoc("2027-01").last
    end
  end

  test "조기 입금이 지배하면 평균 지연일이 음수로 집계된다 (CLIENT-4 — 뷰 'N일 전' 근거)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      client = clients(:gamma_main)
      seed_invoice(gamma, client, "e-a", promised_on: Date.new(2026, 11, 8), status: :paid,
                   paid_on: Date.new(2026, 11, 5))                                        # −3
      seed_invoice(gamma, client, "e-b", promised_on: Date.new(2026, 11, 6), status: :paid,
                   paid_on: Date.new(2026, 11, 5))                                        # −1

      score = Clients::PaymentScorecardQuery.call(client: client)

      assert_equal(-2, score.avg_delay_days)
      # 조기 입금 = 이행(마감 입금일 ≤ 약속일) — 이행률 100%
      assert_equal 100, score.compliance_rate
    end
  end

  test "두 평균이 같은 정수로 반올림되면 비교 배지의 diff는 0이다 (CLIENT-4 반올림 상쇄 경계)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      main = clients(:gamma_main)
      other = gamma.clients.create!(name: "감마제3", contact_name: "감책임", phone: "010-0000-0001")
      # main: (0 + 1)/2 = 0.5 → 1 / other: (0 + 1)/2 = 0.5 → 1 — diff 0 → 배지 미노출 조건
      seed_invoice(gamma, main, "r-a", promised_on: Date.new(2026, 11, 5), status: :paid,
                   paid_on: Date.new(2026, 11, 5))
      seed_invoice(gamma, main, "r-b", promised_on: Date.new(2026, 11, 3), status: :paid,
                   paid_on: Date.new(2026, 11, 4))
      seed_invoice(gamma, other, "r-c", promised_on: Date.new(2026, 11, 5), status: :paid,
                   paid_on: Date.new(2026, 11, 5))
      seed_invoice(gamma, other, "r-d", promised_on: Date.new(2026, 11, 3), status: :paid,
                   paid_on: Date.new(2026, 11, 4))

      score = Clients::PaymentScorecardQuery.call(client: main)

      assert_equal 2, score.clients_count
      assert_equal score.avg_delay_days, score.all_clients_avg_delay
    end
  end

  test "voided·draft 약속 건은 이행률·평균 지연 집계에서도 제외된다 (리뷰 C-1 재발 방지 — 목록과 모집단 일치)" do
    travel_to(Time.zone.parse("2026-11-09 09:00")) do
      gamma = users(:gamma)
      client = clients(:gamma_main)
      # promised 상태에서 채권자가 void!한 시나리오 — 도과된 약속이라도 성적표 분모에 넣지 않는다(P1)
      voided = seed_invoice(gamma, client, "vx-a", promised_on: Date.new(2026, 11, 1))
      voided.void!
      seed_invoice(gamma, client, "vx-d", promised_on: Date.new(2026, 11, 1), status: :draft)

      score = Clients::PaymentScorecardQuery.call(client: client)
      rows = Clients::PromiseComplianceQuery.call(client: client)

      # 확정 건이 없으므로 이행률 nil — voided 도과 약속이 broken으로 계산되면 0%가 된다(모순)
      assert_nil score.compliance_rate
      assert_nil score.avg_delay_days
      assert_empty rows  # 목록도 같은 모집단 — voided·draft 행 없음
    end
  end

  private

  # 마감(paid)이면 paid_on에 입금 1건을 기록하고, promised_on이 있으면 약속 1건을 접수한다.
  # 과거 약속일은 뷰어 접수 경로에서만 차단 대상이므로 시드는 save(validate: false)로 기록한다
  # (PROMISE 검증 자체는 F-PROMISE 테스트 소관).
  def seed_invoice(user, client, label, promised_on:, status: :promised, paid_on: Date.new(2026, 11, 4))
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

    if status == :paid
      Payment.create!(invoice: invoice, amount: 110_000, paid_on: paid_on)
    end
    if promised_on
      Promise.new(invoice: invoice, kind: :date_selected,
                  promised_on: promised_on).save(validate: false)
    end
    invoice
  end
end
