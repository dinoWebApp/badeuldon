# T4 구현 결과 — 픽스처 가드 강화 + 대시보드 서비스 헤더 주석 정리

## 범위
- 리뷰 O-2(`_workspace_prev/05_review.md` T1 절) — 가드의 미커버 형식 2가지
- 리뷰 T5 절 메모 — `Dashboards::ReminderActionsService` 헤더의 ①② 규칙 설명 2중화

## 1. 픽스처 가드 강화 — `test/fixtures_no_future_date_test.rb`

### 변경 전후
- **(a) ERB 혼합 줄**: 변경 전은 줄에 `<%`가 하나라도 있으면 줄 전체를 건너뛰었다 →
  `expires_at: <%= 30.days.from_now %> # 2099-12-31` 같은 줄의 고정 날짜가 미탐.
  변경 후 `text_outside_erb(line)`로 ERB 태그(`<% ... %>`) 부분만 제거한 나머지 텍스트를 검사.
  줄 경계를 넘는 미완결 태그(`<%` 또는 `%>`만 있는 줄)는 태그 바깥만 남긴다.
  여러 줄 ERB 블록 추적(블록 안 줄 제외)은 기존 로직 그대로 유지.
- **(b) 구분자 확장**: `20\d{2}-\d{2}-\d{2}` → `DATE_LITERAL_PATTERN =
  /20\d{2}[.\-\/](?:0[1-9]|1[0-2])[.\-\/](?:0[1-9]|[12]\d|3[01])/` — 점·슬래시 추가,
  월 01~12·일 01~31 범위 제한(캡처 그룹은 scan 배열 반환 방지용 non-capturing).

### 오탐 점검(전체 픽스처 대상)
- `110-234-567890`(계좌번호)·`010-3333-7777`(전화번호): `20` 시작이 아니어도 미매치 — 확인 완료.
- `BD-20260901-001`: 구분자 없는 숫자 나열이라 미매치 — 확인 완료.
- 월·일 범위 제한으로 `2026-13-40` 같은 비날짜도 제외 — 가드 자체 테스트로 고정.
- 점·슬래시 날짜 리터럴은 현재 픽스처에 0건(grep 실측).

### 유지 사항
- 인라인 마커(`# fixtures_no_future_date`) 예외, `Date.current` wall-clock 비교, travel 없음,
  실패 메시지에 파일:라인·리터럴 + **ERB 제거 후 줄 텍스트**(신규 포함).

### 가드 자체 동작 고정
- 판정 로직을 private `future_date_literals(text)`(문자열 입력 → 미래 리터럴 목록)로 분리하고
  5건의 자체 테스트 추가: ① ERB 섞인 줄 미래 날짜 탐지 ② 과거 날짜 미탐 ③ 여러 줄 ERB 블록 무시
  ④ 점·슬래시 탐지 ⑤ 계좌번호·전화번호·품목 코드 오탐 없음 + ⑥ 마커 제외(총 6 test).

## 2. 주석 정리 — `app/services/dashboards/reminder_actions_service.rb`
- 헤더 주석의 ①② 산정 규칙 상세 설명 블록(약 13줄)을 `Reminders::SendSchedule` 단일 출처
  포인터 4줄로 축소(① pending 슬롯 ② next_remind_slot(다음 스캔) — 이 서비스는
  `to_date == 오늘` 필터·정렬·5건 절단만 담당).
- **코드 변경 0건** — 주석 블록만 교체, 다른 주석(정렬 사유·모집합 판정 등) 그대로.
- `Reminders::SendSchedule` 헤더(규칙의 단일 출처)는 변경 없음.

## 테스트 결과
- `DATABASE_URL=sqlite3:tmp/parallel/T4/test.sqlite3 bin/rails test test/fixtures_no_future_date_test.rb test/services/dashboards test/controllers/app/dashboards_controller_test.rb`
  → **47 runs, 216 assertions, 0 failures, 0 errors, 0 skips**
- 픽스처 전수 검사(가드 본 테스트): 현재 고정 미래 날짜 리터럴 **0건** — 통과.
- `bin/rubocop test/fixtures_no_future_date_test.rb app/services/dashboards/reminder_actions_service.rb`
  → **no offenses**

## 소유 파일(외부 변경 없음)
- `test/fixtures_no_future_date_test.rb` — 재작성(가드 강화 + 자체 테스트 6건)
- `app/services/dashboards/reminder_actions_service.rb` — 주석만 축소
