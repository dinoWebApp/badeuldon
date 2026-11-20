# 관리자 운영 대시보드 표현 헬퍼(ADMIN-5) — 솔라피 잔액 카드(ADMIN-5·REM-10). 임계치 비교·
# 상태색·포맷은 표현 로직이라 뷰에서 하지 않고 여기서 캡슐화한다(컨트롤러는 래퍼 호출만).
module Admin::DashboardsHelper
  # 잔액 경고 임계치 — 미만이면 발송 중단 임박으로 간주해 주황(상태색·경고 계열)으로 표시.
  # 알림톡 건당 과금 기준 여유분으로 선정(운영 판단 — PRD ADMIN-5 "잔액 부족 전 알림").
  LOW_BALANCE_THRESHOLD = 50_000

  # 잔액 카드 값 — 조회 실패(nil)는 "일시 조회 불가", 정상은 원화 통화 표기.
  def solapi_balance_text(balance)
    return "일시 조회 불가" if balance.nil?

    number_to_currency(balance[:balance], unit: "₩", precision: 0)
  end

  # 잔액 카드 값 색 — 임계치 미만은 주황 경고, 조회 실패는 중립 회색, 정상은 기본색.
  def solapi_balance_value_class(balance)
    return "text-stone-400" if balance.nil?
    return "text-orange-600" if balance[:balance] < LOW_BALANCE_THRESHOLD

    ""
  end

  # 충전 임박 여부 — 뷰에서 상수·숫자를 직접 비교하지 않게 캡슐화.
  def solapi_balance_low?(balance)
    !balance.nil? && balance[:balance] < LOW_BALANCE_THRESHOLD
  end
end
