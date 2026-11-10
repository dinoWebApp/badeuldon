require "test_helper"

# CLIENT-3/4 — 지급 성적표 뷰 표현 헬퍼(App::ClientsHelper) 단위 테스트.
# 리뷰 W-1·Tester 중점 2·6번 고정 — ① 비교 배지 반올림 경계(차이 정확 1일 → 노출·
# 반올림 후 차이 0 → 미노출)와 방향 색(느림=주황·빠름=emerald — W-1·DESIGN-2),
# ② 조기 입금(음수 지연)의 "N일 전" 표기(뷰 "-" 오노출 방지), ③ 경향 막대의
# 음수 월 정규화 표기. 헬퍼가 색 판정을 담당하므로 단위 레벨에서 경계를 고정한다.
class App::ClientsHelperTest < ActionView::TestCase
  include App::ClientsHelper

  # 리뷰 C-1·W-1 — voided·draft는 쿼리 모집단에서 이미 제외되므로(필요 키만 채운다)
  def scorecard(avg_delay_days:, all_clients_avg_delay:, clients_count:)
    Clients::PaymentScorecardQuery::Result.new(
      total_invoiced_amount: 0, unsettled_count: 0,
      avg_delay_days: avg_delay_days,
      compliance_rate: nil, monthly_trend: [],
      all_clients_avg_delay: all_clients_avg_delay,
      clients_count: clients_count
    )
  end

  test "비교 배지는 반올림 후 차이가 정확 1일이면 노출된다 (CLIENT-4 경계)" do
    # 1일 느림 — 노출 + 주황(W-1: 지연 계열 = 주황, 긍정 녹색 오용 금지)
    badge = client_comparison_badge(scorecard(avg_delay_days: 2, all_clients_avg_delay: 1, clients_count: 2))
    assert_not_nil badge
    assert_equal "평균보다 1일 느린 거래처", badge.first
    assert_match %r{orange}, badge.last
    assert_no_match %r{emerald}, badge.last

    # 1일 빠름 — 노출 + 긍정색
    badge = client_comparison_badge(scorecard(avg_delay_days: 0, all_clients_avg_delay: 1, clients_count: 2))
    assert_equal "평균보다 1일 빠른 거래처", badge.first
    assert_match %r{emerald}, badge.last
    assert_no_match %r{orange}, badge.last
  end

  test "비교 배지는 반올림 후 차이가 0이면 미노출된다 (CLIENT-4 경계 — 반올림 상쇄)" do
    # 실차이는 존재해도 두 평균이 같은 정수로 반올림되면 diff 0 — 배지 만들지 않는다
    assert_nil client_comparison_badge(scorecard(avg_delay_days: 1, all_clients_avg_delay: 1, clients_count: 2))
    assert_nil client_comparison_badge(scorecard(avg_delay_days: -1, all_clients_avg_delay: -1, clients_count: 2))
  end

  test "비교 배지는 지표 결손·거래처 1개에서 만들지 않는다 (CLIENT-4)" do
    assert_nil client_comparison_badge(scorecard(avg_delay_days: nil, all_clients_avg_delay: 1, clients_count: 2))
    assert_nil client_comparison_badge(scorecard(avg_delay_days: 2, all_clients_avg_delay: nil, clients_count: 2))
    assert_nil client_comparison_badge(scorecard(avg_delay_days: 2, all_clients_avg_delay: 1, clients_count: 1))
  end

  test "조기 입금(음수 지연)은 'N일 전'으로 읽히고 '-'로 표기되지 않는다 (CLIENT-4)" do
    assert_equal "2일 전", scorecard_delay_text(-2)
    assert_equal "3일", scorecard_delay_text(3)
    assert_equal "0일", scorecard_delay_text(0)
    assert_equal "-", scorecard_delay_text(nil)
    assert_equal "-", scorecard_rate_text(nil)
    assert_equal "80%", scorecard_rate_text(80)
  end

  test "6개월 경향 막대는 음수 월을 abs로 정규화하고 조기 입금을 'N일 전'으로 표기한다 (CLIENT-4)" do
    trend = [ [ "2026-10", -2 ], [ "2026-11", 4 ], [ "2026-12", nil ], [ "2027-01", 0 ] ]

    bars = scorecard_trend_bars(trend)

    assert_equal [ "2026-10", "2일 전" ], bars[0].first(2)
    assert_equal [ "2026-11", "4일" ], bars[1].first(2)
    assert_equal "-", bars[2][1]           # 마감 없는 월(nil) — 중립 "-"
    assert_equal "0일", bars[3][1]         # 지연 0 월 — "-" 오노출 방지
    # 최댓값(|4|) 대비 정규화 — 음수 월도 절댓값 기준 높이 보유
    assert_equal 50, bars[0][2]
    assert_equal 100, bars[1][2]
    assert_equal 12, bars[2][2]            # nil — 최소 높이 중립 바
  end
end
