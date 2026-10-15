# 01_plan.md — F-PLAN 구독·과금 (토스페이먼츠 테스트 키)

- **일자**: 2026-10-15
- **pipelineType**: Full — 신규 도메인(Subscription·Order)·마이그레이션·외부 API(토스)·과금 UI
- **도메인**: F-PLAN (§6.10 PLAN-1~8) + 토스페이먼츠 코어 API

## A. 모델·마이그레이션

### Subscription
- `user_id`(FK·고유 — 1人1구독), `plan` enum(free/plus), `status` enum(trialing/active/cancelled/expired)
- `trial_ends_at`(Plus 체험 종료), `current_period_start`·`current_period_end`(과금 주기)
- `toss_customer_key`(토스 고객 식별자 — billing key 발급용)
- **한도 체크 전환점**: 기존 상수(`FREE_CLIENT_LIMIT`·`FREE_MONTHLY_INVOICE_LIMIT`) → `Subscription#limit_reached?`(거래처/청구 각각) — Free만 상수값, Plus는 무제한. **with_lock** 으로 동시 업그레이드 방어

### Order
- `user_id`(FK), `product` enum(plus_monthly/collection_pass), `amount`(integer 원)
- `status` enum(pending/paid/failed/cancelled), `toss_order_id`(고유 — 우리 생성), `toss_payment_key`, `toss_billing_key`
- `paid_at`, `metadata`(json — 토스 응답 스냅샷)

### PaymentPass
- `user_id`(FK), `total_uses`(10), `remaining_uses`, `expires_at`(90일) — PLAN-4
- 사용 차감: 발행 시 `remaining_uses -= 1`·0이면 만료 — **with_lock**(동시 발행 방어)

## B. 토스페이먼츠 래퍼 (Service — 외부 API 캡슐화)

### `TossPayments::ClientService`
- Base URL: `https://api.tosspayments.com/v1` (테스트)
- 인증: `Rails.application.credentials.dig(:toss, :secret_key)` Basic Auth
- 메서드:
  - `confirm_payment(order_id:, payment_key:, amount:)` — 단건 결제 승인
  - `issue_billing_key(customer_key:, auth_key:)` — 빌링키 발급
  - `charge_billing_key(customer_key:, billing_key:, order_id:, amount:)` — 정기결제 차감
  - `get_payment(payment_key:)` — 결제 조회
- 에러: `TossPayments::ApiError`(status·code·message) — 컨트롤러 rescue

## C. 구독 플로우

### Plus 시작 (체험 → 결제)
1. 「Plus 시작하기(14일 무료)」 → `Subscription#create_plus_trial` → `trialing` + 14일 후 `trial_ends_at`
2. 체험 종료 전 카드 등록: 랜딩 위젯(Toss Payments JavaScript SDK) → `authKey` → 서버에서 `issue_billing_key` → `toss_billing_key` 저장
3. **자동 갱신**: 결제일에 `charge_billing_key` → Order(paid) 생성 → 주기 연장 — 이번엔 **Job 스케줄러 등록**(recurring.yml — Solid Queue)
4. 체험 종료 시 카드 없으면 → `expired` → Free로 자동 강등

### Plus 해지
- `cancelled` — 기간 종료까지 이용 가능(PLAN-2). 종료 시 Free 강등
- 재가입: 새로운 체험 아님(기존 결제로 즉시 active)

### 수금 패스 (일회성 구매)
- Toss 결제 위젯 → redirect 콜백 → `confirm_payment` → Order(paid) + PaymentPass(10건·90일) 생성

## D. 웹훅 (PLAN-5)

- `POST /webhooks/toss` — 토스에서 결제 상태 변경 이벤트 수신
- `paymentStatusChanged` 이벤트: Order status 업데이트( paid → cancelled/refunded 등)
- 인증: 토스 서명 헤더 검증 또는 payment_key 재조회로 무결성 확인

## E. 화면 (표면 ②)

- `/app/billing` — 요금제 페이지: 현재 플랜 표시·Plus 시작/해지·카드 등록 상태
- `/app/billing/payment/callback` — 토스 결제 redirect 수신(성공/실패 분기)
- 사이드바 「요금제」 메뉴 추가

## F. 한도 전환 (기존 상수 → 구독 체크)

- `Client` 모델: `FREE_CLIENT_LIMIT` → `Subscription#client_limit_reached?` (Free: 5·Plus: 무제한)
- `Invoice` 모델: `FREE_MONTHLY_INVOICE_LIMIT` → `Subscription#monthly_invoice_limit_reached?` (Free: 3·Plus: 무제한)
- **Free 한도 초과 시 Plus 업그레이드 안내 표시**(기존 배너 재사용)

## 후속 제외

- 자동 갱신 실패 재시도(dunning) — 1차 결제 실패 시 즉시 expired
- 내용증명 건당 과금(LEGAL-2 — F-LEGAL 후속)
- 환불 처리(PLAN-6 — 정책만, 토스 콘솔에서 수동)
- 어드민 결제 관리 화면(ADMIN-4 — F-ADMIN 후속)

## 관련 Rule ID

PLAN-1(한도 전환), PLAN-2(Plus 9,900원·14일), PLAN-3(5통 — 기존 유지), PLAN-4(수금 패스), PLAN-5(토스·웹훅), PLAN-6(환불 불가 고지), SEC(빌링키 저장 암호화·웹훅 검증)

## 결정 사항 (제안)

1. **빌링키 저장**: DB 평문 저장(내부 시스템·테스트 키) — 프로덕션 라이브 전환 시 암호화 검토
2. **체험 종료 강등**: Job(매일 체크) — `trial_ends_at < 오늘 && 카드없음` → expired + Free
3. **자동 갱신**: 매월 1일 결제일 Job — 체험/활성 구독 중 `current_period_end < 오늘` → 빌링키 차감 시도
4. **Free 사용자 첫 가입 시**: Subscription(free) 자동 생성(가입 시점)

## 리스크

- 토스 테스트 API 실측 — 결제 위젯 리다이렉트·웹훅 로컬 검증 한계(서버 URL 필요하나 테스트 환경에서는 생략 가능)
- 빌링키 발급 플로우가 브라우저 의존(Toss SDK) — 시스템 테스트 범위 제한
- 기존 한도 상수 전환 시 기존 테스트 대량 갱신 예상
