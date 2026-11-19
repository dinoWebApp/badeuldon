# 월 수수료 정산 스냅샷(SALES-5 — F-SALES·Q24). 대상 월(기본 직전월)의 Plus 월결제
# (plus_monthly·paid·환불 제외) 실차감액을 유치자(referred_by)별로 집계해
# SalesCommission 스냅샷을 upsert한다(복합 유니크 rep·연월 — 재실행 멱등).
#
# 기준·정책(Q24 확정):
#   · 기준 금액 = orders.amount(실차감액 — 첫 달 20% 할인가 포함. charge_and_extend!가
#     차감 금액을 주문 amount로 기록하므로 metadata 파싱 불요)·환불(refunded_at) 제외.
#   · rate는 스냅샷 시점의 rep.effective_rate(개별 오버라이드 우선·역할 기본값 폴백).
#   · sales 역할 12개월 캡 — 유치 사용자 created_at으로부터 12개월 내 결제분만 집계
#     (paid_at이 user.created_at + 12개월 이하). officer는 무기한(필터 없음).
#   · paid 스냅샷(지급 확정분)은 재집계로 덮어쓰지 않는다 — 지급 금액 보존.
# 인자 없는 recurring(매월 1일 00:05 KST)과 관리자 수동 재집계(연월 지정)를 모두 지원한다.
module Sales
  class MonthlySettlementService
    # SALES-1·Q24 — sales 역할 결제 인정 기간(유치 사용자 가입일로부터).
    SALES_CAP_MONTHS = 12

    def initialize(year: nil, month: nil)
      target = year && month ? Date.new(year, month) : Date.current << 1
      @year = target.year
      @month = target.month
    end

    def call
      SalesRep.order(:id).filter_map do |rep|
        base_amount = sum_base_amount(rep)
        next if base_amount.zero? && rep.sales_commissions.for_month(@year, @month).none?

        upsert_snapshot!(rep, base_amount)
      rescue StandardError => e
        Rails.logger.error("[Sales::MonthlySettlementService] rep=#{rep.id} #{@year}-#{@month} #{e.class}: #{e.message}")
        nil
      end
    end

    private

    # 해당 월의 유치 사용자 Plus 결제 실차감액 합계(역할 정책 필터 적용).
    # W-7 — 유저 루프당 orders 집계(N+1)를 rep당 1회 조인 집계로 해소한다. sales 12개월 캡은
    # users.created_at 의존이라 SQL 상수 조건으로 표현할 수 없으므로 캡 판정은 행 단위 Ruby
    # 필터로 유지한다(기존 판정과 동일 — paid_at <= created_at + 12개월, 포함 경계).
    def sum_base_amount(rep)
      scoped = Order.joins(:user)
                    .where(users: { referred_by_sales_rep_id: rep.id })
                    .paid.plus_monthly.not_refunded
                    .where(paid_at: month_range)
      return scoped.sum(:amount) unless rep.sales? # officer — 무기한(캡 필터 없음)

      scoped.pluck("users.created_at", "orders.paid_at", "orders.amount")
            .sum do |joined_at, paid_at, amount|
        paid_at <= joined_at + SALES_CAP_MONTHS.months ? amount : 0
      end
    end

    def month_range
      start_at = Time.zone.local(@year, @month, 1)
      start_at...(start_at + 1.month)
    end

    # upsert(복합 유니크 rep·연월) — 신규는 pending 스냅샷, 기존 pending은 재집계 갱신,
    # paid는 무변경(지급 확정 금액 보존 — SEC-5 멱등). 경합 생성 충돌은 재조회로 흡수.
    def upsert_snapshot!(rep, base_amount)
      rate = rep.effective_rate
      commission = rep.sales_commissions.find_or_create_by!(year: @year, month: @month) do |new_record|
        new_record.base_amount = base_amount
        new_record.rate = rate
        new_record.amount = (base_amount * rate / 100).floor
        new_record.settled_at = Time.current
      end
      return commission if commission.paid?

      commission.update!(base_amount:, rate:, amount: (base_amount * rate / 100).floor,
                         settled_at: Time.current)
      commission
    rescue ActiveRecord::RecordNotUnique
      retry
    end
  end
end
