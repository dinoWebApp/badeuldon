# SALES-2 — 추천 코드 주간 로테이션 recurring Job(매주 월요일 00:00 KST —
# config/recurring.yml sales_referral_codes_rotate · fugit KST 접미사 TIME-1). 인자 없음 —
# 대상(활동 직원 전체)과 발급 연월일은 서비스가 Time.current 기준으로 결정한다(멱등 —
# Sales::RotateReferralCodesService의 당일 발급분 가드). 개별 rep 실패는 로그 후 나머지를
# 계속 처리한다(RecurringInvoices::IssueJob과 같은 패턴).
class Sales::RotateReferralCodesJob < ApplicationJob
  queue_as :default

  def perform
    Sales::RotateReferralCodesService.call
  end
end
