# 08_run_report — 포트원 채널 키 환경 분리 + 결제 확정 검증 (PLAN-5)

2026-11-25 14:55~15:40 KST(문서·소스 수정 시각 기준 — 처음 적은 "18:20~19:20"은 오기) · 오케스트레이터 직접 수행 · 로컬 macOS(arm64) · Ruby 4.0.10 · Rails 8.1.4.1 · Puma 8.1.2 · 미커밋 작업 트리

## 결론

| 항목 | 결과 |
|:---|:---|
| `bin/rails db:prepare` | 정상 (마이그레이션 없음) |
| 앱 부팅 | **성공** — "Rails 8.1.4.1 application starting in development"·Puma 3100 포트 리스닝·부팅 로그에 FATAL/ERROR/DEPRECATION 0건 |
| 주요 경로 응답 | 아래 표 — 500 없음, 예외 0건 |
| 웹훅(`/webhooks/portone`) | 모르는 결제 ID·빈 본문·알 수 없는 type 전부 200 흡수, 포트원 호출 0건 |
| 개발 환경 선택기 | 테스트 채널 키 2개 선택(라이브 키와 다른 값), 검증기 기대값 TEST·KRW |
| 운영 환경 설정 평가 | 라이브 채널 키 2개 선택(테스트 키와 다른 값), 검증기 기대값 LIVE |
| 전체 테스트(직접 재실행) | **1,664 runs · 10,553 assertions · 0 failures · 0 errors** (마지막 반영 F-1~F-4 뒤 최종 수치 — 1,656 → +8) |
| 시스템 테스트(직접 재실행) | 15 runs · 135 assertions · 0 failures |
| RuboCop·zeitwerk·Brakeman | 430파일 0 offenses · 통과 · Errors 0·Security Warnings 0 |
| 외부 API 실호출 | **0건** |

## 요청 응답 (미로그인, `bin/rails server -p 3100`)

| 요청 | 응답 | 판정 |
|:---|:---|:---|
| `GET /` | 200 | 정상 |
| `GET /app/billing` | 302 → `/session/new` | 로그인 가드 정상 (채널 키를 담는 화면) |
| `GET /app/legal_documents/new`·`/app/tax_invoices/new` | 302 → `/session/new` | 로그인 가드 정상 |
| `GET /admin/session/new` | 200 | 정상 |
| `POST /webhooks/portone` `Transaction.Paid` (모르는 paymentId) | 200 | 흡수 — 주문 미발견이라 재조회 전에 종료(포트원 미호출) |
| `POST /webhooks/portone` 빈 본문 | 200 | `JSON::ParserError` 흡수 |
| `POST /webhooks/portone` 알 수 없는 type | 200 | 비동기 대상 아님 — 흡수 |

`log/development.log` 해당 구간: `Completed 200` 6건·`Completed 302` 3건, 500·FATAL·RoutingError·NoMethodError 0건.

## 환경별 선택기·검증기 평가 (runner, 키 값은 출력하지 않고 credentials 항목과의 일치만 확인)

| 평가 | `live_channel?` | `.billing` | `.normal` | 검증기 기대 채널·통화 |
|:---|:---|:---|:---|:---|
| development (작업 트리 credentials) | false | `channel_key_billing_test`와 동일·라이브 키와 다름 | `channel_key_normal_test`와 동일·라이브 키와 다름 | TEST·KRW |
| production 환경 설정(`RAILS_ENV=production`, 로컬 평가) | true | `channel_key_billing`(라이브)와 동일·테스트 키와 다름 | `channel_key_normal`(라이브)와 동일·테스트 키와 다름 | LIVE |

검증기 동작(개발 환경 기대값): `amount.paid 4000`·`channel.type TEST`·`currency KRW`인 결제 건은 통과, `channel.type LIVE`인 결제 건은 `channel_mismatch`로 거절 — 환경 분리가 확정점에도 적용됨.

## 최종 재확인 (마감 리뷰 WARNING F-1~F-4 반영 뒤 — 주문 생성 3곳에 재주문 차단 가드 추가)

- 서버 재기동 정상(부팅 로그 FATAL/ERROR 0건). `GET /` 200, `GET /app/billing`·`/app/legal_documents/new`·`/app/tax_invoices/new` 302 → 로그인.
- `POST /app/legal_documents`·`/app/tax_invoices`·`/app/orders`(미로그인·CSRF 토큰 없음) → 422 — **CSRF 검증이 액션 실행 전에 차단한 기존 동작**(개발 로그: "Can't verify CSRF token authenticity", 쿼리 0회). 이번 변경과 무관.
- `POST /webhooks/portone`(모르는 결제) → 200 흡수. development.log에 500·FATAL·RoutingError·NoMethodError 0건.
- RuboCop 430파일 0 offenses · zeitwerk 통과 · Brakeman Errors 0·Security Warnings 0 · 전체 테스트 1,664 runs 0 failures · 시스템 테스트 15 runs 0 failures(모두 오케스트레이터 직접 재실행).

## 검증하지 못한 것 (실호출 금지 — 실제 결제로만 확인 가능)

- 실제 포트원 결제의 승인 응답 본문이 `pgTxId`·`paidAt`뿐인지, 재조회 응답의 `status`가 즉시 `PAID`인지, `amount.paid`·`channel.type`·`currency`의 실측값.
- 로컬 브라우저에서 결제창·카드 등록 위젯이 실제로 뜨는지(`_test` 채널 2개의 소속·테스트 채널에서 실제 결제가 일어나지 않는지).
- 운영 서버에서의 플랫 도달. 위 운영 평가는 로컬에서 운영 환경 설정으로 돌린 것이다.

## 종료·정리

- 서버 프로세스 종료·3100 포트 해제 확인.
- `bin/dev`(foreman)는 비TTY 환경에서 CSS 감시 프로세스가 즉시 종료되어 전체가 내려가서(선례와 동일 — 이번 변경과 무관) `bin/rails server`를 직접 띄워 확인했다.
- 작업 트리에 검증 부산물 없음.
