# 발송 잡(F-REM — REM-2/3/11) — 평일 14:00 KST. Reminders::DispatchService가 오늘 도래 스텝을
# 스캔·발송한다. 09시 사전통보 이후의 취소 창(REM-11)은 발송 직전 SendService 가드의 재확인
# (마감·보류·수신거부·종결)으로 흡수된다.
module Reminders
  class DispatchJob < ApplicationJob
    queue_as :default

    def perform
      Reminders::DispatchService.new.call
    end
  end
end
