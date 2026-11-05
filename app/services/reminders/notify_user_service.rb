# U1(프리랜서) 향 알림 발송 진입점(F-REM·NOTI-1) — 수신자는 invoice.user의 프로필 번호다.
# REM-3 발송 창을 적용하지 않고 즉시 발송한다(02_prd_update 확정 해석 3 — PERF-1 60초와 창
# 이연의 충돌 회피; 창 판정은 SendService가 recipient_role로 분기한다). scheduled_at이
# 주어지면(사전통보류 noti_prenotice·noti_due_soon) 같은 예정시각의 재실행을 멱등 흡수하고,
# 주어지지 않으면(이벤트 알림) 이벤트마다 새 이력을 기록한다. phone 미등록은 skipped+NO_PHONE
# 으로 기록된다(에러 아님 — 01_plan 리스크 노트).
module Reminders
  class NotifyUserService
    # client — 솔라피 래퍼 주입 지점(W-7 — PortOne 패턴 준용·SendService로 전달).
    # 미주입 시 SendService가 첫 발송 시점에 기본 래퍼를 지연 생성한다.
    def initialize(invoice:, template_key:, scheduled_at: nil, client: nil)
      @invoice = invoice
      @template_key = template_key
      @scheduled_at = scheduled_at
      @client = client
    end

    def call
      Reminders::SendService.new(invoice: @invoice, template_key: @template_key,
                                 recipient_role: :user, scheduled_at: @scheduled_at,
                                 client: @client).call
    end
  end
end
