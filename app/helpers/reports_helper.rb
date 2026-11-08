# 표면 ② 리포트 페이지 표현 로직 — DASH-5/6. 뷰의 표현 3줄+ 계산을 추출한다(규약 §5.3).
module ReportsHelper
  # DASH-5 — 월간 수금 추이 CSS bar chart 막대 높이(%). 최댓값 대비 비율이며
  # 최댓값 0(전월 0원)일 때는 0% — 막대를 아예 그리지 않는다.
  def bar_height_percent(amount, max_amount)
    return 0 if max_amount <= 0

    (amount.to_f / max_amount * 100).round(1)
  end

  # DASH-5 — 거래처별 평균 지급 지연일 표기. 음수는 조기 입금(만기 전 지급)으로 별도 문구.
  def display_delay_days(days)
    return "—" if days.nil?

    if days.negative?
      "#{days.abs}일 조기"
    elsif days.positive?
      "+#{days}일"
    else
      "당일"
    end
  end

  # DASH-5 — 지연일 상태색(DESIGN-2 상태 3종): 지연 주황·조기·당일 녹색.
  def delay_days_classes(days)
    return "text-stone-400" if days.nil?

    days.positive? ? "text-orange-600" : "text-green-700"
  end

  # DASH-5 — 월별 막대 최댓값(그래프 스케일 기준).
  def monthly_max_amount(rows)
    rows.map(&:amount).max.to_i
  end

  # DASH-6 — 신고 주기 집계행 표기용: 분기 라벨·기간 결합.
  def tax_period_title(row)
    "#{row.label} (#{row.period_label})"
  end
end
