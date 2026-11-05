# 연체 저장화(F-REM) — 매일 07:00 KST(TIME-1). unsettled + 만기일 경과 건을 overdue로 전이한다.
# mark_overdue!의 조건부 UPDATE(issued|viewed|partially_paid만, promised 제외 — 약속 트랙 유지
# PROMISE-3)로 멱등이며 재실행 무해다. overdue 스코프(표시용 파생 판정)는 그대로 유지되고,
# 이 잡이 enum의 저장 전환을 수행하는 유일한 경로다("enum 자동 전환은 F-REM 스케줄러와 함께"
# 주석의 이행).
module Reminders
  class OverdueMarkJob < ApplicationJob
    queue_as :default

    def perform
      # due_on: ...Date.current — 무한 시작 범위로 만기일 < 오늘(KST)만 대상(TIME-1)
      Invoice.unsettled.where(due_on: ...Date.current).find_each do |invoice|
        invoice.mark_overdue!
      end
    end
  end
end
