module Dashboards
  # DASH-2·Q31 — 「미열람 방치」 카드 조회. 발행 후 IDLE_DAYS일 이상 지났고 한 번도 열지 않은
  # 미수 청구. "한 번도 열지 않음"은 INV-4 최초 열람 전이(issued→viewed — Invoice#mark_viewed!,
  # ViewEvents::TrackService만 호출하는 유일한 허용 경로)가 상태로 보증하므로 status issued로
  # 판정한다 — viewed·overdue·promised 등 열람·진입 이후 상태는 제외. idle 일수는
  # 오늘 − 발행일(KST 날짜 차, TIME-1)이며 정렬은 발행일 오름차순.
  class UnviewedIdleQuery
    IDLE_DAYS = 3

    Row = Struct.new(:invoice, :idle_days, keyword_init: true)

    def self.call(user:)
      today = Date.current
      threshold = (today - IDLE_DAYS).end_of_day  # "3일 이상 지났다" = 발행일이 오늘−3 이전(당일 포함)

      user.invoices.unsettled.where(status: :issued)
          .where(issued_at: ...threshold)
          .includes(:client).order(:issued_at, :id)
          .map { |invoice| Row.new(invoice:, idle_days: (today - invoice.issued_at.to_date).to_i) }
    end
  end
end
