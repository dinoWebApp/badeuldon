module Dashboards
  # DASH-2·Q31 — 「오늘 발송 예정」 카드의 후보 청구 조회(W-5 층 분리 — 2026-11-26 리뷰 반영).
  # 자격·모집합·후보 범위까지만 판정한 상위 집합을 Relation으로 돌려주는 것만 담당한다 —
  # 과잉 포함이며, 최종 판정(오늘 도래 스텝·상한·실제 발송 예정 시각이 오늘인 행 선별)은
  # Dashboards::ReminderActionsService가 발송 스캔과 같은 단일 출처
  # (Reminders::DispatchService#scheduled_today_keys)로 한다. Query는 Model만 의존한다(규약 §4.1).
  # 성능 — 전체 미수 청구에 스텝 산정을 돌리지 않고 오늘 도래 가능한 후보로 먼저 좁힌다:
  #   기본 트랙 — 스텝 nominal은 만기일 기준 D-1~D+14이고 소급 창은 최대 nominal+3(금요일
  #   nominal의 월요일 창 종료)이므로 due_on ∈ 오늘−17..오늘+1 (오늘−16이 아니다: 금요일 만기의
  #   D+14가 창 종료 월요일까지 살아있는 건은 due = 오늘−17 — 주말 경계 테스트 참조).
  #   약속 트랙 — 스텝 nominal은 약속일 기준 −1(promise_d1)·+1(promise_overdue)이므로
  #   promised_on ∈ 오늘−4..오늘+1.
  # 정렬은 만기일 오름차순(sorted_by_due), 카드 렌더·confirm 분기 판정용 includes 동반.
  class TodaysSendsQuery
    def self.call(user:)
      return Invoice.none unless user.reminder_eligible?  # REM-8 — Free는 자동 발송이 없다(거짓 0건 카드 금지)

      candidate_scope(user, Date.current)  # TIME-1 — KST 기준
    end

    def self.candidate_scope(user, today)
      scope = user.invoices.reminders_dispatchable
      base_ids = scope.where(due_on: (today - 17)..(today + 1)).pluck(:id)
      promise_ids = Promise.where(kind: Promise.kinds.slice(:this_week, :date_selected).values,
                                  promised_on: (today - 4)..(today + 1))
                           .where(invoice_id: scope.select(:id)).pluck(:invoice_id)
      scope.where(id: base_ids | promise_ids)
           .includes(:client, :view_events)  # 카드 렌더·confirm 분기 판정의 N+1 방지
           .sorted_by_due
    end
  end
end
