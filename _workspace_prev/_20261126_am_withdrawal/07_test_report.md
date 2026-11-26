# 07_test_report — T2·T3 분 (2026-11-26, Tester)

병렬 배치(T0 회원 탈퇴·T1 후속은 다른 Tester) 중 **T2 수신 거부 번호 단위(VIEW-7·Q30)**·
**T3 대시보드 오늘의 액션 세 종(DASH-2·Q31)**의 테스트 보강 보고. 앱 코드·픽스처·locale·routes·
db는 수정하지 않았다(테스트 파일만 추가·수정). 외부 API 실호출 0건 — 발송 경로 스캔 테스트는
`with_solapi_client(FakeSolapiClient.new)` 방어선으로 감쌌다(REM-10).

## 1. 실행 명령과 결과

전용 DB: `mkdir -p tmp/parallel/TSTA` 후 `DATABASE_URL=sqlite3:tmp/parallel/TSTA/test.sqlite3`

| 단계 | 명령(요지) | 결과 |
|:--|:--|:--|
| T2 baseline(보강 전) | 지시 T2 명령 9파일 | **211 runs, 1346 assertions, 0 failures** |
| T2 보강 후 | 같은 명령 | **225 runs, 1457 assertions, 0 failures, 0 errors, 0 skips** (+14) |
| T3 baseline(보강 전, 시스템 포함) | 지시 T3 명령 7파일 | **188 runs, 1016 assertions, 0 failures** |
| T3 보강 후 | 같은 명령 | **197 runs, 1063 assertions, 0 failures, 0 errors, 0 skips** (+9) |
| T2+T3 합동 | 14파일 합쳐 실행 | **301 runs, 1787 assertions, 0 failures** |
| 시스템 플레이크 점검 | `app_dashboard_actions_test`·`viewer_refusal_test` 3회 연속 | **3회 모두 3 runs, 22 assertions, 0 failures** |
| RuboCop | 수정 테스트 파일 10개 | **10 files inspected, no offenses** |

전체 스위트(`bin/rails test`)·`test:system` 전체 실행은 지시대로 하지 않았다.

## 2. 신규 테스트 목록 (총 21건 — T2 14·T3 7, 두 명령 세트에 공통 포함 2건)

### T2 — 수신 거부 번호 단위(리뷰 Tester 중점 제안 1~5 + W-5 미단언 4건)

| 파일:테스트명 | 커버 |
|:--|:--|
| `test/models/client_test.rb`:하이픈 조합(없음→있음·있음→있음·없음→없음)도 모두 상속한다 | VIEW-7·Q30 — 제안 3(나머지 3종, 있음→없음은 기존 테스트) |
| `test/models/client_test.rb`:검증 실패로 저장되지 않으면 상속하지 않는다 | VIEW-7·Q30 — W-5③(통과 저장에서만 콜백·refused_at 불변) |
| `test/models/client_test.rb`:거부된 행이 번호를 바꿔 이동하면 새 번호 등록분도 상속한다 | VIEW-7·Q30 — W-2 알려진 한계의 현재 동작 고정(회귀 지점) |
| `test/services/promises/register_service_test.rb`:같은 회원·같은 번호의 여러 건을 전부 마킹한다 | VIEW-7·Q30 — 제안 2(3건·하이픈 섞임) |
| `test/services/promises/register_service_test.rb`:이미 거부된 형제의 접수 시각을 덮지 않는다 | VIEW-7·Q30 — W-5①(선접수 시각 유지) |
| `test/services/promises/register_service_test.rb`:refusal 재접수는 멱등이다 | VIEW-7·Q30 — 제안 2(접수 시각·종결 마킹 불변) |
| `test/services/promises/register_service_test.rb`:전파 뒤 트랜잭션이 실패하면 접수·전파 마킹이 함께 롤백된다 | VIEW-7·Q30 — 제안 2(`finish_sequence!` 강제 실패 → promise·접수·전파 전부 원점) |
| `test/controllers/app/invoices_controller_test.rb`:상속 거래처의 초안 상세는 체크박스 대신 안내를 렌더하고 발행은 인큐 없이 직접 전달 안내로 끝난다 | VIEW-7·Q30·SHARE-6 — 제안 1(상속 경로의 등록→초안→상세→`send_notice=1` 발행 E2E. DeliverJob 0건·발행 성공) |
| `test/controllers/app/invoices_controller_test.rb`:다른 회원이 같은 번호로 등록·발행하면 상속 없이 정상 발행된다 | VIEW-7·Q30 — 제안 5(delta가 gamma 거부 번호로 등록·발행 → 상속 없음·issue_notice 인큐) |
| `test/controllers/app/clients_controller_test.rb`:상속 거래처의 목록·상세에는 수신 거부 배지가 보이고 상세에는 재개 버튼이 없다 | VIEW-7·Q30 — 제안 4(orange 배지·거부 안내 문구·재개·보류 버튼 미노출) |
| `test/controllers/app/invoices_reminders_test.rb`:상속 거래처의 청구 화면에는 발송·재개 버튼이 없고 재개·재시작 요청은 사유 안내로 거부된다 | VIEW-7·Q30 — 제안 4(「지금 1통 보내기」·「안내 재개하기」·「안내 다시 보내기」 미노출 + resume/restart 사유 alert·마킹 무변경) |
| `test/controllers/app/clients_reminders_test.rb`:상속 거래처의 거래처 단위 재개 요청은 상태 변경 없이 사유 안내로 거부된다 | VIEW-7·Q30·REM-7 — 제안 4(거래처 resume ·보류·거부 마킹 유지) |
| `test/services/recurring_invoices/issue_service_test.rb`:상속 거래처 스케줄 발행도 issue_notice 없이 U1 통보만 인큐한다 | VIEW-7·Q30·INV-7 — 제안 1(상속 경로·`noti_recurring_issued`만) |
| `test/services/reminders/send_service_test.rb`:상속 거래처의 채무자 발송도 REFUSED로 차단한다 | VIEW-7·Q30 — 제안 1의 최종 방어선(인큐가 막혀도 가드는 유지 — skipped REFUSED·실발송 0건) |

### T3 — 대시보드 오늘의 액션(2차 리뷰 Tester 중점 제안 1~5 + 적대적 6~8)

| 파일:테스트명 | 커버 |
|:--|:--|
| `test/system/app_dashboard_actions_test.rb` — **실행 확인**(제안 1, 미실행 상태였던 것) | DASH-2·Q31·REM-11 — 보류 E2E 통과(아래 플레이크 점검 참조) |
| `test/services/dashboards/reminder_actions_service_test.rb`:14:00:00 정각 경계 — 13:59:59에는 행이 있고 14:00:00에는 없다 | DASH-2·C-1 — 제안 2 |
| `…`:실제 14시 스캔이 만든 재예약 슬롯을 14시 30분 카드가 ① 경로로 보인다 — 시작 15시 회원은 오늘 15시 | DASH-2·REM-3·C-2 — 제안 4(`DispatchService#call` 실스캔(with_solapi_client) → `reschedule!` 슬롯 15:00 전제 확인 → 14:30 카드 ① 슬롯 시각) |
| `…`:실제 14시 스캔 뒤 종료 14시 회원의 슬롯은 다음 허용 요일이라 14시 30분 카드가 없다 | DASH-2·REM-3·C-2 — 제안 4(수요일 09시 슬롯 → 오늘 카드 없음) |
| `…`:같은 template_key의 U1 향 pending이 있어도 ①에 잡히지 않고 채무자 카드 시각은 ②를 따른다 | DASH-2 — 제안 5(U1 pending 16시 슬롯이 새어 나가지 않음) |
| `…`:마감·보류·거부·종결·상한이 섞인 회원에서 오늘 발송 예정은 자격 있는 행만 정확히 담는다 | DASH-2·PLAN-3·VIEW-7·REM-7·REM-12 — 제안 7(사유별 제외를 한 시나리오에서 id 배열 단언 — 거부만 전용 거래처 분리) |
| `…`:같은 청구가 미열람 방치와 오늘 발송 예정에 함께 놓일 수 있다 — 모순 없음 | DASH-2 — 제안 8(양쪽 종류에 동시 포함 고정) |
| `test/controllers/app/dashboards_actions_test.rb`:카드의 보류하기로 보류한 청구는 다음 대시보드 조회의 오늘 발송 예정에서 빠진다 | DASH-2·REM-11·REM-7 — 제안 6(PATCH suspend → 카드 소멸) |

제안 3(`scheduled_at` nil pending)은 마무리 수정분의 테스트가 이미 존재·통과를 확인했다 —
`reminder_actions_service_test.rb` "scheduled_at 없는 pending(발송 실행 점유)도 ②로 판정…(W-2)"(13시/15시)·
`dashboards_controller_test.rb` "발송 실행 점유 중… 200으로 렌더한다(DASH-2·W-2)".

## 3. 앱 결함 후보

**없음.** 실행 중 발생한 실패 2건은 모두 테스트 오류라 수정 후 재실행했다(코드 버그 아님 — 분류 기록):
1. 신규 컨트롤러 테스트에서 `draft_params`에 `due_on: nil`을 넘겨 초안 검증 422 → 이후 `Invoice.order(:id).last`가 delta fixture를 잘못 집어 404. `due_on` 명시 + POST 303 단언 추가로 해소(테스트 결함).
2. 신규 서비스 테스트에서 `UnviewedIdleQuery::Row`는 `invoice`·`idle_days`만 갖는 Struct인데 `map(&:id)`로 접근. `row.invoice.id`로 해소(테스트 결함).

## 4. 확인된 현재 동작(결함 아님 — 테스트로 고정)

- **W-2 알려진 한계**: 거부된 거래처의 번호를 Y로 바꾸면 그 행은 거부 상태로 남고, 같은 회원이 Y 번호로 거래처를 등록하면 상속받는다(거부한 적 없는 번호의 보수적 차단). PRD VIEW-7 「알려진 한계」 문언과 일치 — client_test에 "현재 동작 고정(회귀 지점)" 명시로 기록.
- **검증 실패 저장은 상속 없음**: `before_save`는 검증 통과 저장에서만 실행 — 같은 인스턴스가 나중에 통과해 저장되면 그때 상속한다(W-3 판정의 동작 범위 확인).
- **① 슬롯이 지나간 뒤의 ② 폴백**: 종료 14시 회원의 오늘 09시 슬롯이 15시에 경과하면 ②로 내려가 다음 허용 요일 발송이 되어 카드가 사라진다(기존 테스트 유지·통과).
- **재예약분 실행 정합·상한 산정 등 기존 발송 경로 테스트 전부 무수정 통과** — T3의 `scheduled_today_keys`·`steps_due_today` 불변과 T2의 가드 순서(REFUSED 최종 방어선 유지) 회귀 없음.

## 5. 플레이크 관찰

- `test/system/app_dashboard_actions_test.rb`(문구·`assert_no_selector` 좁힘 반영분) — 3회 연속 통과(매 회 3 runs·22 assertions·0 failures). `log_in_as`·confirm stub·DOM 클릭 관례 준수 상태로 재현 불안정 요소 관찰되지 않음.
- `test/system/viewer_refusal_test.rb`(비가입 거부 E2E — T2 회귀 확인용) — 같은 3회 실행에 포함, 전부 통과.
- 병렬 실행(8프로세스)에서 전체 8회 실행(T2 3회·T3 3회·합동 1회·3회 플레이크 1세트) 모두 0 failures — 순서·시간 의존 실패 없음. 신규 시간 의존 테스트는 전부 `travel_to`로 2026-11-10(화)~11(수) KST 고정(TIME-1).

---

## T1 분 (2026-11-26, Tester — 회원 자진 탈퇴 AUTH-1.5·Q29 테스트 보강)

위 "T2·T3 분" 절과 같은 병렬 배치의 T1(회원 탈퇴·X-1 수정분) 몫. 앱 코드·픽스처·locale·routes·db는
수정하지 않았다(테스트 파일만). 외부 API 실호출 0건 — 환불 경로는 `with_portone_client`, 예약 잡
수행은 `with_solapi_client(FakeSolapiClient)` 방어선으로 감쌌다(PLAN-5·REM-10).

### 1. 실행 명령과 결과

전용 DB: `mkdir -p tmp/parallel/TSTB` 후 `DATABASE_URL=sqlite3:tmp/parallel/TSTB/test.sqlite3`

| 단계 | 명령(요지) | 결과 |
|:--|:--|:--|
| A — 미실행 시스템 2건 | `app_profile_withdrawal_test` | 3회 연속 **2 runs, 0 failures** |
| A — 미실행 시스템 2건 | `admin_order_refund_test`(X-1 수정분 — 잔여 합계 0 단언) | 3회 연속 **1 run, 0 failures** |
| 보강 후 지정 배치 | services/users + profiles + profiles_remind_settings + pages_policy + billings + admin 전체 | **205 runs, 1,716 assertions, 0 failures, 0 errors, 0 skips** |
| 뷰어 회귀(신규 파일) | `viewer_withdrawal_regression_test` | **2 runs, 20 assertions, 0 failures** |
| 시스템(수정분) | `app_profile_withdrawal_test` 재실행 | 3회 연속 2 runs 0 failures(N-1 단언 포함) |
| RuboCop | 수정·신규 테스트 파일 9개 | **9 files inspected, no offenses** |

전체 스위트(`bin/rails test`)·`test:system` 전체 실행은 지시대로 하지 않았다(다른 Tester와 Chrome 공유).

### 2. 신규·보강 테스트 목록

**서비스 — `test/services/users/withdrawal_service_test.rb`(+7, 파일 총 15)**

| 테스트명 | 커버 |
|:--|:--|
| 풍부한 데이터의 회원이 탈퇴하면 연쇄 대상·부속 기록·첨부 파일까지 전부 0건이 된다 | AUTH-1.5·C-2 — 입금 2건(부분입금)·약속 2건(date_selected+inquiry·U1 답변 포함)·열람 2건·발송 이력(sent)·예약 슬롯(pending·scheduled_at 미래·전화번호 포함)·반복 청구(+last_invoice restrict 경로)·품목·유료 구독·paid 주문·패스·공지 읽음·티켓+메시지+AS 첨부 1장·세금계산서·세션 — 생성 단계부터 단언(공허 방지) 후 전부 0 |
| user_id 컬럼을 가진 모든 테이블에서 탈퇴 회원의 행이 남지 않는다 — 감사 로그만 보존 | B-6 전수 조사 — 스키마에서 user_id 보유 테이블을 런타임 수집해 allowlist(audit_logs) 외 전부 0 단언 |
| 탈퇴 뒤에 실행되는 예약 발송 잡은 흡수되고 발송이 0건이다 | AUTH-1.5 파생 — `DeliverJob.perform_later` 큐잉 → 탈퇴 → `perform_enqueued_jobs`(with_solapi_client) — discard_on RecordNotFound 흡수·솔라피 호출 0건 |
| 연쇄 삭제 중 참조 제약(InvalidForeignKey)이 나면 안내로 흡수되고 감사·계정이 원복된다 | 적대 — destroy! FK 위반 스텁 → 500 아닌 안내·감사 로그·거래처 전부 원복 |
| 정지(suspended) 상태의 회원도 탈퇴할 수 있다 | 현재 동작 고정(아래 5 참조) |
| 탈퇴 직후 같은 이메일·휴대폰으로 재가입하면 유니크 제약이 해제돼 가입할 수 있다 | Q29·AUTH-1.5 — 재가입 성공+Free 구독 행 생성 |
| phone_verifications는 user_id가 없어 탈퇴 대상이 아니다 | 현재 동작(보고용 — 아래 5 참조) |

**컨트롤러 — `test/controllers/app/profiles_controller_test.rb`(+7)**

| 테스트명 | 커버 |
|:--|:--|
| confirm_email을 배열로 변조한 요청은 303 불일치로 끝나고 계정·데이터가 유지된다 | 2차 제안 — `confirm_email[]=` → 303 앵커 복귀·상단 alert·감사 0건 |
| confirm_email을 해시로 변조한 요청도 303 불일치로 끝난다 | 2차 제안 |
| confirm_email 키가 아예 없는 요청은 400으로 거부된다 | 2차 제안 — params.expect 계약 유지 |
| 다른 회원의 이메일을 입력하면 거부되고 누구의 계정도 삭제되지 않는다 | 1차 제안 — 본인·타인 모두 유지 |
| 부분입금이 있는 미수 청구의 잔액 고지는 입금액을 차감해 표시된다 | 1차 제안 — Σ총액−Σ입금(DASH-1 식)이 "#withdrawal p" 고지에 반영 |
| 탈퇴 성공 뒤 같은 요청을 다시 보내면 로그인 화면으로 되돌려지고 감사가 중복 기록되지 않는다 | 적대(멱등) — 404·오류 아닌 인증 가드 수렴·감사 1건 유지 |
| 탈퇴 요청은 CSRF 토큰 없이는 거부된다 | 적대 — allow_forgery_protection=true → 422·계정 유지(sessions_controller_test 선례 방식) |

**뷰어 — `test/controllers/viewer_withdrawal_regression_test.rb`(신설, 2)**

| 테스트명 | 커버 |
|:--|:--|
| 탈퇴 뒤 발행 청구 링크는 만료·폐기 공용 안내와 404로 응답하고 열람 기록을 남기지 않는다 | 1차 제안 — 200(탈퇴 전) → 탈퇴 → 404+VIEW-6 본문·ViewEvent 0건·500 없음 |
| 초안·무효 청구는 링크가 성립하지 않고 탈퇴 뒤에도 404·동일 본문으로 수렴한다 | VIEW-6 — 초안 토큰 nil·void! 후 토큰 즉시 폐기(INV-6 실측)·삭제된 청구의 옛 토큰과 미존재 토큰의 본문 완전 동일 |

**관리자 — `test/controllers/admin/orders_controller_test.rb`(+1)**

| 테스트명 | 커버 |
|:--|:--|
| 픽스처 패스 만료일(2026-12-31) 이후에도 환불 차감이 동작한다 | X-1 회귀 — 같은 단언("수금 패스 10건 차감"+잔여 0)을 `travel_to("2026-12-31 10:00")` 안에서 실행(with_portone_client 필수). admin_login의 내부 travel과의 중첩은 `at:` 옵션으로 피함 |

**시스템 — `test/system/app_profile_withdrawal_test.rb`(보강)**

- 불일치 테스트에 N-1 가시성 단언 추가: `assert_selector "section#withdrawal [role='alert']"`(가시성 기본 검사) + 상단 `p#alert` 병존 확인.

**기존 테스트로 확인(추가 불요)** — 해지 예약(cancelled) 고지 분기·유료/체험 Plus 고지(profiles 테스트)·약관 제11조 ①②·부칙·"정식 오픈 전 … 같은 날 시행" 문장(pages_policy_test — N-5 포함)·감사 로그 60자 초과 detail의 `td[title]` 전문(audit_logs_controller_test — N-4)·X-1 수정분 2건(admin orders 컨트롤러 19 runs·시스템 3회) 모두 기존 정의로 통과 확인.

### 3. B-6 전수 조사 결과 (탈퇴 뒤 잔존 행 — db/schema.rb 전수 대조 + 런타임 테스트)

| 테이블 | 회원 식별 컬럼 | 탈퇴 뒤 | 방식·비고 |
|:--|:--|:--|:--|
| clients·invoices·items·recurring_invoices·subscriptions·orders·payment_passes·notice_reads·tickets·sessions·tax_invoices·message_logs | user_id | **0행** | `dependent: :destroy` + DB FK(message_logs·notice_reads·orders·payment_passes·subscriptions·tickets는 on_delete: :cascade) — 테스트 전수 검증 |
| invoice_items·payments·promises·view_events | invoice_id(user_id 없음) | **0행** | invoices 연쇄 |
| ticket_messages | ticket_id | **0행** | tickets 연쇄 |
| recurring_invoice_items | recurring_invoice_id | **0행** | recurring_invoices 연쇄 |
| active_storage_attachments / blobs | record polymorphic | **0행** | 티켓 첨부 — attachments 즉시 삭제, blob은 purge_later(PurgeJob 수행 시점 정리 — 테스트로 확인) |
| audit_logs | admin_id·target_type/id | **보존(allowlist)** | ADMIN-2·Q13 선례 — 보존이 목적. detail에 이메일 스냅샷(개인정보이나 의도된 기록) |
| phone_verifications | **없음(phone)** | **잔존 가능** | FK 연결이 없어 탈퇴 연쇄가 닿지 않는다. 5분 만료·1회용 소비로 수명 통제됨. **개인정보(전화번호)가 남는 테이블 — 결함 분류는 오케스트레이터 판단용으로 사실만 기록** |
| sales_commissions·sales_reps·coupons | 없음(rep·쿠폰 기준) | 잔존(회원 미식별) | 개인정보 없음. 단, PRD 알려진 한계 ①(SALES 월 정산 기준 소실)과 동일 사실 |
| users | 자체 | 삭제 | 이메일·전화번호·계좌 등 본체 행 소멸 — 재가입 가능(테스트로 검증) |

### 4. 앱 결함 후보

**없음.** 실행 중 발생한 실패·오류 5건은 모두 테스트 오류라 수정 후 재실행해 통과(코드 버그 0 — 분류 기록):
1. 풍부한 데이터 테스트의 Item 수 단언 — alpha fixture 품목 행을 미포함 → 기준치 캡처 방식으로 수정.
2. InvalidForeignKey 테스트의 Client 수 단언 — alpha fixture 거래처 5행 → 같은 방식.
3. viewer 테스트에서 `void!` 뒤 토큰 접근 — void!는 토큰을 즉시 폐기(INV-6)해 nil → 테스트를 실제 동작에 맞게 재구성(아래 5 참조).
4. X-1 회귀 테스트의 `travel_to` 중첩 — admin_login 내부 travel과 충돌 → `at:` 옵션으로 로그인 시각을 만료일 당일로 고정.
5. viewer 테스트의 탈퇴 뒤 `invoice.reload` — 연쇄 삭제로 RecordNotFound → 토큰을 탈퇴 전에 캡처.

### 5. 확인된 현재 동작(결함 아님 — 테스트로 고정·보고)

- **phone_verifications 잔존**: 위 표. user_id 연결이 없어 탈퇴로 지워지지 않는다(단기 수명 통제).
- **정지(suspended) 회원의 탈퇴 허용**: 서비스에 상태 가드가 없다. 정지는 로그인 차단용 가역 상태(user.rb status 주석)이고 PRD AUTH-1.5·Q29에 차단 근거가 없어 의도된 판단으로 보임 — 정책 재검토 여지는 오케스트레이터 몫.
- **초안·무효 청구는 링크 자체가 없다**: 초안은 토큰 미발급, void!는 즉시 토큰 폐기(INV-6) — "탈퇴 뒤 404"와 별도로 이미 링크가 성립하지 않는다. 탈퇴 뒤 삭제된 청구의 옛 토큰은 미존재 토큰과 본문까지 완전히 같은 404(VIEW-6).
- **Active Storage 정리 시점**: 첨부 행은 즉시, blob 파일·행은 purge_later(잡 수행 시점) — 테스트는 perform_enqueued_jobs로 수행해 0건까지 확인.
- **재가입 혜택 리셋**(체험·첫결제 쿠폰 재제공)은 PRD AUTH-1.5 "알려진 한계 ②" 기록 사항 — 테스트는 재가입 가능성(유니크 해제)만 검증.

### 6. 플레이크 관찰

- 시스템 2파일 각 3회 연속 통과. 실행마다 단언 수가 14↔15·17↔20으로 흔들린 것은 Capybara `assert_selector`/`assert_text`의 대기 재시도 내부 계수 차이로, 실패·경고 없음.
- 서비스·컨트롤러 배치 3회 실행(보강 중간 포함) 모두 최종 0 failures — 순서·시간 의존 실패 없음.
- 날짜 폭탄 방지: X-1 회귀는 `travel_to(2026-12-31)`, 나머지 신규 데이터는 `90.days.from_now` 상대 만료일(6차 C-1 방식) — 고정 픽스처 만료일(`delta_active_pass`) 의존 0건.
