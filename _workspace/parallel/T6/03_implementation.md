# T6 — REM-3 발송 요일·시간대 세부 지정 UI (03_implementation)

날짜: 2026-11-16 · 병렬 배치 T6 · 마이그레이션 생성 금지(스키마 선언만 — 3-S 통합)

## 1. 스키마 선언 (마이그레이션은 3-S에서 생성 — 정확 명세)

`users` 테이블 3컬럼 추가:

| 컬럼명 | 타입 | default | null | 비고 |
|---|---|---|---|---|
| `remind_allowed_wdays` | string | `"1,2,3,4,5"` | false | 허용 요일 정수 csv — 1=월…5=금. 0(일)·6(토)은 상시 불허(REM-3 고정 경계). |
| `remind_start_hour` | integer | `9` | false | 허용 창 시작 시각(시). 9 이상 17 이하. |
| `remind_end_hour` | integer | `18` | false | 허용 창 종료 시각(시, 이 시각부터 발송 불가). 10 이상 18 이하, 시작보다 늦어야 함. |

인덱스 불요(사용자 행 단독 조회 경로). 기본값이 REM-3 고정 경계 전체(평일 09~18)와 동일 — 기존 사용자 무중단 호환.

## 2. 변경 파일

| 파일 | 내용 |
|---|---|
| `app/models/user.rb` | `REMIND_ALLOWED_WDAYS`·`REMIND_MIN_HOUR`(9)·`REMIND_MAX_HOUR`(18) 상수, 검증 4종(요일 1~5+최소 1일·start≥9·end≤18·start<end), `remind_allowed_wday_list`(csv 파싱·1~5 필터), `remind_window_open?(time)`, `remind_allowed_wday?(time)`, **`next_remind_slot(from)` 순수 이월 계산** |
| `app/services/reminders/send_service.rb` | `outside_window?` → `!user.remind_window_open?(Time.current)` 단일 출처 위임. `next_window_at` → `user.next_remind_slot(Time.current)`. 미사용 `weekday?` 제거. WINDOW_START/END_HOUR 상수는 고정 경계 문서화로 유지. 헤더·상수 주석 갱신 |
| `app/controllers/app/profiles_controller.rb` | `profile_params`에 `remind_start_hour`·`remind_end_hour`·`remind_allowed_wdays: []` 추가. `remind_profile_params` — 요일 배열→csv 변환 + 1~5 이외(0·6·공백) 서버 제거(고정 경계 이중 보장) |
| `app/helpers/app/profiles_helper.rb` | `REMIND_WDAY_OPTIONS`(월~금), `remind_start_hour_options`(09~17), `remind_end_hour_options`(10~18), `remind_wday_checkbox_classes` |
| `app/views/app/profiles/edit.html.erb` | "알림 발송 시간" 섹션 신설 — 요일 체크박스(월~금, hidden empty로 미체크 제출 보장)·시작/종료 시각 select·도움말("야간·주일(주말) 발송은 정책상 불가…"). 기존 폼 스타일(카드·포커스 링·오류 상태) 재사용 |

## 3. 이월 규칙 명세 (User#next_remind_slot — SendService.next_window_at 위임)

판정: `wday ∈ 허용 요일 && start_hour <= hour < end_hour` → 발송. 밖이면 이월:
- 허용 요일 + 개방 전(hour < start) → **당일** start 시각
- 허용 요일 + 종료 경계 이후(hour >= end) → **다음 날부터** 스캔한 첫 허용 요일의 start 시각
- 비허용 요일 → 다음 허용 요일의 start 시각
- 허용 요일이 검증으로 최소 1개 보장 → 루프 반드시 종료. 시퀀스 D+1/D+7 의미 불변(슬롯 이월만).

예시(검증 스크립트 9케이스 전부 PASS — 2026-11-16=월 기준):

| 설정 | 시각 | 결과 |
|---|---|---|
| 기본(월~금 9~18) | 금 18:00 | 월 09:00 (종료 경계 → 다음 허용일) |
| 기본 | 토 10:00 | 월 09:00 |
| 기본 | 월 07:30 | 당일 09:00 (개방 전) |
| 기본 | 월 17:59 | 그대로 (경계 직전 허용) |
| 화·목 13~16 | 월 14:00 | 화 13:00 |
| 화·목 13~16 | 화 16:00 | 목 13:00 (종료 경계) |

**자체 버그 수정 기록**: 초안은 "허용 요일의 종료 경계 이후"가 당일 start로 되돌아가는 결함 → else 분기를 `from.to_date + 1.day`부터 스캔하도록 교정.

## 4. REM-3 고정 경계 유지 확인

- 확장 경로 전무: 검증(요일 1~5만·start≥9·end≤18) + 컨트롤러 서버 필터(0·6 제거) + select 선택지 자체가 9~18 범위 한정.
- 창 밖 접수분은 기존 `reschedule!` 경로 그대로 — pending+scheduled_at 기록(W-4)·부분 유니크 멱등(SEC-5) 유지.
- U1 향(창 무관 즉시)·PrenoticeService(당일 09시 scheduled_at 표기)는 기존 동작 유지 — 채무자 향만 설정 반영.
- 주간 다이제스트·`config/recurring.yml`·subscription/payments 등 T5·T7 소유 파일 미접촉.

## 5. 자가 검증 결과

- `bin/rubocop` 수정 Ruby 4파일: **0 offense** (ERB는 저장소 기존 베이스라인 노이즈 — stash 비교로 동일 유형 확인).
- `ruby -c` profiles_controller: OK. Rails 부트·테스트·마이그레이션 실행은 fan-out 제약으로 미수행(컬럼 선언 후 통합 검증 필요).
- 이월 로직은 순수 Ruby 복제 스크립트로 9 시나리오 단독 검증 PASS(위 §3 표).
