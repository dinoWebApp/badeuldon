# 07_test_report — 관리자 환불 실행(PLAN-9·ADMIN-11·Q27) 테스트

2026-11-25 · Tester · 기준선: 1,530 runs(가드 테스트 포함) · 최종: **1,582 runs(+52), 0 failures, 0 errors** · app 버그 0건

## 발견한 app 버그

**없음.** C-1(dunning 잔존)·C-2(시도·실패 감사) 회귀는 Phase 6 수정이 이미 반영돼 있음을 테스트로 고정했다.
발견·수정한 것은 기존 **테스트 결함 1건**(Sales::RotateReferralCodesServiceTest 날짜 폭탄 — 아래 D 그룹 절 참조)과
시스템 테스트 플레이크(본 파일 안정화 — F 절 참조)뿐이다.

## 진행 현황

| 그룹 | 파일 | 상태 | 결과 |
|:---|:---|:---|:---|
| A. RefundService | `test/services/orders/refund_service_test.rb` (신설) | 완료 | **29 runs, 207 assertions, 0 failures, 0 errors** |
| B. PaymentPass.revoke_uses! | `test/models/payment_pass_test.rb` (보강) | 완료 | 파일 합계 **13 runs, 37 assertions, 0 failures**(concurrency 회귀 포함) |
| C. Admin::OrdersController | `test/controllers/admin/orders_controller_test.rb` (보강) | 완료 | 3파일 합계 **32 runs, 259 assertions, 0 failures**(AdminsController owner 가드 회귀·base_guard 포함) |
| D. 웹훅 무변경·멱등 | `test/controllers/webhooks/portone_controller_test.rb` (보강) | 완료 | 파일 합계 **13 runs, 61 assertions, 0 failures**(기존 11건 회귀 포함) |
| E. 회원 표기·집계 | legal_documents/tax_invoices/revenue_stats/monthly_settlement (보강) | 완료 | 4파일 합계 **50 runs, 238 assertions, 0 failures** |
| F. 시스템 테스트 | `test/system/admin_order_refund_test.rb` (신설) | 완료 | 단독 10/10 안정 통과·최종 전체 스위트 포함 |

## 최종 전체 스위트(F 뒤 2회차)

| 구분 | 결과 |
|:---|:---|
| `bin/rails test` 전체 | **1,582 runs, 9,958 assertions, 0 failures, 0 errors, 0 skips** |
| 수치 정합 | 이 프로젝트의 `bin/rails test`는 시스템 테스트를 로드하지 않는다(최종 로그에 Capybara 기동 흔적 0건 검증). 기준선 1,530(시스템 13건 제외 수치 — TAX-4 기록과 정합) + 내 비시스템 추가 +52(A 29·B 5·C 10·D 2·E 6) = **1,582 정확히 일치**. 내 추가 총계는 +53(파일별 HEAD 대조 실측 — 위 +52에 시스템 1건) |
| `bin/rails test:system` 전체 | **14 runs, 117 assertions — 내 신규 1건 포함 전원 통과, 기존 1건 플레이크**(AppLegalDocumentPdfTest — 로그인 flash 단정 실패. 단독 재실행 즉시 통과 1 runs·15 assertions·0 failures — 문서화된 로컬 브라우저 플레이크 이력과 동일 계열, 내 변경과 무관) |
| RuboCop(변경 test 파일 10종) | **no offenses** |
| app 코드·PRD·AGENTS.md·progress.json·01/03/05 문서 | 수정 없음 (작업 트리의 app·test_helpers·dunning·client_service 변경은 Developer·Reviewer Phase 6 산출물 — Tester 범위 밖) |

### D 뒤 전체 스위트 1회차 — 기존 테스트 결함 발견·수정

- **발견**: `bin/rails test` 전체에서 3 failures·2 errors — 전부 `Sales::RotateReferralCodesServiceTest`(기존 파일, 이번 변경과 무관). 단독 실행으로도 재현.
- **원인(날짜 폭탄)**: fixture 유효 창이 적재 시점 `Date.current` 상대값(valid_from = 적재일-2)인데 테스트는 고정일 2026-11-23로 travel한다. 적재일(오늘 11-25)과 travel일 간격이 정확히 2일이 되자 fixture `valid_from`(11-23)이 travel `Date.current`와 겹쳐 서비스의 당일 발급분 멱등 가드(SEC-5)가 회전을 막음 → 빈 결과로 5건 실패. 작성일(11-19)에는 간격이 달라 우연히 통과했던 것. fixtures 파일 헤더가 금지한 패턴("travel하는 테스트는 이 fixtures를 경계 판정에 쓰지 않는다")의 위반.
- **수정(테스트 자체 오류 — app 코드 무변경)**: `pinned_current_code` 헬퍼로 fixture 행의 창을 travel 블록 안에서 travel 기준 상대값으로 재설정(`update!` — 가드 우회 아님, 실제 회전이 일어나게 함). 6개 테스트에 적용. 결과 7 runs·47 assertions·0 failures(이전 15 assertions — 조기 실패로 실제 검증이 안 돼 있었음).
- **app 버그 여부**: 아님 — 서비스의 멱등 가드는 설계대로 동작. 테스트가 fixture 상대 창에 의존한 결함.

## A. Orders::RefundService — PLAN-9 (Rule ID별 시나리오)

| 구분 | 시나리오 | 테스트 | 결과 |
|:---|:---|:---|:---|
| 정상 | Plus → 구독 즉시 Free·빌링키·주기 삭제·복사본 정리(같은 키 복사본 nil·다른 키·다른 회원 불변)·metadata["refund"](실행자·금액·사유·기존 키 보존) | Plus 주문 환불은 구독을 즉시 Free로 되돌리고 빌링키 복사본을 정리한다 | PASS |
| 정상 | 수금 패스 → 만료 임박순 10건 차감(6잔여→0·10잔여→6) | 수금 패스 주문 환불은 회원의 유효 패스에서 만료 임박순으로 10건 차감한다 | PASS |
| 정상 | 내용증명 → 주문 기록만 변경·패스/발행물 무변경 | 내용증명 주문 환불은 주문 기록만 변경하고 발행물·패스를 건드리지 않는다 | PASS |
| 정상 | 세금계산서 → 주문 기록만 변경·TaxInvoice 레코드 무변경 | 세금계산서 주문 환불도 주문 기록만 변경한다 | PASS |
| 경계 | 쿠폰가(실차감액) 주문 — 재조회 paid ≥ 주문 금액이면 성공(P6 회귀) | 쿠폰가(실차감액) Plus 주문도 재조회 금액 기준으로 성공한다 | PASS |
| 경계 | 패스 잔여 부족(3건) → 0에서 종료·"미차감 7건"·음수 없음 | 패스 잔여가 모자라면 0에서 종료하고 미차감 수량을 보고한다 | PASS |
| 경계 | 이미 Free(만료) 구독 → 무변경 보고(W-6) | 이미 Free(만료) 구독의 Plus 주문 환불은 무변경 보고를 남긴다 | PASS |
| 경계 | 이미 Free(active) 구독 → 무변경·last_payment_failed_at 비움·키 복사본 정리(W-6·C-1) | 이미 Free(이용 중 상태) 구독도 무변경 보고를 남기고 dunning 잔존 필드는 비운다 | PASS |
| 경계 | **C-1 회귀** — dunning 1단계 구독 환불 → 3필드 비움 → activate! 후 dunning_active? false → 재시도 잡 차감 0건(with_portone_client 감쌈)·새 주문 없음 | C-1 회귀: dunning 진행 구독의 이전 paid 주문 환불은 재시도 상태를 비우고 재등록 후에도 차감이 없다 | PASS |
| 경계 | 콘솔 선취소 — cancel_payment 409 거부 → 재조회 CANCELLED 수렴·정산 1회 | 콘솔 선취소(취소 요청 거부·재조회 CANCELLED)는 재조회로 수렴해 정산 1회로 끝난다 | PASS |
| 경계 | 웹훅 선행 도착(cancelled·refunded_at 없음) → 실행으로 정산 1회 | 웹훅이 먼저 cancelled로 만든 주문도 실행으로 정산 1회가 된다 | PASS |
| 멱등 | 환불 완료 재실행 → 사전 가드 실패·PG 0회·감사 추가 없음 | 이미 환불된 주문의 재실행은 사전 가드로 실패하고 PG 호출·감사가 추가되지 않는다 | PASS |
| 멱등 | 순차 2회 실행 → 2회째 실패·성공 감사 1건 | 같은 주문에 순차 2회 실행은 두 번째가 사전 가드로 실패한다 | PASS |
| 예외 | get_payment ApiError → 실패·시도+실패 감사·로컬 무변경 | 재조회 ApiError는 실패하고 시도·실패 감사를 남긴다 | PASS |
| 예외 | get_payment 비-ApiError(SSL 등) → 실패 Result 흡수(W-1) | 재조회 비-ApiError 예외(SSL·파싱 등)도 실패 Result로 흡수된다 | PASS |
| 예외 | PARTIAL_CANCELLED 명시 실패 | PARTIAL_CANCELLED 재조회는 명시 실패다 | PASS |
| 예외 | amount.paid 누락·0·미만 → 결제 완료 사실 미확인 실패(W-3) | amount.paid 누락·0·주문 금액 미만은 결제 완료 사실 미확인으로 실패다 | PASS |
| 예외 | payment[:id] 불일치 → 실패(W-3 무결성) | 재조회 응답의 결제 ID가 주문과 다르면 실패다 | PASS |
| 예외 | 상태 PAID(미취소) → 전액 취소 미확인 실패 | 상태 PAID(미취소) 재조회는 전액 취소 미확인으로 실패다 | PASS |
| 예외 | cancellations REQUESTED·FAILED만 → 합산하지 않음(W-2) | 취소 합계는 SUCCEEDED 항목만 더한다 — REQUESTED·FAILED만 있으면 실패다 | PASS |
| 경계 | PAID여도 SUCCEEDED 취소 합계 ≥ 주문 금액 → 성공(취소 합계 경로) | 상태가 CANCELLED가 아니어도 SUCCEEDED 취소 합계가 주문 금액 이상이면 전액 취소로 인정한다 | PASS |
| 예외 | 비동기 취소(REQUESTED) → 재실행 안내 문구(W-4b) | 비동기 취소(REQUESTED) 진행 중 안내로 실패하고 재실행 안내를 돌려준다 | PASS |
| 예외 | 흡수된 취소 오류 코드 메시지 보존(W-4a) | 흡수한 취소 요청 오류 코드가 실패 메시지에 보존된다 | PASS |
| 예외 | blank 사유 → 가드·PG 0·감사 0 | blank 사유는 사전 가드로 실패하고 PG 호출·감사가 없다 | PASS |
| 예외 | pending·failed → 가드 | pending·failed 주문은 사전 가드로 실패한다 | PASS |
| 예외 | paid_at 없는 cancelled(가상계좌 말소) → 가드 | paid_at 없는 cancelled 주문은 사전 가드로 실패한다 | PASS |
| 예외 | pg_order_id 없음 → 가드(공백 치환으로 도달 — NOT NULL 방어) | pg_order_id가 없는 주문은 사전 가드로 실패한다 | PASS |
| 예외 | 시도 감사 기록 실패 → PG 호출 없이 중단(C-2) | 시도 감사 기록에 실패하면 PG 호출 없이 중단한다 | PASS |
| 예외 | **C-2 회귀** — PG 성공 뒤 로컬 StatementInvalid → 실패 Result·paid 유지·실패 감사 1건·패스 롤백(W-1) | C-2 회귀: PG 취소·재조회 성공 뒤 로컬 확정 예외는 실패 Result로 흡수되고 실패 감사를 남긴다 | PASS |

테스트 오류 수정 이력(테스트 자체 결함 — 코드 버그 아님): ① 패스 차감 기대값 계산 착오(잔여 10에서 4 차감 → 6이 정답) ② `ActiveRecord::RecordInvalid.new("문자열")` 생성 시 record 인자 `.errors` 호출로 생성 자체 실패 → `StandardError`로 교체 ③ `pg_order_id`는 NOT NULL이라 nil 생성 불가 → 공백 `update_columns`로 가드 도달.

## B. PaymentPass.revoke_uses! — PLAN-9②·Q27

| 구분 | 시나리오 | 테스트 | 결과 |
|:---|:---|:---|:---|
| 정상 | 만료 임박순·여러 패스에 걸친 차감(6→0·10→6)·`[10, 0]` | revoke_uses!는 만료 임박순으로 여러 패스에 걸쳐 차감한다 | PASS |
| 경계 | 잔여 부족(3건) → `[3, 7]`·0에서 종료·음수 없음 | revoke_uses!는 잔여 부족 시 0에서 종료하고 나머지를 무시한다 | PASS |
| 경계 | 만료·소진 패스 제외(유효 4건만 차감 → `[4, 6]`) | revoke_uses!는 만료·소진 패스를 제외하고 유효 패스만 차감한다 | PASS |
| 경계 | 보유 패스 없음 → `[0, 10]` | revoke_uses!는 보유 패스가 없으면 [0, count]를 반환한다 | PASS |
| 예외 | count 0·음수 → ArgumentError | revoke_uses!는 count가 0·음수면 ArgumentError로 거부한다 | PASS |
| 회귀 | 기존 `use!`·동시 사용(with_lock 직렬화) 테스트 전부 통과 | payment_pass_test·payment_pass_concurrency_test 기존 전체 | PASS |

## C. Admin::OrdersController — ADMIN-11·ADMIN-1·ADMIN-2

| 구분 | 시나리오 | 테스트 | 결과 |
|:---|:---|:---|:---|
| 정상 | owner 실행 성공 → 303 + flash 요약(되돌리기 요약 포함) | owner의 환불 실행 성공은 303과 flash 요약을 돌려준다 | PASS |
| 정상 | PG 실패 대역 → 422 + alert(500 아님·로컬 무변경) | PG 실패 대역은 422와 alert으로 응답하고 500이 아니다 | PASS |
| 권한 | staff refund 직접 요청 → 거부(303·alert) + `admin_console_denied` 감사 1건 + PG 호출 0 + 로컬 무변경 | staff의 refund 직접 요청은 거부·감사되고 PG 호출·로컬 변경이 없다 | PASS |
| 권한 | staff 상세 폼 없음 / owner 상세 폼 있음 | staff 상세에는 실행 폼이 없고 owner 상세에는 있다 | PASS |
| 화면 | 환불 완료 실행 건 — 실행자·금액·완료 문구·폼 감춤 | 환불 완료 실행 건 상세는 실행자·금액·완료 문구를 표시하고 폼이 없다 | PASS |
| 화면 | 과거 기록 전용 건(refunded_at만) — "과거 기록 전용 방식" 문구·완료 문구 없음(W-5e) | 과거 기록 전용 건(레거시) 상세는 기록 전용 문구를 표시하고 완료 문구가 없다 | PASS |
| 화면 | 콘솔 선취소 건(cancelled·refunded_at 없음) — 정산 안내 + 폼 | 콘솔 선취소 건 상세는 정산 안내와 실행 폼을 보여준다 | PASS |
| 화면 | pending·failed — 실행 폼 없음 | 결제 완료 적 없는 건(pending·failed)에는 실행 폼이 없다 | PASS |
| 안전망 | 서비스 StandardError → 422 안내(W-1·500 아님) | 실행 중 서비스 예외는 500이 아니라 422 안내로 흡수된다 | PASS |
| 목록 | status=cancelled 필터·환불 필터·"환불됨" 표기 | index 상태 필터 cancelled과 환불 필터가 동작하고 환불됨 표기를 한다 | PASS |
| 회귀 | AdminsController owner 가드(기존 테스트)·base_guard 전부 통과 | admins_controller_test·base_guard_test | PASS |

## D. 웹훅 무변경·멱등 — PLAN-9 정합(03_implementation §4)

| 구분 | 시나리오 | 테스트 | 결과 |
|:---|:---|:---|:---|
| 후행 | 환불 실행 뒤 Transaction.Cancelled 도착 → refunded_at·status·감사 무변경 | 환불 실행 뒤 Transaction.Cancelled 후행 도착은 무변경으로 흡수된다 | PASS |
| 선행 | 웹훅이 status만 cancelled로 만든 주문 → 실행으로 정산 1회 | 웹훅이 먼저 status만 cancelled로 만든 주문은 실행으로 정산 1회가 된다 | PASS |
| 부분 | Transaction.PartialCancelled는 기존처럼 status만 동기화(기존 테스트 유지) | Transaction.PartialCancelled도 cancelled로 동기화한다 | PASS |

## E. 회원 표기·집계 — PLAN-9 파급

| 구분 | 시나리오 | 파일·테스트 | 결과 |
|:---|:---|:---|:---|
| 표기 | 환불 주문은 내용증명 목록에 남고 "환불됨" 배지(P4) | legal_documents — 환불된 주문은 목록에 환불됨 배지로 남는다 | PASS |
| 표기 | 환불 주문 상세 — "이 주문은 환불되었습니다."·정식 다운로드 버튼 없음 | legal_documents — 환불된 주문 상세는 환불 안내를 보여주고 정식 다운로드 버튼이 없다 | PASS |
| 규칙 | 환불 주문 download는 워터마크 미리보기(기존 paid 한정 유지) | legal_documents — 환불된 주문의 download는 정식 PDF가 아닌 워터마크 미리보기를 돌려준다 | PASS |
| 표기 | 세금계산서 환불 상세 — 안내·"다시 발행 요청" 링크 없음(W-5f) | tax_invoices — 환불된 발행 주문 상세는 환불 안내를 보여주고 다시 발행 요청 링크가 없다 | PASS |
| 집계 | 서비스 환불 실행 건 → 매출 제외·MRR 감소(ADMIN-5) | revenue_stats_query — 서비스로 환불 실행한 Plus 주문은 매출에서 제외되고 MRR이 감소한다 | PASS |
| 집계 | 서비스 환불 실행 건 → 수수료 정산 제외(기준 0 → 스냅샷 미생성 — 서비스 SKIP 가드 계약) | monthly_settlement — 환불 실행된 주문은 수수료 기준 금액에서 제외된다 | PASS |

## F. 시스템 테스트 — ADMIN-11 브라우저 E2E

| 구분 | 내용 |
|:---|:---|
| 시나리오 | 관리자 2FA 실로그인 → 주문 상세 실행 폼 → 실행 효과 고지·`data-turbo-confirm` 문구 단정 → 사유 입력 → 확인창 승인(window.confirm stub) → 제출 → 성공 flash·환불 완료 섹션·실행자 표기 → DB 확정(refunded·cancelled·패스 10건 차감·감사 1건) → 목록 "환불됨" 표기 |
| 포트원 방어 | `with_portone_client`(클래스 생성자 교체 — 프로세스 전역이라 Puma 서버 스레드에도 전달·reminders 시스템 테스트와 동일 방식). Turbo 비동기 제출이 완료될 때까지 블록 유지 — 조기 해제 시 실호출 위험 차단. TEST_GUARD 가드는 2차 방어선으로 유지 |
| 안정성 | 초기 버전 10회 중 2회 통과 — chromedriver 클릭 드롭(ApplicationSystemTestCase §7 실측 변주)+ 클릭 드롭 시 `fill_in` 값이 소실된 채 빈 사유로 제출되는 변주까지 관찰("환불 사유는 필수입니다" alert로 검출). 안정화: ① turbo:submit-start·주문 상태 폴링 ② 미시작 시 검증된 네이티브 제출로 폴백 — 사유 재주입+제출을 같은 스크립트에서 원자 실행(확인창 문구 존재는 `data-turbo-confirm` 속성 단정으로 별도 검증) ③ 이중 제출은 서비스 with_lock·재검사(PLAN-9 ⑤)가 흡수함을 확인 |
| 최종 결과 | **10/10 통과**(연속) — 1 runs, 14 assertions, 0 failures |

## 발견한 app 버그

없음 (A 그룹 기준 — C-1·C-2 회귀 수정은 Phase 6에서 이미 반영됨을 확인)

## 포트원 실호출 방어

- 서비스 테스트는 전부 `client:` 생성자 주입(FakePortOneClient) — 실제 `PortOne::ClientService` 인스턴스 미생성
- 컨트롤러·웹훅·시스템 테스트(서버 스레드가 기본 클라이언트를 만드는 경로)는 `with_portone_client`로 감쌈 — 시스템 테스트는 flash·상태 확정까지 블록 유지(Turbo 비동기 제출 대응)
- C-1 재시도 잡(`DunningRetryJob.perform_now`)은 `with_portone_client`로 감쌈 — `fake.calls` 빈 배열 보증
- TEST_GUARD 가드는 그대로 유지(우회·비활성화 없음) — 솔라피·바로빌은 기존 대역만 사용
- 자격 증명 값·토큰은 출력하지 않음

## 커버하지 못한 영역과 이유

| 영역 | 이유 |
|:---|:---|
| 실제 포트원 응답 필드 실측(전액 취소 뒤 `amount.paid` 유지 여부·카드 취소 동기 SUCCEEDED 여부) | 외부 실호출 금지 — 운영 첫 실환불 1건으로 확인 필요(03 문서 §7-4와 동일 후속). 테스트는 공식 OpenAPI v2 확정 필드(`amount.paid·cancelled`·`cancellations[].totalAmount`·status enum) 기준 대역으로 고정 |
| W-4c — 이미 부분 취소된 결제에 대한 전액 취소 요청의 PG 실동작(잔액 전액 취소 vs 거부) | PG 실호출 불가 — 재조회 `PARTIAL_CANCELLED` 명시 실패 경로만 테스트로 고정 |
| 브라우저에서 확인 대화창의 실제 렌더(네이티브 다이얼로그) | 선례(app_invoice_reminders_test)와 같이 `window.confirm` stub 방식 — 네이티브 대화상자 문구는 `data-turbo-confirm` 속성 단정으로 갈음(문구 존재·금액 포함은 검증). 다이얼로그 UI 자체는 headless Chrome 자동화의 알려진 한계 |
| 실제 병렬 이중 제출(스레드 경합) | 트랜잭션 fixture 스레드 격리 제한 — 순차 2회 실행 멱등 테스트(A)와 리뷰어의 with_lock 직렬화 실험(05_review §4-1)로 갈음 |
| 가상계좌 등 환불계좌 필요 결제수단 | 운영 미지원 결제수단(03 문서 §6-3) — `paid_at` 없는 cancelled 가드로 실패 수렴만 테스트 |
| ADMIN 감사 로그 화면의 `order_refund_attempt`·`order_refund_failed` action 라벨 표기 | 감사 화면에 action 사전이 없어(기존 `order_refund`도 미등록) 03 문서 §7-1 판정대로 그대로 둠 — 화면 표기 검증 범위 밖 |

## 변경 파일 목록 (Tester)

| 파일 | 구분 | 내용 |
|:---|:---|:---|
| `test/services/orders/refund_service_test.rb` | 신설 | PLAN-9 서비스 29 시나리오(정상 4종·경계 8·예외 15·멱등 2 — A 절 표) |
| `test/system/admin_order_refund_test.rb` | 신설 | ADMIN-11 브라우저 E2E 1건(F 절 — 10/10 안정) |
| `test/models/payment_pass_test.rb` | 보강 | `revoke_uses!` 5건(B 절) |
| `test/controllers/admin/orders_controller_test.rb` | 보강 | 실행 응답·staff 차단·화면 분기 5종·안전망·index 필터 9건(C 절) |
| `test/controllers/webhooks/portone_controller_test.rb` | 보강 | 후행 무변경·선행 정산 2건(D 절) |
| `test/controllers/app/legal_documents_controller_test.rb` | 보강 | 환불 표기·다운로드 규칙 3건(E 절) |
| `test/controllers/app/tax_invoices_controller_test.rb` | 보강 | 환불 안내·W-5f 링크 제거 1건(E 절) |
| `test/queries/admins/revenue_stats_query_test.rb` | 보강 | 서비스 환불 실행 → 매출·MRR 제외 1건(E 절) |
| `test/services/sales/monthly_settlement_service_test.rb` | 보강 | 서비스 환불 실행 → 수수료 정산 제외 1건(E 절) |
| `test/services/sales/rotate_referral_codes_service_test.rb` | 수정 | 기존 날짜 폭탄 수정(fixture 창을 travel 기준으로 재설정 — D 절) |
| `_workspace/07_test_report.md` | 신설 | 본 보고서(그룹별 누적) |
