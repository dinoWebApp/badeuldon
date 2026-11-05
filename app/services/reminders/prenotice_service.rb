# 사전통보 스캔(F-REM — REM-11·NOTI-1) — 평일 09:00(Reminders::PrenoticeJob). 오늘(소급 창
# 포함) 발송 예정인 연체·도과 단계 스텝을 보유한 청구의 U1에게 noti_prenotice를 먼저 보내
# 14시 발송 전 취소 창(REM-11 — 원클릭 마감·보류로 오발송 차단)을 제공하고, 다음 실행일까지
# 만기 도래하는 청구의 U1에게 noti_due_soon을 청구서별 1통씩 보낸다(NOTI-1 — 카카오 템플릿
# 가변 반복 불가로 건수만큼 개별 발송).
# 발송 예정 판정은 Reminders::DispatchService.steps_due_today(발송 스캔과 동일 소급 창·
# 미발송 판정)의 단일 진입점을 쓴다(C-2 — 주말 nominal의 월요일 소급분도 09시 통보가
# 커버하고, 14시 발송과 같은 모집단을 안다). 대상 모집합은 발송 스캔과 동일한
# reminders_dispatchable이며, noti_prenotice는 실제 발송이 일어날 건(자격 있음 — REM-8)만
# 알린다. 무상태 스캔 — 재실행은 scheduled_at(당일 09시) 기준 멱등 흡수된다(SendService).
module Reminders
  class PrenoticeService
    # client — 솔라피 래퍼 주입 지점(W-7 — U1 향 통보까지 전 경로 stub 주입 가능하게
    # NotifyUserService로 전달). 미주입 시 SendService가 기본 래퍼를 지연 생성한다.
    def initialize(client: nil)
      @client = client
    end

    def call
      notify_prenotice_targets
      notify_due_soon_targets
    end

    private

    def notify_prenotice_targets
      scanner = Reminders::DispatchService.new
      dispatchable.find_each do |invoice|
        next if scanner.steps_due_today(invoice).empty?
        next unless invoice.user.reminder_eligible?  # REM-8 — 발송 예정이 없는 건은 통보도 없다

        Reminders::NotifyUserService.new(invoice: invoice, template_key: "noti_prenotice",
                                         scheduled_at: today_at_9, client: @client).call
      end
    end

    # NOTI-1 — 만기 임박 요약(정보성 — 플랜·자격 무관, 청구서별 1통). 다음 실행일(다음 평일)
    # 까지 만기 도래 건 전부를 커버한다(W-3 — 금요일 아침이 토·일·월 만기분을 묶어 선행
    # 통보한다. 통보 잡 공백(주말)으로 만기가 흘러도 통보 없이 지나가지 않는다).
    def notify_due_soon_targets
      dispatchable.where(due_on: due_soon_range).find_each do |invoice|
        Reminders::NotifyUserService.new(invoice: invoice, template_key: "noti_due_soon",
                                         scheduled_at: today_at_9, client: @client).call
      end
    end

    def dispatchable
      Invoice.reminders_dispatchable.includes(:user)
    end

    # 내일부터 다음 실행일(다음 평일)까지의 만기일 범위 — 평일 잡은 매일 실행되므로
    # 월~목은 내일(=다음 실행일) 1일, 금요일은 토·일·월 3일이다.
    def due_soon_range
      tomorrow = Date.current + 1.day
      next_run = tomorrow
      next_run += 1.day while next_run.saturday? || next_run.sunday?
      tomorrow..next_run
    end

    # 당일 재실행 멱등의 기준값 — 같은 날 재실행은 같은 scheduled_at이라 흡수되고, 다른 날·다른
    # 스텝의 사전통보는 새 이력이 된다(SendService의 U1 향 scheduled_at 판정).
    def today_at_9
      Time.current.change(hour: Reminders::SendService::WINDOW_START_HOUR, min: 0)
    end
  end
end
