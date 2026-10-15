# 07_test_report.md — 포트원 전환 테스트 (Phase 7)

- **일자**: 2026-10-15
- **범위**: 기존 실패 4 failures·41 errors 갱신(전부 결제·구독) + 포트원 신규 시나리오
- **기준**: `_workspace/03_implementation.md` §1(API 매핑)·§2(컬럼 rename)·§3(변경 파일)·§4(갱신 대상), PLAN-5·PLAN-2/4·이슈 #1·#4 회복 경로
- **제약 준수**: 포트원 API 실호출 0건(FakePortOneClient 주입 + `with_http_transport` 전송 계층 대역), 앱 코드 수정 0건

---

## 1. 최종 결과

| 점검 | 결과 |
|:---|:---|
| `bin/rails test` | **490 runs, 2,984 assertions, 0 failures, 0 errors, 0 skips** |
| `bin/rails test:system` | 4 runs, 25 assertions, 0 failures (뷰어 무가입 플로우 — 결제 변경 무영향 확인) |
| `bin/rubocop` | **0 offenses** (136 files) |

기존 463 runs(4F·41E) → 490 runs(0F·0E). 증가 27건은 신규 시나리오(§3)에서 추가된 테스트다.

## 2. 기존 실패 갱신 내역 (9개 파일 — §4 전 항목)

| 테스트 파일 | 갱신 내용 | 결과 |
|:---|:---|:---:|
| `test/models/order_test.rb` | `toss_order_id`→`pg_order_id`, 고유성 검증 키 교체 | 통과 |
| `test/models/subscription_test.rb` | `toss_customer_key`→`pg_customer_key`·`toss_billing_key`→`pg_billing_key` | 통과 |
| `test/services/orders/purchase_service_test.rb` | `payment_key:`→`payment_token:`, 응답 해시 DONE→PAID, `TossPayments::ApiError`→`PortOne::ApiError`, confirm 호출 기록 `{ payment_id:·payment_token:·store_id: }` | 통과 |
| `test/services/orders/purchase_service_concurrency_test.rb` | FakePortOneClient·payment_token 교체 (스레드 격리 유지) | 통과 |
| `test/services/subscriptions/upgrade_service_test.rb` | `auth_key:`→`issue_token:`, 차감 응답 `{ payment: {...} }` 스냅샷, charge 기록 `{ payment_id:·billing_key:·channel_key:·order_name: }`, PG 원문(pg_code·pg_message) 단언 | 통과 |
| `test/controllers/app/orders_controller_test.rb` | 콜백 파라미터 `paymentKey/orderId`→`paymentToken/paymentId`, `with_portone_client` 스텁 | 통과 |
| `test/controllers/app/subscriptions_controller_test.rb` | `auth_key/authKey`→`issue_token`(JS 콜백과 동일 snake_case — `portone_billing_controller.js` §33 확인) | 통과 |
| `test/controllers/app/billings_controller_test.rb` | 셀렉터 `[data-controller=toss-payment]`→`portone-payment`, `data-portone-payment-payment-id-value` | 통과 |
| `test/f_plan_review_fix_test.rb` | 이슈 #1 시나리오의 paymentKey 보존→paymentId(pg_order_id) 보존, 미승인 상태 ABORTED→READY, GET 가드 알림 문구 `/발급 토큰/` | 통과 |

**구 헬퍼 삭제(03 §3 명시분)**: `test/test_helpers/fake_toss_client.rb`·`toss_stubbing.rb` 삭제 — 전소스 grep으로 참조 0건 확인 후 제거. 로드 호용 별칭(`FakeTossClient =`·`with_toss_client`) 소멸.

## 3. 신규 테스트 (24건 + 보강 2건)

### 3.1 `test/services/port_one/client_service_test.rb` — 13건 (신규)
전송 계층(`Net::HTTP.start`)을 `with_http_transport`로 교체해 요청 구성·응답 파싱·오류 정규화를 5 엔드포인트 전수 검증. 성공·실패·타임아웃 커버리지:

| 메서드 | 성공 | 실패 | 타임아웃/접속 |
|:---|:---:|:---:|:---:|
| confirm_payment | ✔ 경로·Authorization(`PortOne` 스킴)·Content-Type·멱등 키(RFC 8941 따옴표 UUID·POST 전용)·본문 | ✔ 404 `PAYMENT_NOT_FOUND` → `ApiError(status·code)` | ✔ TIMEOUT(모호) |
| issue_billing_key | ✔ `billingIssueToken`·`channelKey`·`customer{id}` 본문 | ✔ 최상위 `pgCode/pgMessage` 운반 | — |
| charge_billing_key | ✔ `amount{total}`·`currency=KRW`·`orderName`·멱등 결제 ID 경로 | ✔ `failure` 객체 중첩 pgCode 보완 | ✔ CONNECTION(모호) |
| get_payment | ✔ storeId 질의 GET·멱등 키 없음·body 없음 | ✔ 404 | — |
| cancel_payment | ✔ `reason` 본문 | ✔ 404 | — |

+ 전송 계층 구성(호스트 `api.portone.io`·TLS·open/read 60초), `ApiError#ambiguous?` 분류(TIMEOUT/CONNECTION만 true — 이슈 #1·#4 재확인 대상).

### 3.2 `test/controllers/webhooks/portone_controller_test.rb` — 11건 (신규)
- **Transaction.Paid**: pending 수금 패스 주문 → 재조회 PAID 확정 → paid·패스 10건 발급(200), paymentId로 정확히 1회 재조회
- **멱등 재시도**: 동일 이벤트 2회 → 패스 1회 발급(SEC 멱등)
- **위조 결합 차단**: 재조회 응답 id ≠ 주문 pg_order_id → 무변경 흡수(이벤트 값 미신뢰)
- **Transaction.Paid → settle_renewal**: pending Plus 갱신 주문 → paid·주기 연장(2026-10-31→11-30)
- **Transaction.Cancelled / PartialCancelled**: paid → cancelled 동기화(콘솔 환불)
- **Transaction.Failed**: pending → failed 동기화·발급 없음
- **미지원 type**(`BillingKey.Issued`)·paymentId 공란·미지 결제 ID·깨진 JSON: 전부 200 흡수·재조회 없음

### 3.3 보강 (기존 파일 내)
- **빌링키 발급(issue_token 방식)**: `upgrade_service_test` — 발급 성공 시 `pg_billing_key` 저장·Subscription active·정기결제 채널(`channel_key_billing`)·구독 고객 키(customer.id) 라우팅 기록 단언 / 컨트롤러 PATCH·GET 콜백 양 경로 HTTP 검증
- **차감(charge_billing_key)**: 성공 → Order paid·주기 1개월 연장·`pg_payment_id` = 주문번호 / 명확 실패 → failed 주문(PG 원문 보존)·즉시 만료 / 모호 실패 → pending 유지·구독 유지·`ambiguous` 이력 / 잔존 pending 주문 같은 결제 ID 재사용
- **컬럼 rename 데이터 유지**: `order_test` — fixture 고정값 조회 + `pg_order_id`·`pg_payment_id`·`pg_billing_key` 쓰기→재적재 라운드트립
- **즉시 승인 채널 폴백**: `purchase_service_test`·`orders_controller_test` — paymentToken 없으면 승인 API 호출 없이 get_payment 1회로 확정(03 §1 수동 승인 토큰 명세)

## 4. 실패 원인 분류

최종 실패 0건. 과정 중 1건 테스트 오류(코드 버그 아님):
- 수동 생성 `Net::HTTPOK` 응답의 body를 `Net::HTTP.start` 블록 밖에서 읽어 `IOError: attempt to read body out of block` — 테스트 대역 구성 문제. 읽기 완료 플래그(`@read`) 설정으로 해결 후 전건 통과.

앱 코드에서 발견·수정한 사항 없음(구현 보고 §7.1 수정분이 이미 반영된 상태 — 회복 경로 합류·PG 원문 보존 포함 재검증 완료).

## 5. 회귀 확인

- 구독 생명주기(`subscription_test` 15건)·한도 전환(`plan_limit_transition_test`)·수금 패스 사용·동시성(`payment_pass_test`·`payment_pass_concurrency_test`·`purchase_service_concurrency_test`) 전부 통과
- 무관 도메인(인증·청구·거래처·뷰어·프로미스) 기존 통과 유지 — fixture는 03 §3 명세대로 `pg_*` 키만 갱신된 상태를 사용

## 6. Tester 자체 점검

- [x] 포트원 API 실호출 0건 — 테스트 전체가 FakePortOneClient·FakePortOneTransport 경유만 사용
- [x] 테스트 소스 미사용 정의 0건 · `bin/rubocop` 0 offenses · 2칸 들여쓰기
- [x] `bin/rails test` 전체 회귀 통과(490 runs) + `test:system` 통과(4 runs)
- [x] 구 헬퍼(`fake_toss_client.rb`·`toss_stubbing.rb`) 삭제 — 토스 식별자 테스트 내 잔존 0건(전소스 grep 검증)
- [x] 실패 원인 분류 기재(§4)
