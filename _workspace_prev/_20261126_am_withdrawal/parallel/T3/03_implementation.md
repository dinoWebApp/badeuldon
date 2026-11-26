# 03_implementation — T3 대시보드 「오늘의 액션」 나머지 세 종 (DASH-2·Q31, 2026-11-26)

기준: `_workspace/01_plan.md` T3·`_workspace/02_prd_update.md`(PRD v0.50 §6.9 DASH-2 구현 확정·§6.6 REM-11·§10 Q31)·`ARCHITECTURE_CONVENTION.md`(Query Object §3.2). 병렬 규칙 준수 — 소유 파일만 수정, 격리 DB로 자기 테스트만 실행, 전체 테스트·시스템 실행·서버 기동·db:migrate 없음.

## 1. 변경 파일 목록

### 신설
| 파일 | 내용 |
|:--|:--|
| `app/queries/dashboards/todays_sends_query.rb` | 오늘 발송 예정 조회 — `.call(user:)` → `Row(invoice, template_key)` 배열. Free는 빈 결과(REM-8), 발송 스캔과 같은 단일 출처 판정 |
| `app/queries/dashboards/promises_due_today_query.rb` | 약속일 도래 조회 — 최신 약속(this_week·date_selected)의 약속일이 오늘인 미수 청구 → `Row(invoice, promise)` |
| `app/queries/dashboards/unviewed_idle_query.rb` | 미열람 방치 조회 — `IDLE_DAYS = 3`, status issued·issued_at 3일 이상 경과 → `Row(invoice, idle_days)` |
| `app/views/app/dashboards/_todays_send_card.html.erb` | 오늘 발송 예정 카드(보류하기 button_to + 청구서 확인) |
| `app/views/app/dashboards/_promise_due_card.html.erb` | 약속일 도래 카드 |
| `app/views/app/dashboards/_unviewed_idle_card.html.erb` | 미열람 방치 카드(경과 일수 표기) |
| `app/views/app/dashboards/_action_overflow_note.html.erb` | 종류별 5건 초과 안내("{라벨} 5건 외에 N건이 더 있습니다." + 목록 링크) |
| `test/queries/dashboards/todays_sends_query_test.rb` | 9 케이스 — 정상·내림 경계·주말 이월(2행)·보류/거부/종결·상한·마감/무효/초안·Free·약속 트랙 후보·정렬·격리 |
| `test/queries/dashboards/promises_due_today_query_test.rb` | 7 케이스 — 오늘 약속·정렬·재응답 최신 우위·this_week(금요일)·paid_report/inquiry 비약속·내일 제외·마감/초안·격리 |
| `test/queries/dashboards/unviewed_idle_query_test.rb` | 6 케이스 — 3일 경과·당일 경계(23:59/00:00)·열람·연체 제외·마감/무효/초안/nil 발행 제외·정렬·격리 |
| `test/system/app_dashboard_actions_test.rb` | 오늘 발송 예정 카드 보류 E2E 1건 — **작성만, 실행 안 함(지시)** |

### 수정
| 파일 | 내용 |
|:--|:--|
| `app/services/reminders/dispatch_service.rb` | 공개 메서드 `scheduled_today_keys(invoice)` 신설(만기 예고 `invoice_notice`·약속 전날 `promise_d1` 포함한 오늘 발송 스텝 전체). `steps_due_today`는 이를 위임(`scheduled_today_keys`에서 `PRENOTICE_KEYS` select) — **동작·결과 불변**, 기존 테스트 무수정 통과. 클래스 헤더 주석의 단일 출처 목록에 추가. 그 외 메서드(`call`·`manual_step_key`·`restartable?`·private 전체) 무변경 |
| `app/controllers/app/dashboards_controller.rb` | `DASH_ACTION_LIMIT = 5` 상수 + private `load_reminder_actions` 신설(세 조회 호출 → 종류별 최대 5건·총건수 적재). `show`는 호출 1줄 추가(본문 10줄 규칙 유지 — 기존 구조 그대로) |
| `app/views/app/dashboards/show.html.erb` | DASH-2 섹션 재구성 — 다섯 종 PRD 순서(①오늘 발송 예정 ②약속일 도래 ③미열람 방치 ④마감 대기 ⑤답변 대기), 새 3종은 파셜 렌더, 기존 마감 대기·답변 대기 카드는 **마크업·클래스·문구 그대로 유지**, 초과 종류 뒤 "외 N건" 노트, 다섯 종 모두 없을 때만 기존 빈 상태(문구 유지) |
| `app/helpers/app/base_helper.rb` | `dash_action_badge`·`dash_action_icon_path`에 `todays_send`(주황·시계)·`promise_due`(녹색·달력)·`unviewed`(중립·가린 눈) 추가 — 기존 closure·answer·empty 값 불변 |
| `test/services/reminders/dispatch_service_test.rb` | `scheduled_today_keys` 테스트 6건 추가(기존 테스트 무수정) — 만기 예고 포함·이미 발송 제외·창 경과 제외·상한 빈 배열·promise_d1 차이·연체 단계 동등성 |
| `test/controllers/app/dashboards_controller_test.rb` | 2건 추가 — 다섯 종 PRD 순서(delta·travel 10-12)·종류별 5건 제한과 "외 N건"(gamma·미열람 6건). 클래스 헤더 주석 갱신 + `ReminderFactories` include |
| `test/controllers/app/dashboards_actions_test.rb` | 4건 추가 — 보류하기 액션 제공(form.button_to·turbo_confirm·라벨)·Free 오늘 발송 예정 없음+빈 상태·청구서 있어도 다섯 종 없으면 빈 상태(조건 확장 회귀)·약속일 도래·미열람 카드 판정별 렌더. 헤더 주석 갱신 + `ReminderFactories` include |

수정하지 않은 소유 범위 밖 파일: 없음(요청 불필요 — 아래 §6 참조). `git status`로 확인 — T0/T1/T2·오케스트레이터 파일과 무결.

## 2. Rule ID 매핑

| Rule ID | 구현 |
|:--|:--|
| **DASH-2·Q31** | 다섯 종 카드를 PRD 순서대로 표시(뷰 섹션 재구성), 종류별 최대 5건 + 초과분 "외 N건"·청구서 목록 링크, ①오늘 발송 예정(`TodaysSendsQuery`) ②약속일 도래(`PromisesDueTodayQuery`) ③미열람 방치(3일 — `UnviewedIdleQuery`) 신설, Free 회원 오늘 발송 예정 0건(거짓 0건 카드 금지 — 빈 상태 유지) |
| **REM-11** | 오늘 발송 예정 카드 = 당일 보류 창의 화면 진입점 — 판정은 14시 발송 스캔과 같은 단일 출처(`reminders_dispatchable` ∧ `DispatchService#scheduled_today_keys` — 만기 예고 포함), 상한 도달 청구는 예정 카드에서 제외(PLAN-3·Q28 수렴), 「보류하기」는 기존 REM-7 `suspend_reminders` PATCH 재사용(확인창·성공 시 청구 상세 303) |
| **DESIGN-5** | 카드형 리스트 — 기존 카드 2종의 article 마크업·아이콘 박스(h-11 w-11 rounded-xl)·뱃지·제목 위계·액션 버튼(min-h-11·focus 링)을 새 카드에 그대로 적용, DESIGN-2 상태색 3종(오늘 발송 예정·답변 대기 주황 / 약속일 도래·마감 대기 녹색 / 미열람 중립) |
| **보조** | REM-2 톤(문구에 "독촉·연체" 어휘 없음 — "안내" 어휘), REM-8(자격 없는 회원 오늘 발송 예정 없음), SEC-5·REM-3(scheduled_today_keys가 스캔과 같은 미발송·소급 창 판정 공유 — 이원화 차단), TIME-1(전 판정 `Date.current` KST), 규약 §3.2(조회는 Query Object·컨트롤러 @변수 적재·뷰 쿼리 없음), INV-4(미열람 = status issued — `mark_viewed!` 유일 전이) |

## 3. 사용자 가시 문구 전문 (뷰에 직접 적음 — locale 수정 없음)

- **오늘 발송 예정 카드**: 뱃지 `오늘 발송 예정` / 제목 `{거래처명} · {청구 총액}` / 설명 `오늘 오후 2시에 「{템플릿 라벨}」를 보냅니다. 발송 전까지 보류할 수 있습니다.`(라벨은 `message_template_label` — 예: 만기 예정 안내·입금 확인 안내·재안내(만기 7일 후)·약속일 전날 안내) / 버튼 `보류하기`(확인창: `이 청구서의 자동 안내를 멈춥니다. 보류하시겠습니까?` — 기존 문구 재사용) / 링크 `청구서 확인`
- **약속일 도래 카드**: 뱃지 `약속일 도래` / 제목 동일 / 설명 `오늘 입금하기로 한 약속이 있습니다. 입금되었으면 마감해 주세요.` / 링크 `청구서 확인`
- **미열람 방치 카드**: 뱃지 `미열람` / 제목 동일 / 설명 `발행 후 {N}일이 지났지만 아직 열지 않았습니다.`(N = 오늘 − 발행일) / 링크 `청구서 확인`
- **5건 초과 안내**(종류별): `{라벨} 5건 외에 {N}건이 더 있습니다. 청구서 목록에서 확인`(링크는 `app_invoices_path`)
- **빈 상태**(기존 문구 유지): `오늘 할 일이 없습니다` / `첫 청구서를 발행하면 오늘 발송 예정·약속일 도래 같은 처리할 일이 카드로 표시됩니다.`
- 기존 마감 대기·답변 대기 카드 문구: 변경 없음.

## 4. 실행한 검증과 결과

```bash
mkdir -p tmp/parallel/T3
DATABASE_URL=sqlite3:tmp/parallel/T3/test.sqlite3 bin/rails zeitwerk:check   # 통과 ("Otherwise, all is good!")
bin/rubocop app/services/reminders/dispatch_service.rb app/queries/dashboards/ \
  app/controllers/app/dashboards_controller.rb app/views/app/dashboards/ app/helpers/app/base_helper.rb \
  test/queries/dashboards/ test/controllers/app/dashboards_controller_test.rb \
  test/controllers/app/dashboards_actions_test.rb test/services/reminders/dispatch_service_test.rb \
  test/system/app_dashboard_actions_test.rb
# → 13 files inspected, no offenses
DATABASE_URL=sqlite3:tmp/parallel/T3/test.sqlite3 bin/rails test \
  test/queries/dashboards test/controllers/app/dashboards_controller_test.rb \
  test/controllers/app/dashboards_actions_test.rb test/services/reminders/dispatch_service_test.rb \
  test/services/reminders/prenotice_service_test.rb
# → 82 runs, 342 assertions, 0 failures, 0 errors, 0 skips
```

마지막 두 파일(dispatch·prenotice 서비스 테스트)은 **기존 동작 불변 확인용** — `steps_due_today` 위임 리팩터링 후 무수정 통과. 시스템 테스트는 지시대로 실행하지 않음.

## 5. 판단이 필요했던 부분

1. **후보 좁히기 범위(성능) — 계획 문언보다 넓은 상위 집합으로 확정**. 계획서는 "기본 트랙 만기일 오늘−16일~+1 / 약속 트랙 약속일 오늘−1일~+1"이지만, 소급 창의 최대 길이는 nominal+3(금요일 nominal → 토·일 건너뛰고 월요일 창 종료)이라:
   - 기본 트랙: due+14(최후 스텝 final_d14)의 창 종료가 오늘이 되려면 **due = 오늘−17까지 도래 가능**(예: 금요일 만기의 D+14가 창 종료 월요일까지 살아있음). −16으로 좁히면 월요일에 실제 발송될 청구의 카드가 누락된다 → `(오늘−17)..(오늘+1)` 채택.
   - 약속 트랙: promise_overdue nominal(약속일+1)의 창 종료 월요일 기준 **약속일 = 오늘−4까지 도래 가능**(예: 일요일 약속의 도과 안내 nominal 월요일 창 종료 화요일) → `(오늘−4)..(오늘+1)` 채택.
   - 두 범위 모두 "오늘 도래 가능한 상위 집합"이며 최종 판정은 `scheduled_today_keys`(창·미발송·상한)가 하므로 과잉 포함은 무해하고 누락은 없다. 쿼리 테스트의 주말 시나리오(토 만기의 D+1 일요일 스텝 월요일 이월 — 2행 반환)와 금요일 약속 도과 케이스로 경계를 검증했다.
2. **"최신 약속" 판정** — 후보(약속일=오늘인 Promise, kind this_week·date_selected)의 invoice_id 집합을 뽑은 뒤 그 청구들의 약속 이력 전체를 `created_at, id` 오름차순으로 읽어 **청구별 마지막 행**을 최신으로 삼고, 그 약속일이 오늘인지 재판정한다(재응답으로 최신 약속일이 미래가 되면 오늘 도래에서 제외 — `DispatchService#latest_promise`와 같은 기준). this_week의 약속일은 접수일 기준 서버 산정(평일 접수 = 그 주 금요일)이므로 this_week 건은 금요일에 도래 카드가 된다 — 테스트로 명시.
3. **미열람 기준** — "한 번도 열지 않음"은 INV-4 전이 보증(status issued — `mark_viewed!`가 유일한 issued→viewed 경로)으로 판정하고, "3일 이상 지남"은 `issued_at ≤ (오늘−3).end_of_day`(경계: 3일 전 23:59 포함·2일 전 00:00 제외 — 테스트로 고정). idle_days = 오늘 − 발행일(날짜 차, TIME-1). 상태 `overdue`(연체 enum)는 명세 문자열("상태가 issued")에 따라 제외 — 연체 건은 이미 DASH-1 연체 카운트와 목록 상단에 노출된다.
4. **`steps_due_today` 위임 리팩터링의 동등성** — 기존은 PRENOTICE 필터 후 목록 기준으로 상한 검사, 새 구현은 필터 전 목록 기준이지만 "필터 후 빈 배열 ⇔ 필터 전이 빈 배열이거나 상한 도달"의 두 경우 모두 빈 배열로 수렴하고 select는 순서를 보존하므로 결과 동등. 기존 테스트(사전통보·재개·상한 경계 4/5) 무수정 통과로 확인. 주석도 종전 문언을 유지·보강했다.
5. **오늘 발송 예정의 결과 단위** — `(invoice, template_key)` 행(Struct). 한 청구에서 두 스텝이 같은 날 창 내(주말 이월·장애 복구)면 2장의 카드가 되는데, 14시 스캔도 두 스텝을 모두 발송하므로 화면과 실발송이 정합이다. 정렬은 후보 스코프의 `sorted_by_due`(만기일·id 오름차순).
6. **뱃지 색 배정** — DESIGN-2 상태색 3종 문법 내에서: 오늘 발송 예정=주황(오늘 안의 주의 행동·보류 창), 약속일 도래=녹색(약속 이행 확인 — 마감 대기와 같은 긍정 톤), 미열람=중립(아직 시작되지 않은 대기). 아이콘은 시계/달력/가린 눈(heroicons outline — 기존 아이콘과 같은 stroke 문법).
7. **컨트롤러 테스트의 fixture 실측** — `fixtures` 선언은 상위의 `fixtures :all`과 병합된다(실측 — delta fixture 청구가 쿼리 테스트에 유입). 이에 따라 쿼리 테스트 소유자를 fixture 청구가 없는 gamma로 통일하고(자격은 테스트 내 수금 패스 생성), 격리 테스트는 "gamma 소유 청구가 delta 결과에 없음" 형태로 강화했다. 컨트롤러 테스트의 `seed_invoice` 헬퍼가 `users(:gamma)`로 고정돼 있어 delta 시드는 `ReminderFactories.create_reminder_invoice`로 생성했다.
8. **시스템 테스트 관례** — `app_invoice_reminders_test.rb`의 실측 절차(공용 `log_in_as`·`wait_for_turbo` 후 confirm stub → `dom_click_button`)를 그대로 따랐다. 보류 성공 flash는 청구 상세로 리다이렉트된 후 어설션하고, 대시보드 복귀 시 카드 소멸(reminders_dispatchable 제외)까지 검증했다.

## 6. 범위 밖 수정 요청 (실행하지 않음 — 통합 단계 반영 대상)

1. **없음(파일 수정 요청은 없다)** — 필요한 판정·조회·표현이 모두 소유 파일로 해결됐다.
2. 참고(변경 아닌 관찰 2건):
   - `test/system/app_profile_withdrawal_test.rb`(T1 소유)가 `visit app_root_path`로 대시보드를 지난다 — 이제 대시보드에 미열람 등 새 카드가 뜰 수 있으니 통합 시스템 실행(7-S)에서 어설션 충돌 여부를 확인하면 좋다.
   - 초과 안내 파셜(`_action_overflow_note`)은 문구에 "5건"이 고정돼 있다 — `DASH_ACTION_LIMIT` 상수가 바뀌면 이 파셜 문구만 같이 고치면 된다(뷰는 컨트롤러 상수를 직접 참조하지 않는 규약상 의도된 절충).

## 7. 남은 우려

1. **시스템 테스트 미실행**(지시) — `test/system/app_dashboard_actions_test.rb` 1건은 작성만 했다. 공용 헬퍼(`log_in_as`·`dom_click_button`·`wait_for_turbo`) 의존은 기존 파일과 동일 관례라 위험 낮으나 7-S 통합 실행에서 확인 필요.
2. **"오늘 오후 2시에" 문구의 전제** — 스캔 시각 14:00 기준 고정 문구(지시대로). REM-3 세부 지정(회원별 발송 창 축소)에서 실제 발송 시각은 창 내 다른 시각일 수 있다. 발송이 지연되는 날에도 문구가 참이 아니게 되는 경우는 스캔 지연뿐이고, 발송 직후에는 step_sent?로 카드가 사라진다. 필요하면 후속으로 시각 표기 동적화를 검토할 것.
3. **전체 스위트 미실행** — 자기 소유 테스트만 실행했다(병렬 규칙). 기존 대시보드 방문 테스트(surf3·notices·tax_invoice_gate·sessions·sales·profiles·admin)는 코드 대조로 gamma 중심·배지 문구 비충돌을 확인했으나, 3-S(소유권 대조·rubocop·zeitwerk)와 7-S(전체 테스트)의 전체 실행에서 최종 확인이 필요하다 — 계획서의 동시성·검증 설계 그대로.
4. **오늘 발송 예정 카드의 다중 스텝** — 같은 청구에서 스텝 2개가 같은 날 창 내이면 카드 2장(보류하기 중복 노출). 첫 카드에서 보류하면 두 스텝 모두 취소되므로 동작은 안전하나, 카드 1장으로 묶는 개선(템플릿 라벨 병기)은 후속 후보다.

## 리뷰 반영(6차) — C-1·C-2(실제 발송 시각)·W-2~W-5 (2026-11-26)

`_workspace/05_review.md` T3 절 기준. 처리 결정에 따라 C-1·C-2(3-A 규칙)·W-2·W-3·W-4·W-5를 수정했고, W-1·W-8은 후속 과제로 남겼다(아래 §6'). W-6·W-7은 오케스트레이터가 PRD v0.50 DASH-2 문단으로 정리했다(미열람은 상태 "발행" 동안만·5건 제한은 안내성 세 종만 — 뷰 주석에도 반영).

### 변경 파일(6차)

| 파일 | 변경 |
|:--|:--|
| `app/services/reminders/dispatch_service.rb` | **상수 추가만**(메서드 무변경): `SCAN_HOUR = 14`·`SCAN_WDAYS = [1,2,3,4,5]` — recurring.yml의 reminders_dispatch("0 14 * * 1-5 Asia/Seoul")와 같아야 함을 주석 명시. 대조 테스트가 드리프트를 실패로 잡는다 |
| `app/queries/dashboards/todays_sends_query.rb` | **W-5 축소** — 후보 청구 Relation(자격·reminders_dispatchable·후보 범위 −17..+1·약속 −4..+1·includes·sorted_by_due)만 반환. `Row` Struct·`scheduled_today_keys` 호출·DispatchService 의존 제거 — **Query는 Model만 의존**(규약 §4.1). Free는 `Invoice.none` |
| `app/services/dashboards/reminder_actions_service.rb` | **신설(W-5)** — `Dashboards::ReminderActionsService.call(user:)` → `Result` Struct(`todays_sends`(최대 5건·행은 `SendRow(invoice, template_key, send_at)`)·`todays_sends_total`·`promises_due_today(+_total)`·`unviewed_idle(+_total)`). `DASH_ACTION_LIMIT = 5`를 컨트롤러에서 이곳으로 이동(기존 컨트롤러 상수는 사용처 소멸로 삭제). send_at 산정·5건 절단 담당 |
| `app/controllers/app/dashboards_controller.rb` | `show` 본문 4줄 — `load_summary`(DASH-1·DASH-4 집계를 private로 추출)·`load_action_items`(기존 유지)·`@reminder_actions = Dashboards::ReminderActionsService.call(user: @user)` 1줄 |
| `app/views/app/dashboards/show.html.erb` | `@todays_sends` 등 → `@reminder_actions.*` 소비. 섹션 주석에 실제 발송 시각 선별·색 문법(발송 예정·약속 도래 중립 / 미열람 주의)·W-6·W-7 정리 문언 반영 |
| `app/views/app/dashboards/_todays_send_card.html.erb` | 문구 교체(W-4)·아이콘 박스 주황→중립(W-2)·Row 출처 주석 갱신 |
| `app/views/app/dashboards/_promise_due_card.html.erb` | 아이콘 박스 녹색→중립 stone(W-2) |
| `app/views/app/dashboards/_unviewed_idle_card.html.erb` | 문구 교체(W-4)·아이콘 박스 중립→주의 주황(W-2) |
| `app/helpers/app/base_helper.rb` | `dash_action_badge`: todays_send·promise_due 중립(stone)화, unviewed 주황화(closure 녹색·answer 주황 불변 — PRD DASH-2 색 문언) + `dash_action_send_time_label(send_at)` 신설("오늘 오후 2시"·"오늘 오전 9시"·"오늘 오후 3시 30분" — 0분 생략) |
| `test/queries/dashboards/todays_sends_query_test.rb` | 후보 Relation 계약으로 재작성 — 경계(−17 포함·−18 제외·+2 제외)·Free·마감·정렬·격리. **W-3①**: 보류·수신 거부·종결을 사유별로 거래처를 나누고(테스트 내 거래처 생성) 제외된 청구 외 다른 거래처 청구가 유지됨을 각각 단언. 상한 도달 청구는 후보에 남음(제외 판정은 서비스)을 명시 |
| `test/services/dashboards/reminder_actions_service_test.rb` | **신설** — send_at 경계 11건 + recurring 대조 1건(아래 §3') |
| `test/controllers/app/dashboards_controller_test.rb` | 5건 경계 2건 추가(W-3③) — 오늘 발송 예정·약속일 도래 각각 "정확히 5건 → 노트 없음, 6건 → 노트" |
| `test/controllers/app/dashboards_actions_test.rb` | 문구 단언 갱신(W-4) — 헤더 주석에 6차 반영 기록 |
| `test/system/app_dashboard_actions_test.rb` | 문구 단언 갱신 + 부재 단언을 `assert_no_selector "span", text: "오늘 발송 예정"`으로 좁힘(W-3④). **실행 안 함(병렬 규칙)** |

수정하지 않은 소유 범위 밖 파일: 없음. `git status`로 T1/T2 Developer·오케스트레이터 파일과 무결 확인(`test/services/reminders/dispatch_service_test.rb`의 M 표시는 1차 T3의 미커밋 변경 — 6차에서는 읽기만 함).

### send_at 계산 로직과 경계별 결과(3-A 규칙)

`Dashboards::ReminderActionsService#send_at_for(invoice, template_key)`:

- **① 재예약 슬롯**: 그 청구·그 키의 채무자 향 pending 슬롯(`MessageLog` — debtor×pending 부분 유니크로 최대 1행)의 `scheduled_at`을 그대로 쓴다. 단 **시각이 지나기 전일 때만** — 지나간 슬롯은 발송이 이미 시도됐거나(성공 시 step_sent?로 애초 카드 제외) 곧 실행될 예정이라 "보류할 수 있는 예정"이 아니며, 오전 슬롯을 오후까지 "오전 9시 예정"으로 잘못 보이는 것을 막는다(리뷰 Tester 제안 2의 "다음 날 슬롯 실행 전 오전에는 노출" 구현).
- **② 다음 스캔 비춰보기**: 슬롯이 없으면 다음 스캔 시각(오늘이 스캔 요일이고 14시 전이면 오늘 14시, 아니면 다음 스캔 요일 14시 — KST)을 `user.next_remind_slot`으로 REM-3 허용 창에 비춘다.
- **채택**: `send_at.to_date == Date.current`인 행만 카드에 싣는다. 모집합 판정(`scheduled_today_keys` — 상한·보류·수신 거부·소급 창·이미 발송 제외)은 발송 스캔과 같은 단일 출처 유지.

경계별 결과(기준일 2026-11-10 화, 모두 테스트로 고정):

| 시나리오 | 14시 고정 문구(종전) | 6차(send_at) |
|:--|:--|:--|
| 기본 창 회원·오전(평일) | 오늘 오후 2시 | 오늘 오후 2시(다음 스캔 = 오늘 14시) |
| 토요일·일요일(일요일 만기) | 오늘 오후 2시(거짓) | 카드 없음(다음 스캔 월 14시) |
| 월요일 오전(주말 만기 소급) | 오늘 오후 2시 | 오늘 오후 2시(2스텝이면 2행 — 스캔과 동일) |
| 시작 15시 회원 | 오늘 오후 2시(시각 거짓) | 오늘 오후 3시(`next_remind_slot`이 14시→15시 이월) |
| 종료 14시 회원(09~14) | 오늘 오후 2시(날짜 거짓) | 카드 없음(다음 허용 요일 09시); 전날 재예약 슬롯(오늘 09시)은 **슬롯 실행 전 오전(08시)에만 "오늘 오전 9시"**, 15시에는 소멸(① 경과 → ② → 다음 허용 요일) |
| 비허용 요일("1,3,5"·화요일) | 오늘 오후 2시(날짜 거짓) | 카드 없음(다음 허용 요일 수 09시); 월요일 오전에는 오늘 오후 2시 |
| 당일 15시 이후(기본 창) | 오늘 오후 2시(거짓) | 카드 없음(다음 스캔 내일); 13시에는 오늘 오후 2시 |
| 재예약 슬롯이 내일 발송 | 오늘 오후 2시(거짓) | 카드 없음 |

`recurring.yml` ↔ 상수 대조 테스트: production·development 양쪽의 `reminders_dispatch` 스케줄을 파싱해 분·시각·요일 집합("1-5" 범위 표기 확장)·타임존(Asia/Seoul)이 `SCAN_HOUR`·`SCAN_WDAYS`와 일치하는지 단언 — 어긋나면 실패 문구에 "카드와 실제 발송 모집합이 갈라진다"를 명시.

`scheduled_today_keys`·`steps_due_today`는 **한 줄도 바꾸지 않았다**(리뷰 3-A — `restartable?`·09시 사전통보가 함께 씀). `test/services/reminders`·`test/controllers/app/invoices_reminders_test.rb` 무수정 통과로 불변 확인.

### 사용자 가시 문구 전문(6차 — W-4 반영분)

- **오늘 발송 예정 카드**: 뱃지 `오늘 발송 예정` / 설명 **`{오늘 오전/오후 N시[ M분]}에 다음 안내를 보냅니다: 「{템플릿 라벨}」. 발송 전까지 보류할 수 있습니다.`** (예: "오늘 오후 2시에 다음 안내를 보냅니다: 「만기 예정 안내」. 발송 전까지 보류할 수 있습니다." · "오늘 오전 9시에 …" · "오늘 오후 3시에 …" — 라벨 뒤에 조사를 붙이지 않는 문형(W-4②)). 버튼·확인창·링크 문구는 1차와 동일(`보류하기` / `이 청구서의 자동 안내를 멈춥니다. 보류하시겠습니까?` / `청구서 확인`).
- **미열람 방치 카드**: 설명 **`발행한 지 {N}일째인데 아직 열람 기록이 없습니다.`** (N = 오늘 − 발행일 — W-4①). 뱃지 `미열람`(주의 주황).
- **약속일 도래 카드**: 문구 변경 없음(`오늘 입금하기로 한 약속이 있습니다. 입금되었으면 마감해 주세요.`). 뱃지·아이콘 중립화(W-2).
- **5건 초과 안내·빈 상태·마감 대기·답변 대기**: 문구 변경 없음.

### 실행한 검증과 결과(6차)

```bash
DATABASE_URL=sqlite3:tmp/parallel/T3/test.sqlite3 bin/rails zeitwerk:check   # 통과 ("Otherwise, all is good!")
bin/rubocop <소유 파일 12개>   # 12 files inspected, no offenses
DATABASE_URL=sqlite3:tmp/parallel/T3/test.sqlite3 bin/rails test \
  test/queries/dashboards test/services/dashboards \
  test/controllers/app/dashboards_controller_test.rb test/controllers/app/dashboards_actions_test.rb \
  test/services/reminders test/controllers/app/invoices_reminders_test.rb
# → 184 runs, 995 assertions, 0 failures, 0 errors, 0 skips
```

마지막 두 디렉터리는 `steps_due_today`·`restartable?` 불변 회귀(지시 명령 그대로). 시스템 테스트는 수정만 하고 실행하지 않았다(병렬 규칙).

### W-1·W-8을 안 고친 이유(오케스트레이터 처리 결정)

- **W-1(후보마다 쿼리)** — 후보 청구마다 scheduled_today_keys(스텝 수준 MessageLog 조회)·pending 슬롯 1회·상한 0~1이 돈다. 후보 범위(−17..+1·약속 −4..+1)가 이미 모집단을 좁히므로 대시보드 1회 로딩의 쿼리 수는 후보 수에 비례하는 수십 회 수준 — 후속 배치 조회(`DispatchService`에 배치 진입점을 두고 단일 출처 유지)로 미루는 것이 리뷰 제안과 같다. 6차에서 층 분리(W-5)로 후보 산출·판정 경계가 명확해져 후속 최적화의 주입 지점(`ReminderActionsService#build_todays_sends` 한 곳)이 정리됐다.
- **W-8(같은 청구 카드 2장·"5건" 고정 문자열·약속 kind 중복·미열람 정렬)** — ① 카드 2장은 스캔이 두 스텝을 모두 발송하는 것과 정합(화면=실발송)이고 보류 동작은 안전하다. ② "5건" 고정은 `DASH_ACTION_LIMIT` 상수가 바뀌면 파셜 문구만 같이 고치면 되는 절충(1차 §6 기록 유지). ③ 약속 kind 정의 4곳 중복은 여러 도메인 파일(소유 밖)을 건드린다. ④ 미열람 정렬(발행일 오름차순)은 PRD에 정렬 명세가 없는 관찰 수준. 모두 후속 과제로 남긴다.

### 남은 우려(6차)

1. **지나간 pending 슬롯의 ② 폴백** — 슬롯 시각이 방금 지났고 잡이 늦게 실행되는 창(분 단위)에서는 카드가 순간 사라진다. 실제로는 발송 성공 시 step_sent?로 어차피 사라질 상태라 "보류 불가 예정"을 숨기는 쪽을 택했다(테스트로 고정). 스캔 지연이 수 시간 단위로 발생하는 장애 상황에서는 카드가 과소 표시된다 — 장애 복구 후 스캔이 곧 실발송하므로 오발송 위험은 없다.
2. **시스템 테스트 미실행(지시)** — 문구 단언과 `assert_no_selector` 좁힘만 반영했다. 7-S 통합 실행에서 확인 필요.
3. **W-1 성능** — 위 후속 항목. 대시보드가 최다 로딩 표면인 점은 유지되므로 런칭 전 측정 권장.
4. **전체 스위트 미실행(병렬 규칙)** — 3-S·7-S 통합에서 최종 확인. 뱃지 색 변경은 오늘의 액션 카드에만 적용됐고 청구서 상태 뱃지(reminders_helper 등)는 건드리지 않았다.

## 2차 리뷰 마무리(7차) — W-1 정렬·주석 정리·W-2 테스트

2차 리뷰(05_review.md 「T3 — 2차(재)리뷰」 — APPROVED·B0·C0·W2)의 코드 지적 1건과 메모 1건을 고치고 W-2 테스트를 보강했다(오케스트레이터 처리 결정 「T3 2차」 지시 범위 그대로).

### 변경 파일

1. `app/services/dashboards/reminder_actions_service.rb`
   - **W-1**: `build_todays_sends`가 절단 전에 행을 `send_at` 오름차순(같은 시각은 청구 id 오름차순)으로 정렬한다. 후보 Relation(만기일·id 순)을 그대로 따라가면 재예약된 오전 9시 슬롯 카드가 ②의 오후 2시 행에 밀려 5건 절단에서 잘리고, 잘린 건은 대시보드에서 보류할 수 없었다(PRD DASH-2 "발송 예정 시각이 이른 순서" — 2026-11-26 2차 리뷰 반영 문장). 메서드 이름·반환 형태 불변, `*_total`은 정렬 뒤 행 수라 절단 전 총건수 그대로.
   - 정렬 키 끝에 산정 순서 인덱스를 둬 완전 동률(같은 청구의 두 스텝이 같은 시각 — 주말 이월 케이스)에서는 `steps_for` 산출 순서를 유지한다. Ruby `sort_by`는 안정 정렬이 아님(보장 없음)이므로 명시한다 — 스캔도 그 순서로 발송하므로 화면=실발송 정합이 유지된다. 클래스 헤더·`build_todays_sends` 주석에 절단 순서 근거를 보강.
2. `app/services/reminders/dispatch_service.rb` — **주석만**(코드 불변): `scheduled_today_keys` 정의 위에 남아 새 주석과 겹치던 옛 `steps_due_today` 설명 블록(11행)을 삭제했다. 옛 블록의 사실은 이미 각자의 새 위치에 한 번씩 있다 — ① 사전통보 대상 키(PRENOTICE_KEYS)만 골라낸다는 뜻은 `steps_due_today`의 새 주석에, ② 14시 실제 스캔은 이 판정을 쓰지 않고 상한 도달 단계를 SendService 가드의 CAP_REACHED skip으로 기록한다(P4)는 클래스 헤더 주석에. `git diff`로 삭제·추가 행이 전부 `#` 주석임을 확인.
3. `test/services/dashboards/reminder_actions_service_test.rb` — 테스트 2건 신설
   - **W-2**: `scheduled_at` 없는 pending(14시 스캔의 창 내 즉시 발송이 이력을 점유한 상태 — `SendService#new_log!`이 예약 시각 없이 pending을 만들고 `mark_execution_started!`는 슬롯 실행 표시만 남기는 형태)을 만들어 ① 평일 13시에는 ②로 판정해 오늘 14:00 행이 나오고 ② 15시에는 다음 스캔(수 14시)이라 행이 없음을 단언. nil 가드(`slot.scheduled_at &&`) 없으면 `nil >= Time.current` 예외 경로.
   - **W-1 정렬**: 같은 만기일 청구 6건 중 후보 Relation의 가장 뒤 청구에 재예약 오전 9시 슬롯(전날 14시 창 종료로 미뤄진 형태)을 두고, 첫 5건이 09:00 행부터 오름차순(같은 시각은 청구 id 오름차순)이고 잘리는 행이 정렬 기준 가장 늦은 행(14:00·최대 id)임을 단언. 정렬이 없으면 09:00 행이 6번째로 잘리므로 회귀 시 실패한다. `create_scheduled_slot` 헬퍼 주석에 nil 형태를 보강.
4. `test/controllers/app/dashboards_controller_test.rb` — 테스트 1건 신설(W-2 ③): scheduled_at 없는 pending이 있는 청구에서 `GET /app`이 200으로 렌더하고 「오늘 발송 예정」 카드 1장을 내는지 확인(컨트롤러 경로의 가드 회귀 차단).

### 테스트 결과

```
DATABASE_URL=sqlite3:tmp/parallel/T3/test.sqlite3 bin/rails test \
  test/queries/dashboards test/services/dashboards \
  test/controllers/app/dashboards_controller_test.rb test/controllers/app/dashboards_actions_test.rb \
  test/services/reminders test/controllers/app/invoices_reminders_test.rb
# → 187 runs, 1008 assertions, 0 failures, 0 errors, 0 skips (+3 — 기존 184건 전부 통과, 기대값 변경 없음)

bin/rubocop app/services/dashboards/reminder_actions_service.rb app/services/reminders/dispatch_service.rb \
  test/services/dashboards/reminder_actions_service_test.rb test/controllers/app/dashboards_controller_test.rb
# → 4 files inspected, no offenses detected

bin/rails zeitwerk:check
# → 통과
```

기존 테스트의 만기일 순 의존 확인 — 5건·6건 절단 테스트는 전부 같은 send_at(② 14시)이라 정렬 후에도 청구 id 순과 동일해 기대값 변경이 없었고, 주말 테스트의 2행(template_key 순서 단언)은 동률 시 산정 순서 유지(인덱스 타이브레이크)로 그대로 통과한다.

### 남은 우려(7차)

1. **W-1 성능 후속(6차 우려 3과 동일)** — 정렬 추가는 후보 행 수준의 in-memory 비용만 더한다(쿼리 수 불변). 후속 배치 조회 최적화는 여전히 후속 과제.
2. **14:00:00 정각 경계** — 13:59:59 노출·14:00:00 소멸 단언은 없다(2차 리뷰 Tester 중점 제안 2 — Tester 영역).
3. **시스템 테스트·전체 스위트 미실행(병렬 규칙)** — 7-S 통합에서 최종 확인 필요.
