# 03_implementation — 관리자 환불 실행: 포트원 결제 취소 연동·구독 즉시 Free·수금 패스 차감 (2026-11-24)

`_workspace/01_plan.md`(승인 완료) 설계를 그대로 구현했다. 마이그레이션 없음(환불 실행 정보는 기존
`refunded_at`·`refund_reason`·`status`·`metadata`로 보관). 웹훅(`Webhooks::PortOneController`)·PRD·AGENTS.md는
변경하지 않았다.

## 1. 변경 파일 목록

### 신설
| 파일 | 요약 |
|:---|:---|
| `app/services/orders/refund_service.rb` | PLAN-9 환불 실행 전체 — 사전 가드 → PG 취소(트랜잭션 밖) → PG 재조회 확정(fail-closed) → 로컬 확정 트랜잭션(with_lock + 가드 재검사) → 상품별 되돌리기 → 감사 로그. `client:` 주입으로 테스트 대역 분리. Result는 `Admins::MemberAdminService::Result`와 같은 구조를 Orders 네임스페이스 안에 자체 선언(§4.3 — 타 도메인 내부 클래스 참조 회피) |
| `app/helpers/admin/orders_helper.rb` | `order_item_label`(item_type 한국어 라벨 — 내용증명·세금계산서 주문은 product가 collection_pass라 item_type으로만 구분), `refund_effect_summary`·`refund_confirm_message`(ADMIN-11 확인 대화창 실행 효과 문구) |

### 수정
| 파일 | 요약 |
|:---|:---|
| `app/models/payment_pass.rb` | `PaymentPass.revoke_uses!(user:, count:)` 신설(31~54행) — 회원 단위 차감(만료 임박순), 0에서 종료·나머지 무시, 건별 `with_lock` + 잠금 후 `usable?` 재판정(`use!`와 같은 이중 방어). 반환 `[차감 건수, 무시 수량]` |
| `app/controllers/admin/base_controller.rb` | `require_owner`를 AdminsController의 private에서 **protected**로 이동(43~56행) — 동작 그대로(거부 시 `Admins::RoleService.record_denied!` 감사 + 303 안내) |
| `app/controllers/admin/admins_controller.rb` | 이동된 `require_owner` 정의 제거·안내 주석만 남김. `before_action :require_owner, except: %i[index]` 유지(기존 테스트 전부 통과 — 회귀 없음) |
| `app/controllers/admin/orders_controller.rb` | `mark_refunded`(기록 전용) → `refund`(실행) 교체(23행). `before_action :require_owner, only: :refund`(7행). 성공 303 + flash 요약 / 실패 422 재렌더(500 금지 — W-1 유지). `set_order`가 `@can_refund`(owner 플래그)·`@refund_info`(metadata["refund"])를 공급(36~41행 — 뷰에서 모델 클래스 메서드 호출 회피). 목록 필터 화이트리스트에 `cancelled` 추가(49행) |
| `config/routes.rb` | admin orders member `patch :mark_refunded` → `patch :refund`(157행). 헬퍼 `refund_admin_order_path` |
| `app/views/admin/orders/show.html.erb` | "환불 사유 기록" 폼 → "결제 취소(환불) 실행" 폼으로 교체. 상품 행을 item_type 라벨로 표기(내용증명·세금계산서 주문의 "collection_pass" 오인 방지). 환불 완료 건: 일시·사유·실행자·금액 표시 + 폼 감춤. staff: 실행 불가 안내(폼 없음). pending·failed·`paid_at` 없는 건: 버튼 없이 안내. `cancelled`+`refunded_at` 없음(콘솔 선취소): "포트원에서 이미 취소됨 — 정산을 완료하세요" 주황 안내 + 같은 폼. 파괴 버튼은 기존 선례 bg-orange-600 유지, `turbo_confirm` 확인창(관리자 화면 선례 방식) |
| `app/views/admin/orders/index.html.erb` | "기록됨" → "환불됨", 필터 라벨 "환불 기록 있음/없음" → "환불됨/환불 안 됨", 상태 필터에 "취소·환불"(cancelled) 옵션 추가, 하단 안내 문구를 실행 절차(ADMIN-11·PLAN-9)로 갱신 |
| `app/views/app/legal_documents/index.html.erb` | 상태 뱃지를 `order_payment_badge` 헬퍼로 교체 — `refunded?` 우선 "환불됨" 표기 |
| `app/views/app/legal_documents/show.html.erb` | `refunded?` 분기 신설 — "이 주문은 환불되었습니다." + 재주문 안내. 다운로드는 기존 paid 한정 규칙 그대로(환불 건은 불가 — 의도된 동작) |
| `app/views/app/tax_invoices/show.html.erb` | `refunded?` 분기 신설 — "이 발행 주문은 환불되었습니다." + 재발행 안내 |
| `app/helpers/application_helper.rb` | `order_payment_badge` 헬퍼 신설 — [라벨, 상태색 클래스] 반환(환불됨=주황·완료=녹색·대기=중립·실패·취소=빨강). 3개 뷰 공용 |
| `test/controllers/admin/orders_controller_test.rb` | `mark_refunded` 경로 3건을 `refund` 실행 경로로 최소 수정(원 의미 유지 — ① B-1 폼 페이로드 E2E: 303·refunded?·감사 1건 + status cancelled 확장 어설션 ② 이중 실행 422·감사 미기록 ③ blank 사유 422). PG 실호출 방지를 `with_portone_client(FakePortOneClient)`로 차단 — `raise_on`으로 가드 통과 없이는 PG 호출이 없음을 보증. 신규 시나리오 테스트는 Tester 범위라 추가하지 않음 |

## 2. Rule ID별 구현 매핑

### PLAN-9 확정 절차 (`app/services/orders/refund_service.rb`)
| 절차 | 구현 | 위치 |
|:---|:---|:---|
| ① 사전 가드(로컬·PG 무호출) | 사유 blank / 이미 환불 / paid·cancelled 외 상태 / `paid_at` nil / `pg_order_id` 없음 — 각각 실패 Result | `refund_service.rb:47~55(precheck_error)` |
| ② PG 취소(전액·즉시·트랜잭션 밖) | `client.cancel_payment(payment_id: pg_order_id, reason:)` — `PortOne::ApiError`를 흡수하고 ③으로 진행(콘솔 선취소·응답 유실 재동기화) | `refund_service.rb:65~72(confirm_cancellation!)` |
| ③ PG 재조회 확정(fail-closed) | ① 결제 완료 사실(금액 ≥ 주문 금액) ② 전액 취소(상태 CANCELLED 계열 또는 취소 합계 ≥ 주문 금액) **모두** 확인. PARTIAL_CANCELLED는 명시 실패. 확인 불가는 전부 실패·로컬 무변경 | `refund_service.rb:85~127(ensure_full_cancellation·payment_paid_fact?·fully_cancelled?·cancellations_total)` |
| ④ 로컬 확정 트랜잭션 | `ActiveRecord::Base.transaction` + `order.with_lock` 후 가드 재검사(`refundable_state?`) — 이중 제출·경합에서 이긴 요청만 1회 실행 | `refund_service.rb:129~148(finalize!)·150~152` |
| 주문 확정 | `mark_refunded!`(refunded_at·refund_reason 재사용) + `status: :cancelled` + metadata 병합(B-1 선례 — 기존 키 보존, `refund` 키에 실행자·일시·금액·사유) | `refund_service.rb:154~174(apply_refund!·merged_metadata)` |
| Plus 주문 되돌리기 | 구독 `with_lock` 안에서 `expire!`(자동 갱신·dunning 잡과 같은 잠금 방식). 이미 Free·만료면 무변경. expire! 전 빌링키를 캡처해 그 회원의 `orders.pg_billing_key` 복사본 일괄 nil(키 nil이면 쿼리 생략 — `where(pg_billing_key: nil)` 오염 방지) | `refund_service.rb:190~208(expire_subscription!)` |
| 수금 패스 주문 되돌리기 | `PaymentPass.revoke_uses!(user:, count: PaymentPass::TOTAL_USES)` — 10건 차감 | `refund_service.rb:210~214` · `payment_pass.rb:31~54` |
| 내용증명·세금계산서 주문 | 되돌릴 것 없음 — 주문 기록만(발행물 보존·세금계산서 취소 요청 없음) | `refund_service.rb:176~188(revert_product!)` |
| ⑤ 감사 로그 | `AuditLogs::RecordService.call(action: "order_refund", target: order, detail: 사유 + 환불 금액 + 상품별 요약)` — 기존 action 이름 유지 | `refund_service.rb:216~219` |
| Result 요약 | "환불 금액 N원 · 구독 즉시 Free 전환 / 수금 패스 N건 차감(미차감 M건)" | `refund_service.rb:221~224` |

### ADMIN-11 환불 실행 콘솔
| 조항 | 구현 | 위치 |
|:---|:---|:---|
| 실행 버튼·사유 필수 | show 폼(text_area required) → `PATCH /admin/orders/:id/refund` | `show.html.erb:41~55` · `routes.rb:157` |
| 확인 대화창에 실행 효과 | `refund_confirm_message`(환불 금액 전액 즉시 + 상품별 효과)·폼 하단 안내 | `orders_helper.rb:20~32` · `show.html.erb:50~54` |
| owner 전용·staff 차단 | `before_action :require_owner, only: :refund`(가드는 BaseController protected로 이동 — AdminsController와 공용). staff 뷰: 실행 불가 안내·폼 없음 | `orders_controller.rb:7` · `base_controller.rb:43~56` · `show.html.erb:27~28` |
| 실행 결과 표시 | 환불일·사유·실행자(metadata["refund"]["executed_by"] — @refund_info로 공급)·금액 + flash 요약 | `show.html.erb:13~20` · `orders_controller.rb:36~41` |
| 콘솔 선취소 건 안내 | `cancelled` + `refunded_at` 없음: "포트원에서 이미 취소됨 — 정산을 완료하세요" + 같은 폼(재조회 재동기화로 수렴) | `show.html.erb:31~35` |
| 결제 완료 적 없는 건 | pending·failed·`paid_at` 없음: 버튼 없이 안내만 | `show.html.erb:29~30` |
| 감사 로그 | ADMIN-2 — PLAN-9 ⑤와 동일(기존 `order_refund` action — 기존 감사 화면·테스트와 정합) | `refund_service.rb:216~219` |

### Q27 확정 6건
| # | 결정 | 구현 위치 |
|:---|:---|:---|
| 1 | 포트원 취소 연동·즉시 전액 | `refund_service.rb:65~72` |
| 2 | Plus 주문 → 구독 즉시 Free | `refund_service.rb:190~208` |
| 3 | 수금 패스 10건 차감·0에서 종료 | `payment_pass.rb:31~54` |
| 4 | 발행물은 그대로(환불만) | `refund_service.rb:176~188` |
| 5 | owner 전용 | `orders_controller.rb:7` · `base_controller.rb:43~56` |
| 6 | 카드 미저장·빌링키만 정리(구독+주문 행 복사본) | `refund_service.rb:190~208` — 카드 관련 값은 어디에도 다루지 않음 |

### 부수 규칙
- **ADMIN-5** 매출 집계 제외 — `refunded_at` 기준 기존 스코프·집계 로직 그대로(`status` 변경과 무관하게 `refunded?`는 `refunded_at` 판정 — `order.rb:48~50`).
- **SURF-3 등 기존 표면 정책** — 관리자 화면 구조 변경 없음.
- **DESIGN** — 기존 관리자 타이포·여백·상태색 유지, 파괴 버튼 주황(bg-orange-600) 기존 선례, 터치 타깃 기존 클래스 재사용.

## 3. PG 재조회 응답 해석 근거 ([INFERENCE] 경계 명시)

**실측 기반(기존 코드가 이미 이 키로 읽는다)**:
- `payment[:status]` — 웹훅이 `ORDER_STATUS_BY_PORTONE.fetch(payment[:status])`(portone_controller.rb:59), PurchaseService가 confirm 응답 `payment[:status] == "PAID"`로 승인 판정(purchase_service.rb:87). 상태 값 집합 PAID·CANCELLED·PARTIAL_CANCELLED·CONSOLE_CANCELLED·FAILED(웹훅 매핑 상수 — 운영 웹훅 실측).
- `payment[:id]` — 웹훅 무결성 확인(`payment[:id] != order.pg_order_id` — portone_controller.rb:56).

**[INFERENCE](포트원 V2 공식 문서 원문 대조 실패 — 스크립트 렌더링·01_plan 리스크 1)**:
- `payment.dig(:amount, :paid)` / `:total` / `:cancelled` — 결제 객체 amount 구조 후보.
- `payment[:cancellations]` 배열의 `:cancellationAmount` / `:amount` — 취소 내역 후보.

**fail-closed 정책**:
- ① 결제 완료 사실은 **금액 필드로만** 확정한다(관대한 후보 키 2종을 읽되, 둘 다 없으면 확인 불가 → **성공 처리 금지**).
- ② 전액 취소는 상태(CANCELLED·CONSOLE_CANCELLED) 또는 취소 합계(amount.cancelled → cancellations[] 합계)로 확정. 두 근거 모두 없으면 실패.
- PARTIAL_CANCELLED는 명시적 실패(부분 취소는 PLAN-9 범위 밖 — 콘솔에서 나머지 환불 후 재실행 안내).
- **첫 실환불 1건으로 응답 필드를 실측해 확정할 것**(운영 후속 — 01_plan 리스크 1). 실측 결과가 후보 키와 다르면 `payment_paid_fact?`·`fully_cancelled?`·`cancellations_total` 3개 메서드만 수정하면 된다.

> **[2026-11-24 정정 — 리뷰 W-2·W-3 반영, §7 참조]** 위 [INFERENCE] 후보 키는 리뷰어가 공식
> OpenAPI v2 스펙(`src/schema/v2.openapi.json`, version 1.16.0)과 대조해 확정됐다. 확정값:
> `cancellations[].totalAmount`(required, 항목 `status`는 SUCCEEDED·REQUESTED·FAILED 3종),
> 상태 enum 7종(READY·PENDING·VIRTUAL_ACCOUNT_ISSUED·PAID·FAILED·PARTIAL_CANCELLED·CANCELLED —
> `CONSOLE_CANCELLED`는 스펙에 없음), `amount.paid·cancelled` required. 이전 후보 키
> `cancellationAmount`·`amount`는 스펙에 없어 제거했다. 실측 전 후보로 쓴 본 절의 표기는
> §7의 확정 구현이 우선한다. §6-1의 "fail-closed라 안전하게 떨어진다" 서술도 정정했다 —
> 판정 실패 시에도 PG에서는 환불이 실행됐을 수 있다(§7 W-8·C-2).

## 4. 웹훅 무변경 판단 근거 (`app/controllers/webhooks/portone_controller.rb` — 변경 없음)

- **후행 도착(우리 실행 뒤 Transaction.Cancelled)**: 주문이 이미 `cancelled` → `apply_status`의 `return if order.status == status`(71행)에서 무동작. 상태 수렴이 같으므로 멱등.
- **선행 도착(포트원 콘솔 선취소 → 웹훅이 status만 cancelled로)**: 이후 관리자가 실행 버튼을 누르면 사전 가드(`paid? || cancelled?` + `paid_at` 존재)를 통과하고, PG 취소 요청은 ApiError(ALREADY 계열)여도 재조회로 전액 취소 확정 → 로컬 정산 1회 기록. 스모크 검증 완료(아래 §5).
- **웹훅으로는 회복되지 않는 상태**: PG 취소 성공 + 로컬 확정 실패(cancelled인데 refunded_at 없음) — 웹훅은 상태만 보므로 이 건은 콘솔 안내("정산을 완료하세요")+ 재실행 버튼으로 회복(01_plan §3 설계 그대로).
- 부분 취소 이벤트(Transaction.PartialCancelled)도 웹훅은 기존처럼 status만 동기화 — PLAN-9 서비스는 부분 취소를 실패 처리해 상충 없음.

## 5. 실행한 검증 명령과 결과

| 명령 | 결과 |
|:---|:---|
| `bin/rails zeitwerk:check` | 통과("Otherwise, all is good!") |
| `bin/rails routes` | `refund_admin_order PATCH /admin/orders/:id/refund` 확인 |
| `bin/rubocop -a` (변경 파일 8종) | 8 files inspected, **no offenses** |
| `bin/rails test test/controllers/admin/orders_controller_test.rb` | **8 runs, 56 assertions, 0 failures** |
| `bin/rails test test/controllers/admin/admins_controller_test.rb test/models/order_test.rb test/models/payment_pass_test.rb test/controllers/webhooks/portone_controller_test.rb test/services/port_one/client_service_test.rb` | **50 runs, 247 assertions, 0 failures** |
| `bin/rails test test/controllers/app/legal_documents_controller_test.rb test/controllers/webhooks/tax_invoice_settle_test.rb` | **15 runs, 92 assertions, 0 failures** |
| `bin/rails test test/controllers/app/tax_invoices_controller_test.rb` | **19 runs, 101 assertions, 0 failures** |
| `bin/rails test` (전체) | **1,529 runs, 9,562 assertions, 0 failures, 0 errors** — 기존 전체 스위트와 동일 건수 유지 |
| 자체 스모크(임시 테스트 — 실행 후 삭제, 커밋 대상 아님) | **5 runs, 22 assertions, 0 failures** — ① 패스 10건 차감·만료 임박순(6잔여→0 먼저, 10잔여→6) ② 잔여 3건 → 0에서 종료·"미차감 7건" 요약 ③ Plus → 구독 즉시 Free·구독/주문 행 빌링키 동시 nil ④ PARTIAL_CANCELLED·paid_at 없는 cancelled 실패(로컬 무변경) ⑤ cancel_payment ApiError → 재조회로 재동기화 성공(콘솔 선취소 수렴) |

포트원·솔라피·바로빌 실호출 없음 — 전 테스트가 `FakePortOneClient` + `with_portone_client` 대역만 사용.

## 6. 미해결·리스크·오케스트레이터가 알아야 할 점

1. **[INFERENCE] 대부분 해소(2026-11-24 리뷰 정정 — §7 W-2·W-3)** — 재조회 응답의 금액·취소 내역 필드는 공식 OpenAPI v2 스펙으로 확정됐다(`amount.paid·cancelled`·`cancellations[].totalAmount`·상태 enum 7종 — `CONSOLE_CANCELLED` 없음). 남은 미확인 2건: **전액 취소 뒤 `amount.paid` 유지 여부·카드 취소의 동기(SUCCEEDED) 여부** — 첫 실환불 1건으로 확인할 것. 이전 서술("fail-closed라 안전하게 떨어진다")은 절반만 맞다: 판정 실패는 로컬 무변경이지만 **취소 요청이 판정 앞에 실행되므로 PG에서는 환불이 일어났을 수 있다** — §7 C-2의 시도·실패 감사(action `order_refund_attempt`·`order_refund_failed`)로 추적한다. 성공 오인 위험은 없다는 판정은 유지된다.
2. **`Order.cancelled` 스코프** — index 필터 확장(`filtered_orders`의 `%w[paid failed cancelled]`)은 enum 자동 스코프에 의존한다(Rails enum은 값별 조건 스코프를 생성). 전체 테스트 통과로 동작 확인했으나, `Order` 모델의 명시 스코프(paid·failed)와 혼재해 있다 — 정리는 별도 과제로.
3. **가상계좌 등 비동기·환불계좌 필요 결제수단** — cancel_payment가 환불 계좌 정보를 요구하는 결제수단(01_plan 리스크 1)은 ApiError → 재조회에서 CANCELLED가 아니면 실패로 안전하게 떨어진다. 운영에서 발생하면 §3 실측과 함께 절차를 확정할 것.
4. **임시 스모크 파일 삭제 완료** — `test/dev_smoke_refund_test.rb`는 자체 검증용으로만 사용하고 삭제했다(정식 시나리오 테스트는 Tester 범위 — 01_plan §에이전트 지시 요약의 Tester 목록).
5. **감사 action 이름 "order_refund" 유지** — 기존 감사 로그 화면·테스트와 정합. 실행 절차가 기록 전용에서 실행으로 바뀌었으므로 운영 참고: 과거 기록(레거시 "사유 기록")과 신규 실행 건이 같은 action으로 남는다(detail 본문으로 구분 — 신규 실행 건은 "환불 금액 N원 ·" 접두 형식).
6. **`update_all` 사용 1곳** — `expire_subscription!`의 주문 행 빌링키 일괄 정리(검증 컬럼이 아닌 복사본·읽는 곳 없는 값 — 01_plan §1 지시 "update_all 또는 동등 방식" 준수). 그 외 전부 검증 경유(`update!`).

## 7. Phase 6 수정(리뷰 반영 — 2026-11-24)

`_workspace/05_review.md`의 이슈(C-1·C-2·W-1~W-9)와 사고 대응(R1~R3)을 수정했다. 마이그레이션·라우트 변경 없음. 웹훅 컨트롤러·PRD·AGENTS.md는 변경하지 않았다.

### 7-0. 포트원 test 환경 실호출 차단 가드(최우선 — W-9·사고 대응 R1~R3)

솔라피(`solapi/client_service.rb` perform 가드)·이메일(`outbound_mail/client_service.rb`) 선례를 그대로 따랐다.

| 파일 | 내용 |
|:---|:---|
| `app/services/port_one/client_service.rb:94~108(perform)` | `Rails.env.test? && !Thread.current[:portone_http_stub]`이면 `ApiError(status: nil, code: "TEST_GUARD")` — 실제 연결(`Net::HTTP.start`) 직전에 예외로 차단. development·production은 무관 |
| `test/test_helpers/portone_stubbing.rb:18~32` | `with_http_transport`이 `Thread.current[:portone_http_stub] = true`로 켜고 `ensure`에서 nil 복원(솔라피·이메일 플래그와 같은 방식) — HTTP transport stub 경유 테스트(`client_service_test` 전체)는 통과 유지 |
| `test/services/port_one/client_service_test.rb`(테스트 1건 신설) | 대역 없이 `get_payment` 호출 → `TEST_GUARD` ApiError + `Net::HTTP.start` 호출 기록 0건(네트워크 연결 0회 보증). **가드 테스트 +1로 전체 1,529→1,530건** |
| `test/services/subscriptions/dunning_retry_test.rb:133~150`(R3) | 갱신 스윕 `SubscriptionRenewalJob.perform_now`를 `with_portone_client(@ok)`로 감쌈 — 같은 파일 ⑤·157행 선례. epsilon fixture(active·주기 종료 10-31)의 차감 간섭을 ⑤와 같은 `update_columns`로 제거하고 `assert_empty @ok.calls`로 강등 경로의 차감 호출 0건을 보증. 테스트 의미(3회 소진 → cancelled → 스윕에서 Free 강등)는 불변 |

가드는 `with_portone_client`(생성자 교체) 경로에는 적용되지 않는다 — 생성자 교체 시점에 실제 클라이언트 인스턴스가 만들어지지 않으므로 연결 자체가 없다. 가드는 "실제 `PortOne::ClientService#perform`이 test에서 실행되는 모든 경로"를 막는 2차 방어선이다.

### 7-1. 이슈별 수정 매핑

| 이슈 | 수정 | 위치 |
|:---|:---|:---|
| **C-1**(dunning 잔존 → 재등록 뒤 새 카드 차감) | `expire_subscription!`의 `with_lock` 안에서 `expire!`과 함께 `reset_dunning!`(멱등) + `last_payment_failed_at` nil(스키마 확인 — subscriptions 테이블에 컬럼 존재)을 실행. 이미 Free여서 `expire!`을 건너뛴 경우에도 dunning 필드가 남아 있으면 비운다 | `refund_service.rb:293~313` |
| **C-2**(PG 취소 시도의 감사 부재) | ① PG 호출 직전 시도 감사를 별도 트랜잭션으로 기록 — action `order_refund_attempt`, target=주문, detail=사유. **기록 실패 시 PG 호출 없이 실패 Result**(기록 없는 취소 금지) ② PG 호출 뒤 정산이 안 끝난 모든 경로(재조회 실패·판정 실패·`finalize!` 재검사 실패·로컬 예외)에 action `order_refund_failed`(detail=사유+실패 사유). 롤백 뒤 별도 기록 — 감사 기록 자체가 실패해도 실패 Result는 유지 ③ 성공 action `order_refund`는 그대로 ④ 사전 가드에서 걸린 시도(PG 호출 없음)는 기록하지 않음(변경 없음). 감사 화면(`admin/audit_logs/index.html.erb`)에는 action 라벨 사전이 없어(행위 필터는 원문 나열·기존 `order_refund`도 미등록) **그대로 둠** — 지시 "없으면 그대로" 적용 | `refund_service.rb:44~53(call)·80~92(record_attempt_audit!)·239~248(fail_with_audit)` |
| **W-1**(500 유출) | `finalize!` rescue를 `ActiveRecord::ActiveRecordError`(StatementInvalid·ConcurrencyError·RecordInvalid 포함) + 그 외 `StandardError`까지 확대 — 전부 실패 Result로 전환, 예외 클래스·메시지는 `Rails.logger.error`(사용자 메시지에는 클래스명만). `confirm_cancellation!`의 `get_payment`도 `StandardError`를 실패 Result로. 컨트롤러 `refund` 액션에 마지막 안전망 `rescue StandardError`(로깅 + flash 안내 + 422 show 재렌더 — 액션 본문 10줄 이내 유지, 성공·실패 응답은 private 헬퍼로 분리) | `refund_service.rb:206~237` · `orders_controller.rb:20~44` |
| **W-2**(스펙 불일치) | `FULL_CANCELLED_STATUSES`에서 `CONSOLE_CANCELLED` 제거(`%w[CANCELLED]`) + 공식 enum 7종 주석. `cancellations_total`은 `status == "SUCCEEDED"` 항목의 `totalAmount`만 합산(틀린 후보 키 `cancellationAmount`·`amount` 제거). 웹훅 컨트롤러 상수는 변경 금지대라 유지 | `refund_service.rb:30~36·176~181` |
| **W-3**(total 폴백·ID 검증) | `payment_paid_fact?`에서 `amount.total` 폴백 제거(`paid`는 필수 — 없으면 확인 불가 실패). `ensure_full_cancellation` 첫 검사로 `payment[:id] == @order.pg_order_id` 일치 확인 신설(웹훅 선례 `portone_controller.rb:56`) | `refund_service.rb:130~134·158~162` |
| **W-4a**(사유 상실) | 흡수한 취소 요청 오류를 실패 메시지에 덧붙임 — "포트원 취소 요청 오류: {code} — …"(ApiError는 `code`, 그 외 예외는 클래스명) | `refund_service.rb:195~207` |
| **W-4b**(비동기 취소) | 취소 응답 본문(신뢰하지 않고 참고만)의 `cancellation.status == "REQUESTED"` + 재조회에서 미전액취소 → 실패 메시지를 "취소가 비동기로 진행 중입니다. 잠시 후 다시 실행해 주세요."로 대체(재실행은 재조회로 수렴) | `refund_service.rb:149~153·183~190` |
| **W-4c**(부분 취소 가드 위치) | **변경 없음** — 오케스트레이터 판정(현행 유지: 이미 부분 취소된 결제는 PG가 잔액 전액을 취소해 전액 환불되거나 거부되어 명시 실패로 끝난다) | — |
| **W-5a~c**(확인창 문구) | Plus="남은 결제 기간 소멸·이 주문 금액만 환불" / 수금 패스="회원 보유 패스 중 만료 임박순 차감" / 발행물="환불 뒤 앱에서 재다운로드 불가" — `refund_effect_summary` 1곳 수정(폼 안내·확인창 공용이라 자동 반영) | `orders_helper.rb:11~23` |
| **W-5d**(사실과 다른 안내) | "PG 취소 요청 없이 재조회로 확인…" → "포트원에 결제 취소를 요청한 뒤 포트원에 다시 조회해 전액 취소를 확인합니다(이미 취소된 결제는 확인만 합니다)" + 부분 취소 실패 안내 추가 | `admin/orders/show.html.erb:47~53` |
| **W-5e**(레거시 건 문구) | `@refund_info` 유무로 분기 — 있으면 기존 문구(되돌리기·감사 완료), 없으면 "과거 기록 전용 방식으로 기록된 주문입니다(실제 환불·되돌리기는 이 화면으로 실행된 것이 아닙니다)" | `admin/orders/show.html.erb:13~27` |
| **W-5f**(막다른 길 링크) | 세금계산서 회원 화면 환불 분기의 "다시 발행 요청" 링크 제거 → "재발행이 필요한 경우 고객지원(문의)으로 연락해 주세요."(같은 뷰 취소 건 분기 선례 문구) | `app/tax_invoices/show.html.erb:66~78` |
| **W-6**(이미 Free 판정) | `already_free = subscription.free?`(상태 무관) — expire! 생략 + 보고 "구독은 이미 Free(무변경)". 빌링키 복사본 정리 쿼리는 `billing_key.present?`일 때만(기존 유지 — 이미 Free면 키가 nil이라 쿼리 생략) | `refund_service.rb:293~313` |
| **W-8**(주석·문서 정정) | 서비스 헤더 절차 주석 전면 정정: 롤백 경로의 주문은 **실행 전 상태(paid 등)로 미정산 채 남는다**(이전 "cancelled로 남는다"는 롤백 경로와 불일치 — 웹훅 도착 뒤 재실행으로 회복). "fail-closed"는 로컬 무변경만 보장하고 **PG 환불 부재는 보장하지 않는다**(취소 요청이 판정 앞에 실행 — C-2 감사로 추적). 본 문서 §3·§6-1도 같은 취지로 정정 | `refund_service.rb:1~21` · 본 문서 §3 정정 노트·§6-1 |

### 7-2. 바꾼 기존 테스트(의미 변경 목록)

| 테스트 | 변경 | 이유 |
|:---|:---|:---|
| `dunning_retry_test.rb` ④ "재시도 3회 소진…" | 스윕 실행에 `with_portone_client(@ok)` + epsilon 간섭 제거 + `assert_empty @ok.calls` 추가 | R3 — 대역 없이는 운영 API 실호출(가드로도 차단되지만 테스트 자체를 정상 경로로 고정) |
| `client_service_test.rb` | 가드 테스트 1건 신설(이것만 추가) | W-9 — 가드 동작·네트워크 0회 정식 고정 |

`orders_controller_test.rb`는 **변경 없이 통과**한다 — ①~③의 감사 어설션이 전부 `action: "order_refund"` 한정이라 시도·실패 감사(`order_refund_attempt`·`order_refund_failed`) 신설과 무충돌이고, blank·이중 실행은 사전 가드(PG 호출 0)라 시도 감사도 남지 않는다(의미 불변).

### 7-3. 실행한 검증(가드 활성 상태)

| 명령 | 결과 |
|:---|:---|
| `bin/rails test`(전체) | **1,530 runs(+1 — 가드 테스트), 9,568 assertions, 0 failures, 0 errors** |
| 대상 파일 선행 실행(가드·dunning·관리자 주문) | 32 runs, 207 assertions, 0 failures |
| `bin/rubocop` | 422 files inspected, **no offenses**(-a 자동 교정 4건은 인라인 if 할당 → guard 스타일 수동 전환) |
| `bin/rails zeitwerk:check` | 통과("all is good") |

### 7-4. 남은 [INFERENCE]·운영 주의

- **[INFERENCE] 2건 유지**: 전액 취소 뒤 `amount.paid` 유지 여부(유지 추정 — 같은 PaymentAmount 타입)·카드 취소의 동기(SUCCEEDED) 여부. **첫 실환불 1건(실결제 검증용 수금 패스 권장)으로 확인**하고 리뷰어 §8 테스트로 회귀 고정할 것.
- **W-4c 운영 관찰**: 이미 부분 취소된 결제에 대한 전액 취소 요청의 PG 동작(잔액 전액 취소 vs 거부)은 미확인 — 어느 쪽이든 명시 실패 또는 전액 취소 확정으로 수렴하지만, 첫 실제 발생 시 로그로 확인.
- **시도 감사의 성공 쌍**: 성공 환불은 `order_refund_attempt` + `order_refund` 2건이 남는다(의도 — 시도 기록은 결과와 독립). 감사 화면 필터에 이 2개 action은 미등록(기존 `order_refund`도 미등록 — 사전 없음)이라 필요 시 별도 과제로.
- **R1·R2 사고 후속(Developer 범위 밖)**: 리뷰어가 보낸 1회 차감 요청은 가짜 빌링키로 포트원이 거부(`BILLING_KEY_NOT_FOUND`) — 포트원 콘솔에 실패 요청 기록이 남을 수 있다. 시크릿의 운영 키 여부는 확인 대상.
