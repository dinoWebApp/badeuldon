# 사전통보 잡(F-REM — REM-11·NOTI-1) — 평일 09:00 KST. Reminders::PrenoticeService가 오늘
# 발송 예정(D+1/7/14) 건의 U1 사전통보와 내일 만기 요약을 수행한다(14시 발송 전 취소 창 제공).
module Reminders
  class PrenoticeJob < ApplicationJob
    queue_as :default

    def perform
      Reminders::PrenoticeService.new.call
    end
  end
end
