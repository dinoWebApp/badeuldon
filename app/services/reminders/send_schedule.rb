# 실제 발송 예정 시각 산정(F-REM — REM-11·DASH-2·REM-3·TIME-1) — 09:00 사전통보와 대시보드
# 「오늘 발송 예정」 카드가 같은 모집단을 같은 시각으로 보게 하는 **단일 출처** 값 객체.
#   ① 그 단계의 채무자 향 pending 슬롯(Reminders::SendService#reschedule!이 REM-3 창 밖 발송을
#     미둔 예약 — Reminders::DeliverJob이 scheduled_at에 실행)에 scheduled_at이 있고 아직
#     지나지 않았으면 그 값. 지나간 슬롯은 발송이 이미 시도됐거나 곧 실행될 예정이라 "보류할 수
#     있는 예정"이 아니다(오전 슬롯을 오후까지 "오전 9시 예정"으로 잘못 보는 것 방지 — 발송되면
#     단계는 sent가 되어 애초 예정이 없다).
#   ② 없으면 다음 스캔 시각(평일 14시 KST — DispatchService::SCAN_HOUR·SCAN_WDAYS,
#     config/recurring.yml의 reminders_dispatch와 같아야 한다)을 회원의 REM-3 허용 창에
#     비춘 실행 시각(User#next_remind_slot).
# nil 반환 없음 — (회원, 청구, template_key)에 항상 다음 실행 예정 시각을 돌려주므로 소비자는
# `to_date == Date.current` 비교로 "실제 발송일이 오늘인가"만 판정한다(주말·비허용 요일·
# 14시가 창 밖인 회원의 미룸·당일 스캔 경과분은 오늘이 아니게 된다).
# 발송 스캔·스텝 모집합 판정은 DispatchService 단일 진입점을 그대로 쓴다 — 이 객체는 시각 산정만.
module Reminders
  class SendSchedule
    # (청구, template_key)의 실제 발송 예정 시각 — 위 클래스 헤더의 ①② 규칙. 항상 Time.
    def self.send_at_for(user:, invoice:, template_key:)
      slot = MessageLog.find_by(invoice_id: invoice.id, template_key: template_key,
                                recipient_role: :debtor, status: :pending)
      return slot.scheduled_at if slot && slot.scheduled_at && slot.scheduled_at >= Time.current

      user.next_remind_slot(next_scan_time)
    end

    # 다음 발송 스캔 시각 — 오늘이 스캔 요일이고 스캔 시각 전이면 오늘, 아니면 다음 스캔
    # 요일의 스캔 시각(KST — TIME-1). 스캔 요일·시각은 DispatchService 스캔 상수 단일 출처.
    def self.next_scan_time
      today = Date.current
      scan = Time.zone.local(today.year, today.month, today.day,
                             Reminders::DispatchService::SCAN_HOUR)
      return scan if Reminders::DispatchService::SCAN_WDAYS.include?(today.wday) && Time.current < scan

      date = today + 1.day
      date += 1.day until Reminders::DispatchService::SCAN_WDAYS.include?(date.wday)
      Time.zone.local(date.year, date.month, date.day, Reminders::DispatchService::SCAN_HOUR)
    end
  end
end
