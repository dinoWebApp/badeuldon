module Dashboards
  # DASH-2·Q31 — 「오늘의 액션」 안내성 세 종의 산출(W-5 층 분리 — 2026-11-26 리뷰 반영).
  # 후보 조회는 Query Object(app/queries/dashboards/)가, 발송 예정 시각 산정·5건 절단은
  # 이 서비스가 담당한다. 결과는 Result Struct — 컨트롤러는 @변수 1개로 받아 뷰에 전달한다
  # (뷰 쿼리 없음, 액션 본문 10줄 규칙).
  #   todays_sends — SendRow(invoice·template_key·send_at) 최대 DASH_ACTION_LIMIT건과
  #                  todays_sends_total(절단 전 총건수 — 뷰의 "외 N건" 안내용). 절단은
  #                  발송 예정 시각 오름차순으로 한다(DASH-2 "발송 예정 시각이 이른 순서")
  #   promises_due_today·unviewed_idle — 각 Query의 Row 배열과 *_total
  #
  # 「오늘 발송 예정」의 send_at(리뷰 C-1·C-2) — 실제 발송 예정 시각 산정(① pending 슬롯
  # ② next_remind_slot(다음 스캔))은 Reminders::SendSchedule이 단일 출처다(복제 금지 —
  # 위임만 한다). 이 서비스는 send_at.to_date == 오늘 필터·정렬·5건 절단만 담당한다.
  # 모집합 판정(scheduled_today_keys — 상한·보류·수신 거부·소급 창·이미 발송 제외)은
  # 발송 스캔과 같은 단일 출처를 유지한다(REM-11 당일 보류 창의 화면 진입점).
  class ReminderActionsService
    DASH_ACTION_LIMIT = 5  # DASH-2·Q31 — 안내성 세 종의 종류별 표시 상한(초과분은 "외 N건" 안내)

    Result = Struct.new(:todays_sends, :todays_sends_total,
                        :promises_due_today, :promises_due_today_total,
                        :unviewed_idle, :unviewed_idle_total, keyword_init: true)
    SendRow = Struct.new(:invoice, :template_key, :send_at, keyword_init: true)

    def self.call(user:)
      new(user: user).call
    end

    def initialize(user:)
      @user = user
    end

    def call
      todays_sends = build_todays_sends
      promises = PromisesDueTodayQuery.call(user: @user)
      unviewed = UnviewedIdleQuery.call(user: @user)
      Result.new(
        todays_sends: todays_sends.first(DASH_ACTION_LIMIT),
        todays_sends_total: todays_sends.size,
        promises_due_today: promises.first(DASH_ACTION_LIMIT),
        promises_due_today_total: promises.size,
        unviewed_idle: unviewed.first(DASH_ACTION_LIMIT),
        unviewed_idle_total: unviewed.size
      )
    end

    private

    # 후보 청구(TodaysSendsQuery — 상위 집합)를 스캔과 같은 단일 출처 판정으로 좁히고,
    # 실제 발송 예정 시각이 오늘인 행만 남긴다. 한 청구에서 두 스텝이 같은 날 창 내에 있으면
    # (주말 이월 등) 행 2개 — 스캔도 두 스텝을 모두 발송하므로 화면과 실발송이 정합이다.
    # 후보 Relation은 만기일 순이라 5건 절단(W-1) 시 재예약된 이른 슬롯(오전 9시) 카드가
    # 늦은 ②(오후 2시) 행에 밀려 잘릴 수 있다 — 잘린 건은 대시보드에서 보류할 수 없으므로
    # 절단 전에 발송 예정 시각 오름차순(같은 시각은 청구 id 오름차순, 완전 동률은 산정 순서
    # 유지 — 스캔도 steps_for 순서로 발송한다)으로 정렬한다(DASH-2·2차 리뷰 W-1).
    def build_todays_sends
      today = Date.current
      scanner = Reminders::DispatchService.new
      rows = TodaysSendsQuery.call(user: @user).flat_map do |invoice|
        scanner.scheduled_today_keys(invoice).filter_map do |template_key|
          send_at = Reminders::SendSchedule.send_at_for(user: @user, invoice: invoice,
                                                        template_key: template_key)
          next unless send_at.to_date == today  # 실제 발송일이 오늘이 아닌 건은 카드에서 뺀다(C-1·C-2)

          SendRow.new(invoice: invoice, template_key: template_key, send_at: send_at)
        end
      end
      rows.sort_by.with_index { |row, index| [ row.send_at, row.invoice.id, index ] }
    end
  end
end
