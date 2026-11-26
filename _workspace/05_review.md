status: APPROVED

# 05_review — 수신 거부 청구의 재개 차단 + 발송 상한에 수동 발송 합산 (2026-11-26, Reviewer)

> 기록: Reviewer 프로필에 쓰기 도구가 없어 최종 답변으로 돌려준 산출물을 오케스트레이터가 옮겨 적었다(내용 무변경·HTML 엔티티만 복원). 1회차 리뷰(2026-11-25)는 사용량 한도로 중단됐고 이것은 재시도 결과다.

**BLOCKER 0 · CRITICAL 0 · WARNING 7.** 1차·2차 구현을 통합해 봤다. 코드는 고치지 않았고, 지시된 기존 테스트 파일만 실행했다.

두 수정 모두 PRD v0.49의 의도대로 동작하고 데이터 무결성·소유권·발송 차단에 문제가 없다. WARNING은 세 갈래다.
- 이번에 메운 "죽은 버튼·틀린 안내"와 같은 유형이 거래처 목록 카드에 한 군데 남았다(W-1).
- 상한이 새로 걸리는 청구에서 U1 안내가 실제와 어긋난다(W-3·W-4).
- 문서와 테스트에 빈틈이 있다(W-2·W-5·W-6·W-7).

## 1. 이슈

| ID | 심각도 | Rule | 파일:줄 | 문제 | 수정 제안 |
|:--|:--|:--|:--|:--|:--|
| W-1 | WARNING | VIEW-7 | `app/views/app/clients/_client.html.erb:43-50` | 거래처 목록 카드는 `client.reminders_suspended?`를 먼저 판정한다. 그래서 **수신 거부 + 거래처 단위 보류**가 겹친 거래처에 「재개」 버튼이 그대로 보인다. 거래처 상세는 `if @client.refused?`가 먼저라 막혀 있다. 누르면 컨트롤러 가드가 상태 변경 없이 alert로 거부한다(무결성 영향 없음). 이 겹침은 자연스럽게 생긴다: 거래처를 보류한 뒤 채무자가 거부하면 `RegisterService`가 보류 마킹을 지우지 않는다. 03 문서 §7의 "거래처 상세 뷰 무변경" 서술은 목록 카드를 포함하지 않았다. | `unless client.refused?`로 감싸고 안에서 보류 여부로 「재개」/「보류」를 가른다(또는 1행 조건 `client.reminders_suspended? && !client.refused?`). 거래처 목록 GET 테스트 1건(거부+보류 → 「재개」 없음)을 더한다. |
| W-2 | WARNING | VIEW-7·REM-7 | `PRD.md:228`(VIEW-7), `:168`(REM-7) | PRD v0.49 VIEW-7은 「안내 다시 보내기」(REM-12 재개)만 서술하고 "REM-7의 보류는 재개 가능"이라고 대비한다. 2차 구현은 수신 거부 거래처의 **REM-7 보류 재개(청구 건·거래처 단위)**도 버튼 미노출·상태 변경 없이 거부한다. 코드가 PRD보다 앞서 있다. 동작 자체는 VIEW-7 취지에 맞다: 거부 거래처는 보류를 풀어도 발송이 없고 거부를 되돌릴 경로가 없다. | VIEW-7에 "청구 건·거래처 단위 보류 재개(「안내 재개하기」)도 노출하지 않고 상태 변경 없이 사유 안내로 거부한다. 보류 마킹은 그대로 남는다"를 명시한다. REM-7에 "(수신 거부 거래처는 제외 — VIEW-7)" 단서를 단다. |
| W-3 | WARNING | REM-11·PLAN-3 | `app/services/reminders/prenotice_service.rb:26-35` | 사전통보는 `steps_due_today`와 플랜 자격만 본다. **상한 도달 청구**는 09:00에 "오늘 보낼 예정입니다" 통보를 받지만 14:00 발송은 `CAP_REACHED`로 막힌다. REM-11 "무응답 시 예정대로 자동 발송된다"와 어긋나고, 서비스 주석의 "실제 발송이 일어날 건만 알린다"(자격 필터 선례)도 깨진다. 구조는 기존이지만 Q28로 범위가 넓어졌다: 수동 2통 + 기본 트랙이면 `requeue_d7`까지 5통이라 `final_d14`가 막히고 그날 아침 통보가 나간다. 채무자 영향은 없고 U1이 단계마다 쓸데없는 통보를 받는 수준이다. 코드 경로를 읽어 확인했고, 실행으로 재현하지는 않았다. | 이번 런에서 고치는 것을 권장한다(량이 작다). 상한 도달 청구는 사전통보 대상에서 뺀다. 판정은 `SendService#cap_reached?`(private)를 복제하지 말고 공개 진입점 하나로 둔다(예: 클래스 메서드 `Reminders::SendService.cap_reached?(invoice)`). 테스트: 수동 5통 + D+1 09시 `PrenoticeService.call` → `noti_prenotice` 0건. |
| W-4 | WARNING (확인 요청) | PLAN-3·REM-12·NOTI-1 | `app/helpers/app/reminders_helper.rb:73-86`, `app/views/app/invoices/show.html.erb:243-281`, `app/services/reminders/send_service.rb:214-226` | 상한이 수동 합산으로 걸린 청구는 끝까지 종결되지 않는다. `finish_sequence!`는 `final_d14`·`promise_overdue` **발송 성공**에만 붙어 있다. 그동안 상세 화면은 「자동 안내 중」 배지, 「안내 보류하기」, 「지금 1통 보내기」, "다음 안내" 라벨을 그대로 보여주지만 모든 자동 단계가 막혀 있다. 종전에는 수동 5통 뒤에도 자동 단계가 실제로 나가서 배지가 참이었는데, 이번 변경으로 거짓이 됐다(이 런이 고친 1번 결함과 같은 성격). 사용자는 발송 이력의 "상한(5통)에 도달" 행으로만 알 수 있다. 또 약속 트랙에서 `promise_overdue`가 상한에 걸리면 U1 향 `noti_promise_unkept`(약속 미이행 통보)도 함께 나가지 않는다. 코드 경로 분석이고 실행 재현은 하지 않았다. | 제품 결정이 필요하다. (a) 상한 도달을 배지·버튼·라벨에 표시할지, (b) 마지막 단계가 상한으로 막히면 시퀀스를 종결하고 U1에게 알릴지. (b)를 택하면 종결 배너의 「안내 다시 보내기」가 상한 청구에서 다시 죽은 버튼이 되므로 함께 설계해야 한다. 결정 전까지는 발송 무결성에 문제가 없다. |
| W-5 | WARNING | VIEW-7·PLAN-3 | `test/controllers/app/invoices_reminders_test.rb:291-320` | 커버 빈틈. (a) **수신 거부하지 않은 종결 청구에 「안내 다시 보내기」가 보인다**는 양성 단언이 없다(플랜 시나리오 3의 "버튼 노출"). 기존 C-3 테스트는 액션 성공만 본다. 이번 변경이 그 분기에 `&& !refused?`를 넣었으므로 조건이 잘못 바뀌어도 못 잡는다. (b) `restart_reminders` 거부 테스트(`:339`)가 `refused_at`·`reminders_suspended_at` 보존을 단언하지 않는다(경미). (c) 14시 스캔 경로에서 CAP_REACHED 기록·API 0회를 직접 본 단언이 없다(서비스 단위만, 위험은 낮다). | (a) `:291` 테스트에 GET show + `assert_select "button", text: "안내 다시 보내기"`를 더한다. (b) `:339` 테스트에 마킹 2개 단언을 더한다. |
| W-6 | WARNING | PLAN-3 | `LAUNCH_TEST_CHECKLIST.md:368, 1097, 1151, 1161, 1457-1458` | 옛 이름 `MessageLog.sequence_sent_count`와 수정 전 기대값(G-05-4 "6통이 된다", G-07-3 "버튼이 보인다")이 남아 있다. 미추적 파일이고 플랜상 완료 뒤 재생성 예정이다. | 런칭 테스트 시작 전에 재생성한다. `LAUNCH_TEST_SCENARIOS.md`는 이미 갱신돼 있다(`:602`·`:611`·`:627`). |
| W-7 | WARNING | — (테스트 기반) | `test/system/app_invoice_reminders_test.rb:24-31` | 선등록 `log_in_as`의 `click_button "로그인"`이 가끔 제출되지 않는다. 내 실행 1회차에 기존 REM-6·8 케이스(`:32`)가 "로그인되었습니다." 미검출로 실패했고 2회차에 통과했다. 스크린샷은 두 필드가 채워진 로그인 화면이다(입력 유실이 아니라 제출 누락). 같은 크기(23,316바이트)의 로그인 실패 스크린샷이 11-25 17:17~18분에도 3장 남아 있다(당시 출력은 확인하지 못했다). 파일 머리 주석의 chromedriver 클릭 드롭과 같은 현상으로 보인다. `button_to`에는 DOM 클릭 우회가 돼 있지만 로그인에는 없다. 기존 코드고 이번 diff가 만든 것은 아니지만, 새 시스템 테스트 2건이 이 헬퍼에 의존하고 `bin/ci` 게이트에 걸린다. | 로그인 제출도 같은 DOM 클릭 우회를 쓴다. 수정 뒤 같은 파일을 3회 연속 실행해 확인한다. |

## 2. Rule ID 준수 매핑

| Rule ID | 판정 | 근거 |
|:--|:--|:--|
| VIEW-7 | 준수 | 상세 뷰 분기 2·3에 `!client.refused?`. 배너는 거부가 최우선. 세 재개 액션이 모든 쓰기보다 먼저 거부. 전 청구 배제는 `Invoice.reminders_dispatchable`의 `Client.reminders_active`. 잔존 W-1·W-2. |
| REM-7 | 준수 | 거부하지 않은 경로는 불변(청구·거래처 재개 성공 테스트, 시스템 토글 통과). 거부 겹침 시 재개 불가는 PRD 보완 필요(W-2). |
| REM-8 | 준수(불변) | `remind`·`manual_step_key` 무변경. 거부 거래처 수동 발송 REFUSED 기록 테스트 통과. |
| REM-12/13 | 준수 | 비거부 종결 청구의 재개·"남은 단계 없음"은 기존 테스트 통과. 거부 종결은 재개 불가(VIEW-7 단서). |
| PLAN-3·Q10/Q11/Q28 | 준수 | 집계가 debtor·sent·(시퀀스성 템플릿 OR origin=manual). SQL 확인. 자동 1회성 3종은 집계 밖, 수동 가드 불변. 파생 W-3·W-4. |
| REM-11 | 조건부 어긋남 | W-3 |
| SEC-5·P4 | 준수 | `claim_log`·`skip!` 경로 무변경. CAP_REACHED도 skipped+error_code로 기록된다. |

## 3. 확인했으나 문제없음

### ① PRD 정합성
- VIEW-7(`PRD.md:228`)의 "재개 요청도 상태 변경 없이 사유 안내로 거부"는 세 액션 모두 303 + `flash[:alert]`로 지켜진다.
- "그 거래처의 모든 청구가 자동 안내 대상에서 빠진다"는 `app/models/invoice.rb:100-105`가 `refused_at: nil` 거래처만 병합해 지켜진다. 사전통보 스캔도 같은 스코프를 쓴다.
- REM-12 단서("수신 거부로 종결된 청구는 재개할 수 없다")와 PLAN-3·Q28 집계 정의는 코드와 일치한다.

### ② 데이터 무결성·보안
- **상태 불변**: 세 가드가 쓰기보다 앞에 있다. `invoices_controller.rb:166`(쓰기 `:168`), `:209`(쓰기 `:212`), `clients_controller.rb:68`(쓰기 `:70`). `refused_at`을 쓰는 곳은 `promises/register_service.rb:58` 한 군데라 어느 경로에서도 지워지지 않는다.
- **소유권**: `set_unsettled_invoice`(`invoices_controller.rb:18`, `:306-308`)와 `set_client`(`clients_controller.rb:6`, `:84-86`)가 before_action이라 가드보다 먼저다. 타 사용자 404 테스트(`invoices_reminders_test.rb:444-455`) 통과.
- **우회 경로**: 3개 액션 모두 직접 URL에도 가드가 있다. `invoice_params`·`client_params`에 상태 컬럼이 없어 대량 할당 우회도 없다.
- **발송 경로 전수**: 채무자 향 발송은 `SendService` 하나로 모인다(직접 호출 `invoices_controller.rb:181`·`dispatch_service.rb:123`, `deliver_job.rb:24`, 인큐 5곳). `guard_failure` 첫 줄이 REFUSED다. 거부 상태에서 API 호출이 나가는 경로가 없다.
- **다른 진입점**: `grep`으로 `reminders_suspended?`·`sequence_finished?`·`reminders_active?`·`refused?`를 app 전체에서 찾았다. 재개·보류 해제 조작은 청구 상세, 거래처 상세, 거래처 목록 카드 3곳뿐이다. 대시보드·관리자·뷰어에는 없다. 잔존은 W-1 하나다.
- **경합**: 가드 통과 뒤 재개 직전에 거부가 접수돼도 REFUSED 가드와 스코프가 발송을 막는다(무해).

### ③ 상한 집계
- **생성 SQL**(실행 확인): 공통 조건 3개가 AND로 묶이고 OR가 괄호 안에 있으며 enum이 정수로 바인딩된다.
  `WHERE invoice_id = 1 AND recipient_role = 0 AND status = 1 AND (template_key IN (7종) OR origin = 1)`
- **중복 없음**: 행 단위 OR다. 모델 테스트에서 겹치는 행(수동 `requeue_d7`) 1개를 포함해 3건이 3으로 센다.
- **범위**: 들어가야 할 것(시퀀스성 모든 origin, 수동은 템플릿 무관)은 들어가고, 빠져야 할 것(자동 1회성, U1 향 `recipient_role`, skipped·failed·pending)은 빠진다.
- **수동 가드**: `manual_cap_reached?` 무변경. 자동 집계가 수동 집계의 부분집합이라 수동 발송의 차단이 느슨해지지 않는다.
- **CAP_REACHED 기록**: `skip!`(`send_service.rb:174-177`)가 skipped+error_code로 남긴다. 재실행은 같은 슬롯을 갱신해 행이 불지 않는다.
- **재예약 시점**: 창 판정(`send_service.rb:37-38`)은 예약만 하고, 상한은 예약 실행 시점에 `sent`만 세어 판정한다. 예약과 실행 사이의 수동 발송도 반영된다.

### ④ 아키텍처·컨벤션
- **액션 길이**: `resume_reminders` 4~5줄, `restart_reminders` 9줄(공백 제외)로 10줄 이내다.
- **응답**: 303 + flash 규약. 상태 가드는 권한 검증이 아니라 액션 본문에 둬도 규약(:413)과 어긋나지 않는다.
- **의존 방향**: 컨트롤러 → `DispatchService.restartable?`(공개 진입점) → 모델. 모델이 서비스를 부르지 않는다.
- **뷰**: 분기 조건이 2항이고 쿼리가 없다. `raw`·`html_safe` 없음.
- **네이밍**: `counted_for_cap`·`cap_sent_count`·`redirect_*_refused`가 의미에 맞다.
- **옛 이름**: app·test·config·lib·bin·db에 0건. 루트 문서 1곳이 W-6이다.

### ⑤ 테스트 품질

| 플랜 시나리오 | 테스트 | 결과 |
|:--|:--|:--|
| 1 거부+종결: 버튼 없음·배너 | `invoices_reminders_test.rb:324`, 시스템 `:121` | 통과 |
| 2 restart → 303+alert, 마킹 유지 | `invoices_reminders_test.rb:339` | 통과 |
| 3 비거부 종결: 액션 성공 | 기존 `:291`·`:305` | 통과 (버튼 노출 양성 단언 없음 → W-5) |
| 4 수동 issue_notice 5통 → 자동 CAP, API 0 | `send_service_test.rb:273` | 통과 |
| 5 수동 4 + 자동 1 = 5 → 다음 CAP | `send_service_test.rb:290` | 통과 |
| 6 자동 1회성은 상한 도달에도 발송·집계 밖 | 기존 `send_service_test.rb:334`, `:309` | 통과 |
| 7 수동 가드 불변 | 기존 `invoices_reminders_test.rb:214`, `send_service_test.rb:309` | 통과 |
| 8 수동 시퀀스성 템플릿 종전대로 집계 | 기존 `send_service_test.rb:401`, `message_log_test.rb:45` | 통과 |
| 겹침(거부+보류+종결) 화면·PATCH | `invoices_reminders_test.rb:358`·`:377`, 시스템 `:140`, `clients_reminders_test.rb:23` | 통과 |
| 거래처 비거부 재개 성공(회귀) | `clients_reminders_test.rb:11` | 통과 |

- **단언**: 응답 본문, flash, `reload`한 DB 상태, 대역 호출 수를 직접 본다.
- **실호출**: 새 테스트는 `FakeSolapiClient` 주입 또는 `with_solapi_client`만 쓰고, VIEW-7 테스트는 발송 자체가 없다.
- **날짜 의존**: 새 테스트는 `travel_to(2026-11-10 10:00)`로 고정돼 있고 "오늘 이후" 검증이 있는 약속 생성이 없다. 종결 재개 테스트는 그 시각에 `restartable?`이 참이라 가드가 없으면 성공했을 테스트라 변별력이 있다.

## 4. 신규 문구 검증

새로 생긴 사용자 가시 문구는 flash alert 2개뿐이다(뷰에는 추가 없음).
- "이 거래처가 추가 안내 수신을 거부하여 자동 안내를 재개할 수 없습니다."
- "이 거래처가 추가 안내 수신을 거부하여 자동 안내를 다시 진행할 수 없습니다."

기존 거부 배너("이 거래처가 추가 안내 수신을 거부했습니다")와 스킵 사유("거래처가 추가 안내 수신을 거부하여…")의 어휘·톤이 같다. "독촉·연체" 대신 "안내"를 쓰고 책망·과장이 없어 P1에 맞다. 동사도 각 버튼의 성공 안내("재개했습니다"·"다시 진행합니다")와 짝이 맞다. 다만 성공 안내는 "정기 안내", 거부 alert은 "자동 안내"로 명사가 다르다(기존 UI가 두 단어를 섞어 쓰고 있어 수정 필수는 아니다).

## 5. 범위 밖 관찰 (기존 동작)

- **수신 거부 우회 (확인 요청)**: `refused_at`은 거래처 행 단위다. 같은 번호로 거래처를 새로 등록해 발행하면 거부한 번호로 다시 보낼 수 있다(`clients.phone` 유니크 인덱스 없음, 번호 기준 거부 조회 없음). VIEW-7 "해당 번호 발송 중단" 취지와 어긋나는 기존 설계라 제품 판단이 필요하다.
- **창 판정이 가드보다 앞**: 상한 도달·거부·보류 청구에 창 밖 수동 발송이 들어오면 "다음 평일 오전 9시에 발송됩니다"로 예약됐다가 실행 시점에 CAP_REACHED·REFUSED로 넘어간다. 수신 거부는 직접 URL로만 닿고, 상한 도달은 「지금 1통 보내기」가 계속 보여 실제로 닿는다.
- **거래처 단위 보류 + 청구 종결 겹침**: 「안내 다시 보내기」가 보이고 "다시 진행합니다" 안내를 주지만 거래처 보류가 남아 발송이 없다(거래처를 재개하면 나간다).
- **`suspend_reminders`**: 수신 거부 거래처에도 보류 마킹을 남긴다(버튼은 없고 직접 URL로만). 재개가 막혀 마킹이 영구 남고 W-1 상태를 만든다. 발송 영향은 없다.

## 6. Tester 중점 테스트 제안

1. **스캔 경로 상한**: 수동 issue_notice 5통 → D+1 14:00 `DispatchService.call` → CAP_REACHED 기록·API 0회.
2. **사전통보(W-3 수정 뒤)**: 수동 5통 + D+1 09:00 `PrenoticeService.call` → `noti_prenotice` 0건.
3. **거래처 목록 카드(W-1 수정 뒤)**: 거부+보류 거래처에 「재개」 없음.
4. **양성 가시성(W-5)**: 비거부 종결 청구에 「안내 다시 보내기」 노출, 비거부 보류 청구에 「안내 재개하기」 노출.
5. **혼합 집계**: 수동 시퀀스성 재발송 + 수동 issue_notice + 자동 단계의 5통 경계, 약속 트랙에서 수동 포함 5통 뒤 `promise_overdue` 차단.
6. **재예약**: 창 밖 수동 5번째가 다음 평일 09시에 sent 된 뒤 그날 14시 자동 단계가 CAP_REACHED.
7. **거부 상태 직접 URL**: `suspend`·`remind`·`resume`·`restart` 모두 상태 불변·API 0회.
8. **시스템 로그인 플레이크(W-7)**: 같은 파일 3회 연속 실행.

## 7. 실행한 명령과 결과

- `bin/rails runner 'puts MessageLog.counted_for_cap(1).to_sql; …'`: SQL만 출력(조회 없음).
- `bin/rails test`로 `message_log_test.rb`, `send_service_test.rb`, `invoices_reminders_test.rb`, `clients_reminders_test.rb`, `tickets/notify_answer_service_test.rb`, `tax_invoices/notify_issued_service_test.rb`: **81 runs, 423 assertions, 0 failures, 0 errors**.
- `bin/rails test test/system/app_invoice_reminders_test.rb`: 1회차 5 runs 중 1 failure(선등록 REM-6·8 케이스, W-7), 2회차 **5 runs, 39 assertions, 0 failures**. 새 VIEW-7 2건은 두 번 다 통과.
- `grep`·`git diff`·`sed`로 본 문서·뷰·테스트 구간: 위 각 절의 근거.
- **실행하지 않은 것**: 전체 테스트(지시). `viewer_refusal_test.rb`·`dispatch_service_test.rb`·`prenotice_service_test.rb`·`deliver_job_test.rb`는 정적으로만 봤다(옛 이름 사용 없음, 수동 발송 로그가 1건씩이라 상한 변경 영향 없음).
- **부수 산출물**: 실패한 1회차 실행이 `tmp/screenshots/failures_test_-_-_-_-_-_-_-_-_-_-_-_-_-REM-6-8-.png`를 남겼다(git-ignored, W-7 근거). 그 밖에 만들거나 바꾼 파일, git 상태 변경, 외부 API 호출은 없다.

---

status: CHANGES_REQUESTED

# 마감 리뷰 — 3~6차 변경분 (2026-11-26, Reviewer)

> 기록: 리뷰 이후 변경분(3~6차·Tester 1차 테스트)에 대한 두 번째 리뷰. 정적 리뷰만(테스트 미실행 — 같은 시각 Tester가 시스템 테스트를 돌렸다). Reviewer가 쓰기 도구가 없어 최종 답변으로 돌려준 산출물을 오케스트레이터가 옮겨 적었다(내용 무변경·HTML 엔티티만 복원).

**BLOCKER 0 · CRITICAL 1 · WARNING 6.** 코드는 고치지 않았고, 테스트는 지시대로 실행하지 않았다(grep·`git diff`·파일 읽기만).

3~6차 변경분이 만든 회귀는 없다. W-1·W-3·W-4·W-5는 PRD v0.49대로 해소됐고, 5·6차의 슬롯 논리는 a~h 경로에서 중복 발송·멱등 깨짐·P4 훼손이 없다.

CRITICAL 1건은 5차가 고친 결함군(예약 슬롯 실행 누락)의 잔여 경로다. PRD REM-3에 이번에 들어간 "다음 평일 09시에 반드시 실행된다"와 충돌한다. **5차 이전부터 있던 동작이고 이번 diff가 만들지 않았다.** 수정량은 작다.

## 1. 이슈

| ID | 심각도 | Rule | 파일:줄 | 문제 | 수정 제안 |
|:--|:--|:--|:--|:--|:--|
| C-1 | CRITICAL | REM-3(재예약분 실행 정합)·SEC-5 | `app/services/reminders/send_service.rb:132-134`(`in_flight?`), `:127`, `:67`·`:82` | 창 시작 직전 약 1분 이내에 접수된 창 밖 발송은 예약 슬롯이 영구 pending으로 남고 발송되지 않는다. **원인**: `in_flight?`는 pending이고 `updated_at`이 1분 내면 "다른 실행이 발송 중"으로 본다. 예약 슬롯도 접수 시각에 생성돼 이 창에 들어간다. claim은 SELECT라 `updated_at`이 갱신되지 않는다. **조건**: `next_remind_slot`(`app/models/user.rb:177-187`)은 창 시작 전 접수분을 당일 시작 시각으로 예약한다. 접수가 [실행 시각 − 60초, 실행 시각)이면 흡수된다. 기본 설정에서는 08:59:02~08:59:59 접수분이다. 수동·자동(DeliverJob 재시도·수동 발행 안내)이 같고, 반복 청구 06:30 발행분은 안전하다. **결과**: `:duplicate`로 끝나 재실행 잡이 없다. 회원에게는 "다음 평일 오전 9시에 발송됩니다" flash만 남는다. **근거**: 코드 경로 분석이다(실행 재현은 지시로 하지 않았다). 기존 테스트 `test/services/reminders/send_service_test.rb:78-91`는 08:59:00 접수 → 09:00:00 실행만 본다. 정확히 60초라 `updated_at > 1.minute.ago`가 거짓이라 통과하고, 결함이 가려졌다. | (A) `in_flight?`에서 예약 슬롯(`scheduled_at` 있음)을 제외한다. 실행 시점의 슬롯 `updated_at`은 접수 시각이라 "진행 중"의 근거가 못 된다. 실질 변화는 접수 직후 1분뿐이다. 또는 (B) claim한 슬롯을 `touch`해 선점을 기록한다(B는 동시 실행 경합도 줄인다). 테스트: 08:59:30 접수 → 09:00:02 `DeliverJob` → `:sent`·sent 1건·pending 0. |
| W-1 | WARNING (확인 요청 — 코드 경로 분석) | REM-3·REM-6·P4 | `app/services/reminders/send_service.rb:38`, `app/services/reminders/dispatch_service.rb:114-130` | 자동 경로에서 "sent 이력 + pending 슬롯"이면 슬롯이 영구 pending으로 남는다. `call`은 창 판정이 멱등 판정보다 앞이라, 스캔이 창 밖이면 이미 보낸 단계에도 `reschedule!`이 슬롯을 만든다. `dispatch_step`은 sent 여부를 보지 않는다. 다음 날 DeliverJob은 `step_sent?`로 duplicate가 되고 슬롯은 그대로 남는다. **발생 범위**: 14시 스캔이 창 밖인 사용자, 즉 REM-3 세부 설정으로 종료 시각을 14시 이전으로 당기거나 스캔 요일을 제외한 경우다. 그 단계마다 「예정」 행이 영구 남는다. 기본 설정 사용자는 해당 없음. 발송 누락이 아니다(이미 sent). 상한 집계도 sent만 세어 무영향. | `reschedule!` 앞에서 자동 시퀀스성 스텝의 `step_sent?`를 확인해 duplicate로 종료한다. 운영 확인: `status=pending AND scheduled_at < now`인 채무자 향 행을 조회한다. |
| W-2 | WARNING | PLAN-3·Q28 | `app/views/app/invoices/show.html.erb:235` | "이 청구서에는 청구 건당 5통을 모두 보냈습니다"는 집계 기준의 5통이다. 자동 1회성(발행 안내·부분입금·마감 감사)은 집계 밖이라, 실제 총 발송은 5통보다 많다. 발행 안내는 기본 켬이라 대부분 6통이다. U1은 발송 이력에서 「발송됨」 6줄과 "5통"을 같은 화면에서 본다. 셋째 문장은 잔액·감사만 설명하고 발행 안내는 설명하지 않는다. | "단계별 안내와 직접 안내를 합쳐 청구 건당 5통을 모두 보냈습니다."로 바꾼다. |
| W-3 | WARNING (확인 요청) | REM-8·PLAN-3 | `app/services/reminders/send_service.rb:197-200`, `app/views/app/invoices/show.html.erb:260` | 두 상한 집계가 다르다. 자동은 `cap_sent_count`, 수동은 채무자 향 sent 전체다. 자동 1회성이 5통 이상이고 시퀀스성+수동이 4통 이하이면 「상한 도달」 배지·상자가 없고 「지금 1통 보내기」가 보인다. 누르면 CAP_REACHED로 막힌다(죽은 버튼). 예: 부분입금 5회 + 시퀀스 4통. 극단적이라 빈도는 낮다. | 버튼 노출 조건에 수동 상한을 더한다(예: 컨트롤러에 `@manual_cap_reached`를 적재해 `cap_reached \|\| manual_cap_reached`로 숨긴다). 아니면 기존 동작으로 받아들이고 테스트 1건으로 고정한다. |
| W-4 | WARNING | — (테스트 커버) | `test/services/reminders/send_service_test.rb` | 3군데가 비어 있다. (a) C-1의 창 시작 직전 경계. (b) 1회성의 창 밖 재예약 실행: `partial_paid` 슬롯과 과거 sent 이력이 있을 때 다음 날 발송. 5차의 `new_log!` 수정으로 종전 누락이 개선된 경로인데 단언이 없다(`rescheduled`와 1회성을 함께 보는 테스트 0건). (c) W-1의 자동 경로 sent+슬롯. | 각 1건을 더한다. (b)는 `partial_paid` sent 1건 → 창 밖 재예약 → 다음 날 `DeliverJob` → `:sent`·sent 2건. |
| W-5 | WARNING | — (주석) | `send_service.rb:52-56`, `dispatch_service.rb:13-15`·`:64-67`, `send_service.rb:127` | 낡은 서술. (a) `claim_log` 블록 주석 "수동은 … 이력을 누적하고"는 이제 예외가 있다(pending 슬롯 재사용). (b) `DispatchService` 머리 주석은 `steps_due_today`가 스캔과 "같은 산정"이라고 쓰는데, 상한 필터가 생겨 다르다(메서드 주석에만 설명). (c) `restartable?` 주석에 상한 도달 분이 없다. (d) `new_log!`의 `slot.sent?`는 `find_pending_slot`이 pending만 돌려주므로 항상 거짓이다(죽은 조건, 무해). | 주석을 현재 동작에 맞추고 (d)는 제거한다. |
| W-6 | WARNING | PLAN-3·REM-3 | `PRD.md:161`(REM-3), `:212`(PLAN-3) | 문서-코드 차이. (a) PLAN-3 상한 안내 문구에 "미수 청구 한정"(4차)이 없다. (b) REM-3 "반드시 실행된다"에 설계상 예외(상한·보류·수신거부·상태 변경으로 인한 skip)가 없다. C-1이 그대로면 이 문장은 거짓이 된다. | PLAN-3에 "미수 청구에만 표시"를 더한다. REM-3은 C-1을 고친 뒤 "가드 skip은 제외" 단서를 단다. |
| W-7 | WARNING | — (용어) | `app/helpers/app/reminders_helper.rb:36`, `show.html.erb:233` | 같은 상황에 두 용어가 나온다. 스킵 행과 수동 flash는 "청구 건당 안내 상한(5통)에 도달", 상자는 "발송 상한에 도달했습니다", 배지는 「상한 도달」이다. 랜딩은 "발송 상한"을 쓴다. | 스킵 라벨을 "청구 건당 발송 상한(5통)에 도달하여…"로 맞춘다. |

## 2. 경로별 추적 (발송 슬롯 논리)

| 경로 | 결과 | 근거 |
|:--|:---|:--|
| (a) 수동 즉시 | 변화 없음, 문제없음 | `new_log!` 직행. pending 슬롯이 없으면 새 행, 있으면 슬롯을 흡수해 즉시 발송한다. 종전에는 과거 sent가 있으면 duplicate로 누락됐다. |
| (b) 창 밖 수동 → 다음 날 실행 | 과거 sent 있음·없음·failed·상한 모두 올바름. **단 창 시작 직전 1분 접수분은 누락(C-1)** | 테스트 `:436`·`:388`·`:495`가 각각 변별력 있다. |
| (c) 자동 스캔 | 변화 없음 | sent 가드가 슬롯 우선보다 앞이다. 슬롯이 없으면 `slot \|\| log \|\| new_log!`가 종전과 같다. |
| (d) 자동 실패 후 재시도·재예약 | 올바름 | 재시도는 failed 행을 갱신한다(불변). 재예약분은 슬롯을 우선해 sent로 만들고 failed는 보존한다(테스트 `:463`). |
| (e) U1 향 즉시 알림 | 변화 없음 | 첫 줄에서 `new_log!` 직행. |
| (f) U1 향 예정 알림 | 올바름 | 6차 한정으로 슬롯 우선을 타지 않는다. 같은 예정 시각은 흡수, 다른 날은 새 이력이다(테스트 `:631`·`:653`). |
| (g) `partial_paid` | 올바름 | `new_log!` 직행. 창 밖 재예약분도 슬롯을 탄다(종전에는 과거 sent에 흡수돼 누락). 테스트 없음(W-4b). |
| (h) 동시 실행 2개 | 회귀 없음 | 종전과 같은 설계다. `in_flight?`는 슬롯 생성 1분 뒤에는 흡수하지 않고, `step_sent?` 뒤의 SELECT 사이 경합은 종전에도 있었다. 새로 열린 경합은 없다. |

- **P4**: 슬롯은 미발송 선점이라 sent·skipped로 바꿔도 기록을 덮지 않는다. 자동 재시도가 failed·skipped 행을 sent로 갱신하는 것은 기존 설계다. 5차로 "failed + 슬롯"에서 failed가 보존되게 됐다.
- **가드 순서**: 가장 오래된 이력이 sent가 아닐 때 순서는 sent → `step_sent?` → in_flight → 슬롯 → 갱신 행이다. 슬롯을 집어도 `guard_failure`는 그 뒤에 실행된다(테스트 `:495`).

## 3. 확인했으나 문제없음

- **VIEW-7 목록 카드(W-1 해소)**: `app/views/app/clients/_client.html.erb:45`에 `!client.refused?`. 겹침 카드에서 재개·보류가 모두 없다. 거래처 상세(`show.html.erb:122`)는 거부가 먼저다. 컨트롤러·시스템 테스트가 수정 전 코드를 실패시킨다.
- **REM-11(W-3 해소)**: `steps_due_today`(`dispatch_service.rb:59`)가 상한 도달이면 빈 배열이다. 테스트가 0건을 단언한다.
- **PLAN-3·Q28 상한 안내(W-4 해소)**: 상자·배지는 미수 청구에만 붙는다. 상한 도달 시 버튼 행과 무료 플랜 문구를 렌더하지 않는다(`show.html.erb:260`). 종결 마킹은 없다. 자동 1회성은 계속 나간다(테스트 `:368`).
- **상한 판정 단일 출처**: `Invoice#reminder_cap_reached?`의 호출처는 `SendService#cap_reached?`, `steps_due_today`, `RemindersContext` 3곳이다. 뷰·목록·대시보드에서 직접 부르지 않는다. 상세 1건당 count 1회, 사전통보는 예정 스텝이 있는 청구만 세므로 N+1 없음.
- **`restartable?`**: 상한 도달이면 false가 되고 마킹은 유지된다. PRD "재개 가능 판정에서도 빠진다"와 맞다.
- **분기 조합**: 거부 / 거부+보류+종결 / 상한 / 상한+보류 / 상한+종결 / 상한+무료 / 상한+paid·voided를 대조했다. 죽은 버튼·거짓 배너는 없다(W-3의 극단적 틈은 별도).
- **§5-3**: 거래처 보류 + 종결은 버튼을 숨기고 보류 배너가 재개 경로를 알린다. 재개 뒤 버튼이 돌아온다(양성 단언 있음).
- **U1 예정 알림 멱등의 전제**: `today_at_9`는 `Time.current.change(hour: 9, min: 0)`이다. ActiveSupport 8.1.4.1 소스에서 `change`가 상위 단위가 주어지면 sec·usec을 0으로 만드는 것을 확인했다. 운영에서도 당일 재실행 흡수가 성립한다.
- **아키텍처**: 의존 방향은 Controller·Service → Model이다. 뷰는 `@reminder_cap_reached`만 쓴다. 422 재렌더 경로(Payments·Promises)도 같은 @변수를 적재한다. 액션 본문 변경이 없다. 헬퍼 시그니처 `reminder_state_badges(invoice, cap_reached: false)`의 호출처는 1곳이다.
- **테스트 품질**: 새 테스트는 `travel_to`로 고정돼 있다. 솔라피는 대역만 쓴다. 5·6차 4건(`:436`·`:463`·`:495`·`:653`)은 수정 전 코드에서 모두 실패할 단언이다.
- **공용 `log_in_as`**(`test/application_system_test_case.rb:43-49`): 로그인 페이지의 제출 버튼은 1개여서 모호하지 않다. 자체 정의가 있는 파일은 그 정의가 우선한다.

## 4. 신규 문구

- **배지 「상한 도달」**: 「종결」·「보류」와 병렬이고 중립 톤이다. 문제없음.
- **상자 본문**: "독촉" 대신 "안내"를 쓰고 책망·과장이 없다. "직접 안내"는 무료 플랜 문구와 같은 어휘다.
- **미흡한 점**: 5통의 산정 범위(W-2), 용어 불일치(W-7). 후속 안내가 없어 막힌 느낌을 줄 수 있다. 종결 배너는 후속 문구가 있다. "이후 진행은 거래처와 직접 소통으로 확인해 주세요" 1절을 검토한다(제품 판단).

## 5. 범위 밖 관찰

- 09시 사전통보 시점에 상한 미도달이고 그 뒤 수동 1통이 더해지면, 통보는 나가지만 14시 발송은 CAP_REACHED로 막힌다. 좁은 시차다.
- 약속 트랙에서 `promise_overdue`가 상한에 막히면 `noti_promise_unkept`도 나가지 않는다(03 문서 §8의 기록대로, 의도된 현재 동작).
- `new_log!`의 유니크 복구가 U1 향에서는 실행되지 않는다(인덱스 2개 모두 해당 없음). 역할 조건이 없는 `find_pending_slot`을 쓰므로, 인덱스를 추가할 때는 `return nil unless debtor?`를 함께 두는 것이 안전하다.
- `terms:83`·랜딩의 "자동 리마인더는 건당 최대 5통"은 Q28(수동 합산) 뒤에도 "최대"라 모순은 아니다. 수동을 쓰면 자동이 그만큼 줄어든다는 설명은 없다.

## 6. Tester 중점 테스트 제안

1. **C-1**: 08:59:30 창 밖 접수 → 09:00:02 `DeliverJob` → `:sent`·pending 0. 수동·자동 각 1건.
2. **W-1**: 스캔 시각이 창 밖인 사용자 설정 + sent 단계 → 스캔 뒤 pending 슬롯 0건.
3. **W-4b**: `partial_paid` sent 1건 → 창 밖 재예약 → 다음 날 발송 1건 추가.
4. **W-3**: 자동 1회성 5통 + 시퀀스 4통 청구의 GET show(버튼 노출 여부는 결정 뒤).
5. **분기 조합**: 상한+보류, 상한+거부, 상한+종결 각각의 화면.

## 7. 실행한 명령

- `git status --short`, `git log --oneline -8`, `git diff --stat -- app test`
- `git diff -- <파일>`: `invoice.rb`, `message_log.rb`를 비롯한 app 7개, 테스트 11개
- `git show HEAD:app/services/reminders/send_service.rb`(회귀 대조용)
- `grep`·`sed`: `_workspace/05_review.md`, `03_implementation.md`, `07_test_report.md`, `02_prd_update.md`, `PRD.md` §6.6·§6.9·§6.10·§10, `ARCHITECTURE_CONVENTION.md`, `db/schema.rb:194-218`, `config/recurring.yml`, ActiveSupport 8.1.4.1 소스 2곳
- **실행하지 않은 것**: 테스트 전체, `bin/rails runner`·`console`. 파일 수정·임시 파일·git 상태 변경·외부 API 호출은 없다.
