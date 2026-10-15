# 03_implementation.md — F-PLAN 구독·과금 (토스페이먼츠 테스트 키)

- **일자**: 2026-10-15
- **대상**: PRD v0.20 §6.10(PLAN-1~8) · §6.19(EXT) · `_workspace/01_plan.md`
- **Rule ID 매핑**: PLAN-1(한도 전환) · PLAN-2(Plus 9,900원·14일 체험) · PLAN-4(수금 패스 10건 4,000원 90일) · PLAN-5(토스 결제·웹훅) · PLAN-6(환불 불가 고지 — 화면 문구) · SEC(웹훅 무결성 재조회) · TIME-1(Seoul TZ·크론 KST)

---

## 1. 변경 파일

### 신규
| 파일 | 내용 |
|---|---|
| `db/migrate/20261015000001_create_subscriptions_orders_and_payment_passes.rb` | 3개 테이블. 1인 1구독 고유 인덱스, toss_customer_key 부분 고유 인덱스, toss_order_id 고유 인덱스, toss_payment_key 인덱스, remaining_uses 음수 방지 체크 제약. 신규 3테이블의 user FK는 `on_delete: :cascade`(원시 delete_all 경로 방어선 — dependent: :destroy와 이중, 무해) |
| `app/models/subscription.rb` | plan(free/plus)·status(trialing/active/cancelled/expired) enum, 한도 판정점 2종, 생명주기 4종(`start_trial!`/`activate!`/`cancel!`/`expire!`), `before_create` customer_key 발급 |
| `app/models/order.rb` | product(pending 기본)·status enum, `PRODUCT_AMOUNTS`(정가 단일 지점), `amount_for` |
| `app/models/payment_pass.rb` | `usable?`/`use!`(with_lock), `UsesExhausted`, `usable` 스코프 |
| `app/services/toss_payments/api_error.rb` | status·code·message 운반 예외. 타임아웃/접속 실패는 code TIMEOUT/CONNECTION으로 정규화 |
| `app/services/toss_payments/client_service.rb` | 순수 Ruby(AR 무의존 — stub 가능). Basic Auth(secret_key), 타임아웃 10초, JSON 파싱, 4개 API |
| `app/services/subscriptions/upgrade_service.rb` | 체험 시작·카드 등록·해지·만료·자동 갱신의 단일 진입점(`#call` + action 디스패치). 토스 실패 주문 기록+강등 원자화 |
| `app/services/orders/purchase_service.rb` | 수금 패스 승인 확정. 주문 with_lock + pending 재판정으로 이중 콜백 흡수(발급 정확히 1회) |
| `app/jobs/subscription_trial_expiry_job.rb` | 체험 종료 && 카드 없음 → 강등(멱등) |
| `app/jobs/subscription_renewal_job.rb` | 주기 종료 → 차감·연장 / 해지·카드 부재 → 강등. 개별 실패가 전체를 중단하지 않음 |
| `app/controllers/app/billings_controller.rb` | 요금제 페이지(show). `resource :billing`의 Rails 관례 매핑(app/billings#show)에 맞춰 복수형 — PlanTester 리뷰 반영 |
| `app/controllers/app/subscriptions_controller.rb` | create(체험)·update(카드 등록 — 위젯 GET 콜백과 수동 PATCH가 authKey 유무로 수렴 / 해지) |
| `app/controllers/app/orders_controller.rb` | create(대기 주문 — 기존 pending 재사용 멱등)·callback(토스 리다이렉트 수신) |
| `app/controllers/webhooks/toss_controller.rb` | 비인증·CSRF skip. 이벤트 값 대신 `get_payment` 재조회로 확정(위조 차단). 항상 200 |
| `app/helpers/app/billings_helper.rb` | 플랜 배지·상태 문구·패스 요약 |
| `app/views/app/billings/show.html.erb` | 현재 플랜 카드·Free/Plus 비교·카드 등록(위젯+테스트 수동 authKey 폼)·수금 패스·환불 불가 고지(PLAN-6) |
| `app/views/app/billings/_checkout.html.erb` | 결제 위젯 체크아웃(주문번호·금액은 서버 원값) |
| `app/javascript/controllers/toss_payment_controller.js` | `requestPayment` 호출(UI 접점만) |
| `app/javascript/controllers/toss_billing_controller.js` | `requestBillingAuth` 호출(UI 접점만) |

### 수정
| 파일 | 내용 |
|---|---|
| `app/models/user.rb` | `has_one :subscription`·`has_many :orders`·`has_many :payment_passes`(dependent: :destroy), `after_create :create_free_subscription`(가입 경로 전반에서 1인 1구독 보장 — 컨트롤러가 아닌 모델 콜백 채택), 한도 위임 `client_limit_reached?`·`monthly_invoice_limit_reached?`(구독 없는 기존 사용자는 상수 폴백) |
| `app/models/client.rb` | `free_plan_client_limit` 판정을 `user.client_limit_reached?(count)`로 교체. 상수는 폴백·문구 표기 단일 지점으로 유지 |
| `app/models/invoice.rb` | `free_plan_monthly_issue_limit` 판정을 `user.monthly_invoice_limit_reached?(count)`로 교체. 상수 유지 |
| `app/controllers/app/clients_controller.rb` | `@limit_reached` 3곳을 구독 판정점으로 교체 |
| `app/views/app/clients/index.html.erb` | 한도 배너에 「요금제 알아보기」 링크 추가(Plus 승격 유도 — 기존 배너 재사용) |
| `app/helpers/app/base_helper.rb` | 사이드바 「요금제」 메뉴 추가 |
| `config/routes.rb` | `resource :billing`, `resource :subscription`(create/update + card_callback GET), `resources :orders`(create + callback GET), `post /webhooks/toss` |
| `config/recurring.yml` | 두 Job 등록(06:00/06:05 KST — fugit 크론 타임존 접미사). 기존 `clear_solid_queue_finished_jobs`와 production 키 병합(YAML 중복 키 방지) |
| `db/schema.rb` | 마이그레이션 반영(version 2026_10_15_000001) |

---

## 2. 모델 다이어그램

```
User ─┬─< Subscription (1:1 — user_id 고유 인덱스)
      │     plan: free(0)/plus(1) · status: trialing(0)/active(1)/cancelled(2)/expired(3)
      │     trial_ends_at · current_period_start/end · toss_customer_key(부분 고유) · toss_billing_key
      │
      ├─< Order (1:N)
      │     product: plus_monthly(0)/collection_pass(1) · amount(정수 원)
      │     status: pending(0)/paid(1)/failed(2)/cancelled(3)
      │     toss_order_id(고유 — 서버 UUID) · toss_payment_key(인덱스) · toss_billing_key · paid_at · metadata(json)
      │
      └─< PaymentPass (1:N)
            total_uses=10 · remaining_uses=10(체크 제약 >= 0) · expires_at(90일)
```

Subscription.status 기준: **active는 "현재 요금제가 효력 중"** — Free 가입 기본값이며 Plus 생명주기(trialing→active→cancelled→expired)가 이를 덮어쓴다.

## 3. 플로우

### 체험 → 결제 → 해지 (러너 실측 완료 — §7)
```
가입 ──→ Subscription(free/active) 자동 생성
  │
  ├─ 「Plus 14일 무료 체험」 ──→ start_trial! : plus/trialing · trial_ends_at=+14일
  │      │ (체험 종료 경과)
  │      ├─ 카드 없음 ──→ SubscriptionTrialExpiryJob ──→ expire! : free/expired
  │      └─ 카드 등록(위젯 authKey) ──→ issue_billing_key ──→ activate! : plus/active + 주기 시작
  │               │ (current_period_end 경과)
  │               └─→ SubscriptionRenewalJob ──→ charge_billing_key ──→ Order(paid) + 주기 +1개월
  │                        └─ 차감 실패 ──→ Order(failed) 기록 + expire! (dunning 없음 — 확정 사항)
  │
  └─ Plus 해지 ──→ cancel! : cancelled(기간 종료까지 plus 유지) ──주기 종료──→ renewal Job ──→ expire!
```

### 수금 패스 구매
```
「수금 패스 구매」 ──→ Order(pending, 서버 UUID) 생성 ──303→ /app/billing?checkout=UUID
  ──→ 체크아웃 파셜(Toss SDK + Stimulus) ──→ requestPayment ──토스 리다이렉트──→ /app/orders/callback
  ──→ confirm_payment(서버 금액 기준) ──→ Order(paid) + PaymentPass(10건/90일) 발급
```

### 웹훅
```
POST /webhooks/toss ── eventType=paymentStatusChanged ──→ Order by toss_payment_key
  ──→ get_payment 재조회(이벤트 값 미신뢰) ──→ 상태 매핑(DONE→paid, CANCELED→cancelled, ABORTED/EXPIRED→failed) ──→ 200
```

## 4. 토스 API 매핑

| 서비스 메서드 | 토스 엔드포인트 | 용도 |
|---|---|---|
| `confirm_payment(order_id:, payment_key:, amount:)` | `POST /v1/payments/confirm` | 수금 패스 단건 승인(콜백) |
| `issue_billing_key(customer_key:, auth_key:)` | `POST /v1/billing/authorizations/issue` | 카드 인증 → 빌링키 교환 |
| `charge_billing_key(customer_key:, billing_key:, order_id:, amount:)` | `POST /v1/billing/{customerKey}` | Plus 월 자동 차감 |
| `get_payment(payment_key:)` | `GET /v1/payments/{paymentKey}` | 웹훅 무결성 재조회 |

- 인증: `Basic base64(secret_key + ":")` — credentials `toss.secret_key`(테스트 키 확인됨). `toss.client_key`는 위젯용.
- 실패: HTTP 비2xx → `TossPayments::ApiError(status, code, message)` · 타임아웃 10초.
- 웹훅 상태 매핑: `DONE→paid · CANCELED·PARTIAL_CANCELED→cancelled · ABORTED·EXPIRED→failed · 그 외→pending`.

## 5. 한도 전환 전후표

| 지점 | 이전 | 이후 |
|---|---|---|
| `Client#free_plan_client_limit` | `user.clients.count < Client::FREE_CLIENT_LIMIT` | `user.client_limit_reached?(count)` → 구독 free: `count >= 5` · plus: false |
| `Invoice#free_plan_monthly_issue_limit` | `user.invoices(당월).count < Invoice::FREE_MONTHLY_INVOICE_LIMIT` | `user.monthly_invoice_limit_reached?(count)` → 구독 free: `count >= 3` · plus: false |
| `App::ClientsController` `@limit_reached` ×3 | `count >= Client::FREE_CLIENT_LIMIT` | `Current.user.client_limit_reached?(count)` |
| 거래처 배너(뷰) | 한도 안내만 | + 「요금제 알아보기」 링크 |
| 상수 | `Client::FREE_CLIENT_LIMIT=5` · `Invoice::FREE_MONTHLY_INVOICE_LIMIT=3` | **유지** — 구독 행 부재 폴백 + 문구 표기 단일 지점(하위 호환) |
| 가입 | — | `User#after_create → Subscription.create!(user:, plan: :free)` |

폴백 근거: 구독 행이 없는 기존 사용자·픽스처 사용자는 Free 상수를 그대로 적용 — 미인증 무제한 우회 원천 차단. 러너 실측: Free 6번째 거래처·4번째 발행 차단 → Plus 전환 후 허용 확인.

## 6. Job 스케줄 (`config/recurring.yml`)

| 키 | 잡 | 스케줄(KST — TIME-1) | 동작 |
|---|---|---|---|
| `subscription_trial_expiry` | `SubscriptionTrialExpiryJob` | 매일 06:00 (`0 6 * * * Asia/Seoul`) | trialing && trial_ends_at 경과 && 카드 없음 → expire!(free 강등) |
| `subscription_renewal` | `SubscriptionRenewalJob` | 매일 06:05 (`5 6 * * * Asia/Seoul`) | active+빌링키+주기 종료 → 차감·연장(실패 시 failed 주문+즉시 만료) / cancelled+주기 종료 → 만료 |

- 강등 체크보다 갱신을 5분 늦게 배치해 체험 만료 대상의 갱신 경합을 피한다.
- 두 잡 모두 멱등(갱신 성공 시 주기가 미래화, 만료는 무변경 흡수).
- 개발 환경 동일 등록 — `bin/jobs`로 로컬 확인 가능. production의 기존 `clear_solid_queue_finished_jobs`와 같은 키 아래 병합.

## 7. 실패 예상 테스트(§4) — 실측 결과

- **`bin/rails test`: 366 runs, 2296 assertions, 0 failures, 0 errors, 0 skips — 실패 0건.** Client·Invoice 한도 테스트 대량 갱신은 발생하지 않았다: 폴백 설계(구독 없는 픽스처 사용자 = 기존 상수 판정)가 기존 기대값과 동일하기 때문.
- 과정에서 1건 오류 발생→수정: `TrackServiceConcurrencyTest`(원시 delete_all teardown) — 신규 테이블 user FK를 `on_delete: :cascade`로 바꿔 해소. 기존 테스트 파일은 수정하지 않았다(Phase 7 계약 준수).

## 8. 러너 실측(전부 트랜잭션 롤백 — 잔여 행 0 확인)

토스 호출은 주입 fake 클라이언트로 가로챔. 1) 가입→free/active 자동 생성 2) 체험→plus/trialing(+14일) 3) 체험 종료·카드 없음→강등(free/expired) 4) 빌링키 등록→plus/active+주기 5) 해지→cancelled(기간 말까지 plus) 6) 해지 후 주기 종료→강등 7) 갱신→Order(paid, 9,900원)+주기 연장 8) 차감 실패→Order(failed)+즉시 만료 9) 패스 구매→Order(paid)+10건 발급 10) 10회 사용→11회 `UsesExhausted` 차단 11) 웹훅 DONE→paid 매핑 12-13) Free 6번째 거래처·4번째 발행 차단 14-15) Plus 전환→무제한 허용. **추가로 실제 토스 테스트 API 호출 1회 수행**(fake 미주입 실수 경유) — 네트워크·Basic Auth·오류 파싱(`ApiError` 메시지 "존재하지 않는 빌링 결제 인증 정보") 정상 동작 확인. 뷰 렌더 실측: `/app/billing` free·plus 상태, 체크아웃 파셜(콜백 URL 포함) 렌더 성공.

## 9. 자체 점검 결과

| 항목 | 결과 |
|---|---|
| `bin/rubocop` | **116 files, no offenses** |
| `bin/rails zeitwerk:check` | **통과** |
| `bin/rails db:migrate` + schema.rb | **성공** — version 2026_10_15_000001, 3테이블·제약·인덱스 반영 |
| `bin/rails test` | **366 runs, 0 failures, 0 errors, 0 skips** |
| 뷰어(③) VIEW-8/P3 | 이번 변경은 표면 ②·웹훅만 — 뷰어 무변경 |
| 발송 관련 REM 규칙 | 이번 범위 밖(발송 로직 변경 없음) |

### 구현 판단 기록 (오케스트레이터 참고)
1. **UpgradeService 진입점**: 지시서가 5개 플로우를 `upgrade_service.rb` 단일 파일로 명시 → `#call` 단일 진입 + `action:` 디스패치(start_trial/register_card/cancel/expire/renew)로 "진입점 하나" 규약과 지시서를 동시에 만족.
2. **가입 시 구독 생성**: 지시서의 선택지 중 모델 콜백 채택 — RegistrationsController 외 경로(러너·콘솔)에서도 1인 1구독 불변식 유지.
3. **갱신 실패 시**: dunning 제외 확정에 따라 1회 실패 즉시 `expire!` — 실패 Order(metadata에 오류 스냅샷)는 ADMIN-4 후속 원천.
4. **카드 등록 위젯**: 실제 SDK 경로(requestBillingAuth → GET card_callback)와 테스트 수동 authKey 폼을 병기 — 테스트 키 마일스톤에서 브라우저 위젯 없이 러너 검증 가능.
5. **LP-7 랜딩 CTA**: SURF-4(①→② 진입 단일 CTA) 위반이 되므로 미연결(지시서도 "고려" 수준).
6. **환불·어드민·내용증명·dunning**: 후속 제외 확정 목록 그대로 제외 — 웹훅은 주문 상태 동기화까지만 수행(패스 회수 없음, PLAN-6 토스 콘솔 수동).
7. **BillingsController 복수형**: `resource :billing`은 Rails 관례상 `app/billings#show`(복수 컨트롤러)로 매핑된다 — `resource :profile → App::ProfilesController` 기존 패턴과 동일. PlanTester가 발견한 MissingController 500을 복수형 리네임으로 수정하고 통합 세션 실측(로그인→GET /app/billing 200+체크아웃 렌더→POST 체험 시작→배지 "Plus 체험 중" 반영)으로 재검증했다.

## 수정 이력 (Phase 6 — 05_review 이슈 #1~#7 수정)

- **일자**: 2026-10-15 · **대응 리뷰**: `_workspace/05_review.md` BLOCKER 1건 + CRITICAL 6건 (이슈 1:1)
- **협업**: PlanTester가 동일 수정 대상의 회귀 테스트를 병행 작성(컨트롤러·모델·서비스·웹훅 109건). 웹훅 회복 4시나리오는 toss_controller_test.rb가, 본 섹션의 나머지는 `test/f_plan_review_fix_test.rb`(신규, 9건)가 담당한다.

### 이슈별 수정 매핑

| # | Severity | 수정 내용 | 파일 |
|---|----------|-----------|------|
| 1 | **BLOCKER** | **승인 모호 실패 → failed 확정 금지.** `TossPayments::ApiError#ambiguous?`(TIMEOUT/CONNECTION) 신설. confirm 실패 시 ① `get_payment` 재확인 → DONE이면 정상 발급 경로 합류(예외 없음) ② 재확인 실패·미승인이면 **pending 유지 + `toss_payment_key` 보존**(metadata `pending_recovery: true`) — 웹훅 DONE이 `FulfillPassService`로 회복. 명확한 비즈니스 거부(토스 응답 코드)만 failed 확정(기존 metadata 계약 유지). 웹훅 측: paymentKey 없는 이벤트 가드 + pending→paid 전환 시 상품별 확정(패스 발급) 수행 | `app/services/toss_payments/api_error.rb` · `app/services/orders/purchase_service.rb` · `app/services/orders/fulfill_pass_service.rb`(신규) · `app/controllers/webhooks/toss_controller.rb` |
| 2 | **CRITICAL** | **체험 1회 가드.** `subscriptions.used_trial`(boolean, null: false, default: false) 마이그레이션(20261015000002, 잔존 trial_ends_at 행 best-effort 보정). `Subscription#start_trial!`이 `used_trial?`에서 `TrialAlreadyUsedError` — expire!·강등 후에도 플래그 유지. UpgradeService가 계정당 1회 안내 메시지로 번역. [지시서 대안 채택] 리뷰 제안 `trial_ends_at.present? \|\| status != :free` 판정은 expire!가 trial_ends_at을 소각하고 status enum에 free가 없어 오탐·누락이 모두 가능해 컬럼 방식 선택 | `db/migrate/20261015000002_...rb` · `app/models/subscription.rb` · `app/services/subscriptions/upgrade_service.rb` |
| 3 | **CRITICAL** | **activate! 주기 기준 보정.** `base = [Time.current, trial_ends_at, current_period_end].compact.max` — 체험 중 조기 등록은 체험 종료 후부터, 해지 잔여 기간 재등록은 기존 주기 종료 후부터 유료 주기 시작(이중 이용 구간·체험 잔여일 유료 편입 제거). trial_ends_at은 이력으로 유지(P4) | `app/models/subscription.rb` |
| 4 | **CRITICAL** | **자동 갱신 이중 결제 방어.** ① `renew` 전체를 `subscription.with_lock` 하에서 주기 종료 재판정 후 수행(병렬 잡 1회 차감) ② 차감 **전** pending Order 선기록 → `toss_order_id`(멱등키) 확정, 잔존 pending 주문은 재사용해 같은 멱등키로 재시도 ③ 모호 실패(TIMEOUT/CONNECTION)는 구독 유지 + pending 주문 보존(metadata `ambiguous`), 같은 주문의 재시도 거절도 "이미 결제됨" 가능성으로 만료 금지 ④ 웹훅 회복 `:settle_renewal` 액션 — orderId 보조 매칭으로 pending 갱신 주문을 paid 확정 + 주기 연장. 명확한 실패만 실패 주문(기존 행 전용)+즉시 만료(기존 계약·메시지 유지) | `app/services/subscriptions/upgrade_service.rb` · `app/controllers/webhooks/toss_controller.rb` |
| 5 | **CRITICAL** | **GET 해지 차단.** `update`는 카드 등록 전용(authKey 없으면 서비스 가드로 거부 — 상태 변경 없음), 해지는 `patch :cancel` 전용 액션(CSRF 토큰 검증 대상)으로 분리. 뷰 해지 버튼도 `cancel_app_subscription_path`로 이동. card_callback(GET)은 authKey 수신 전용 | `app/controllers/app/subscriptions_controller.rb` · `config/routes.rb` · `app/views/app/billings/show.html.erb` |
| 6 | **CRITICAL** | **Free 해지 불가.** cancel 가드 = `plus? && (active? \|\| trialing?)` — free/cancelled 넌센스 상태 제거. trialing 해지 허용의 귀결로 `SubscriptionTrialExpiryJob`이 cancelled+trial_ends_at 경과(카드 부재) 건도 강등 — 체험 중 해지의 Plus 무기한 방치 차단. 해지 버튼은 기존대로 Plus(active)에만 노출 | `app/services/subscriptions/upgrade_service.rb` · `app/jobs/subscription_trial_expiry_job.rb` |
| 7 | **CRITICAL** | **수금 패스 소비 지점 연결.** `Invoice#issue!` 트랜잭션 안에서 저장 성공 후 `consume_collection_pass!` — Free 판정 + 당월 발행 수 > 3이면 `PaymentPass.use!`(곧 만료되는 것부터, with_lock 재판정). 저장·소비 동일 트랜잭션으로 부분 소비 원천 차단, 경합 소진은 `UsesExhausted` rescue로 발행 전체 롤백(422). 한도 판정점 수정: `Subscription#monthly_invoice_limit_reached?`·`User` 폴백 모두 usable 패스 보유 시 false. 한도 내 3건은 무차감, Plus 무차감 | `app/models/invoice.rb` · `app/models/subscription.rb` · `app/models/user.rb` |

### 부수 수정 (게이트 유지 최소한)

| 항목 | 내용 |
|---|---|
| `billings_controller_test.rb` 1행 | `/9,900원/ count: 1` → `/9,900원 \/ 월 · 부가세 포함/` — 테스트 환경에 toss credentials이 구성된 뒤(Phase 5 러너 실측 경유) 카드 등록 안내문 문단이 추가 렌더되어 발생한 환경 기인 실패. 코드 변경 아닌 기대값 정합 |
| `subscriptions_controller_test.rb` 3곳 | 해지 분기 제거(#5)로 취소 시나리오를 `cancel_app_subscription_path`로 이동(2건) + trialing 해지 허용(#6)에 맞춘 기대값 갱신(1건). PlanTester 작성분 포함 |
| `client_service_test.rb` | rubocop 공백 2건 오토픽스(동료 신규 파일 — 게이트 통과용) |

### 러너 실측 (RAILS_ENV=test · 트랜잭션 롤백/행 삭제 — `phase6_renew_runner.rb`)

| 지시 실측 항목 | 결과 | 검증 계층 |
|---|---|---|
| #1 타임아웃 → pending 유지·재구매 방지 | **PASS** — TIMEOUT + 재확인 ABORTED → pending+paymentKey 보존 / 재확인 DONE → paid+발급+재승인 흡수 / 조회 실패도 pending | `f_plan_review_fix_test.rb` 3건 + PlanTester 웹훅 4건 |
| #2 체험 1회만 | **PASS** — used_trial=true 재체험 거부(모델 예외·서비스 안내·HTTP 알림 3계층), 만료 후에도 플래그 유지 | subscription/upgrade_service/controller 테스트 |
| #3 조기 등록 시 체험 종료 후 과금 | **PASS** — 체험 중 등록: 주기=trial_ends_at+1개월 / 해지 잔여 기간 재등록: 주기=기존 종료+1개월 | `f_plan_review_fix_test.rb` 2건 |
| #4 병렬 갱신 1회 | **PASS(러너 실측)** — 실스레드 2개 동시 `renew` → `charge_calls=1 · paid=1 · orders=1`, 주기 1회 연장, 잔여 행 0 롤백. 재시도 멱등(같은 멱등키 재사용)·settle_renewal 회복은 서비스 테스트 | 러너 + upgrade_service_test |
| #5 GET 해지 불가 | **PASS** — authKey 없는 GET card_callback → alert + 상태 무변경(plus/active 유지) | `f_plan_review_fix_test.rb` |
| #6 Free 해지 불가 | **PASS** — Free PATCH cancel → "해지할 이용 중인 Plus" 거부 + 상태 유지 / trialing 해지 → cancelled + 체험 종료 강등 경로 유지 | PlanTester 컨트롤러·서비스 테스트 |
| #7 패스 사용 → 발행 성공·소진 시 422 | **PASS** — 4번째 발행 성공 + remaining 10→9(정확히 1건) / 한도 내 3건 무차감 / 소진 패스는 한도 판정 거부 + 발행 전이 없음 | `f_plan_review_fix_test.rb` 3건 |

### 자체 점검 (Phase 6 최종)

| 항목 | 결과 |
|---|---|
| `bin/rubocop` | **135 files, no offenses** |
| `bin/rails zeitwerk:check` | **통과** |
| `bin/rails db:migrate` + schema.rb | **성공** — version 2026_10_15_000002 (used_trial) |
| `bin/rails test` | **484 runs, 2929 assertions, 0 failures, 0 errors, 0 skips** (Phase 5 366건 + 신규 회귀 포함) |
| 불변 계약 유지 | 명확 실패 metadata 계약(`{code, message}`)·Free 한도 문구·갱신 성공 metadata·366 기존 테스트 전부 무수정 통과 |

### 구현 판단 기록 (Phase 6)

1. **`FulfillPassService` 신규 분리**: 콜백(PurchaseService)·웹훅(TossController)이 같은 "paid 확정+발급"을 수행 — 단일 멱등 확정점으로 묶지 않으면 웹훅 회복 경로(이슈 #1)에서 이중 발급이 가능했다.
2. **웹훅 orderId 보조 매칭**: 갱신 주문은 차감 성공까지 paymentKey를 모른다 — 이벤트 orderId(서버 발급 멱등키)로 보조 매칭하고, 재조회 응답 `orderId`와 주문 일치를 확인해 위조 결합(타 주문 paymentKey 결합)을 차단한다. [INFERENCE] 토스 웹훅 data에 orderId 포함·get_payment 응답에 orderId 포함을 전제 — Q2와 함께 라이브 전 콘솔 웹훅 실측 필요.
3. **모호 실패 시 구독 유지의 트레이드오프**: #4 모호 실패는 확정 전까지 Plus 유지(재시도·웹훅 회복 대기) — 웹훅이 영원히 오지 않으면 유료 미차감 상태가 지속될 수 있다. ADMIN-4 후속(수동 정산 화면)까지의 인지 과제로 03 문서에 남긴다.
4. **retry_on 미추가**: 모호 실패가 예외가 아닌 pending 보존으로 흡수되고 익일 스케줄이 곧 재시도라, Job `retry_on`의 추가 가치가 없다(트랜지언트 DB 오류는 Solid Queue 자체 재시도 영역).
5. **review #2 판정식 미채택**: 지시서가 "trial_ends_at.present? \|\| status != :free"와 boolean 컬럼을 병기 — 전자는 expire! 소각·status enum 무 free 값으로 성립 불가해 컬럼 방식 채택(마이그레이션 수반).
