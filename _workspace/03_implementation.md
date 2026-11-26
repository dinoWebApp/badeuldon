# 03_implementation — 수신 거부 청구의 재개 차단 + 발송 상한에 수동 발송 합산 (2026-11-25, Developer)

승인 플랜 `_workspace/01_plan.md`·`_workspace/02_prd_update.md`(PRD v0.49) 기준. 수정 2건 모두 소스·기존 테스트 갱신만으로 완료 — 마이그레이션·라우트 변경 없음.

## 1. 변경 파일 목록 (git diff --stat)

```
 app/controllers/app/invoices_controller.rb         | 12 ++++++
 app/models/message_log.rb                          | 21 +++++++----
 app/services/reminders/send_service.rb             | 14 +++++--
 app/views/app/invoices/show.html.erb               |  9 +++--
 test/controllers/app/invoices_reminders_test.rb    | 34 +++++++++++++++++
 test/models/message_log_test.rb                    | 26 ++++++++-----
 test/services/reminders/send_service_test.rb       | 44 ++++++++++++++++++++--
 .../tax_invoices/notify_issued_service_test.rb     |  2 +-
 .../services/tickets/notify_answer_service_test.rb |  2 +-
 test/system/app_invoice_reminders_test.rb          | 19 ++++++++++
 10 files changed, 152 insertions(+), 31 deletions(-)
```

범위 밖 파일은 수정하지 않았다. 단, `test/services/tickets/notify_answer_service_test.rb`와 `test/services/tax_invoices/notify_issued_service_test.rb`는 지시서의 "옛 이름(`sent_sequence`·`sequence_sent_count`)을 쓰는 곳을 전부 새 이름으로 바꾼다"에 해당하는 호출처라 기계적 이름 교체만 수행했다(단언 의미 불변 — 아래 5번 참조). 두 파일 모두 포트원 런의 미커밋 파일이 아니다(git status에서 클린).

## 2. 변경 요약

### 수정 1 — 수신 거부한 거래처의 청구는 재개할 수 없다 (VIEW-7·REM-12/13)

- **`app/views/app/invoices/show.html.erb`**
  - 버튼 분기 `elsif @invoice.sequence_finished?` → `elsif @invoice.sequence_finished? && !@invoice.client.refused?` — 수신 거부한 거래처에서는 「안내 다시 보내기」 버튼과 그 아래 보조 문구(`<p class="text-xs text-stone-400">종결 시점에 남아 있던 단계부터…</p>`)가 함께 렌더되지 않는다. 사용자 가시 문구는 추가하지 않았다(기존 거부 배너가 사유를 이미 설명).
  - 상태 배너 분기(`if @invoice.client.refused?`가 최우선 — "이 거래처가 추가 안내 수신을 거부했습니다")는 지시대로 무변경.
  - 섹션 머리 주석(199~201행)을 설계 의도 실제와 맞게 정정: 활성 → 보류 버튼 / 청구 보류 → 재개 버튼 / 거래처 수신 거부 → 안내만(재개 불가) / 그 밖의 종결 → 다시 보내기 버튼. 재개 버튼 분기 주석에 VIEW-7 배제 사유 한 줄 보강.
- **`app/controllers/app/invoices_controller.rb`**
  - `restart_reminders` 첫 줄에 거부 가드: `return redirect_restart_refused if @invoice.client.refused?` — `restartable?` 판정·`restart_sequence!`(종결 마킹 해소)에 도달하기 전에 상태 변경 없이 차단한다.
  - 안내 redirect는 private `redirect_restart_refused`로 분리(303 + `flash[:alert]` = "이 거래처가 추가 안내 수신을 거부하여 자동 안내를 다시 진행할 수 없습니다."). 액션 본문은 논리 7줄로 10줄 이내 유지.

### 수정 2 — 자동 시퀀스 상한에 수동 발송을 합산한다 (PLAN-3·Q10/Q11/Q28)

- **`app/models/message_log.rb`**
  - 집계 교체: `sent_sequence` 스코프 + `sequence_sent_count` → `counted_for_cap` 스코프 + `MessageLog.cap_sent_count(invoice_id)`.
  - 집계 정의: `recipient_role = debtor AND status = sent AND (template_key IN SEQUENCE_TEMPLATE_KEYS OR origin = manual)` — `.or`로 결합(생성 SQL 확인 완료, 아래 4번). 시퀀스성은 origin 무관(기존 합산 유지), 수동은 템플릿 무관(신규).
  - 자동 1회성 3종(auto `issue_notice`·`partial_paid`·`paid_thanks`)과 U1 향(noti_*·recipient_role=user)은 집계 밖(Q10). `SEQUENCE_CAP`(5)·`SEQUENCE_TEMPLATE_KEYS`(7종)는 무변경.
  - 스코프 주석에 Q10·Q11·Q28 관계를 기록했다.
- **`app/services/reminders/send_service.rb`**
  - `cap_reached?`가 `MessageLog.cap_sent_count`를 쓴다. `sequence_step?`·가드 순서(REFUSED→SUSPENDED→FINISHED→INVALID_STATUS→INELIGIBLE_PLAN→수동 CAP→자동 CAP)는 무변경.
  - `guard_failure`의 상한 주석과 `cap_reached?`·`manual_cap_reached?` 주석을 Q28 규칙에 맞게 보강. `manual_cap_reached?`(수동 가드 — 채무자 향 sent 전체 5통)의 동작은 무변경.

## 3. Rule ID별 구현 매핑

| Rule ID | 구현 | 위치 |
|:---|:---|:---|
| VIEW-7 | 수신 거부 청구의 재개 진입점 미노출 + 재개 요청 상태 변경 없이 사유 안내로 거부 | `show.html.erb` 버튼 분기, `InvoicesController#restart_reminders` 가드 + `redirect_restart_refused` |
| REM-12/13 | "재개는 U1의 수동 재요청으로만" — 단, 수신 거부로 종결된 청구는 재개 불가(VIEW-7 단서). 수신 거부하지 않은 종결 청구의 재개·`restartable?`·PAST_WINDOW 차단은 기존 동작 유지 | `restart_reminders` 가드 위치(거부 우선, 그 외 로직 무변경) |
| PLAN-3 | 청구 건당 5통 하드리밋의 집계 확장 — 시퀀스성(origin 무관) + 수동(템플릿 무관) 합산 5통에서 자동 단계 차단 | `MessageLog.counted_for_cap`·`cap_sent_count`·`SendService#cap_reached?` |
| Q10 | 자동 1회성 3종(auto issue_notice·partial_paid·paid_thanks)은 상한 도달에도 발송·집계 밖 — 기존 guard(`sequence_step?` 한정) 유지로 회귀 없음 | `SendService#guard_failure`·기존 테스트 2건(서비스 "상한 도달에도 1회성…"·"수동 상한…Q10") |
| Q11 | 상한의 산정 대상 = 시퀀스성 자동 발송 및 수동 발송 — 수동 1회성(issue_notice) sent도 자동 상한 집계에 포함 | `counted_for_cap`의 `OR origin = manual` 절 |
| Q28 | 위 Q11 확정 집계의 구현 기록 — 스코프·서비스 주석에 근거 명시 | `message_log.rb` 상단 주석·`send_service.rb` 주석 |
| (부수) REM-6·P4·SEC-5 | 무변경 — 집계 교체는 판정 로직만이고 발송 이력·멱등·기록 경로는 그대로 | — |

## 4. 실행한 테스트 명령과 결과

| 명령 | 결과 |
|:---|:---|
| `bin/rails test test/models/message_log_test.rb test/services/reminders/send_service_test.rb test/controllers/app/invoices_reminders_test.rb` | **65 runs, 318 assertions, 0 failures, 0 errors, 0 skips** |
| `bin/rails test:system test/system/app_invoice_reminders_test.rb` | **16 runs, 139 assertions, 0 failures, 0 errors, 0 skips** — Rails `test:system` 태스크가 파일 필터 없이 시스템 테스트 전체를 실행했다(파일 필터 미적용 실측). 신규 VIEW-7 케이스 포함 전부 통과. |
| `bin/rails test test/services/tickets/notify_answer_service_test.rb test/services/tax_invoices/notify_issued_service_test.rb` | **12 runs, 78 assertions, 0 failures, 0 errors, 0 skips** — 이름 교체 파일 검증용(지시 목록 밖 추가 실행) |
| `bin/rubocop` | 430 files inspected, **no offenses** |
| `bin/rails zeitwerk:check` | all good |
| 생성 SQL 확인(`bin/rails runner 'puts MessageLog.counted_for_cap(1).to_sql'` — DB 접근 없음) | `…recipient_role = 0 AND status = 1 AND (template_key IN (7종) OR origin = 1)` — enum이 정수 바인딩됨을 확인(hash+`.or` 경로라 타입 캐스팅은 Rails가 담당) |

전체 테스트(`bin/rails test`)는 지시대로 실행하지 않았다. git 상태 변경 명령·외부 API 실호출도 없었다(테스트는 기존 `FakeSolapiClient`·`with_solapi_client` 대역만 사용).

## 5. 스스로 판단이 필요했던 부분과 판단 근거

1. **옛 이름 호출처 2곳 추가 수정(tickets·tax 테스트)** — 지시서의 수정 범위 표에 없지만 "옛 이름을 쓰는 곳을 전부 새 이름으로 바꾼다"는 테스트 지시에 직접 해당하고, 교체 없으면 해당 파일이 `NoMethodError`로 깨진다. 단언 내용(티켓·세금계산서 U1 알림은 상한 집계 밖 = 0)은 새 집계에서도 동일하게 성립한다(recipient_role=user·noti_* 계열은 새 스코프에서도 제외). 이름 교체만 하고 로직은 건드리지 않았다.
2. **집계 스코프 구현 방식** — 지시서가 SQL 문자열 조건의 enum 정수 바인딩 확인을 언급해 문자열 조건도 고려했으나, hash 조건 + `.or` 결합이 타입 캐스팅을 Rails에 맡겨 실수 여지가 없어 이를 택하고 생성 SQL로 정수 바인딩(`origin = 1`)을 확인했다(4번 표).
3. **가드 적용 순서** — 거부 가드를 `restartable?` 판정보다 앞에 뒀다. 거부 청구는 `restartable?`이 참이어도 재개해 발송이 절대 없으므로(`reminders_dispatchable`에서 영구 제외) "남은 단계 없음" 안내로 수렴시키는 것보다 정확한 사유 안내가 맞다. FINISHED 가드가 상한보다 먼저인 기존 서비스 가드 순서(선례: 서비스 테스트 6통째 차단을 별도 청구로 검증한 이유)와 같은 취지다.
4. **뷰의 보조 문구 범위** — 「안내 다시 보내기」 버튼 아래 보조 문구(`<p class="text-xs text-stone-400">…`)는 버튼 분기 내부에 있어 분기 추가만으로 함께 숨겨진다. 별도 조건 없이 단일 `elsif` 조건 확장으로 처리했다. 종결 배너("필요하면 「안내 다시 보내기」로…")는 refused 분기가 최우선이라 수신 거부 시 렌더되지 않는다 — `assert_no_match(/안내 다시 보내기/)` 단언이 이를 함께 검증한다.
5. **테스트 설치 위치·시점 고정** — 신규 테스트는 각 계층 기존 파일의 관련 섹션 뒤에 붙였고(컨트롤러는 REM-12·13 섹션 뒤 VIEW-7 섹션 신설), 시나리오 시각은 파일 관례대로 `travel_to(2026-11-10 10:00)`로 고정했다(TIME-1·파일 내 C-2 선례 — GET도 블록 안에서 수행).
6. **`sequence_sent_log` 헬퍼 미사용** — 신규 서비스 테스트의 수동 issue_notice 설치는 `origin: :manual`이 필요해 헬퍼(auto 기본) 대신 `MessageLog.create!` 직접 기록으로 했다(테스트 대역 헬퍼 추가 없이 최소 변경).

## 6. 하지 않은 것 / 남은 우려

- **하지 않은 것(지시 범위 밖·명시적 무변경)**: 청구 건 단위 보류 재개(`resume_reminders`)·거래처 보류 재개·수신 거부하지 않은 종결 청구의 재개 동작·수동 발송(`remind`)·`manual_cap_reached?` 동작·`SEQUENCE_CAP`·`SEQUENCE_TEMPLATE_KEYS`·가드 순서·상태 배너 분기. 문서(PRD·AGENTS·LAUNCH_TEST_*)는 수정하지 않았다(오케스트레이터 담당). 전체 테스트 미실행(지시).
- **우려 1 — 엣지: 수신 거부 + 청구 단위 보류 병존** — 거래처가 거부했고 그 청구에만 `reminders_suspended_at`이 남은 경우, 버튼 분기상 청구 보류 재개(「안내 재개하기」)가 여전히 노출된다. 재개해도 거래처 거부로 발송은 없지만(SendService REFUSED 가드) 버튼이 죽은 버튼처럼 보일 수 있다. 지시서가 `resume_reminders`를 "바꾸지 않는 것"으로 명시해 그대로 두었다 — 필요하면 별도 결정으로 정리 대상.
- **우려 2 — 상한 합산의 사용자 체감** — 수동 발송을 5통 쓴 청구는 이후 자동 단계가 전부 CAP_REACHED로 막히고, 발송 이력의 스킵 사유 안내("상한(5통)에 도달")만으로 U1에게 전달된다. PRD Q11·Q28의 의도된 동작이며 운영 데이터는 사실상 테스트 계정뿐이라 영향이 제한적이다(플랜 리스크 절과 동일 판단).
- **우려 3 — `test:system`의 파일 필터 미적용** — 파일 1개만 실행하려 했으나 태스크가 시스템 테스트 전체(16건)를 실행했다. 전부 통과했지만 포트원 런의 미커밋 시스템 테스트(`app_billing_channel_key_notice_test.rb` 등)도 함께 돌았고 0 실패였다 — 실호출 없이 대역만 쓰는 기존 헬퍼 경로라 안전했다.
- **후속 제안(이번 범위 밖)** — `LAUNCH_TEST_SCENARIOS.md` G-07-3·G-05-4 기대값과 체크리스트 재생성(플랜의 문서 절), 청구 상세의 CAP_REACHED 스킵 사유 라벨이 수동 합산 사유를 U1이 이해하기 쉬운지 운영 관찰.

## 7. 보완 구현(2차) — 보류·수신 거부 겹침 재개 차단 (2026-11-25, Developer)

1차 구현 §6 우려 1("수신 거부 + 청구 단위 보류 병존")과 같은 종류의 구멍 2곳을 같은 기준(VIEW-7 — 수신 거부는 채무자 의사라 어떤 "재개" 조작도 노출하지 않고, 요청이 들어와도 상태를 바꾸지 않고 사유를 안내한다)으로 메운다. 마이그레이션·라우트 변경 없음.

### 변경 파일·요약

| 파일 | 변경 |
|:--|:--|
| `app/views/app/invoices/show.html.erb` | 버튼 분기 2번 `elsif @invoice.reminders_suspended?` → `&& !@invoice.client.refused?` — 거래처 수신 거부와 청구 보류가 겹친 청구에서 「안내 재개하기」가 렌더되지 않는다. 섹션 머리 주석의 "청구 보류 → 재개 버튼" 줄에 겹침 단서("거래처 수신 거부와 겹치면 재개해도 발송이 없어 버튼 없이 안내만")를 보강하고, 분기 아래 한 줄 주석 추가(분기 3번 선례 스타일). 사용자 가시 문구 추가 없음(거부 배너가 사유 설명). |
| `app/controllers/app/invoices_controller.rb` | `resume_reminders` 첫 줄 거부 가드: `return redirect_resume_refused if @invoice.client.refused?` — 보류 마킹 해소(`update_column`) 전에 상태 변경 없이 차단. 안내 redirect는 private `redirect_resume_refused`(303 + `flash[:alert]` = "이 거래처가 추가 안내 수신을 거부하여 자동 안내를 재개할 수 없습니다.")로 분리 — 1차 수정의 `redirect_restart_refused` 패턴과 동일. 액션 본문 논리 5줄. 기존 주석("수신거부는 별도 상태다")을 가드 도입에 맞게 정정. |
| `app/controllers/app/clients_controller.rb` | `resume_reminders` 같은 가드 — `@client.refused?`면 상태 변경 없이 거래처 상세로 303 + 같은 문구의 alert(private `redirect_resume_refused`). 액션 본문 논리 5줄. 기존 주석(「수신거부는 재개 대상이 아니다」)에 가드 근거(되돌리는 경로 없음·발송 없음)를 명시. |
| `test/controllers/app/invoices_reminders_test.rb` | VIEW-7 섹션에 겹침 2건 추가: (a) 거부+보류+종결 청구 화면 GET — 「안내 재개하기」·「안내 다시 보내기」 모두 미노출 + 거부 배너 노출 (b) `PATCH resume_reminders` → 303 + alert 문구, `reminders_suspended_at`·`sequence_finished_at` 모두 유지. |
| `test/controllers/app/clients_reminders_test.rb` | **신설** — 거래처 보류·재개 컨트롤러 테스트가 기존에 전무함을 확인하고 같은 이름 체계로 만든다. 2건: 수신 거부하지 않은 거래처의 재개 성공(303·notice·마킹 해소) + 수신 거부 거래처의 재개 차단(303·alert·보류·거부 마킹 모두 유지). |
| `test/system/app_invoice_reminders_test.rb` | 1차 VIEW-7 케이스(종결+거부) 아래 인접 케이스 1건 추가 — 보류+종결+거부 겹침에서 거부 배너만 보이고 「안내 재개하기」 버튼이 없음을 브라우저 E2E로 검증. 기존 케이스는 무변경. |

바꾸지 않은 것(지시 준수): `suspend_reminders`(청구·거래처), 수신 거부하지 않은 경우의 재개 동작, 1차 수정의 `restart_reminders` 가드·뷰 분기 3번, 상태 배너 분기, 뷰의 "안내 다시 보내기" 관련 코드, 거래처 상세 뷰(이미 `if @client.refused?`가 최우선 — 버튼 미노출은 기존대로).

### Rule ID 매핑

| Rule ID | 구현 | 위치 |
|:--|:--|:--|
| VIEW-7 | 수신 거부한 거래처의 청구·거래처에 재개 조작을 노출하지 않고, 직접 요청도 상태 변경 없이 사유 안내로 거부 — "재개 불가" 기준의 보류 경로 확장 | `show.html.erb` 버튼 분기 2번, `InvoicesController#resume_reminders`·`ClientsController#resume_reminders` 가드 + 각 `redirect_resume_refused` |
| REM-7 | 보류 재개 경로의 자격 정제 — 보류 마킹이 있어도 거래처가 거부 상태면 재개 불가(정상 경로는 무변경) | 두 컨트롤러 `resume_reminders` 가드 위치(거부 우선, 이외 로직 무변경) |

### 실행한 테스트와 결과

| 명령 | 결과 |
|:--|:--|
| `bin/rails test test/controllers/app/invoices_reminders_test.rb test/controllers/app/clients_reminders_test.rb` | **24 runs, 143 assertions, 0 failures, 0 errors, 0 skips** — 신규 5건(청구 2·거래처 2파일 신설 분) 포함 전부 통과 |
| `bin/rails test:system test/system/app_invoice_reminders_test.rb` | **17 runs, 144 assertions, 0 failures, 0 errors, 0 skips** — 1차 때와 같이 `test:system` 태스크가 파일 필터 없이 시스템 전체를 실행(실측 유지). +1건은 신규 겹침 케이스 |
| `bin/rubocop` | 431 files inspected, **no offenses** |
| `bin/rails zeitwerk:check` | all good |

전체 테스트(`bin/rails test`)·git 상태 변경 명령·외부 API 실호출 없음(지시 준수 — 기존 대역만 사용).

### 판단이 필요했던 부분과 근거

1. **겹침 시나리오의 상태 구성** — 테스트를 "보류+거부" 최소 구성이 아니라 구멍 A의 실제 상태(보류+종결+거부 — 1차 §6 우려 1이 기술한 상태)로 재현했다. 이러면 버튼 분기 2번(신규 배제)과 3번(1차 배제)이 모두 거부에 의해 잡히는 것을 한 화면에서 검증하고, PATCH 차단 테스트도 두 마킹의 보존을 함께 단언한다.
2. **거래처 컨트롤러 테스트 파일 신설** — `resume_reminders_app_client`·`suspend_reminders_app_client`를 참조하는 기존 테스트가 0건임을 확인(grep 실측)해, 지시의 "적절한 기존 파일이 없으면 같은 이름 체계의 새 파일" 조건으로 `clients_reminders_test.rb`를 신설했다. 가드 검증 외에 수신 거부하지 않은 재개 성공 1건을 같은 파일에 넣어 "가드가 정상 경로를 막지 않는다"를 증명한다(지시의 "재개 성공 기존 테스트 유지"에 해당하는 테스트가 없었기 때문 — 이것이 그 역할을 대신한다).
3. **시스템 테스트는 인접 케이스 추가(지시의 두 선택지 중)** — 앞선 Developer의 기존 VIEW-7 케이스(종결+거부)는 전제가 "종결만"이라 건드리지 않고, 겹침을 별도 케이스로 분리해 각 케이스의 전제를 단일하게 유지했다.
4. **컨트롤러 주석 정정 범위** — `resume_reminders` 기존 주석이 "수신거부는 별도 상태다(화면 배지로 안내)"로 가드 부재를 전제하고 있어, 가드 도입과 함께 실제 동작을 서술하도록 고쳤다(주석-코드 불일치 방지 — 1차 때 뷰 주석 정정과 같은 취지).
5. **클라이언트 컨트롤러의 private 배치** — `redirect_resume_refused`는 `App::ClientsController`의 기존 `private` 절 맨 앞에 두었다(파일에 private 메서드 추가 선례 위치). 문구는 청구 컨트롤러와 정확히 동일 문자열로 통일해 U1이 어느 화면에서 봐도 같은 사유를 본다.

### 남은 우려

- **거래처 상세 화면의 보류 배너 문구** — 거래처가 거부한 뒤에는 거부 안내가 최우선이라 올바르지만, 거래처 단위 보류만 단독으로 걸린 상태의 배너·재개 버튼은 기존대로다(무변경 — 정상 경로).
- **보류·종결 마킹의 영구 잔존** — 거부 거래처의 보류 마킹은 재개 경로가 막혀 데이터상 남는다. 발송에는 영향 없음(REFUSED 가드가 모든 발송을 우선 차단)이며 재개 불가 원칙상 정리 경로를 두지 않는 것이 의도다.
- **1차 우려 1 해소** — 이번 보완 구현의 대상 자체다. 1차 §6의 우려 목록은 1차 시점 기록으로 그대로 둔다.

## 8. 리뷰 반영(3차) — W-1·W-3·W-4·W-5·§5-3 (2026-11-26, Developer)

`_workspace/05_review.md`(APPROVED — WARNING 7)의 지시 이슈 5건만 최소 수정한다. W-2(PRD 문언)·W-6(LAUNCH_TEST 재생성)·W-7(시스템 로그인 플레이크)은 문서·`test/system/` 담당(오케스트레이터·Tester)이라 이번 범위 밖이다. 마이그레이션·라우트 변경 없음. 범위 밖 파일 수정 없음. 이미 구현돼 있는 것(거부 가드 3종·`counted_for_cap` 집계)은 되돌리지 않았다.

### 변경 파일·요약

| 파일 | 이슈 | 변경 |
|:--|:--|:--|
| `app/views/app/clients/_client.html.erb` | W-1 | 재개 분기 `if client.reminders_suspended?` → `&& !client.refused?`(보류 분기는 기존 `elsif !client.refused?` 그대로). 수신 거부 + 거래처 보류 겹침 거래처 카드에는 재개·보류 버튼이 모두 렌더되지 않는다(수정·삭제는 그대로). 주석 1줄 보강(죽은 버튼 방지 근거). |
| `app/models/invoice.rb` | W-3 | 공개 메서드 `reminder_cap_reached?` 신설 — `MessageLog.cap_sent_count(id) >= MessageLog::SEQUENCE_CAP`. 상한 판정의 단일 출처. 주석에 PLAN-3·Q28·위임 관계 명시. |
| `app/services/reminders/send_service.rb` | W-3 | private `cap_reached?`가 `@invoice.reminder_cap_reached?`에 위임(집계 로직 복제 제거 — 판정 단일 출처). 주석 정리(집계 상세는 MessageLog 스코프 주석 참조로 이관). |
| `app/services/reminders/dispatch_service.rb` | W-3 | `steps_due_today`: 발송 예정 스텝이 있는 청구가 `invoice.reminder_cap_reached?`면 빈 배열 반환(스텝 산정 뒤 판정 — 대다수 청구는 상한 조회 없이 통과). 효과: ① PrenoticeService가 상한 도달 청구를 건너뛴다(REM-11 거짓 안내 해소) ② `restartable?` false → 「안내 다시 보내기」 요청이 "남은 단계가 없다"로 수렴. 14시 실제 스캔(`call`)·`notify_due_soon_targets`는 무변경(CAP_REACHED skip 기록 유지 — P4). 주석 보강. |
| `app/controllers/concerns/reminders_context.rb` | W-4 | `set_reminder_context`에 `@reminder_cap_reached = @invoice.reminder_cap_reached?` 추가 — 상세 화면을 그리는 3개 컨트롤러(Invoices·Payments·Promises)가 동일 @변수를 갖고 뷰는 @변수만 소비(쿼리 금지 유지). |
| `app/helpers/app/reminders_helper.rb` | W-4 | `reminder_state_badges`에 키워드 인자 `cap_reached: false` 추가 — 참이면 `["상한 도달", 종결과 같은 중립 톤]` 배지를 추가하고 「자동 안내 중」 배지를 내지 않는다. 수신 거부·보류·종결 배지 로직 무변경. 호출처는 show.html.erb 1곳(grep 확인). |
| `app/views/app/invoices/show.html.erb` | W-4·§5-3 | ① 배지 호출에 `cap_reached: @reminder_cap_reached` 전달 ② 상태 배너 분기: 거부 분기 다음에 `elsif @reminder_cap_reached` 신설 — 상한 안내 상자(중립 stone 톤 — 거부·종결 상자와 같은 마크업) ③ 버튼 행: 외부 조건을 `if @invoice.unsettled? && !@reminder_cap_reached`로 확장해 버튼 행 div와 무료 플랜 문구를 함께 렌더하지 않음(상한 도달 시 버튼 0개) ④ 분기 3번(「안내 다시 보내기」)에 `&& !@invoice.client.reminders_suspended?` 추가(§5-3 — 거래처 보류 겹침은 버튼 숨김, 배너가 재개 경로를 안내. 거래처 재개 후 다시 보임) ⑤ 섹션 머리 주석에 상한 도달·거래처 보류 겹침 상태 추가. |
| `test/controllers/app/clients_reminders_test.rb` | W-1 | 신규 2건: 거부+보류 거래처 카드의 목록 GET — 재개·보류 미노출·수정 유지·거부 배지 노출(delta 유일 거래처라 카드 단독) + 거래처 보류 단독의 재개 버튼 노출 회귀. |
| `test/controllers/app/invoices_reminders_test.rb` | W-4·§5-3·W-5(a)(b) | 신규 3건: 상한 도달 청구 GET(안내 상자·배지 노출, 버튼·라벨·무료 플랜 문구 미노출 — gamma로 무료 문구까지 검증) / 상한 전 청구 버튼 행 회귀 / 거래처 보류+종결 겹침 버튼 숨김+재개 후 복귀(assert_select 양성). 기존 2건 갱신: 재개 성공 테스트(REM-7)에 「안내 재개하기」 양성 단언, 종결 재개 성공 테스트(C-3)에 GET+「안내 다시 보내기」 양성 단언(W-5a), restart 거부 테스트에 보류 마킹 추가+`reminders_suspended_at`·`sequence_finished_at`·`refused_at` 보존 단언(W-5b). |
| `test/services/reminders/prenotice_service_test.rb` | W-3 | 신규 1건: 수동 issue_notice 5통 sent → D+1 09시 `PrenoticeService.call` → `noti_prenotice` 0건·stub 호출 0. |
| `test/services/reminders/dispatch_service_test.rb` | W-3·W-5(c) | 신규 2건: 상한 경계 4통 `restartable?` 참 → 5통 `steps_due_today` 빈 배열·`restartable?` 거짓 / 14시 스캔 — 수동 5통 → 자동 단계 `skipped`+`CAP_REACHED` 기록·stub 호출 0(P4 유지 검증). |
| `test/models/invoice_test.rb` | W-3 | 신규 1건: `reminder_cap_reached?` 경계 — 0·4통 거짓(집계 밖 U1 향·skipped 행 무영향 포함), 5통 참. |

### 리뷰 이슈 ID별 매핑

| 이슈 | 구현 | 검증 |
|:--|:--|:--|
| W-1 | 목록 카드 재개 분기에 `!client.refused?` — 거부 겹침 카드의 죽은 버튼 제거 | clients_reminders_test 신규 2건(거부 겹침 미노출 + 단독 보류 노출 회귀) |
| W-3 | 상한 판정 단일 출처 `Invoice#reminder_cap_reached?` → SendService 위임 → `steps_due_today` 상한 수렴(사전통보·재개 판정 동시 해소) | invoice_test 경계 4/5·prenotice_test 0건·dispatch_test 재개 판정·스캔 CAP_REACHED |
| W-4 | 제품 결정 반영: 상한 도달을 화면에 표시한다(배지+안내 상자), 종결 마킹은 하지 않는다. 버튼 행·무료 플랜 문구·「자동 안내 중」 배지는 상한 도달 시 미노출 | invoices_reminders_test 신규 2건(상한 화면·회귀) |
| W-5(a) | 비거부 종결·보류 청구의 재개 버튼 양성 단언(`assert_select`) | 기존 2건 갱신 |
| W-5(b) | restart 거부 테스트의 세 마킹 보존 단언 | 기존 1건 갱신 |
| W-5(c) | 14시 스캔 경로의 CAP_REACHED 기록·API 0 직접 단언 | dispatch_test 신규 1건 |
| §5-3 | 거래처 보류 + 청구 종결 겹침의 「안내 다시 보내기」 숨김(+재개 시 복귀) | show.html.erb 분기 3번 + invoices_reminders_test 신규 1건 |
| (미처리) W-2·W-6·W-7 | PRD 문언·LAUNCH_TEST 재생성·시스템 로그인 플레이크 — 문서·test/system 담당(지시의 수정 금지 범위) | — |
| (미처리) §5 관찰 1·2·4 | 번호 기준 거부 조회 부재·창 판정이 가드보다 앞(상한 도달 「지금 1통 보내기」는 이번에 버튼 자체가 숨겨져 실질 해소)·거부 거래처 suspend 마킹 잔존 — 지시 범위 밖 | — |

### 새로 추가한 사용자 가시 문구 전문

flash 신규 없음. 뷰 신규 3건(모두 청구 상세 "자동 안내 현황" 섹션):

1. 상태 배지: **「상한 도달」**
2. 상한 안내 상자 제목: **"발송 상한에 도달했습니다"**
3. 상한 안내 상자 본문: **"이 청구서에는 청구 건당 5통을 모두 보냈습니다. 단계별 자동 안내와 직접 안내는 더 보낼 수 없습니다. 입금을 기록하면 나가는 안내(잔액·감사)는 계속 발송됩니다."**

기존 배너·flash의 어휘("안내"·"발송 상한")·중립 톤(stone 상자 — 거부·종결 안내 상자와 같은 마크업)을 따른다(LP-12·REM-2 톤 준칙). REM-9 금지 표현 대상(사용자 편집 문구)이 아니며 책망·과장 표현 없음.

### 실행한 테스트와 결과

| 명령 | 결과 |
|:---|:---|
| `bin/rails test test/controllers/app/clients_reminders_test.rb test/controllers/app/invoices_reminders_test.rb test/models/invoice_test.rb test/models/message_log_test.rb test/services/reminders/` | **153 runs, 736 assertions, 0 failures, 0 errors, 0 skips** — 신규 11건(W-1 2·W-3 4·W-4 2·§5-3 1·W-5 파생 포함)+갱신 3건 포함 전부 통과 |
| `bin/rubocop` | 431 files inspected, **no offenses** |
| `bin/rails zeitwerk:check` | all good |

첫 실행에서 신규 스캔 테스트 1건 실패(내 단언이 setup용 수동 이력 5건까지 집계 — `dispatched_logs_for`는 전 이력 반환) → `where.not(template_key: "issue_notice")`로 스캔 결과만 단언하도록 수정 후 재실행 통과. 소스 결함 아님. 전체 테스트(`bin/rails test`)·git 상태 변경 명령·외부 API 실호출 없음(기존 `FakeSolapiClient`·`with_solapi_client` 대역만 사용). 기존 시스템 테스트가 변경 뷰의 문자열("자동 안내 중"·버튼 라벨)을 쓰지만 그 시나리오는 상한 미도달·거부 분기라 영향 없음을 정적으로 확인(Tester 실행 전 — 시스템 테스트는 이번에 실행하지 않았다).

### 판단이 필요했던 부분과 근거

1. **상한 배너 분기의 위치** — 지시대로 거부 분기 바로 다음(보류 분기보다 앞)에 뒀다. 보류+상한 도달 겹침에서는 상한 안내가 우선인데, 보류 배너의 "재개하면 다음 단계 안내부터 이어집니다"는 상한 도달 시 재개해도 발송이 없어 거짓이 되기 때문이다(재개 버튼도 버튼 행 숨김으로 함께 없다).
2. **버튼 행 숨김 방식** — 분기 사슬 각각에 조건을 더하는 대신 외부 조건을 `@invoice.unsettled? && !@reminder_cap_reached`로 확장했다. 상한 도달 시 빈 `border-t` 행이 렌더되는 것을 막고 무료 플랜 문구도 같은 조건으로 한 번에 숨겨진다(지시의 두 요구를 하나의 진실 출처로 처리).
3. **helper 인자 경유** — `cap_reached` 판정을 뷰에서 모델 메서드로 직접 부르지 않고 컨트롤러 컨텍스트(@변수)로 전달했다. `reminder_state_badges` 호출처가 show.html.erb 1곳임을 grep으로 확인했고 RemindersContext를 포함한 3개 컨트롤러(422 재렌더 경로 포함)가 모두 같은 @변수를 적재한다.
4. **W-5(b)의 마킹 구성** — `reminders_suspended_at` 보존 단언이 유의미하려면 값이 설정돼 있어야 해서 restart 거부 테스트의 전제를 거부+종결에서 거부+보류+종결로 넓혔다. resume 겹침 테스트(2차 §7)와 액션(resume vs restart)이 달라 별개 커버리지다.
5. **W-4 GET 테스트의 사용자** — gamma(Free)로 구성해 "무료 플랜은 자동 발송이 없습니다" 문구의 숨김까지 같은 화면에서 검증했다(delta·Plus로 하면 이 단언이 공허해진다).
6. **`steps_due_today`의 상한 판정 시점** — 지시대로 스텝 산정 뒤에 뒀다. 상한 조회는 count 쿼리 1회라 발송 예정 스텝이 없는 대다수 청구가 이 비용을 내지 않게 하는 배려다(빈 배열 조기 반환보다 산정 선행이 지시 취지).

### 남은 우려

- **약속 도과 U1 통보의 상한 결합(W-4가 지적한 잔여)** — 상한 도달 상태에서 `promise_overdue`가 CAP_REACHED로 막히면 U1 향 `noti_promise_unkept`(약속 미이행 통보)도 나가지 않는다(NOTI-1 훅이 발송 성공에 묶여 있음). 이번 지시는 상한 도달의 U1 "화면"만 다루므로 코드를 바꾸지 않았다 — 통보 누락이 문제라면 별도 결정(U1 향은 상한 집계 밖으로 등)이 필요하다.
- **상한 안내 상자의 settled 표시** — 배너 분기는 refused·suspended와 같이 settled 여부를 보지 않는다. paid 청구에 상한 도달 이력이 남으면 안내 상자가 표시되는데("입금을 기록하면…" 문구가 어울리지 않는 창) — 기존 배너들과 동일한 상태 기준 표기라 그대로 두었다. 운영 관찰 대상.
- **W-2·W-6·W-7** — 이번 지시 범위 밖(PRD 문언 보완·LAUNCH_TEST 재생성·시스템 로그인 DOM 클릭 우회) — 오케스트레이터·Tester 단계에서 처리 필요.

## 9. 마무리(4차) — 상한 안내는 미수 청구 한정 (2026-11-26, Developer)

§8 남은 우려 2("상한 안내 상자의 settled 표시")의 마무리 수정 1건. 3차에서 추가한 상한 안내 상자·「상한 도달」 배지가 수금 완료(paid)·무효(voided) 청구에도 그려지던 것을 **미수 청구에만** 표시하도록 좁혔다 — 완납된 청구에 "입금을 기록하면 나가는 안내(잔액·감사)는 계속 발송됩니다"는 맞지 않는 안내다(발송 가능 여부는 미수 청구에만 의미가 있다). 마이그레이션·라우트 변경 없음.

### 변경 파일·요약

| 파일 | 변경 |
|:--|:--|
| `app/views/app/invoices/show.html.erb` | 상한 안내 상자 분기 `elsif @reminder_cap_reached` → `elsif @reminder_cap_reached && @invoice.unsettled?`. 분기 순서(거부 → 상한 → 보류 → 종결) 유지. 분기 주석에 "미수 청구 한정 — 완납·무효 청구는 발송 대상이 아니라 안내하지 않는다" 1줄 보강. |
| `app/helpers/app/reminders_helper.rb` | `reminder_state_badges`의 「상한 도달」 배지 조건 `if cap_reached` → `if cap_reached && invoice.unsettled?`. 메서드 주석에 같은 단서 1줄 추가. 수신 거부·보류·종결·「자동 안내 중」 배지 로직 무변경. |
| `test/controllers/app/invoices_reminders_test.rb` | 신규 1건: 채무자 향 수동 발송 5통(상한 도달)인 **수금 완료** 청구의 `GET app_invoice_path` — "발송 상한에 도달했습니다"·"상한 도달" 모두 미노출. 상한 도달 상태 설치는 §8 기존 테스트와 동일 방식(수동 issue_notice sent 5건)을 재사용했다. |

거부 배너·보류 배너·종결 배너는 기존 기준(미수 여부 무관) 그대로 둔다 — 이번 지시는 상한 안내에만 해당한다.

### Rule ID 매핑

| Rule ID | 구현 | 위치 |
|:--|:--|:--|
| PLAN-3·W-4(표시) | 상한 도달 표시의 모집단 정의 — 발송이 의미 있는 미수 청구에만 배지·안내 상자. 상한 집계·발송 차단 로직은 무변경 | `show.html.erb` 상한 분기, `reminders_helper.rb` 배지 조건 |
| (무변경) VIEW-7·REM-7·REM-12 | 거부·보류·종결 배너는 미수 여부 무관 기존 기준 유지(지시 3번) | `show.html.erb` 분기 1·3·4 |

### 실행한 테스트와 결과

| 명령 | 결과 |
|:--|:--|
| `bin/rails test test/controllers/app/invoices_reminders_test.rb` | **26 runs, 172 assertions, 0 failures, 0 errors, 0 skips** — 기존 상한 도달 GET 테스트(미수 청구 — 안내 상자·배지 노출·버튼 없음) 포함 전부 통과 + 신규 1건 |
| `bin/rubocop` | 431 files inspected, **no offenses** |
| `bin/rails zeitwerk:check` | all good |

전체 테스트는 지시대로 실행하지 않았다. git 상태 변경 명령·외부 API 실호출 없음(신규 테스트는 발송이 없는 GET이라 솔라피 대역 불요 — 기존 테스트들도 대역 사용분 무변경).

### 판단이 필요했던 부분과 근거

1. **paid 전이 방법** — 팩토리로 만든 issued 청구에 `Invoice#mark_paid!`(INV-4의 유일한 paid 진입 경로 — issued→paid 조건부 UPDATE)를 썼다. `update_column` 우회 대신 실제 전이를 써야 "마감된 청구"라는 시나리오 전제가 검증 경로와 일치한다. 입금 레코드는 만들지 않았다 — 뷰의 paid 박스·잔액 표기는 `paid?`와 금액 스냅샷 기반이라 GET 렌더에 영향이 없다(실측 — 테스트 통과).
2. **분기 통과 뒤의 잔여 동작** — paid 청구는 상한 분기를 건너뛴 뒤 보류·종결 분기 판정을 계속 받는다(기존 기준 유지). 보류·종결 마킹이 없는 paid 청구는 배너 없이 지나간다. 배지 쪽도 「상한 도달」을 뺀 뒤 `badges`가 비어도 「자동 안내 중」 분기가 이미 `invoice.unsettled?`를 요구하므로 paid에 녹색 배지가 붙는 일은 없다 — 완납 청구의 배지는 (보류·종결 마킹이 없으면) 아무 것도 안 붙는다.
3. **단언 문자열의 충돌 여부** — "상한 도달" 미노출 단언은 발송 이력의 스킵 사유 문구("청구 건당 안내 상한(5통)에 도달하여 발송하지 않았습니다")와 부분 일치하지 않는다("상한(5통)에 도달"이라 "상한 도달" 연속 문자열이 아니다). 따라서 paid 청구 화면에 CAP_REACHED 스킵 이력 행이 남아 있어도 두 단언은 성립한다.

### 남은 우려

- **배너 3종(거부·보류·종결)의 settled 무관 표기는 기존 기준 그대로다**(지시 3번 — 명시적 무변경). paid 이후에도 종결 배너("필요하면 「안내 다시 보내기」로…")가 남을 수 있지만 이번에 손대지 않았다.
- **무효(voided) 청구의 상한 안내**도 이번 분기 조건으로 함께 숨겨진다(`unsettled?`가 voided를 제외) — 지시가 지적한 "paid·voided 여도 표시된다" 두 모집단을 한 조건으로 커버한다. voided 상세는 자동 안내 섹션 자체가 그려지는 모집단이라 배지·상자만 사라지고 섹션은 유지된다.


## 10. 기존 결함 수정(5차) — 창 밖 재예약 수동 발송의 흡수 (2026-11-26, Developer)

`_workspace/07_test_report.md` §4-1(기존 결함 후보)의 수정. 마이그레이션·라우트 변경 없음. 범위 밖 파일·포트원 미커밋 변경은 건드리지 않았다(git 상태 변경 명령·외부 API 실호출 0 — 기존 `FakeSolapiClient`·`with_solapi_client` 대역만 사용).

### 원인

창 밖 수동 발송은 `reschedule!`이 예약 슬롯(`create_scheduled_log` — pending+scheduled_at 선기록)을 남기고 `DeliverJob`(다음 평일 09시)을 예약한다("다음 평일 오전 9시에 발송됩니다" flash). 다음 날 잡이 실행되면 `claim_log`의 manual 경로는 무조건 `new_log!`이고, 그 INSERT가 부분 유니크 인덱스(`idx_message_logs_debtor_pending_uniq` — invoice×template, debtor×pending)에 걸린다. 복구 로직이 `find_existing_log`(가장 오래된 이력 1행)을 돌려줬기 때문에 **같은 템플릿의 과거 sent 이력이 있으면** 그 행(`sent`)의 가드 `log.sent?` → nil → `:duplicate`로 흡수됐다. 결과: 예약 슬롯은 영구 pending으로 남고(발송 이력의 「발송 예정」 유령 행 — show.html.erb의 pending+scheduled_at 표기) 회원에게 약속한 발송이 일어나지 않았다. 같은 템플릿의 과거 이력이 없으면 가장 오래든 행이 예약 슬롯이라 정상 발송됐다(테스트 #4 경로).

### 수정 — pending 슬롯 우선 원칙

| 파일 | 변경 |
|:--|:--|
| `app/services/reminders/send_service.rb` | ① 신규 private `find_pending_slot` — 같은 청구·템플릿·역할의 pending 슬롯 1행(유니크 인덱스가 0·1행 보장). ② `new_log!`의 `RecordNotUnique` 복구: 가장 오래된 이력 대신 **pending 슬롯**을 찾아 돌려준다. 기존 가드 유지 — 슬롯 없음·이미 sent·`in_flight?`(1분 내 갱신 = 다른 실행 발송 중)면 nil(duplicate), 그 외에는 슬롯을 갱신 경로로 이어 발송. ③ `claim_log`의 자동 경로: 갱신 경로 판정 후 pending 슬롯이 남아 있으면 그 슬롯을 우선 실행(아래 2번 판정). |
| `test/services/reminders/send_service_test.rb` | 결함을 고정하던 "현재 동작 기록" 테스트를 올바른 동작으로 교체(:sent·sent 2건·pending 0건·stub 호출 2회·`cap_sent_count` 2) + 회귀 2건 신설(자동 경로 슬롯 우선·상한 결합 가드 순서 불변). |

### 2번 판정 — claim_log의 "오래된 failed/skipped + pending 슬롯" 조합

**문제가 되므로 같은 원칙으로 최소 수정했다.** 자동 경로에서 가장 오래된 이력이 failed/skipped이면(가드 통과 시) 갱신 경로로 그 행을 재사용하는데, 그 사이 예약 슬롯(창 밖 지연 실행분이 `reschedule!`로 남긴)이 있으면 발송 자체는 일어나도 **슬롯이 영구 pending으로 남는다**. 이후 `claim_log`는 sent가 된 오래된 이력에서 조기 nil로 수렴해 슬롯을 다시 손대지 않고, 유령 「발송 예정」 행이 발송 이력에 영구 잔존한다. 도달 경로는 자동 발송 실패(HTTP_400 등) 후 같은 단계의 창 밖 지연 실행(잡 큐 지연·배포 공백 등 — 소급 창 설계가 전제하는 이벤트)이며, 실측 테스트로 증명했다: failed 이력 + 예약 슬롯 상태에서 다음 날 자동 실행 → **슬롯이 sent가 되고**(scheduled_at 보존) failed 이력은 P4 기록으로 보존·pending 0건. 기존 가드(sent·step_sent?·in_flight?)의 순서와 의미는 유지했다 — sent·진행 중 흡수 판정은 슬롯 우선보다 먼저 평가되므로 SEC-5 멱등은 불변이다.

### 영향 범위

- 자동 채무자 발송의 멱등(SEC-5)·가드 순서(수신거부→보류→종결→상태→자격→상한)·상한 집계(Q28)·origin 덮어쓰기(W-6)·`reschedule!` 흡수(W-4)는 전부 불변 — 변경은 "어느 행을 claim하는가"만이다. 슬롯을 claim해도 발송은 여전히 `guard_failure` 통과 뒤에 일어난다.
- 상한 결합(지시 4번): 상한 도달 청구의 예약 실행은 슬롯을 claim한 뒤 가드에서 CAP_REACHED skip으로 마킹된다(슬롯이 sent가 되지도 pending에 남지도 않는다) — 신설 테스트로 증명.
- 기존 재예약 테스트 4건(창 시작/종료 경계·주말 접수분·2회 재예약 1개 흡수·Free origin 보존)과 "수동 진행 중(pending) 슬롯의 자동 충돌은 duplicate" 등 멱등 테스트 전부 무수정 통과 — 부실(stale) pending 슬롯을 갱신 경로로 재사용하던 기존 동작은 슬롯 우선 경로와 같은 행을 고르므로 결과가 동일하다.

### 실행한 테스트와 결과

| 명령 | 결과 |
|:--|:--|
| `bin/rails test test/services/reminders/send_service_test.rb test/services/reminders/dispatch_service_test.rb test/models/message_log_test.rb test/controllers/app/invoices_reminders_test.rb` | **100 runs, 532 assertions, 0 failures, 0 errors, 0 skips** — 교체 1건 + 신설 2건 포함 |
| `bin/rubocop` | 431 files inspected, **no offenses** |
| `bin/rails zeitwerk:check` | all good |

전체 테스트(`bin/rails test`)는 지시대로 실행하지 않았다.

### 남은 우려

1. **07_test_report §6-2(테스트 #4·#5의 수동 issue_notice 반복 구성 현실성)** — 이번 교체 테스트는 실제 버튼이 고르는 confirm_d1(manual_step_key 기준)을 쓰도록 유지했다(기존 결함 테스트와 동일 구성). §6-2의 "버튼 경유 시 예약분이 실제로 sent 된다는 전제" 우려는 이번 수정으로 해소됐다 — 예약분은 이제 실제로 발송된다.
2. **유령 슬롯의 기존 데이터 정리** — 결함이 운영에서 발생시킨 영구 pending 슬롯이 이미 있을 수 있다(진단 쿼리: `MessageLog.where(status: :pending, recipient_role: :debtor).where.not(scheduled_at: nil)` 중 scheduled_at이 과거인 행). 수정 뒤에는 같은 템플릿의 다음 발송 시도가 슬롯을 흡수해 자체 해소되지만, 다시 요청될 가능성이 없는 템플릿의 슬롯은 남는다 — 데이터 정리는 별도 결정(러너로 skipped 마킹 등) 대상.
3. **claim_log 자동 경로의 극단 경합** — 오래된 failed 이력 + 신규 pending 슬롯 + 동시 실행 조합에서 슬롯의 `in_flight?` 흡수(1분 창)로 이중 발송을 막지만, 1분 경과 뒤의 경합은 기존 설계와 동일하게 인덱스 선점에 의존한다(변경 전부터 존재하는 이론 경합 — 이번 범위 밖).

## 11. 후보(6차) — pending 슬롯 우선을 채무자 향으로 한정 (2026-11-26, Developer)

§10(5차) "pending 슬롯 우선"의 후속 결함 수정. 마이그레이션·라우트 변경 없음. 변경 파일은 `app/services/reminders/send_service.rb`·`test/services/reminders/send_service_test.rb` 2개뿐이며, 작업 트리의 포트원 미커밋 변경은 건드리지 않았다(git 상태 변경 명령 0·외부 API 실호출 0 — 기존 `FakeSolapiClient`·`with_solapi_client` 대역만 사용).

### 원인

§10에서 `claim_log` 자동 경로에 넣은 슬롯 우선(`slot = find_pending_slot`)에 역할 조건이 없었다. "같은 청구·템플릿·역할의 pending 슬롯은 0 또는 1행"이라는 전제는 **채무자 향 부분 유니크 인덱스**(`idx_message_logs_debtor_pending_uniq` — `recipient_role=debtor AND status=pending`)가 만드는 것인데, U1 향 알림(`noti_prenotice` 등 — `recipient_role=user`, `scheduled_at` 지정)에는 그 인덱스가 없어 **다른 예정 시각의 pending 이력이 공존**할 수 있다(예: 전날 실행이 크래시해 남은 stale pending). U1 향의 멱등 규칙은 "같은 예정 시각의 재실행만 흡수"(파일 머리 주석·`find_existing_log`의 `scheduled_at` 필터)다.

결함 경로: U1 예정 알림 실행 시 슬롯 우선이 다른 예정 시각의 stale pending을 재사용해 그 행을 sent로 갱신 → **오늘 scheduled_at의 이력이 남지 않음** → 오늘 잡이 재시도되면 `find_existing_log`가 nil이라 같은 알림을 한 번 더 발송(멱등 깨짐·P4 기록 어긋남).

### 수정

| 파일 | 변경 |
|:--|:--|
| `app/services/reminders/send_service.rb` | `claim_log`: 슬롯 우선 판정을 채무자 향으로 한정 — `slot = find_pending_slot if debtor?`. U1 향은 5차 이전 경로(`log \|\| new_log!`)를 그대로 탄다(slot이 nil이므로 `slot \|\| log \|\| new_log!`가 `log \|\| new_log!`와 동일). 주석에 "슬롯 우선은 채무자 향 부분 유니크 인덱스 전제 — U1 향은 예정 시각별 멱등" 전제 명시. 가드 순서(sent → step_sent? → in_flight?)·`new_log!`의 `RecordNotUnique` 복구(RecordNotUnique는 채무자 향에서만 나므로 무변경)·그 외 로직 무변경. `find_pending_slot` 자체는 무변경 — 이번 한정 뒤 호출처가 채무자 향 경로 2곳(claim_log 슬롯 우선·new_log! 유니크 복구)만이 되어 "인덱스가 0·1행 보장" 주석이 그대로 참이 된다. |
| `test/services/reminders/send_service_test.rb` | 회귀 1건 신설 — "U1 예정 알림은 다른 예정시각의 stale pending이 있어도 자기 예정시각의 새 이력으로 발송한다 (SEC-5·S9)": 전날(11-09 09시) 크래시 잔여 pending을 심고 오늘(11-10 09시) 실행 → sent 1건 추가·오늘 scheduled_at 보유·stale pending은 기록으로 보존(P4)·총 2건. 같은 scheduled_at의 sent 흡수(②)는 기존 S9 테스트("U1 사전통보는 같은 예정시각 재실행을 흡수하고 다른 날은 새 이력이다")가 이미 커버 — 확인만 하고 무수정. |

### 5차 테스트 무수정 통과 확인

- "창 밖 재예약분의 실행은 동일 템플릿 sent 이력이 있어도 예약 슬롯을 재사용해 발송한다 (REM-3·SEC-5)" — 수동 경로는 `new_log!`의 유니크 복구(슬롯 반환)를 타므로 이번 변경과 무관, 통과.
- "자동 재시도는 오래된 failed 이력보다 예약 슬롯을 우선 실행하고 유령 슬롯을 남기지 않는다 (REM-3·SEC-5·P4)" — 채무자 향이라 `debtor?` 한정과 무관히 슬롯 우선 유지, 통과.
- "상한 도달 청구의 예약 실행은 슬롯을 CAP_REACHED skip으로 마킹하고 발송하지 않는다 (PLAN-3·Q28·REM-3)" — 채무자 향, 통과.

### 실행한 테스트와 결과

| 명령 | 결과 |
|:--|:--|
| `bin/rails test test/services/reminders/send_service_test.rb test/services/reminders/prenotice_service_test.rb test/services/reminders/notify_user_service_test.rb` | **50 runs, 286 assertions, 0 failures, 0 errors, 0 skips** |
| 위에서 신규 1건 + 5차 3건 + 기존 S9 1건 이름 필터 실행 | **5 runs, 39 assertions, 0 failures, 0 errors, 0 skips** |
| `bin/rubocop` | 431 files inspected, **no offenses** |

전체 테스트·임시 재현 테스트는 지시대로 실행하지 않았다.

### 남은 우려

1. **U1 stale pending의 잔존** — 이번 한정으로 U1 예정 알림은 stale pending을 흡수하지 않으므로 크래시 잔여 pending이 기록으로 남는다(P4 관점 의도). 정리(러너로 skipped 마킹 등)가 필요한지는 별도 결정 대상 — §10 남은 우려 2와 동일 성격.
2. **극단 경합은 §10 남은 우려 3을 그대로 승계** — U1 향은 인덱스 선점이 없어(원래 설계) 같은 scheduled_at 동시 재실행 시 `in_flight?`(1분 창) 흡수에 의존한다. 이번 변경으로 달라진 것은 없다.

## 12. 마감 리뷰 반영(7차) — C-1·W-1~W-5·W-7·W-4 (2026-11-26, Developer)

`_workspace/05_review.md` 마지막 절 "마감 리뷰 — 3~6차 변경분"의 이슈만 반영한다. 마이그레이션·라우트 변경 없음. 작업 트리의 포트원 미커밋 변경은 건드리지 않았다(git 상태 변경 명령 0·외부 API 실호출 0 — 기존 `FakeSolapiClient`·`with_solapi_client` 대역만 사용). 시스템 테스트는 지시대로 실행하지 않았다(단언 호환은 정적으로 확인 — 아래 6번).

### 변경 파일·요약

| 파일 | 이슈 | 변경 |
|:--|:--|:--|
| `app/services/reminders/send_service.rb` | C-1·W-1·W-3·W-5(a)(c)(d) | ① `call`: `auto_sequence_step? && step_sent?`면 창 판정보다 앞서 `:duplicate`(W-1) / `claim_log`가 슬롯을 돌려주면 `mark_execution_started!`(C-1). ② `in_flight?`: 기존 2조건(pending·1분 내 갱신)에 예약 슬롯 조건(`scheduled_at` 있으면 `updated_at >= scheduled_at`일 때만 진행 중)을 AND로 추가. ③ 신규 private `mark_execution_started!` — 예약 슬롯(`scheduled_at` 있음)만 `touch`(실행 시작 표시). ④ `new_log!` 복구의 `slot.sent?` 제거(`find_pending_slot`은 pending만 돌려주므로 항상 거짓 — W-5c). ⑤ `find_pending_slot` 첫 줄에 `return nil unless debtor?`(방어 — W-5d). ⑥ `manual_cap_reached?`를 `Invoice#manual_reminder_cap_reached?`에 위임(W-3 — 판정 단일 출처). ⑦ `claim_log` 블록 주석의 "수동은 이력을 누적하고"에 예약 슬롯 재사용 예외 반영(W-5a). |
| `app/services/reminders/dispatch_service.rb` | W-5(b) | 주석만: 머리의 "같은 산정" 서술에 `steps_due_today`의 상한 필터(PLAN-3·Q28) 단서 추가, `restartable?` 주석에 상한 도달 분(빈 배열 수렴) 추가. |
| `app/models/invoice.rb` | W-3 | 공개 메서드 `manual_reminder_cap_reached?` 신설 — 채무자 향 sent 전체 >= `SEQUENCE_CAP`(PLAN-3·Q11 수동 하드리밋). 주석에 자동 상한(`reminder_cap_reached?`·Q28)과의 집계 차이와 위임 관계 명시. |
| `app/controllers/concerns/reminders_context.rb` | W-3 | `set_reminder_context`에 `@manual_cap_reached = @invoice.manual_reminder_cap_reached?` 적재(뷰는 @변수만 소비 유지). |
| `app/helpers/app/reminders_helper.rb` | W-7 | `SKIP_REASON_LABELS["CAP_REACHED"]`를 "청구 건당 안내 상한(5통)에 …" → "청구 건당 발송 상한(5통)에 도달하여 발송하지 않았습니다"로(상자 문구·랜딩 용어 정합). |
| `app/views/app/invoices/show.html.erb` | W-2·W-3 | 상한 안내 상자 본문을 지시 문언 그대로 교체(W-2). 활성 분기(`@invoice.reminders_active?`)에서 `@manual_cap_reached`이면 「지금 1통 보내기」 버튼과 「다음 안내:」 라벨을 렌더하지 않고 그 자리에 한 줄 안내(기존 보조 문구와 같은 `text-xs text-stone-400`)를 렌더한다. 「안내 보류하기」는 유지. 무료 플랜 문구의 조건을 `@reminder_eligible || @manual_cap_reached`로 확장(W-3). 분기 주석에 W-3 근거 보강. |
| `test/services/reminders/send_service_test.rb` | W-4·C-1·W-1 | 신규 6건(아래 표). 기존 08:59 접수 → 09:00 실행 경계 테스트(d)는 무수정 유지. |
| `test/models/invoice_test.rb` | W-3·W-4 | 신규 1건 — `manual_reminder_cap_reached?` 경계(0·4통 거짓 → 5통 참) + 자동 상한 집계와의 독립성(partial_paid 5통에도 `reminder_cap_reached?` 거짓) + U1 향·skipped 행 무영향. |
| `test/controllers/app/invoices_reminders_test.rb` | W-3 | 신규 1건 — 수동 상한만 도달한 청구 GET(버튼·라벨·무료 문구·자동 상한 표시 없음, 한 줄 안내·「안내 보류하기」 있음). |

### 이슈 ID별 구현 매핑

| 이슈 | 구현 | 검증 |
|:--|:--|:--|
| C-1 | 예약 슬롯은 실행 시작 표시(`touch`)가 있을 때만 진행 중 — `in_flight?`에 `scheduled_at` 조건 AND 추가 + `call`의 claim 직후 `mark_execution_started!` | 신규 4건(수동 08:59:30 → 09:00:02 `:sent`·자동 동일 경계·첫 실행 뒤 30초 중복 흡수·표시만 있고 미발송인 병렬 실행 흡수) + 기존 재예약·멱등 테스트 전체 무수정 통과 |
| W-1 | `call` 첫 줄에서 이미 sent인 자동 단계는 `:duplicate`(재예약하지 않음) | 신규 1건 — 허용 종료 13시로 축소한 회원의 14시 스캔 → `:duplicate`·pending 0건·호출 0 |
| W-2 | 상자 본문 3문장 교체(첫 문장 산정 범위 명시·둘째 주어 보강·셋째 유지) | 기존 단언(`/입금을 기록하면 나가는 안내/` 등) 무수정 통과 — 구문구를 단언한 테스트는 없었음 |
| W-3 | 판정 단일 출처 `Invoice#manual_reminder_cap_reached?` → SendService 가드 위임 + `@manual_cap_reached` 적재 + 뷰 버튼·라벨 숨김·한 줄 안내 | invoice_test 신규 1건 + invoices_reminders_test 신규 1건 + 기존 수동 상한 가드 테스트 무수정 통과(위임이 같은 집계임) |
| W-5 | (a) `claim_log` 주석 예외 반영 (b) `dispatch_service` 머리·`restartable?` 주석 정정 (c) `new_log!` 복구의 죽은 조건 제거 (d) `find_pending_slot` 역할 방어 | 정적 — 동작 변경 없음(테스트 전체 무수정 통과로 확인) |
| W-7 | CAP_REACHED 스킵 라벨 "발송 상한" 용어 통일 | 기존 단언 `assert_match(/상한\(5통\)에 도달하여 발송하지 않았습니다/)`가 새 문구의 부분 문자열이라 무수정 통과 |
| W-4 | 위 C-1 4건 + W-1 1건 + 1회성 창 밖 재예약 1건 + invoice_test 1건 | 신규 7건 전부 통과 |

### C-1 설계 검증 ①~③ (지시 항목)

1. **예약 슬롯 생성 시 `updated_at < scheduled_at`** — 성립. 슬롯은 `reschedule!`의 접수 시각에 생성되고 예약 대상은 미래 시작 시각(창 시작 직전 접수: 08:59:30 생성·09:00 예약 / 전날 밤 접수: 20:00 생성·익일 09:00 예약)이라 항상 그렇다. 신규 테스트가 `assert slot.updated_at < slot.scheduled_at`으로 직접 고정했다.
2. **touch 뒤 `updated_at >= scheduled_at`** — 성립. `mark_execution_started!`가 claim 직후 실행 시각으로 `updated_at`을 올린다. 같은 예약 슬롯에 대한 두 번째 실행은 1분 조건·예약 조건이 모두 참이 되어 `:duplicate`로 흡수된다(SEC-5) — "표시만 있고 미발송인 병렬 실행" 테스트가 단언.
3. **다른 `in_flight?` 호출처의 부작용 없음** — ① `claim_log`의 `log && in_flight?(log)`: 자동 경로에서 log가 슬롯 자신일 때는 2번과 같은 판정. **U1 향 예정 알림**(오늘 09시 `scheduled_at`·09시 생성)은 생성 직후 `updated_at >= scheduled_at`이고 1분 조건이 먼저 평가되므로 기존과 같이 **생성 후 1분간** 진행 중 취급(S9 테스트·6차 stale pending 테스트 무수정 통과로 확인). 같은 예정시각 크래시 잔여 pending의 1분 경과 뒤 회복도 1분 조건이 우선이라 유지된다. ② `slot && in_flight?(slot)`(갱신 경로의 슬롯 우선): 창 밖 재예약분은 접수가 하루 이전이라 1분 조건에서 이미 탈락 — 무영향(5차 테스트 계열 무수정 통과). ③ `new_log!` 복구: `RecordNotUnique`는 채무자 향에서만 나므로(C-1의 대상 경로) 같은 판정 — 창 시작 직전 접수분이 이 경로로 발송된다(신규 테스트 a).

### 새로 바뀐 사용자 가시 문구 전문

1. **상한 안내 상자 본문(W-2)** — `이 청구서에는 단계별 안내와 직접 안내를 합쳐 청구 건당 5통을 모두 보냈습니다. 이 청구서의 자동 안내와 직접 안내는 더 보낼 수 없습니다. 입금을 기록하면 나가는 안내(잔액·감사)는 계속 발송됩니다.` (제목 "발송 상한에 도달했습니다"는 무변경)
2. **수동 상한 한 줄 안내(W-3·신설)** — `직접 안내는 청구 건당 5통을 모두 보내 더 보낼 수 없습니다.` (「지금 1통 보내기」·「다음 안내:」 라벨 자리 — 기존 보조 문구와 같은 크기·톤)
3. **CAP_REACHED 스킵 사유 라벨(W-7)** — `청구 건당 발송 상한(5통)에 도달하여 발송하지 않았습니다` (기존 "청구 건당 안내 상한(5통)에 …")

flash 신규·변경 없음. 세 문구 모두 "안내" 어휘·중립 톤 유지(LP-12·REM-2 준칙 — REM-9 금지 표현 대상 아님).

### 실행한 테스트와 결과

| 명령 | 결과 |
|:--|:--|
| `bin/rails test test/services/reminders test/models/invoice_test.rb test/models/message_log_test.rb test/controllers/app/invoices_reminders_test.rb test/controllers/app/clients_reminders_test.rb test/services/tickets test/services/tax_invoices/notify_issued_service_test.rb` | **195 runs, 1,019 assertions, 0 failures, 0 errors, 0 skips** — 신규 8건(C-1 4·W-1 1·W-4b 1·invoice 1·컨트롤러 1) 포함, 기존 테스트 무수정 통과 |
| `bin/rubocop` | 431 files inspected, **no offenses** |
| `bin/rails zeitwerk:check` | all good |

### 판단이 필요했던 부분과 근거

1. **`in_flight?` 예약 조건의 결합 방식(AND vs 치환)** — 지시 문언 "기존 조건에 더해 … 일 때만 진행 중으로 본다"를 AND(추가 요건)로 구현했다. 치환으로 구현하면 U1 예정 알림의 크래시 잔여 pending이 1분 경과 뒤에도 영구 진행 중이 돼 회복이 깨진다(검증 ③ — S9·6차 테스트의 전제). AND로 두면 U1은 1분 조건이 우선 평가돼 기존 동작 그대로다.
2. **W-1 조기 반환의 위치** — 지시의 "call 첫 줄 쪽"대로 `outside_window?`보다 앞에 뒀다. 창 판정이 먼저면 이미 sent인 단계에 재예약이 일어나는 것이 W-1의 원인 자체다.
3. **(c) 동시 실행 회귀 테스트의 origin 선택** — 지시의 ":duplicate·stub 호출 1회"가 성립하는 경로는 자동 origin이다. 수동은 REM-8상 재발송 허용이라 첫 발송 뒤 30초의 두 번째 수동 실행은 duplicate가 아니라 정상 누적이기 때문(기존 테스트 "수동 재발송은 멱등 판정 밖" 참조). touch 기반 흡수를 직접 보는 테스트는 별도로 "첫 실행의 claim 표시 시뮬레이션"(슬롯 touch → 수동 실행 → duplicate·호출 0)으로 추가했다.
4. **수동 상한 화면에 「안내 보류하기」를 남긴 판단** — PRD PLAN-3의 자동 상한 문언("보류·직접 발송·재개·다시 보내기 … 노출하지 않는다")과 수동 상한 문언("「지금 1통 보내기」와 「다음 안내」 표기를 숨기고 한 줄 안내를 보인다")이 다르다. 지시도 "「안내 보류하기」는 유지"로 명시해 수동 상한 문언을 따랐다 — 보류는 발송 조작이 아니라 자동 안내 중단 조작이라 막힌 조작이 아니다.
5. **한 줄 안내의 표기 위치·톤** — 활성 분기 안 보류 버튼 옆, 기존 「다음 안내」 라벨과 같은 클래스(`text-xs text-stone-400`)로 지시의 "기존 보조 문구와 같은 크기·톤"을 충족했다.
6. **시스템 테스트 무수정 확인(실행 없이)** — `test/system/app_invoice_reminders_test.rb`가 단언하는 문자열은 상자 제목("발송 상한에 도달했습니다")·셋째 문장("입금을 기록하면 나가는 안내")·배지("상한 도달")·버튼 라벨("지금 1통 보내기")로 이번에 바꾸지 않은 것들이다(정적 grep·파일 읽기 확인). 상한 도달 시나리오는 delta(Plus) 기반이라 무료 플랜 문구 단언과도 무관하다.

### 남은 우려

1. **claim-touch와 발송 사이의 극단 경합은 §10 남은 우려 3의 승계** — `mark_execution_started!`로 진행 중 창의 기점이 접수 시각에서 claim 시각으로 옮겨졌을 뿐, claim 직후~touch 직전의 창(밀리초 단위)에서의 동일 슬롯 동시 실행은 기존 설계와 같이 인덱스 선점 의존이다(이번 diff가 만든 경합 아님).
2. **C-1 이전 운영 데이터의 유령 슬롯** — 결함이 만든 영구 pending 슬롯(진단: `MessageLog.where(status: :pending, recipient_role: :debtor).where.not(scheduled_at: nil).where(scheduled_at: ..Time.current)`)은 §10 남은 우려 2와 같은 별도 정리 결정 대상이다(수정 뒤 같은 템플릿의 다음 발송 시도가 흡수해 자체 해소되는 경로도 유지된다).
3. **수동 상한 청구의 약속 트랙 결합** — 수동 상한만 도달한 청구에서 약속 트랙 자동 단계(`promise_overdue`)는 시퀀스성이라 자동 상한 집계(cap_sent_count — 수동 포함)로 막히고 `noti_promise_unkept`도 나가지 않는다(§8 남은 우려 1의 기존 동작 — 이번 W-3는 화면 표시만 다룬다).

