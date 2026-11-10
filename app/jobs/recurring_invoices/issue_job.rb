# 반복 청구 자동 발행(INV-7) — 매일 06:30 KST(TIME-1). 발행일이 오늘 또는 이미 경과한(C-2
# 완화 — 미실행일 커서 고착을 다음 실행이 만회) 이용 중 스케줄을 발행 플로우
# (RecurringInvoices::IssueService — 보류·한도 skip·issue! 재사용·with_lock 원자화)에 넘긴다.
# 개별 스케줄 실패는 로그 후 나머지를 계속 처리하며, 성공·skip 모두 next_issue_on이 다음 달로
# 이동해 재실행에 무해한 멱등 설계(SEC-5 준칙)다.
class RecurringInvoices::IssueJob < ApplicationJob
  queue_as :default

  def perform
    RecurringInvoice.due_or_overdue.find_each do |schedule|
      RecurringInvoices::IssueService.new.call(schedule)
    rescue StandardError => e
      Rails.logger.error("[RecurringInvoices::IssueJob] schedule=#{schedule.id} #{e.class}: #{e.message}")
    end
  end
end
