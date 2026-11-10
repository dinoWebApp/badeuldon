module App
  # 거래처 카드·지급 성적표 표기 헬퍼(CLIENT-3·CLIENT-4 — Q14 파생 판정의 뷰 표현).
  # 지표가 nil이면 "-" 표기·배지 미노출(약속 없는 거래처 — 02_prd_update 확정).
  # "지연"은 약속일 대비로 DASH-5(만기 대비)와 정의가 다르며 화면 문구로 구분한다.
  module ClientsHelper
    # 평균 지급 지연일 표기 — nil은 "-", 조기 입금(음수)은 "N일 전"으로 읽는다.
    def scorecard_delay_text(days)
      return "-" if days.nil?
      return "#{days.abs}일 전" if days.negative?

      "#{days}일"
    end

    # 약속 이행률 표기 — 확정 건이 없으면 nil이고 "-"로 읽는다.
    def scorecard_rate_text(rate)
      rate.nil? ? "-" : "#{rate}%"
    end

    # CLIENT-4 비교 배지 — 동일 사용자 전체 거래처 평균 지연일 대비, 차이 ≥ 1일일 때만.
    # 거래처가 1개뿐이면 비교 대상이 없어 배지를 만들지 않는다. 지표가 없으면 nil(미노출).
    # 반환은 [문구, class] — 방향 색 판정도 여기서 담당한다(W-1 — DESIGN-2 상태색 3종:
    # 빠름=딥 그린(긍정)·느림=주황(지연 계열)). 색을 뷰에 두지 않아 양쪽 표기가 절대 어긋나지 않는다.
    def client_comparison_badge(scorecard)
      own = scorecard.avg_delay_days
      avg = scorecard.all_clients_avg_delay
      return nil if own.nil? || avg.nil? || scorecard.clients_count <= 1

      diff = own - avg
      return nil if diff.abs < 1

      if diff.negative?
        [ "평균보다 #{diff.abs.round}일 빠른 거래처",
          "bg-emerald-50 text-emerald-800" ]
      else
        [ "평균보다 #{diff.round}일 느린 거래처",
          "bg-orange-50 text-orange-600" ]
      end
    end

    # 6개월 경향 막대 표기용 — [월 라벨, 표기값, 높이 비율(%)] 배열. 최댓값 대비 비율로
    # 정규화하며 지연 없는 월(0)과 마감 없는 월(nil)은 최소 높이의 중립 바로 표기한다.
    def scorecard_trend_bars(trend)
      values = trend.map { |_month, avg| avg }
      max = values.compact.map(&:abs).max || 0
      trend.map do |month, avg|
        height = avg.nil? || max.zero? ? 12 : [ (avg.abs * 100.0 / max).round.clamp(12, 100), 12 ].max
        [ month, scorecard_delay_text(avg), height ]
      end
    end

    # 약속 이행 상태 배지 — 이행 녹색 / 미이행 주황 / 판정 중 중립(DESIGN-2 상태색 3종).
    def promise_status_badge(status_key)
      spec = {
        "fulfilled" => [ "이행", "bg-green-50 text-green-700 ring-1 ring-inset ring-green-200" ],
        "broken"    => [ "미이행", "bg-orange-50 text-orange-600 ring-1 ring-inset ring-orange-200" ],
        "pending"   => [ "판정 중", "bg-stone-100 text-stone-600 ring-1 ring-inset ring-stone-200" ]
      }.fetch(status_key)
      content_tag :span, spec.first, class: "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-bold #{spec.last}"
    end
  end
end
