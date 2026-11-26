# T5 03_implementation — 사전통보 실제 발송 시각 정합(REM-11·REM-3·DASH-2)

## 변경 파일

| 파일 | 변경 |
|:--|:--|
| `app/services/reminders/send_schedule.rb` | **신설** — `Reminders::SendSchedule` 값 객체(단일 출처) |
| `app/services/dashboards/reminder_actions_service.rb` | 프라이빗 `send_at_for`·`next_scan_time` 삭제 → `Reminders::SendSchedule.send_at_for` 위임(동작 불변) |
| `app/services/reminders/prenotice_service.rb` | `notify_prenotice_targets`에 `today_send?` 필터 추가 + 헤더 주석 갱신 |
| `test/services/reminders/send_schedule_test.rb` | **신설** — 8 케이스 |
| `test/services/reminders/prenotice_service_test.rb` | 5 케이스 보강(음성·양성 모두 단언) |

수정 없음: `dispatch_service.rb`(읽기만 — SCAN_HOUR·SCAN_WDAYS·steps_due_today 참조)·`send_service.rb`·모델·컨트롤러·config·db·locales·픽스처.

## SendSchedule 코드 전문

```ruby
module Reminders
  class SendSchedule
    def self.send_at_for(user:, invoice:, template_key:)
      slot = MessageLog.find_by(invoice_id: invoice.id, template_key: template_key,
                                recipient_role: :debtor, status: :pending)
      return slot.scheduled_at if slot && slot.scheduled_at && slot.scheduled_at >= Time.current

      user.next_remind_slot(next_scan_time)
    end

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
```

(파일에는 REM-11·DASH-2 단일 출처·①② 규칙·nil 없음 주석 포함.) 로직은 기존 `ReminderActionsService` 프라이빗 메서드와 1:1 이동 — 대시보드는 위임만 하고 기존 테스트 무수정 통과.

## 사전통보 선별 로직 (전후)

- 전: `next if scanner.steps_due_today(invoice).empty?` → 통보(REM-11 사실 아님 통보 발생).
- 후: `steps_due_today`가 비어 있지 않아도 `today_send?(invoice, due_keys)` — 각 template_key의 `SendSchedule.send_at_for(...).to_date == Date.current`가 하나라도 참일 때만 통보. `scheduled_at: today_at_9`·멱등 기준·`noti_due_soon`·`reminders_dispatchable`·`reminder_eligible?` 필터 불변.

## 테스트 결과 (케이스별 — travel_to KST 고정)

| 케이스 | 회원 창 | 판정 | 결과 | 근거 시각 |
|:--|:--|:--|:--|:--|
| 기본 창 화요일 13시 | 09~18 | 통보함 | 기존 동작 유지 | 다음 스캔 = 오늘(화) 14:00 |
| 종료 14시 + 오늘 nominal 스텝 | 09~14 | 통보 없음 | 음성 | ② 폴백 → 수(11-11) 09:00 |
| 시작 15시 | 15~18 | 통보함 | 양성 | 오늘(화) 15:00 |
| 오늘이 비허용 요일(화, wday 1·3·5) | — | 통보 없음 | 음성 | 수 09:00 |
| 전날 재예약된 오늘 09시 pending 슬롯 | 09~14 | 통보함 | 양성(① 경로) | 슬롯 scheduled_at 오늘 09:00 |
| 주말 소급분(토 만기→nominal 일) 월요일 09시 | 09~14 | 통보 없음 / 기본 창 복원 뒤 통보함 | 음성+양성 대조 | 창 밖 → 화 09:00 / 기본 → 월 14:00 |

SendSchedule 단위 8건: 기본 14:00 / 시작 15시 오늘 15:00 / 종료 14시 다음 허용 요일 시작 시각 / 비허용 요일·주말·14시 정각 경과 → 오늘 아님 / ① 슬롯 우선(미래)·경과 슬롯·nil pending → ② 폴백 / U1 향 슬롯 미인식 / `next_scan_time` 13:59:59→오늘 14:00, 14:00:00→다음 평일 14:00, 금 저녁→월 14:00.

## 검증

- `DATABASE_URL=sqlite3:tmp/parallel/T5/test.sqlite3 bin/rails test test/services/reminders test/services/dashboards test/controllers/app/dashboards_controller_test.rb test/controllers/app/dashboards_actions_test.rb test/queries/dashboards test/controllers/app/invoices_reminders_test.rb` — **209 runs, 1082 assertions, 0 failures** (기존 `reminder_actions_service_test.rb` 무수정 통과 — 위임 동작 불변 확인)
- `bin/rubocop <자기 5파일>` — 0 offenses
- `bin/rails zeitwerk:check` — "Otherwise, all is good!"
- 솔라피 실호출 없음 — Prenotice 테스트는 기존 `client:` 주입(FakeSolapiClient) 체계 사용, SendSchedule·대시보드 테스트는 산정만 수행(발송 경로 없음). 템플릿·문구 무변경.

## 남은 우려

1. **09:00 정각 슬롯 경계**: `scheduled_at >= Time.current`라 오전 9시 정각에 사전통보가 실행되는 순간 오늘 09:00 재예약 슬롯은 "아직 안 지났다"로 ①을 타고 통보한다. 슬롯이 09시 정각 실행되어 즉시 발송되면 통보가 발송 직후 도착할 수 있으나, 실제 DeliverJob 실행과의 경합은 극단적 케이스(통보는 발송 창 시작 전 취소 창 제공이 목적이므로 오알림 부작용 최소).
2. `today_send?`는 steps_due_today의 키마다 MessageLog 1회 조회 + next_remind_slot 계산 — 사전통보 대상 청구 수가 적어(연체 도래분) 성능 영향 미미.
3. `MessageLog.delete_all`로 대조하는 주말 소급분 테스트(음성→양성 전환)는 같은 travel 블록 내 설정 변경을 전제로 한다 — 설정 검증 순서 의존은 테스트 내부에 한정.
