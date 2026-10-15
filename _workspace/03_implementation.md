# 03_implementation.md — 토스 → 포트원(KG이니시스) 결제 게이트웨이 전환

- **일자**: 2026-10-15
- **Rule ID**: PLAN-5 (§6.10), PLAN-2/4 연동부, §6.19 EXT — PRD v0.21
- **범위**: 래퍼 재작성 · 컬럼 rename · 서비스 · 웹훅 · UI SDK 교체 (크린 컷오버)

---

## 1. API 매핑 표 (토스 → 포트원)

| 구분 | 기존 (토스페이먼츠 코어 V1) | 신규 (포트원 V2 — `api.portone.io`) |
|:---|:---|:---|
| 인증 | Basic Auth (secret_key) | `Authorization: PortOne {api_secret}` |
| 공통 파라미터 | — | `storeId` (credentials `portone.store_id`) |
| 멱등키 | orderId 선기록(주문 UUID) | `Idempotency-Key: "{uuid}"` (POST, RFC 8941 따옴표) + paymentId 재사용 거부 |
| 타임아웃 | 10초 | 60초 (포트원 권장 — PG 응답 지연 고려) |
| 단건 승인 | `POST /v1/payments/confirm` (orderId·paymentKey·amount) | `POST /payments/{paymentId}/confirm` (storeId·paymentToken) |
| 빌링키 발급 | `POST /v1/billing/authorizations/issue` (customerKey·authKey) | `POST /billing-keys/confirm` (storeId·billingIssueToken·channelKey·customer{id}) — 응답 `billingKey` |
| 자동결제 차감 | `POST /v1/billing/{customerKey}` | `POST /payments/{paymentId}/billing-key` (billingKey·channelKey·orderName·amount{total}·currency=KRW·customer{id}) |
| 결제 조회 | `GET /v1/payments/{paymentKey}` | `GET /payments/{paymentId}?storeId=` |
| 결제 취소 | (미사용 — 콘솔 수동) | `POST /payments/{paymentId}/cancel` (storeId·reason) — 신규 |
| 오류 본문 | `{ code, message }` | `{ type, message }` (PG 기인 시 `pgCode`·`pgMessage`, `failure` 객체) → `PortOne::ApiError(status·code·message·pg_code·pg_message)` |
| 결제 상태 | DONE·CANCELED·ABORTED·EXPIRED… | PAID·CANCELLED·PARTIAL_CANCELLED·CONSOLE_CANCELLED·FAILED·READY·PAY_PENDING… |
| 웹훅 이벤트 | `paymentStatusChanged` | `Transaction.Paid`(승인)·`Transaction.Cancelled`(취소)·`Transaction.Failed`(실패)·`Transaction.PartialCancelled`(부분취소) — 플랜 문구의 TransactionConfirmed/Cancelled/Failed에 해당하는 [포트원 웹훅 v2(2024-04-25) 공식 type](https://developers.portone.io/opi/ko/integration/webhook/readme-v2?v=v2). 그 외(Ready·PayPending·CancelPending·BillingKey.*·미지원 신규 type)는 규격대로 흡수 |
| UI SDK | `js.tosspayments.com/v1/payment` (리다이렉트 successUrl/failUrl) | `cdn.portone.io/v2/browser-sdk.js` (Promise 응답 — paymentId·paymentToken·billingIssueToken을 JS가 콜백으로 전달) |
| 채널 | — | `channel_key_normal`(INIpayTest — 수금 패스 단건)·`channel_key_billing`(INIBillTst — 구독 빌링) |

**매핑 원칙**: 포트원 paymentId = 서버가 채번한 주문 번호(`pg_order_id`)를 그대로 사용한다(위젯·빌링키 결제 공통). 따라서 웹훅의 `data.paymentId`로 곧바로 주문 조회가 가능하고, 토스식 `paymentKey` 별도 보관은 `pg_payment_id` 스냅샷으로 대체한다.

**수동 승인 토큰**: SDK 성공 응답의 `paymentToken`은 수동 승인 채널에서만 온다(스키마 optional). 있으면 승인 API로 확정, 없으면(즉시 승인 채널) `get_payment` 재조회로 PAID 확정 — 기존 이슈 #1 재확인 패턴 재사용.

## 2. 컬럼 rename 표 (데이터 유지 — `rename_column`)

| 테이블 | 기존 | 신규 | 비고 |
|:---|:---|:---|:---|
| orders | `toss_order_id` (NOT NULL, unique) | `pg_order_id` | 서버 채번 UUID — 포트원 paymentId로 사용 |
| orders | `toss_payment_key` | `pg_payment_id` | 포트원 결제 ID 스냅샷 |
| orders | `toss_billing_key` | `pg_billing_key` | |
| orders | index `index_orders_on_toss_order_id` | `index_orders_on_pg_order_id` | rename_index |
| orders | index `index_orders_on_toss_payment_key` | `index_orders_on_pg_payment_id` | rename_index |
| subscriptions | `toss_customer_key` | `pg_customer_key` | 포트원 customer.id (부분 고유 인덱스 유지) |
| subscriptions | `toss_billing_key` | `pg_billing_key` | |
| subscriptions | index `idx_subscriptions_on_toss_customer_key_uniq` | `idx_subscriptions_on_pg_customer_key_uniq` | WHERE 절 포함 — drop+create로 재정의(§6 참조) |

마이그레이션: `db/migrate/20261015000003_rename_toss_columns_to_pg.rb` (up/down 왕복 실측 완료 — §7)

## 3. 변경 파일

### 신규
| 파일 | 내용 |
|:---|:---|
| `app/services/port_one/client_service.rb` | 포트원 V2 래퍼 — confirm·빌링키 발급·차감·조회·취소. 순수 Ruby(AR 무의존, stub 가능), Idempotency-Key(POST), 타임아웃 60초 |
| `app/services/port_one/api_error.rb` | status·code·message·pg_code·pg_message + `ambiguous?`(TIMEOUT/CONNECTION) |
| `app/controllers/webhooks/portone_controller.rb` | `POST /webhooks/portone` — 비인증·CSRF 면제·항상 200. 이벤트 type 분기 → get_payment 재조회로 무결성 확정 → Order 상태 반영(pending→paid는 상품별 확정 동반: 패스 발급·settle_renewal) |
| `app/javascript/controllers/portone_billing_controller.js` | `requestIssueBillingKey({storeId, channelKey, billingKeyMethod:"CARD", customer{customerId}})` → billingIssueToken을 card_callback으로 전달. SDK 미로드 시 무영향(테스트 환경 스텁 처리) |
| `app/javascript/controllers/portone_payment_controller.js` | `requestPayment({storeId, channelKey, paymentId, orderName, totalAmount, currency:"KRW", payMethod:"CARD"})` → paymentId·paymentToken(수동 승인) 또는 code·message(실패)를 callback으로 전달. SDK 미로드 시 무영향 |
| `test/test_helpers/fake_portone_client.rb` | ClientService 테스트 대역(5 메서드 — cancel 포함) |
| `test/test_helpers/portone_stubbing.rb` | `with_portone_client`·`with_http_transport` |
| `test/test_helpers/fake_toss_client.rb`·`toss_stubbing.rb` | **[Phase 7 대기 로드 호용]** 삭제된 토스 이름으로 기존 테스트 파일이 로드되도록 별칭/위임만 제공(`FakeTossClient = FakePortOneClient`, `with_toss_client` → `with_portone_client`). 기존 테스트 파일 수정 금지 제약 하에 러너 전체 중단(LoadError)을 막기 위한 최소 파일 — Phase 7 테스트 갱신 시 제거 |

### 수정
| 파일 | 내용 |
|:---|:---|
| `db/migrate/20261015000003_rename_toss_columns_to_pg.rb` | 컬럼·인덱스 rename (§2) |
| `app/models/order.rb` | `pg_order_id` 검증·주석 |
| `app/models/subscription.rb` | `pg_customer_key` 검증·before_create, `activate!`/`expire!`의 `pg_billing_key` |
| `app/services/subscriptions/upgrade_service.rb` | PortOne 클라이언트 주입, `issue_token:` 파라미터, `portone_channel_key_billing` 헬퍼(발급·차감 모두 정기결제 채널), charge 시그니처(payment_id·channel_key·customer_id·order_name), `pg_*` 저장, 결제 ID 멱등 주석 |
| `app/services/orders/purchase_service.rb` | `confirm_payment(payment_id:, payment_token:)`, 토큰 없으면 get_payment 재확인, `PendingApprovalError`(승인 전 — pending 유지·웹훅 회복), 모호 실패 재확인 합류 유지 |
| `app/services/orders/fulfill_pass_service.rb` | `payment_id:` 파라미터, `pg_payment_id` 저장 |
| `app/controllers/app/billings_controller.rb` | `pg_order_id` 체크아웃 조회, `@portone_store_id`·`@portone_channel_key_normal`·`@portone_channel_key_billing` 적재 |
| `app/controllers/app/orders_controller.rb` | callback이 포트one 위젯 결과(code·paymentId·paymentToken) 수신, 소유권 격리 `pg_order_id` |
| `app/controllers/app/subscriptions_controller.rb` | `auth_key` → `issue_token`(빌링키 발급 토큰) |
| `app/jobs/subscription_trial_expiry_job.rb` | `pg_billing_key: nil` |
| `app/jobs/subscription_renewal_job.rb` | 주석 갱신 |
| `config/routes.rb` | `/webhooks/toss` 제거 → `/webhooks/portone` 추가 |
| `config/initializers/inflections.rb` | `inflect.acronym "PortOne"` — `portone_controller.rb` → `Webhooks::PortOneController` (zeitwerk 정규화) |
| `app/views/app/billings/show.html.erb` | PortOne SDK 스크립트, portone-billing 컨트롤러 데이터 속성(storeId·channelKey·customerId·callbackUrl), 수동 등록 폼 `issue_token`, 안내 문구 |
| `app/views/app/billings/_checkout.html.erb` | portone-payment 컨트롤러 데이터 속성, `pg_order_id` |
| `test/fixtures/orders.yml`·`subscriptions.yml` | 속성 키만 rename(toss_*→pg_*) — 값 무변경. `fixtures :all`이 모든 테스트에서 전체 fixture를 적재하므로 미갱신 시 결제 무관 테스트까지 전부 FixtureError로 붕괴 → §4 실패 목록의 의미가 소실되어 갱신(테스트 로직 무변경) |
| `PRD.md` | §6.10 PLAN-5 본문 + §6.19 결제 행 — 포트원 전환 반영(02_prd_update.md 명시분. 버전 행만 v0.21로 올라가 있고 본문이 미반영 상태였음) |

### 삭제 (크린 컷오버)
| 대상 | 비고 |
|:---|:---|
| `app/services/toss_payments/` (client_service.rb·api_error.rb) | PortOne 래퍼로 대체 |
| `app/controllers/webhooks/toss_controller.rb` | PortOne 웹훅으로 대체 |
| `app/javascript/controllers/toss_billing_controller.js`·`toss_payment_controller.js` | PortOne 컨트롤러로 대체 |
| `test/controllers/webhooks/toss_controller_test.rb` | 대상 컨트롤러 삭제에 따른 동반 삭제(존재하지 않는 라우트·컨트롤러 테스트) |
| `test/services/toss_payments/client_service_test.rb` | 대상 래퍼 삭제에 따른 동반 삭제 |
| `test/test_helpers/fake_toss_client.rb`·`toss_stubbing.rb` | PortOne 버전으로 갱신(§3 신규 참조) — 위 로드 호용 파일명으로 재생성 |
| `POST /webhooks/toss` 라우트 | `/webhooks/portone`으로 대체 |

## 4. 실패 예상 테스트 (Phase 7 갱신 대상 — 기존 테스트 파일 무수정)

`bin/rails test` 전수 실행 결과: **463 runs, 2574 assertions, 4 failures, 41 errors, 0 skips**.
실패 45건 **전부** F-PLAN 결제·구독 표면(컬럼 rename·래퍼 교체·파라미터명 변경)이며, 그 외 도메인(인증·청구·거래처·뷰어 등)은 전부 통과.

| 테스트 파일 | 건수 | 원인 |
|:---|:---:|:---|
| `test/models/order_test.rb` | 3 | `toss_order_id` → `pg_order_id` (UnknownAttributeError·NoMethodError) |
| `test/models/subscription_test.rb` | 6 | `toss_customer_key`·`toss_billing_key` |
| `test/services/orders/purchase_service_test.rb` | 6 | `toss_order_id` 생성부 + `FakeTossClient` 시그니처(order_id·payment_key) + `TossPayments::ApiError` |
| `test/services/orders/purchase_service_concurrency_test.rb` | 1 | 상동 |
| `test/services/subscriptions/upgrade_service_test.rb` | 14 | `toss_billing_key`·`auth_key:`→`issue_token:`·`TossPayments::ApiError`·토스 응답 해시(paymentKey·billingKey) |
| `test/controllers/app/orders_controller_test.rb` | 6 | `toss_order_id`·`paymentKey` 파라미터 |
| `test/controllers/app/subscriptions_controller_test.rb` | 3 | `auth_key`/`authKey` 파라미터·토스 응답 해시·안내 문구 |
| `test/controllers/app/billings_controller_test.rb` | 2 | `data-controller=toss-payment` 셀렉터 → `portone-payment` |
| `test/f_plan_review_fix_test.rb` (FPlanReviewFixTest·HttpTest) | 4 | `toss_order_id`·`paymentKey` 보존 단언·`authKey` 문구 |

갱신 방향(Phase 7): `pg_*` 속성, `FakePortOneClient` 시그니처(payment_id·payment_token·channel_key·customer_id·order_name), `PortOne::ApiError`, 웹퍼 `Transaction.Paid` 이벤트 본문, `portone-payment` 셀렉터, `issue_token` 파라미터.

## 5. 후속 제외 (플랜 합의)
- 토스 credentials 키 제거 — 라이브 전환 확정 시
- 포트원 SDK 브라우저 실측(빌링키 발급 성공·단건 결제 성공) — 배포 후 브라우저에서 확인
- AGENTS.md 로드맵 — Phase 9
- 신규 포트원 테스트 작성 — Phase 7

## 6. 구현 중 발견·결정 사항
1. **SQLite 부분 고유 인덱스**: SQLite는 인덱스 정의(WHERE 절)를 원문 보관 → 컬럼 rename 테이블 재구축 시 `WHERE toss_customer_key`가 남아 실패. up: rename **전에** 인덱스 선삭제 후 재생성, down도 동일 순서로 수정.
2. **Zeitwerk inflection**: `portone_controller.rb`의 기본 camel화는 `PortoneController` — 명세의 `Webhooks::PortOneController` 유지를 위해 `inflect.acronym "PortOne"` 추가(서비스 모듈 `PortOne::`와 표기 일관).
3. **웹훅 이벤트 type**: 플랜 문구(TransactionConfirmed 등)는 포트원 실제 규격(`Transaction.Paid` 등)으로 구현 — §1 표 각주.
4. **즉시 승인 채널 폴백**: paymentToken 미수신(즉시 승인 채널) 시 get_payment로 승인 확정 — 수동 승인 채널 의존 제거(기존 이슈 #1 재확인 패턴 재사용).
5. **PRD 본문**: v0.21 버전 행만 갱신되고 PLAN-5 본문·§6.19가 토스로 남아 있어 Phase 2 명시분(02_prd_update.md)대로 보완.

## 7. 자체 점검 결과

| 점검 | 결과 |
|:---|:---|
| `bin/rubocop` | **0 offenses** (136 files) |
| `bin/rails zeitwerk:check` | 통과 (`Webhooks::PortOneController`·`PortOne::ClientService` 상수 확인) |
| `bin/rails db:migrate` | 성공 — `db/schema.rb` 갱신(pg_* 컬럼·인덱스) |
| 마이그레이션 롤백 실측 | `db:rollback STEP=1` → 데이터 유지 확인(`toss_order_id: "retest-order-2"`) → 재적용 → 데이터 유지 확인(`pg_order_id: "retest-order-2"`) — **rename 왕복 데이터 무손실** |
| `bin/rails test` (최종) | 463 runs — 4 failures·41 errors, 전부 §4의 예상 갱신 대상. 무관 도메인 0건 |
| 포트원 API 러너 실측(실패 경로) | 5 엔드포인트 전수: get_payment·confirm_payment·cancel_payment = `404 PAYMENT_NOT_FOUND`, charge_billing_key·issue_billing_key = `404 BILLING_KEY_NOT_FOUND` — 인증 헤더·경로·storeId·오류 정규화(code=type) 실측 확인. **성공 경로는 브라우저 위젯 필요 — 배포 후 실측 항목(§5)** |
| PurchaseService 러너 실측(FakePortOneClient — 신규 코드 전 경로) | ①토큰 confirm 확정(paid+패스 발급+metadata) ②즉시 승인 채널(토큰 없음) 조회 확정 ③미승인(READY) → pending 유지+지연 안내 PurchaseError ④모호 실패→재확인 PAID 합류(paid+발급) ⑤모호 실패→재확인도 실패 → pending 유지 ⑥명확 실패 → failed+pg_code·pg_message 보존 — **6/6 통과** |
| UpgradeService 러너 실측(신규 코드 갱신·회복 경로) | ①갱신: 정기결제 채널(channel_key_billing)·billing_key·customer_id·amount 9,900·payment_id=주문번호로 차감 → paid+1개월 연장 ②settle_renewal: 재조회 payment{id}로 paid+연장 ③모호 차감 → 구독 유지 ④명확 차감 → failed(pg_code 보존)+즉시 만료 ⑤모호 이력 스티키 가드(재시도 거절 만료 금지 — 이슈 #4) — **5/5 통과** |
| 웹훅 러너 실측 | `Transaction.Paid` → 주문 paid·패스 발급(200), 재시도 → 멱등(패스 추가 발급 없음), 위조 결합(타 paymentId 재조회) → 흡수 무변경, 미지원 type(BillingKey.Issued)·깨진 JSON → 200 흡수. 라우트 `POST /webhooks/portone` 확인 |
| `TossPayments` 상수 | `defined?(TossPayments)` → nil — 완전 제거 확인 |
| 토스 잔여 참조 | `app/`·`config/` 0건 (과거 마이그레이션 `20261015000001`은 이력 보존상 무수정 — rename이 전제) |

### 7.1 러너 검증에서 발견해 수정한 버그
1. **`PurchaseService#recover_from_recheck!` 발급 누락** — 재작성 시 재확인 합류 경로에서 `FulfillPassService` 호출이 빠져 있었다(모호 실패→재확인 PAID 시 주문만 pending 잔류). 실측 ④에서 포착 → 재조회 응답으로 FulfillPassService 호출하도록 수정 + `PendingApprovalError`도 흡수하도록 rescue 확장.
2. **`UpgradeService#record_charge_failure!` PG 원문 미보존** — 실패 주문 metadata에 pg_code·pg_message가 빠져 CS 조사 근거가 없었다. PurchaseService#record_failure!와 정렬해 보존하도록 수정(실측 ④에서 포착).

## 8. 러너 실측 시 주의(운영 무관)
러너에서 integration 세션으로 POST 후 같은 스레드에서 모델 쿼리를 날리면 Rails 8.1 QueryLogs의 ExecutionContext 판독(nil)으로 크래시 — 러너+integration 조합 한정 아티팩트. 앱 요청·테스트 러너(별도 프로세스)에는 영향 없음. 실측 스크립트는 raw SQL 판독으로 회피했으며 임시 스크립트는 삭제함.

---

## 수정 이력 (Phase 6) — 리뷰 BLOCKER 1건 + CRITICAL 2건

- **일자**: 2026-10-15 · **대상 리뷰**: `_workspace/05_review.md` 이슈 B1·C1·C2 — 1:1 대응
- **스펙 재실측**: 포트원 `browser-sdk.yml` 스키마(IssueBillingKeyRequestBase·OfferPeriod)·KG이니시스 V2 문서 재조회 — `customer.fullName` 항상 필수, `phoneNumber`·`email` PC 필수/모바일 선택, `issueId`(ASCII만)·`issueName` 필수, `offerPeriod`(형식 `${number}m`) 모바일 빌링키 발급 필수/PC 선택 확인

| 이슈 | 수정 내용 | 파일 |
|:---|:---|:---|
| **B1** BLOCKER — KG이니시스 필수 파라미터 미전달 | `requestPayment`에 `customer { fullName, phoneNumber, email }` 전달(fullName은 항상, PC 필수 phone·email은 값이 있을 때만). `requestIssueBillingKey`에 `issueId`(서버 채번 UUID — ASCII 제약 충족)·`issueName`("받을돈 정기결제 등록")·`customer { customerId, fullName, phoneNumber }`·`offerPeriod { interval: "1m" }`(월 구독 — 모바일 발급 필수) 전달. 사용자 표시명·연락처·이메일은 billings 컨트롤러가 적재해 `data-portone-*-customer-*-value`·`data-portone-billing-issue-id-value`로 뷰→위젯 전달(표시명은 프로필 완료 가드 AUTH-1.3, 이메일은 AUTH-1.4로 항상 존재) | `app/javascript/controllers/portone_payment_controller.js` · `portone_billing_controller.js` · `app/controllers/app/billings_controller.rb` · `app/views/app/billings/_checkout.html.erb` · `app/views/app/billings/show.html.erb` |
| **C1** CRITICAL — confirm 재시도 `ALREADY_PAID`가 명확 실패로 확정 | `PortOne::ApiError#already_paid?` 추가(code에 ALREADY_PAID 포함 — 실패가 아닌 결제 완료의 확정 신호로 분류). `PurchaseService` rescue에서 모호 실패와 함께 `recover_from_recheck!` 합류 대상으로 확장 — 재조회 PAID면 paid+패스 발급 경로로 합류, 재조회마저 실패하면 pending 유지(웹훅 `settle_paid` 회복). 명확한 비즈니스 거부의 failed 확정은 유지. 갱신 차감의 스티키 가드(upgrade_service 187-196)와 단건 경로 대칭화 | `app/services/port_one/api_error.rb` · `app/services/orders/purchase_service.rb` |
| **C2** CRITICAL — `redirectUrl` 미설정(반환값 방식 — 모바일 결제창 미표시) | `requestPayment`·`requestIssueBillingKey` **모두**에 `redirectUrl: callbackUrl` 전달로 페이지 이동 방식 전환. PC 위젯이 Promise로 응답하는 환경용 기존 수동 이동은 폴백으로 유지. SDK 리다이렉트가 응답 필드명 그대로 쿼리 전달 → ① 결제 콜백(`paymentId`·`paymentToken`·`code`·`message`)은 기존 수신 그대로 호환 ② 빌링 콜백은 `billingIssueToken` 파라미터명 수용 추가(`issue_token` 폴백 병존) | `app/javascript/controllers/portone_payment_controller.js` · `portone_billing_controller.js` · `app/controllers/app/subscriptions_controller.rb` |

**비고**
- C1 리뷰의 "부차" 경로(웹훅 `failed→paid` 상태만 뒤집는 전환)는 수정 제안 ②가 아니라 채택된 ①(ALREADY_PAID 합류)로 C1 시나리오의 재현 경로(ALREADY_PAID→failed 확정)가 소멸해 더 이상 도달하지 않는다 — 웹훅 코드 무변경.
- B1에서 모바일 필수 `offerPeriod`는 리뷰 이슈 표에 명시된 요건으로 지시문 예시에 없더라도 C2(모바일 주류)와 직결되어 함께 반영했다. `issueId`는 매 페이지 렌더마다 서버가 새로 채번한다(발급 건 고유 — 별도 보관 컬럼 없음).

### 자체 점검 (Phase 6)

| 점검 | 결과 |
|:---|:---|
| `bin/rubocop` | **0 offenses** (136 files) |
| `bin/rails zeitwerk:check` | 통과 |
| `bin/rails test` | **490 runs, 2984 assertions, 0 failures, 0 errors, 0 skips** — 기준선(490 runs 전체 통과) 유지 |
| C1 러너 실측(FakePortOneClient — 실외부 호출 없음, 실측 후 행 정리) | ① confirm `ALREADY_PAID` + 재조회 PAID → **paid 확정 + 패스 1회 발급**(재조회 1회, 실패 메타 없음) ② `ALREADY_PAID` + 재조회 TIMEOUT → pending 유지·`pending_recovery: true`·발급 0회(웹훅 회복 경로) ③ 명확 거부(PG_PROVIDER_ERROR) → failed + pg_code 보존(기존 동작 회귀 없음) — **3/3 통과** |
