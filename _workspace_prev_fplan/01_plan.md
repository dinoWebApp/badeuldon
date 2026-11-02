# 01_plan.md — 토스 → 포트원(KG이니시스) 전환

- **일자**: 2026-10-15
- **pipelineType**: Full — 래퍼 재작성·서비스·웹훅·UI SDK 교체
- **도메인**: F-PLAN(§6.10 PLAN-5 결제 연동 교체)

## 변경 개요

기존 토스 래퍼 패턴을 유지하면서 결제 게이트웨이 계층만 포트원으로 교체. **모델(Subscription·Order·PaymentPass)은 무변경**.

## A. PortOne::ClientService (신규 — 토스 래퍼 대체)

### 인증·공통
- Base URL: `https://api.portone.io`
- `Authorization: PortOne {api_secret}` — credentials `portone.api_secret`
- 모든 요청에 `storeId` 포함 — credentials `portone.store_id`
- `Idempotency-Key` 헤더 — UUID (POST 요청)
- 타임아웃: 60초 (포트원 권장)

### 메서드 (기존 TossPayments 대응)

| 기존 (Toss) | 신규 (PortOne) | 엔드포인트 |
|:---|:---|:---|
| `confirm_payment(order_id, payment_key, amount)` | `confirm_payment(payment_id:, payment_token:)` | `POST /payments/{paymentId}/confirm` |
| `issue_billing_key(customer_key, auth_key)` | `issue_billing_key(customer_id:, channel_key:, issue_token:)` | `POST /billing-keys/confirm` |
| `charge_billing_key(customer_key, billing_key, order_id, amount)` | `charge_billing_key(payment_id:, billing_key:, channel_key:, amount:, customer_id:)` | `POST /payments/{paymentId}/billing-key` |
| `get_payment(payment_key)` | `get_payment(payment_id)` | `GET /payments/{paymentId}` |
| — | `cancel_payment(payment_id:, reason:)` | `POST /payments/{paymentId}/cancel` |

### 채널 키 구분
- `channel_key_normal` — 수금 패스 단건 결제 (INIpayTest)
- `channel_key_billing` — Plus 구독 빌링키 발급·차감 (INIBillTst)

## B. Services 갱신

### `Subscriptions::UpgradeService`
- `TossPayments::ClientService` → `PortOne::ClientService`
- 빌링키 발급: `issue_billing_key(channel_key: channel_key_billing, ...)`
- 갱신 차감: `charge_billing_key(channel_key: channel_key_billing, ...)`
- 응답 필드 매핑: 토스 `paymentKey` → 포트원 `paymentId` (우리 order_id)

### `Orders::PurchaseService`·`FulfillPassService`
- `confirm_payment` 호출부: `channel_key_normal` 사용
- 응답 필드 매핑

## C. 웹훅 (신규 — 포트원 전용)

### `Webhooks::PortOneController` (신규)
- `POST /webhooks/portone` — 비인증·CSRF 면제
- 이벤트 타입: `TransactionConfirmed`·`TransactionCancelled`·`TransactionFailed`
- 무결성: 이벤트 값 미신뢰 → `get_payment(payment_id)` 재조회로 확정
- 기존 `Webhooks::TossController`는 **삭제** (더 이상 토스 웹훅 수신 불필요)

## D. 빌링 UI (JavaScript)

### Toss SDK 제거 → PortOne SDK
- 기존: `<script src="https://js.tosspayments.com/v1/payment">` + `toss_billing_controller.js`·`toss_payment_controller.js`
- 신규: `<script src="https://cdn.portone.io/v2/browser-sdk.js">` + `portone_billing_controller.js`·`portone_payment_controller.js`
- 결제 위젯 초기화 파라미터: `storeId`·`channelKey`·`paymentId`
- 콜백: 포트원 SDK는 `issueToken` 반환 → 서버로 전달 → 빌링키 발급

## E. 정리 (토스 코드 제거)

| 제거 대상 | 이유 |
|:---|:---|
| `app/services/toss_payments/` 전체 | 포트원 래퍼로 대체 |
| `app/controllers/webhooks/toss_controller.rb` | 포트원 웹훅으로 대체 |
| `app/javascript/controllers/toss_*.js` | 포트원 컨트롤러로 대체 |
| `POST /webhooks/toss` 라우트 | 포트원 라우트로 대체 |

## 후속 제외
- 토스 credentials 키 제거 (라이브 전환 확정 시)
- 포트원 SDK 브라우저 실측 (배포 후 브라우저에서 확인)
- 어드민 결제 관리 (F-ADMIN)

## 결정 사항 (제안)

1. **기존 Order.toss_payment_key 필드**: 컬럼명 유지(`toss_payment_key`→의미상 포트원 paymentId 저장 — 컬럼명 변경은 마이그레이션 불필요, `payment_key`로 별칭)
2. **토스 즉시 삭제**: 코드 정리(래퍼·웹훅·JS) — 크린 컷오버
3. **빌링키 발급 플로우**: 포트원 SDK의 `issueToken` 방식 채택 (브라우저에서 카드 인증 → 토큰 → 서버 발급)

## 리스크

- 포트원 테스트 환경에서 빌링키 발급이 API로 가능한지 확인 필요 — 테스트 채널(INIBillTst)은 API 키 발급 방식 확인
- 웹훅 이벤트 실측 필요 (배포 후 실제 이벤트 확인)
- 포트원 SDK 초기화 파라미터 정확성 — 브라우저 배포 후 확인
