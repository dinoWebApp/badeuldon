# SALES-5 — 월 수수료 정산 recurring Job(매월 1일 00:05 KST — config/recurring.yml
# sales_monthly_settlement · fugit KST 접미사 TIME-1). 인자 없음 — 대상 월(직전월)은
# Sales::MonthlySettlementService가 결정하며 upsert(복합 유니크)로 재실행 멱등이다.
# 개별 rep 실패는 서비스가 로그 후 나머지를 계속 처리한다(주간 잡과 같은 패턴).
class Sales::MonthlySettlementJob < ApplicationJob
  queue_as :default

  def perform
    Sales::MonthlySettlementService.new.call
  end
end
