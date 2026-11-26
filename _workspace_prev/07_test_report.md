# 07_test_report — 포트원 채널 키 환경 분리 + 결제 확정 검증 (PLAN-5·Tester 단계, 2026-11-25)

## 요약

| 항목 | 값 |
|:---|:---|
| 신규·보강 테스트 | **66건 추가**(단위·통합 65 + 시스템 1) — 기존 0건 수정, 기존 단언 보존 |
| 비시스템 전체 | `bin/rails test` — **1,656 runs · 10,504 assertions · 0 failures · 0 errors · 0 skips**(기준선 1,590/10,003 대비 +66 runs · +501 assertions) |
| 시스템 전체 | `bin/rails test:system` — **15 runs · 135 assertions · 0 failures**(기준선 14/131 대비 +1) |
| RuboCop | `bin/rubocop test/` — 201 files inspected, **no offenses** |
| Zeitwerk | `zeitwerk:check` — all is good |
| 포트원 실호출 | **0건** — 전 경로 대역(`FakePortOneClient` 주입/생성자 교체, `with_http_transport` 전송 대역, 가드 경로는 API 호출 전 예외 + TEST_GUARD 방어선) |
| app 버그(BUG-n) | **없음** — 전 시나리오가 구현대로 동작했다. 테스트 자체 오류 2건(transport stub을 끼워 가드를 우회한 케이스·nil metadata 접근)은 스스로 수정 |
| credentials 의존 | 없음 — 선택기·검증기·가드·화면 모두 `credentials:`·`live:` 인자 또는 `with_portone_channel_keys` 일시 교체로 고정(로컬=마스터 키 有, CI=無 동일 결과). `config.x.portone_live_channel`은 교체 후 `ensure`에서 원복 |

## 그룹별 시나리오 표

### A. 채널 키 선택기 `PortOne::ChannelKey` — 신설 `test/services/port_one/channel_key_test.rb`(10건)

| 구분 | 시나리오 | 테스트 | 결과 |
|:---|:---|:---|:---|
| 정상 | `live: true` → 기본 키(billing·normal) | 운영 기대(live: true)… | 통과 |
| 정상 | `live: false` → `_test` 키(billing·normal) | 비운영 기대(live: false)… | 통과 |
| 경계 | kind 문자열("billing"/"normal") | kind는 문자열도 심볼과 동일… | 통과 |
| 예외 | 비운영인데 테스트 키 없음 + 라이브 키 有 → **nil(라이브 대체 금지)** | 비운영에서 테스트 키가 없으면… | 통과 |
| 예외 | 운영인데 라이브 키 없음 → nil | 운영 기대인데 라이브 키가 없으면… | 통과 |
| 예외 | `portone` 블록 없음(CI) → nil | credentials에 portone 블록이 없어도… | 통과 |
| 예외 | kind `:foo`/nil/""/"billing_test"/정수 → ArgumentError(메시지에 billing/normal) | 허용 kind는 billing·normal뿐… | 통과 |
| 경계 | test 환경 `live_channel?` = false(플래그 미정의) | live_channel?는 test 환경(플래그 미정의)… | 통과 |
| 경계 | 플래그 행렬 true→live, "true"·nil·1·false→테스트 채널(**`== true` 비교 유지** — Rails 8.1 config.x 미정의 키는 truthy OrderedOptions) | live_channel?는 true만 라이브로 판정… | 통과(ensure 원복) |
| 정상 | `.billing`/`.normal`이 `fetch` 기본 인자를 탄다(kind만 전달·kwargs {} — 실제 credentials 비의존) | .billing과 .normal은 fetch를 kind만 넘겨… | 통과 |

### B. 클라이언트 가드·본문 — `test/services/port_one/client_service_test.rb`(보강 2건)

| 구분 | 시나리오 | 결과 |
|:---|:---|:---|
| 예외 | `issue_billing_key`에 channel_key nil/""/"   " → `MissingChannelKey`(ArgumentError 아님·`refute_kind_of`)+ HTTP 요청 0건 | 통과 |
| 예외 | `charge_billing_key` 동일 → `MissingChannelKey` + HTTP 요청 0건 | 통과 |
| 정상 | `confirm_payment` 본문 `totalAmount`·`isTest`·`currency` 전달 — **기존 테스트가 정확한 본문 등식으로 이미 고정**(`{storeId, paymentToken, totalAmount, isTest, currency}`) — 추가 보강 불요 | 통과(기존) |

### C. 갱신·재시도 잡 — 신설 `test/jobs/subscription_renewal_job_test.rb`(3건) + `dunning_retry_test.rb`(보강 2건)

| 구분 | 시나리오 | 테스트 | 결과 |
|:---|:---|:---|:---|
| 예외 | 키 없음: 차감 대상(active·빌링키)은 가드로 건너뛰고 **선기록 pending 주문은 롤백으로 미잔존**(dunning 0·next_retry_at nil·상태 active 유지), **해지 후 주기 종료 구독은 만료 강등이 정상 처리**(클라이언트 무호출 경로) | 채널 키가 없어도 차감 대상만 건너뛰고… | 통과 |
| 정상 | 건너뛰기 시 `Rails.logger.error("[SubscriptionRenewalJob] user=…")` 기록(`broadcast_to` 캡처) | 채널 키 미등록으로 건너뛴 구독은 오류 로그… | 통과 |
| 예외 | 전용 예외 아님: `ArgumentError`(대역 주입)는 잡이 삼키지 않고 실패 — 롤백으로 오염 없음 | 전용 예외가 아닌 코드 오류는 잡이 삼키지… | 통과 |
| 예외 | `DunningRetryJob`: 키 없음 → `dunning_stage`·`next_retry_at`·주문 수 **무변경**(설정 오류 ≠ 카드 거절), 잡 실패 없음 | 채널 키 미등록 재차감은 dunning 단계… | 통과 |
| 예외 | `DunningRetryJob`: `ArgumentError`는 잡 밖으로 — 범용 rescue 금지 | 전용 예외가 아닌 코드 오류는 재시도 잡도… | 통과 |

### D. `PortOne::PaymentVerifier` 행렬 — `test/services/port_one/payment_verifier_test.rb`(신설 파일, 보강 15건)

| 구분 | 시나리오 | 결과 |
|:---|:---|:---|
| 정상 | 기본(TEST·4,000원·KRW) 통과 + payment 그대로 반환 / Float 4,000.0 통과 / `live: true`+LIVE·`live: false`+TEST 각각 통과 | 통과 |
| 예외(금액) | 100·5,000 → `amount_mismatch` / paid nil·amount 키 누락 → 실패 / `"4000"`(문자열) → 실패 / amount가 String·Array·Integer → 실패(TypeError 아님) / payment nil·"PAID"·Array → 실패 | 통과 |
| 예외(채널) | `live: true`인데 TEST·`live: false`인데 LIVE / type 누락·`"TEST "`(공백)·`"test"`(소문자)·`:TEST`(심볼) → `channel_mismatch` / channel이 String·Array·Integer → 실패(TypeError 아님) | 통과 |
| 예외(통화) | "USD"·nil·키 누락 → `currency_mismatch`(detail에 expected=KRW) | 통과 |
| 예외 | **문자열 키 해시 → amount_mismatch**(관대 수용 금지) | 통과 |
| 경계 | `live:` nil/"true"/1/0/"" → TEST 기대 해석(LIVE 거절·TEST 통과 — 라이브 해석 경로 없음) | 통과 |
| 정상 | `VerificationError`가 `reason`·`detail`·message(라벨 "금액 불일치/채널 불일치/통화 불일치"·접두 "결제 확정 검증 실패") 운반 | 통과 |
| 예외 | 10종 비정상 응답 전부 `VerificationError`로 정규화 — TypeError·NoMethodError·KeyError 없음(REASON_LABELS 키 순환) | 통과 |
| 정상 | 검증 순서 금액→채널→통화(기존 5건 유지·재확인) | 통과(기존) |

### E. `Orders::PurchaseService` 콜백 경로 — 보강 10건

| 구분 | 시나리오 | 핵심 단언 | 결과 |
|:---|:---|:---|:---|
| 정상 | 세금계산서 주문(tax_invoice·300원) 정상 확정 — paid·paid_at·metadata에 재조회 스냅샷(amount.paid)·**패스 0건**·승인 요청 인자(`total_amount: 300, is_test: true, currency: "KRW"`)·legal/tax도 `FulfillPassService` 경유 | 통과 |
| 예외 | 금액 불일치(재조회 paid=100) → `PurchaseError`("결제 확인에 실패했습니다…")·주문 **failed**·paid_at nil·`verification_failed?`·metadata `code=PAYMENT_VERIFICATION_FAILED`+`verification.reason=amount_mismatch`+`VERIFICATION_FAILED_MESSAGE`·**pg_payment_id 스냅샷**·패스 0·승인 1회+재조회 1회·메시지에 내부 값 미노출 | 통과 |
| 예외 | 채널 불일치(`paid_payment(live: true)`를 비운영 기대에) → `channel_mismatch`·failed | 통과 |
| 예외 | 통화 불일치(USD) → `currency_mismatch`·failed | 통과 |
| 경계 | 즉시 승인 채널(토큰 없음)도 검증 실패 → failed(승인 호출 0건·재조회 1회) | 통과 |
| 예외 | 모호 실패(TIMEOUT) 회복 재조회 불일치 → pending 회복이 아니라 **failed 확정**(pending_recovery 미기록) | 통과 |
| 경계 | ALREADY_PAID 회복 재조회 불일치 → failed 확정 | 통과 |
| 경계 | 승인 성공 뒤 재조회가 **PAID 아님**(PAY_PENDING) → failed 금지·**pending 유지**+`pending_recovery`·재조회 재시도 0회(기존 TIMEOUT 회귀와 별개 변형) | 통과 |
| 경계 | 승인 요청 자체 거부(400 PG_PROVIDER_ERROR) → failed지만 `metadata["verification"]` **nil**·`verification_failed?` false — `record_failure!` 경로와 분리 | 통과 |
| 경계 | legal_doc 주문 검증 실패 기록도 `metadata["invoice_id"]` 보존(B-1 병합) | 통과 |
| (H 이관) | 이미 paid 주문의 재검증 실패 기록 무시(멱등)는 모델 계층에서 고정(H 그룹) | — |

### F. 웹훅 `Webhooks::PortOneController` — 보강 5건

| 구분 | 시나리오 | 핵심 단언 | 결과 |
|:---|:---|:---|:---|
| 예외 | pending + `Transaction.Paid` + 재조회 금액 불일치 → 확정 없이 **failed**·`verification_failed?`·reason 기록·**pg_payment_id 스냅샷(웹훅 경로도 R2-5 단일 구현 경유)**·패스 0·**응답 200**·재조회 정확 1회 | 통과 |
| 예외 | 채널 불일치(LIVE)·통화 불일치(USD) → 동일 실패 처리 + 200 | 통과 |
| 경계 | 같은 Paid 이벤트 재수신 → 멱등 무변경(metadata 등식 — `mark_verification_failed!`가 이미 failed인 주문을 건드리지 않음) | 통과 |
| 예외 | **일반 PG 거절 failed 주문 + Transaction.Paid**(재조회는 PAID·금액 일치) → paid로 되돌려지지 않음·paid_at nil·PG 사유 보존·verification nil·`updated_at` 불변(update! 미실행 프록시) — R2-1 가드가 **failed 전체**에 적용됨 | 통과 |
| 정상 | pending→failed 동기화·paid→cancelled(환불)·R2-1 검증 실패 주문 회귀·Plus 갱신 `settle_renewal` 무검증 경로 — **기존 테스트 9건 유지로 회귀 확인** | 통과(기존) |

### G. 회원 화면(컨트롤러·통합) — billings 3건·legal_documents 7건·tax_invoices 5건

| 화면 | 시나리오 | 결과 |
|:---|:---|:---|
| billings#show | 선택기 고정값이 `data-portone-payment-channel-key-value`·`data-portone-billing-channel-key-value`에 그대로 심김 + 결제하기 1 | 통과 |
| billings#show(checkout) | normal 키 nil → 결제하기 0 + "결제 채널이 설정되지 않았습니다" + **`data-controller=portone-payment` 블록 유지**(W-1 결정 범위) | 통과 |
| billings#show | billing 키 nil → 카드 등록 버튼(속성) 0 + 안내 | 통과 |
| legal_documents#show | 키 nil → 버튼 0 + 안내 + 위젯 블록 유지 / 키 有+연락처 無 → 연락처 안내 / 키·연락처 有 → 결제하기 1 + 키 값 속성 | 통과 3건 |
| legal_documents#show | 검증 실패 주문 → "결제 확인에 실패했습니다. 고객지원(문의)으로 연락해 주세요." + "다시 결제하지 말아 주세요" + 문의 링크 + **재주문 버튼 없음** / `payment_failed=1` 파라미터와 와도 **검증 실패 안내 우선** / 일반 PG 실패 주문은 기존 재주문 안내·버튼 유지(회귀) | 통과 3건 |
| legal_documents (R2-1 변형) | 검증 실패 legal_doc 주문 + 정상 금액 `Transaction.Paid` 재수신 → failed 유지·paid_at nil·`invoice_id` 보존 → download는 **워터마크 미리보기**(정식 PDF와 바이트 다름) | 통과 |
| tax_invoices#show | 키 nil(pending·설정 완료 사용자) → 버튼 0 + 안내 + 위젯 블록 유지 / 키·연락처 有 → 결제하기 1 + 키 속성 / 연락처 無 → 연락처 안내 | 통과 2건 |
| tax_invoices#show | 검증 실패 → 문의 안내 + "다시 결제하지 말아 주세요" + 재발행 버튼 없음 + 일반 실패 분기 미노출 / `payment_failed=1` 우선순위 / 일반 PG 실패는 기존 "다시 발행 요청" 유지(회귀) | 통과 3건 |

### H. `Order#mark_verification_failed!` 모델 — 보강 4건

| 구분 | 시나리오 | 결과 |
|:---|:---|:---|
| 정상 | pending → failed + `pg_payment_id`(=pg_order_id) + metadata(code·message·`verification{reason,detail}`) + true 반환 | 통과 |
| 정상 | 기존 metadata(invoice_id) 보존 병합(B-1) | 통과 |
| 예외 | 이미 paid → 무변경 + false(paid_at·metadata 보존) / 이미 failed(일반 PG) → 사유 미덮어쓰기 + false(경합 멱등) | 통과 |
| 경계 | `verification_failed?`는 "failed + 검증 코드 일치"만 true — 일반 failed·paid(코드 有라도)·pending false | 통과 |

### I. 시스템 테스트 — 신설 `test/system/app_billing_channel_key_notice_test.rb`(1건)

- 채널 키 nil 상태에서 로그인 → /app/billing 체크아웃 도달 → "결제 채널이 설정되지 않았습니다" 표시·"결제하기" 버튼 없음·위젯 블록 유지. **"결제하기" 클릭 없음**(SDK 실호출 차단 원칙), 로그인·이동·렌더만 검증.
- `with_portone_channel_keys`는 프로세스 공유 대역이라 서버 스레드에도 적용되며 블록 종료 시 복원.
- 안정성: 단독 파일 기준 **10/10 통과**. 전체 시스템 스위트 16회 샘플에서 2회 실패 — 모두 **기존 테스트의 선존재 플레이크**(`AppLegalDocumentPdfTest` 로그인 단계 — 1차 리뷰 O-3과 동일, `ViewerPromiseTest` 1회)로 신규 테스트와 무관. 따라서 유지함.

## 발견한 app 버그(BUG-n)

**없음.** 전 시나리오(선택기·가드·잡·검증기·콜백·웹훅·화면·모델)가 구현 보고(03_implementation §1~§10)와 동일하게 동작했다. 테스트 작성 중 생긴 오류 2건은 모두 테스트 측 결함이었다:

1. **잡 테스트의 대역 선택 오류(수정 완료)** — `SubscriptionRenewalJob`·`DunningRetryJob`의 키 미등록 시나리오를 `with_portone_client(fake)`로 실행하면 가드(`ClientService#ensure_channel_key!`)를 지나 가짜가 그대로 응답해 시나리오가 성립하지 않았다. 가드는 실제 ClientService 계층의 것이므로 전송 계층 대역 없이 실제 클라이언트로 실행(가드가 HTTP 전에 예외 — 우발적 유출은 TEST_GUARD가 잡 밖으로 노출)하도록 수정하고 재검증했다.
2. **nil metadata 접근(수정 완료)** — `OrderTest` 멱등 테스트에서 metadata 없이 만든 paid 주문의 `metadata["code"]` 접근을 `metadata&.dig("code")`로 수정.

## 커버하지 못한 영역과 이유

| 영역 | 이유 |
|:---|:---|
| 포트원 실제 응답 필드 실측(`amount.paid`·`channel.type`·`currency` 실값·`pgTxId`/`paidAt` 승인 응답) | 실호출 금지 — 첫 실결제 1건으로 기록해야 하는 운영 과제(03 §9·§10 남은 리스크 유지) |
| 웹훅 `get_payment` `ApiError` → 500(포트원 재시도 유지) 단언 | 기존 스위트에 이 경로의 통합 테스트가 없고, 컨트롤러가 재조회 실패를 흡수하지 않는 동작은 ActionDispatch::IntegrationTest에서 예외 전파 단언으로 가능하나 이번 매트릭스(F 그룹) 지시 범위 밖 — 후보로 남김 |
| 콜백↔웹훅 경합에서 검증 실패 기록 정확 1회(리뷰 §7-8) | 실스레드 경합은 `purchase_service_concurrency_test.rb`(기존)가 커버하며, 검증 실패 조합의 경합 변형은 이번 지시 매트릭스 밖 — `mark_verification_failed!`의 경합 멱등은 H에서 잠금 단독으로 고정 |
| 세금계산서 주문 검증 실패 → 바로빌 SOAP 호출 0건(리뷰 §7-11) 단언 | 검증 실패 시 paid 전환이 없어 `FulfillTaxInvoiceService`에 도달하지 않는 것이 구현이며, 발행 경로 자체는 기존 `fulfill_tax_invoice_service_test`·`tax_invoice_settle_test`가 검증 — 중복 단언으로 판단해 생략 |
| 시스템 테스트의 검증 실패 주문 화면 E2E | 컨트롤러 통합 테스트(G)가 동일 표면을 검증하며 시스템 테스트는 지시대로 채널 키 미설정 화면 1건만 수행(안정성 기준 충족) |
| `LAUNCH_TEST_SCENARIOS.md` 등 사용자 문서의 로컬 결제창 확인 | 브라우저 수동 확인 영역(리뷰 W-4·R-3 유지 항목) |

## 실행 명령과 결과

| 명령 | 결과 |
|:---|:---|
| `mise exec -- bin/rails test` | **1,656 runs, 10,504 assertions, 0 failures, 0 errors, 0 skips** |
| `mise exec -- bin/rails test:system` | **15 runs, 135 assertions, 0 failures, 0 errors, 0 skips** |
| `mise exec -- bin/rails test:system test/system/app_billing_channel_key_notice_test.rb`(단독×10) | 10/10 — 1 runs, 4 assertions, 0 failures(전체 스위트의 간헐 실패는 기존 AppLegalDocumentPdfTest·ViewerPromiseTest — 1차 리뷰 O-3 동일) |
| `mise exec -- bin/rubocop test/` | 201 files inspected, no offenses |
| `mise exec -- bin/rails zeitwerk:check` | all is good |

## 변경 파일(전부 test/ — app·문서·credentials 무변경)

- 신설: `test/services/port_one/channel_key_test.rb` · `test/jobs/subscription_renewal_job_test.rb` · `test/system/app_billing_channel_key_notice_test.rb` · (`test/services/port_one/payment_verifier_test.rb` — Developer가 재리뷰 단계에서 만든 5건에 행렬 15건 보강)
- 보강: `test/test_helpers/portone_stubbing.rb`(`with_portone_channel_keys` 헬퍼 — ensure 복원 계약) · `client_service_test.rb` · `dunning_retry_test.rb` · `purchase_service_test.rb` · `webhooks/portone_controller_test.rb` · `billings_controller_test.rb` · `legal_documents_controller_test.rb` · `tax_invoices_controller_test.rb` · `order_test.rb`
- 기존 테스트 수정(기존 단언 변경): **0건**
