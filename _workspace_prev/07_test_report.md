# 07_test_report — F-REM 리마인더 시퀀스 (Phase 7 Tester, 2026-11-04)

- **결론: 전부 통과** — `bin/rails test` **628 runs, 3717 assertions, 0 failures, 0 errors, 0 skips**
  (작업 개시 시점 스위트 대비 **+128건**, 기존 테스트 회귀 0)
- **게이트**: `bin/rubocop` 168 files **no offenses** · `bin/brakeman` **no warnings** ·
  `bin/rails zeitwerk:check` 통과
- **외부 API 실호출 0** — 솔라피 전 경로를 `FakeSolapiClient` 생성자 주입(`client:`) +
  `SolapiStubbing.with_solapi_client`(클래스 생성 경로 방어선)으로 차단(REM-10·W-7 방어선 준수)

---

## 1. 생성·확장 파일 (이번 세션 신규 107건)

| 파일 | 건수 | 커버 시나리오 → Rule ID |
|---|---|---|
| `test/services/reminders/send_service_test.rb` | 28 | **최우선** — 창 내 정상 발송+기록·변수(REM-1/2/6)·창 경계 08:59/09:00/17:59/18:00·주말 재예약·U1 창 무관(REM-3)·재예약 origin 전달+pending 선기록·2회 흡수(B-2·W-4)·가드 매트릭스 7종(REFUSED·SUSPENDED·FINISHED·INVALID_STATUS·INELIGIBLE_PLAN·CAP_REACHED·NO_PHONE — 1회성 3종 제외 포함 B-1)·상한 경계 4→5통 통과/6통째 차단·1회성 집계 밖(PLAN-3·Q10)·auto 2회 멱등·수동 sent 후 자동 차단·수동 이력 누적·수동 pending 경합 S8·U1 scheduled_at 멱등 S9·이벤트 중복 허용(SEC-5·C-1)·final_d14/promise_overdue 성공 시에만 종결+U1 통보(REM-12/13·NOTI-1)·HTTP_400 확정 실패/TIMEOUT 모호 실패 기록(P4·§11.2)·failed 슬롯 origin 덮어쓰기(W-6)·부분입금 잔액 변수·약속일 치환(REM-4·PAY-2·PROMISE-4) |
| `test/services/reminders/dispatch_service_test.rb` | 18 | 기본 트랙 D-1/D+1 미열람·열람 분기·분기 고정·D+7·D+14·소급 창 PAST_WINDOW 기록/churn 0·주말 nominal 월요일 이연(REM-2/3/4·SHARE-5)·약속 트랙 대체·도과 종결+U1 통보·재약속 무상태 재계산·부분입금 청구는 시퀀스만(PROMISE-3·PAY-2)·Free INELIGIBLE skip(REM-8)·`steps_due_today` 연체 단계 한정+발송 제외(C-2·REM-11)·`restartable?` 재개 판정+이어발송·재개 불가(C-3)·`manual_step_key` 단일 출처(W-1·REM-8) |
| `test/services/reminders/prenotice_service_test.rb` | 6 | 사전통보 모집단(연체·도과 한정 — invoice_notice·promise_d1 제외)·자격 필터(REM-8)·noti_due_soon 내일 1일(평일)·자격 무관·금요일 토·일·월 3건 묶음(W-3·NOTI-1)·당일 재실행 멱등(REM-11·C-2) |
| `test/services/reminders/notify_user_service_test.rb` | 3 | NOTI-1 8종 전 경로 sent·phone 미등록 NO_PHONE skip·창 밖 즉시 발송(NOTI-1·REM-3 제외) |
| `test/services/solapi/client_service_test.rb` | 7 | v4 단일 발송 요청(경로·HMAC-SHA256 헤더·kakaoOptions·번호 정규화·timeout 옵션)·MISSING_TEMPLATE/MISSING_CREDENTIALS fail-fast(요청 0)·HTTP 오류 본문 code 매핑·HTTP_<status> 폴백·TIMEOUT/CONNECTION 정규화+retryable(REM-10·[INFERENCE] 계약 고정) |
| `test/jobs/reminders/overdue_mark_job_test.rb` | 4 | 만기 경과→overdue 저장화·당일 경계(경과일에만)·promised 제외·draft/paid/voided 무영향·멱등 재실행(INV-4·PROMISE-3·TIME-1) |
| `test/jobs/reminders/deliver_job_test.rb` | 6 | perform_now stub 발송·origin 기본 auto(3인자 호환)·4번째 origin 전달(B-2)·**창 밖 접수→재예약 pending(manual)→다음 평일 실행 sent 전체 여정(B-2·W-4)**·재예약 재인큐 origin 유지·존재하지 않는 청구 discard_on·자동 Free INELIGIBLE 유지(REM-8·W-7) |
| `test/controllers/app/invoices_reminders_test.rb` | 12 | 보류/재개 303·마킹(REM-7)·초안·수금완료 404 수렴(unsettled 스코프)·Free 수동 발송 성공(REM-8)·REFUSED 가드 저지 flash+skipped 기록(VIEW-7)·창 밖 재예약 flash(REM-3)·재개 가능 303+해소·재개 불가 alert+마킹 유지(REM-12/13·C-3)·issue send_notice 1/0/부재 → 인큐 1·0·1+flash 분기(SHARE-6)·타 사용자 4격리 |
| `test/controllers/app/payments_reminders_test.rb` | 4 | 원클릭 마감 send_thanks 미전송(구폼)=기본 켬 인큐(PAY-4)·해제=인큐 0·부분입금 partial_paid 옵션 무관 인큐(REM-4·PAY-2)·422 재렌더 발송 이력 컨텍스트 적재(RemindersContext — REM-6) |
| `test/controllers/viewer_refusal_test.rb` | 8 | refusal 접수 PRG→전용 완료 화면·거래처 refused_at+청구 종결+noti_refusal 인큐(VIEW-7)·위조 promised_on/memo 무시(PROMISE-2)·재접수 refused_at 불변+이력 보존(P4)·접수 후 자동 스캔 발송 전무+수동 REFUSED 가드(이중 방어)·완료 화면 VIEW-8/SURF-3/4(③→③ 링크만·noindex)·무효 토큰 404 수렴(VIEW-6)·rate_limit 10회/10분 공유(PROMISE-2) |
| `test/system/viewer_refusal_test.rb` | 2 | **비로그인 E2E** — 열람→거부 진입(summary 재확인·JS 불요)→접수→완료 화면 문구→refused_at·종결 마킹→③→③ 링크 한정(VIEW-7·PROMISE-2·VIEW-8·P1)·거부 후에도 열람·응답 가능(발송만 중단) |
| `test/system/app_invoice_reminders_test.rb` | 2 | **/app 회귀 E2E** — UI 로그인→자동 안내 현황·배지·다음 안내 라벨(manual_step_key)→지금 1통 보내기(turbo_confirm→flash→발송 이력 갱신·채널 표기 REM-6/8)→보류/재개 토글 전체 여정(REM-7) |
| `test/models/client_test.rb` (+2) | 확장 | refused?·reminders_suspended?·reminders_active? 접근자·reminders_active 스코프 제외(Rem-7·VIEW-7) |
| `test/models/promise_test.rb` (+3) | 확장 | refusal kind enum·주입 필드 nil 강제·mark_promised! 비대상+이력 보존+재응답 공존(VIEW-7·P4) |
| `test/services/promises/register_service_test.rb` (+2) | 확장 | paid_report→청구 즉시 일시정지+noti_deposit_reply 인큐·**접수 후 자동 스캔 발송 전무**(PROMISE-7·REM-7·리뷰 중점 8) |

이전 세션 산출물(검증 통과·1건 오류 수정): `test/models/message_log_test.rb` 13건(enum·검증·PLAN-3 카운트·pending 슬롯 유니크 C-1 회귀)·`test/models/invoice_test.rb` F-REM 12건(mark_overdue!·finish/restart_sequence!·reminders_dispatchable·접근자).

## 2. 리뷰 중점 9건 검증 결과 (05_review.md §Tester)

| # | 중점 항목 | 검증 테스트 | 결과 |
|---|---|---|---|
| 1 | **B-1 회귀** — 전액 마감→paid_thanks sent·부분입금→partial_paid sent·1회성 REFUSED/SUSPENDED 유지 | send_service_test: 상태 가드 시퀀스 한정(2건)·자격 가드 범위(1회성)·SUSPENDED 1회성 유지·부분입금 변수(sent) | **통과** — paid 청구 paid_thanks `:sent`, partially_paid 청구 partial_paid `:sent`, REFUSED/SUSPENDED는 1회성도 `skipped` |
| 2 | **B-2 회귀** — Free+18시 이후 remind→재예약 pending(manual)→다음 평일 09시 실행 sent·origin=manual | deliver_job_test: 창 밖 접수분 전체 여정·4번째 origin 인자·재예약 재인큐 / send_service_test: Free 수동 창 밖 / controller: 창 밖 flash | **통과** — 토 20시 접수→월 09시 실행→sent·manual·pending이 sent로 갱신(로그 1개) |
| 3 | **C-1** — 수동 sent 후 DispatchService 재발송 부재·분기 고정 | send_service_test: 수동 sent→자동 `:duplicate`·로그 0 / dispatch_service_test: D+1 발송 후 분기 고정(재열람 무영향)·steps_due_today 수동 sent 제외 | **통과** — 동일 단계 sent 1건 유지, 열림 변화로 타 분기 재발송 없음 |
| 4 | **C-2** — 금 만기→월 09시 steps_due_today/noti_prenotice→14시 발송·due_soon 3건 묶음 | dispatch_service_test: 주말 nominal 소급(아침 산정→14시 발송) / prenotice_service_test: promise_d1 제외·promise_overdue 포함·금요일 3건 | **통과** — 09시 통보와 14시 발송 동일 모집단, 금 아침 토·일·월 선행 통보 |
| 5 | **C-3** — 종결+창 내 미발송→restart 303·해소·이어발송 / 소진 종결→alert·마킹 유지 | controller: restart 2건 / dispatch: restartable? 2건(재개 후 final_d14 sent→재종결 포함) | **통과** |
| 6 | **SEC-5 경합** — auto 2회·수동 진행 중 자동(S8)·U1 사전통보 반복(S9) | send_service_test: 멱등 4건 | **통과** — auto×auto sent 1건, 수동 pending→`:duplicate`, 다른 날 사전통보 sent 2건 |
| 7 | **PLAN-3 경계** — sent 4→5통째 sent→6통째 CAP_REACHED·1회성 집계 제외 | send_service_test: 상한 2건 | **통과** — 5통째 통과·6통째 skipped(CAP_REACHED)·paid_thanks는 상한 도달에도 sent·카운트 불변 |
| 8 | **PROMISE-7·VIEW-7** — paid_report 후 스캔 전무·noti_deposit_reply·refusal 즉시 차단·PRG·rate_limit·인앱 VIEW-1 | register_service_test(+2)·viewer_refusal_test(8건)·system viewer_refusal | **통과** — paid_report→suspended·스캔 모집합 제외·noti_deposit_reply 인큐 / refusal 전 경로 / rate_limit 11회째 429 / 인앱 UA는 기존 viewer_controller_test가 회귀 통과 |
| 9 | **W-7 대비** — DeliverJob 등 잡·스캔 경로 stub 선행 | deliver_job_test 전체 `with_solapi_client`·dispatch 스캔 `with_solapi_client` 래핑 | **통과** — 실호출 0(REM-10). 시스템 테스트 Turbo 경합 이슈 1건 발견→플래시 어설션까지 stub 유지로 수정(§4 참조) |

## 3. 시간 규칙(TIME-1·REM-3) 커버

- 창 경계 4점(08:59 skip→당일 09시 예약 / 09:00 sent / 17:59 sent / 18:00 skip→익일 09시)·주말(토·일)→다음 평일 09시
- 금 만기→일요일 nominal→월요일 소급 발송(PAST_WINDOW 병행 기록)·만기 당일은 연체 아님(다음날 전환)
- 월말·연말은 `next_window_at`·`window_end`의 평일 롤링 산술로 커버(토→월·일→월 단정)
- 주의: `Invoice#overdue?` 등 **파생 판정은 Date.current 의존**이라 어설션을 travel_to 블록 안에서 수행(블록 밖은 실제 오늘 기준) — 이번 세션의 테스트 오류 원인 1건

## 4. 실패 이력·원인 분류 (전부 자체 수정 완료 — 최종 0 실패)

| 분류 | 건수 | 내용 |
|---|---|---|
| **테스트 오류**(자체 수정) | 다수 | ① 기존 세션 산출분 `invoice_test.rb` 3건이 존재하지 않는 `mark_overdue?` 호출(올바른 이름 `mark_overdue!`) ② `overdue?` 파생 판정을 travel 블록 밖에서 단언 ③ date_selected에 과거일 주입(모델이 과거일을 거부 — 접수일 기준 생성으로 수정) ④ 소급 창에 걸린 invoice_notice의 PAST_WINDOW 기록을 기대 배열에 누락 ⑤ fixture 간섭(만기 10-30 청구의 D+14 nominal이 금요일 11-13에 도래 → 통보 모집단 합류 — 무간섭 금요일로 변경) ⑥ `click_on`은 `<summary>`를 찾지 못함(`find("summary")`로 수정) ⑦ 시스템 테스트에서 Turbo 확인 후 비동기 요청 중 stub 블록이 먼저 종료되어 **원본 래퍼로 실호출 1회 발생(응답 실패)** → flash 어설션까지 stub 유지로 수정 ⑧ SHARE-6 테스트가 draft 아닌 issued를 생성(404) ⑨ 기타 어설션 정합성 |
| **코드 버그**(미수정 — 보고만) | 0건 | 차단 수준 버그 없음. 관찰 2건은 아래 §5 |

## 5. 발견 사항 (코드 미수정 원칙 준수 — Developer 판정 대상)

1. **[경계 낮음] W-7 주입 체계의 잔여 gap** — `Reminders::SendService#after_send_hook`의
   promise_overdue 성공 경로가 `Reminders::NotifyUserService.new(invoice:, template_key:)`를
   **client: 미전달로 생성**해 생성자 주입 체계(DispatchService→SendService→NotifyUserService)가
   이 1지점에서 끊긴다. 실측: 주입 테스트에서 해당 경로가 credentials의 유효 키로 실제 솔라피
   호출을 시도(HTTP_400 실패 기록). `with_solapi_client`(클래스 생성 경로 방어선)으로는 커버되어
   테스트는 통과하나, 후속 접촉 시 `after_send_hook`에 `client: @client` 전달을 권장한다.
2. **[경계 낮음·[INFERENCE] 연계] `Solapi::ClientService#parse`의 비객체 오류 본문** — HTTP 오류
   응답 본문이 JSON 객체가 아닌 원시값(예: `"internal"`)이면 `payload[:code]` 접근에서
   TypeError(ApiError 대신)가 발생한다. 실솔라피는 객체 본문 가정([INFERENCE] 표)이라 라이브
   실측 후 재확인 대상. 테스트는 현실적인 객체 본문 케이스로 계약을 고정했다.
3. **[환경 노트] 테스트 DB 고아 행** — 비트랜잭션 동시성 테스트(`use_transactional_tests = false`
   계열)의 잔존 payments 행이 명시적 fixture 목록 로드 시의 전체 FK 검증(`foreign_key_check`)을
   실패시킬 수 있다. `bin/rails db:test:prepare`로 재초기화해 해소 — 재발 시 동일 조치.

## 6. 최종 게이트 (2026-11-04)

```
bin/rails test          → 628 runs, 3717 assertions, 0 failures, 0 errors, 0 skips
bin/rubocop             → 168 files, no offenses
bin/brakeman            → no warnings
bin/rails zeitwerk:check → Otherwise, all is good!
```

---

## 7. CI 안정화 (2026-11-06) — 시스템 테스트 클릭 유실(chromedriver) 제거

### 현상의 경과 (3단계)

1. **최초**: GitHub Actions(ubuntu-latest)에서만 REM-7 실패 — `Capybara::ModalNotFound`(`accept_confirm` 블록 내 `click_button "안내 보류하기"`). 로컬 재현 없음.
2. **1차 시도(wait_for_turbo — Turbo 부트 레이스 제어) 후 CI 재실행**: REM-7은 통과했으나 **반대 테스트 REM-6·8에서 동일 ModalNotFound 재발**(시드별 랜덤). wait_for_turbo 통과 직후의 클릭이므로 **부트 레이스 가설 기각**.
3. **2차 접근(window.confirm stub + 평범한 click_button) 후 로컬 재현 획득**: 로컬에서도 간헐 실패(보류/재개 flash 미표시, 재현율 ~30~50%). 실패 run의 서버 로그에서 **클릭에 대응하는 HTTP 요청이 아예 없음**을 확인 — preventDefault 후 제출 유실이 아니라 요청 자체가 미발생.

### 근원 확정 (임시 진단 테스트 + 페이지 내 이벤트 계측 실측)

`submit`/`pointerdown`/`turbo:*` 이벤트 계측으로 두 클릭 경로를 동일 세션에서 비교:

| 경로 | 결과 | 이벤트 흔적 |
|---|---|---|
| Selenium 합성 클릭(`click_button`) | **8/8 유실** | `ev=[]` — pointerdown 포함 이벤트 전무(뷰 요소에는 도달했으나 이벤트가 발화되지 않음) |
| DOM 레벨 클릭(`execute_script`로 `btn.click()`) | **8/8 성공** | `click→submit dp=false→turbo:submit-start→turbo:visit→turbo:load` 전 체인 정상 |

**결론**: selenium-webdriver 4.50.0 + Chrome 156 조합에서 chromedriver의 합성 클릭이 세션 상태에
따라 입력 이벤트를 통째로 드롭한다(로컬 macOS·CI ubuntu 공통 — 양측 모두 최신 Chrome). 최초
CI의 ModalNotFound도 같은 근원이다: 클릭 유실 → 폼 미제출 → 다이얼로그 미발생 → accept_confirm
대기 초과. Turbo·Selenium 다이얼로그 처리 경합설은 폐기. 세션별 건전/불량이 갈려 재현율이
불규칙했던 것까지 설명된다.

### 최종 수정 (test/ 2파일만 — 앱 코드 변경 0)

| 파일 | 변경 |
|---|---|
| `test/application_system_test_case.rb` | ① `wait_for_turbo(timeout: 5)` — 유지(Turbo Confirmers가 부르는 `window.confirm` stub의 주입 시점 보장: readyState complete 폴링, 초과 시 `Minitest::Assertion`, 드라이버 경합 오류는 재폴링) ② `dom_click_button(label)` 신설 — `find(:button)`(Capybara 대기·부재 실패 규칙 유지) 후 `execute_script("arguments[0].click()")`로 DOM 클릭. 실제 클릭과 동일한 click→submit→Turbo(fetch) 체인을 타므로 흐름 검증 목적에 동등 |
| `test/system/app_invoice_reminders_test.rb` | ① 두 테스트의 `wait_for_turbo` 직후 `page.execute_script("window.confirm = () => true")` 주입(Turbo Confirmers가 부르는 confirm을 true 고정 — 네이티브 다이얼로그 미발생) ② `accept_confirm` 2곳 폐기, button_to 제출 3클릭(지금 1통 보내기·안내 보류하기·안내 재개하기)을 `dom_click_button`으로 전환 ③ 로그인은 `click_button` 유지(전 실측에서 유실 0건 — 세션 최초 클릭은 건전) |

### 커버 손실 명시

confirm 대화상자 문구 자체 검증은 포기한다 — REM-6/7/8의 목적은 안내 흐름이지 다이얼로그 UI가
아니다. 뷰의 `turbo_confirm` 속성 존재는 기존 컨트롤러·뷰 테스트 패턴(예: `invoices_controller_test`
재발급 버튼, `clients_controller_test` 삭제 버튼)이 별도 고정한다.

### 무관 확인

viewer 시스템 테스트 3종의 재확인 방식(`<details>`/`<summary>` 펼침, VIEW-1)은 네이티브
modal과 무관 — 이번 수정 대상 아님. **유의**: `<summary>` 클릭 자체는 Selenium 합성 클릭이라
본 근원의 잠재 영향권이다(지금까지 실패 관측 없음 — 동 증상 재발 시 `dom_click_button` 패턴
적용을 권장한다).

### 검증 결과

```
bin/rails test test/system/app_invoice_reminders_test.rb  10회 연속 → 각 2 runs, 22 assertions, 0 failures
bin/rails db:test:prepare test:system                     → 8 runs, 61 assertions, 0 failures, 0 errors
bin/rubocop (변경 2파일)                                   → no offenses
bin/rails test (전체 회귀)                                 → 628 runs, 3717 assertions, 0 failures (2026-11-04 베이스라인 동일)
```

**한계 명시**: 근원이 환경(chromedriver×Chrome 156)이므로 로컬 녹색이 CI 녹색을 완전 보장하지는
않는다. 다만 본 수정은 유실 경로(Selenium 입력 합성) 자체를 우회하므로 환경 차이에 대한 민감도가
구조적으로 낮아진다. CI에서 2~3회 연속 녹색 확인을 권장한다. chromedriver/Chrome 버전 조합이
바뀌어 합성 클릭이 회복되면 `dom_click_button`은 그대로 두어도 무해(동일 체인)다.
