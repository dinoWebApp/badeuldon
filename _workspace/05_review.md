# 05_review.md — 토스 → 포트원(KG이니시스) 전환 리뷰

- **일자**: 2026-10-15 · **리뷰어**: PortOneReviewer
- **대상**: git 변경분 전수(래퍼 2 신규·웹훅 1 신규·JS 2 신규·서비스 3·컨트롤러 3·모델 2·잡 2·마이그레이션·fixtures·테스트 헬퍼·PRD·routes)
- **기준**: PRD v0.21 §6.10 PLAN-5 · §6.19 EXT · 검증기준 6항(결제 무결성·래퍼 보안·컬럼 rename·웹훅·크린 컷오버·UI)
- **외부 근거**: 포트원 공식 문서 실조회 — [인증 결제 연동](https://developers.portone.io/opi/ko/integration/start/v2/checkout?v=v2) · [빌링키 발급](https://developers.portone.io/opi/ko/integration/start/v2/billing/issue?v=v2) · [수동 승인](https://developers.portone.io/opi/ko/extra/manual-confirm/readme-v2?v=v2) · [웹훅 v2](https://developers.portone.io/opi/ko/integration/webhook/readme-v2?v=v2) · [REST V2 결제 API](https://developers.portone.io/api/rest-v2/payment?v=v2) · [KG이니시스 V2 연동](https://developers.portone.io/opi/ko/integration/pg/v2/inicis-v2?v=v2) · npm `@portone/browser-sdk@0.1.13` 타입 실측
- **이전 리뷰 추적**: `_workspace_prev/05_review.md`(F-PLAN 최초) 이슈 #1~#7은 본 전환에서 구조적으로 해소 확인(§이전 이슈 해소 매핑). #8·#10·#11은 하단 참조.

## Status: CHANGES_REQUESTED

**BLOCKER 1건(위젯 파라미터)** — 수정 후 해당 경로 재리뷰 대상. 이하 CRITICAL 2건도 결제 정합성·주요 플랫폼 동작에 직결되어 수정 권고. 기존 테스트 4 failures + 41 errors는 전환으로 인한 예상 갱신 대상(Phase 7 합의)으로 리뷰 이슈에서 제외.

---

## 이슈 목록

| # | Severity | Rule ID | File:Line | 설명 | 수정 제안 |
|---|----------|---------|-----------|------|-----------|
| B1 | **BLOCKER** | PLAN-5 | `app/javascript/controllers/portone_payment_controller.js:18-26` · `portone_billing_controller.js:19-24` · `app/views/app/billings/_checkout.html.erb:5-10` | **KG이니시스 채널 필수 파라미터 미전달 — 위젯 요청이 PG에서 거부될 수 있음.** 포트원 공식 KG이니시스 V2 문서 기준 필수: ① `requestPayment` — `customer.fullName`(또는 first+last) **필수**, PC 결제 시 `customer.phoneNumber`·`customer.email` **필수**(모바일은 optional). ② `requestIssueBillingKey` — `issueId`(발급 건 고유 ID)·`issueName` **필수**, `customer.fullName` **필수**, PC 발급 시 `customer.phoneNumber` 필수, **모바일 발급 시 `offerPeriod` 필수**. 현재 구현은 어느 쪽도 전달하지 않는다(payment: storeId·channelKey·paymentId·orderName·totalAmount·currency·payMethod만 / billing: +customerId만). 채널(INIpayTest·INIBillTst)이 KG이니시스 모듈이므로 단건 결제·카드 등록 모두 결제창 단계에서 거부 가능성 — 금전 기능 전체 불능. [INFERENCE] 최종 확정은 배포 후 브라우저 실측(§5 후속)이 필요하나 문서가 "필수 입력해야 합니다"로 명시하는 결정적 누락. 러너 실측(03 §7)은 전부 오류 경로(404)라 위젯 성공 경로를 커버하지 못했다. | ① 결제 컨트롤러·뷰에 `customer: { fullName: 표시명, phoneNumber, email }` 데이터 속성 추가(프로필·User에서 적재) ② 빌링 발급에 `issueId: SecureRandom.uuid` 상당(ASCII), `issueName: "받을돈 Plus 자동결제"`, `customer` 동일 + 모바일 `offerPeriod` 전달 ③ 수정 후 KG이니시스 테스트 채널로 위젯 E2E 실측 |
| C1 | **CRITICAL** | PLAN-5 (SEC-5 준용) | `app/services/orders/purchase_service.rb:42-48,96-104` · `app/controllers/webhooks/portone_controller.rb:71-76`(부차) | **confirm 재시도의 `ALREADY_PAID`가 명확 실패로 확정 — 결제는 됐는데 패스 미발급.** 시나리오: ① 승인 요청 타임아웃(모호 실패) + 재조회도 실패(일시적 장애) → pending 유지 ② 사용자가 콜백 URL 새로고침/재클릭(콜백은 GET — 재실행 쉬움) → 포트원 `POST /payments/{id}/confirm`은 이미 승인된 결제에 `AlreadyPaidError`(400, type `ALREADY_PAID` — 공식 API 문서 ConfirmPaymentError 구성원 확인) 반환 ③ `e.ambiguous?`가 아니므로 `record_failure!`로 **failed 확정** ④ 이후 웹훅 `Transaction.Paid`가 와도 `apply_status`는 `pending→paid`만 확정(FulfillPassService)하고 `failed→paid`는 상태만 뒤집어 **발급 없는 paid 주문** 잔류. "모호 실패를 failed로 굳히면 결제는 됐는데 패스는 없는 상태"(파일 상단 주석)가 비모호 코드 하나에서 재현되는 구조. 갱신 차감에는 같은 상황을 막는 스티키 가드(`metadata["ambiguous"]`, upgrade_service.rb:187-196)가 있어 단건과 비대칭. 토스 시절에도 동일 갭이 있었으나(구 purchase_service 확인) 이번 재작성 코드에 그대로 이식됨. | ① `PurchaseService`에서 `e.code == "ALREADY_PAID"`(confirm)는 "이미 결제됨 = 성공 신호"로 `recover_from_recheck!` 합류(실패 기록 금지) — 갱신 스티키 가드와 대칭화 ② `apply_status`의 `failed→paid` 전환은 상품 확정(패스 발급·주기 연장) 또는 최소 CS 감지 가능한 metadata 기록을 동반하도록 ③ 시나리오 테스트(Phase 7) |
| C2 | **CRITICAL** | PLAN-5 | `app/javascript/controllers/portone_payment_controller.js:15-39` · `portone_billing_controller.js:15-34` | **`redirectUrl` 미설정 반환값(Promise) 방식 — 공식 문서상 모바일에서 결제 UI가 표시되지 않을 수 있음.** "redirectUrl이 설정되지 않은 경우(반환값 방식) — **모바일 결제 UI가 제대로 표시되지 않을 수 있습니다. PC 결제 UI로 충분할 때만 사용**하십시오"(인증 결제 연동 문서). 수동 리다이렉트(`window.location.href`)는 이 제약을 해소하지 못한다. 받을돈 /app 대시보드는 모바일 웹 사용이 주류인 U1 표면 — 단건 결제·카드 등록 모두 모바일에서 결제창 미표시 = 구매 불가 위험. KG이니시스는 PC/모바일 모듈이 분리된 PG라 문서 경고의 직접 대상. | `requestPayment`·`requestIssueBillingKey`에 `redirectUrl: (기존 callback URL)` 전달(필요 시 `forceRedirect` 또는 SDK 자동 환경 전환 사용). 단, SDK 리다이렉트는 응답 필드명 그대로 쿼리 전달 → ① 결제 콜백은 `paymentId`/`paymentToken`/`code`/`message` 수신 이미 호환 ② 빌링 콜백은 `billingIssueToken` 파라미터명 수용 추가(`params[:issue_token]` 또는 `params[:billingIssueToken]`) 필요. 변경 후 모바일 실기기 E2E |
| W1 | WARNING | PLAN-5 | `app/services/subscriptions/upgrade_service.rb:52-57,122-130` · `portone_billing_controller.js:33` | **카드 등록 플로우가 빌링 채널 '수동 승인' 설정에 하드 의존.** `billingIssueToken`은 채널에 수동 승인이 **켜져 있을 때만** 반환(수동 승인 문서 — 꺼져 있으면 빌링키가 즉시 발급되고 토큰 없음). INIBillTst에 수동 승인이 꺼져 있으면 `issue_token=""` → 서버 가드 "카드 인증 정보(발급 토큰)가 없습니다"로 **카드 등록이 항상 실패**한다. 코드·03 어디에도 이 채널 설정 전제가 명시돼 있지 않다. 단건 채널은 토큰 유무 양쪽을 처리해 안정적. | 배포 체크리스트에 "INIBillTst 채널 수동 승인 ON" 명시(03 §5 후속 목록에 추가). 라이브 전환 시 채널 설정-코드 전제 일치 재확인 |
| W2 | WARNING | PLAN-5 | `app/services/subscriptions/upgrade_service.rb:122-130` | **빌링키 발급의 모호 실패 회복 경로 부재(비대칭).** 발급 confirm 타임아웃 시 즉시 "카드 등록에 실패했습니다" 안내 — 발급이 실제로는 성공했을 수 있어도 재등록(신규 토큰→신규 빌링키)으로만 자가 회복된다. `BillingKey.*` 웹훅 흡수는 설계 합의 사항이라 위반으로 보지 않되, 승인·차감에만 회복 경로가 있는 비대칭은 운영 인지 필요(고아 빌링키가 포트원 콘솔에 축적). | 수용 가능. 03 구현 판단 기록에 "발급 모호 실패는 재등록으로 회복, 고아 빌링키는 콘솔 정리" 명시 권고 |
| W3 | WARNING | PLAN-5(크린 컷오버) | `config/routes.rb:32` | **잔존 주석** — `# 카드 인증 위젯 successUrl(토스가 GET 리다이렉트) — authKey 수신 전용(이슈 #5).` 토스·authKey(구 파라미터) 용어가 그대로 남아 크린 컷오버 명세와 불일치(동작 영향 없음). | 포트원 SDK 콜백·`billingIssueToken` 용어로 주석 갱신 |
| W4 | WARNING | PLAN-5 | `app/controllers/webhooks/portone_controller.rb:32-38,46-61` | **재조회 `get_payment`의 `PortOne::ApiError` 미처리 → 500.** 상단 명세 "응답은 항상 200"과 불일치(구 #8 계열). 포트원은 5xx를 재시도하므로 일시 장애 회복에는 오히려 유리하나, 예외 통보·로그 노이즈와 명세-구현 괴리가 남는다. | 수용 시 "재조회 실패는 5xx로 재시도 유도"로 명세 수정, 또는 `ApiError` rescue 후 200 + 재처리 큐. 판단 기록 권고 |
| W5 | WARNING | 아키텍처(성능) | `app/services/subscriptions/upgrade_service.rb:84-96,105-115` · `app/services/orders/purchase_service.rb:30-37` | **잠금 순서 비대칭 + 잠금 내 60초 외부 호출.** renew는 subscription→order 순으로, settle_renewal(웹훅)은 order→subscription 순으로 잠금 — SQLite(현행, 단일 라이터)에선 무해하나 PG 이식 시 동일 사용자 갱신 건에 데드락 여지. 타임아웃 10초→60초로 잠금 내 외부 호출 최대 시간도 6배 증가(구 #10의 연장). | 현 규모 수용 가능. PG 이식 시 잠금 순서 통일(주문 우선) 또는 외부 호출 잠금 밖 이탈 구조 검토 — 03 제약 사항으로 기록 |
| W6 | WARNING | PLAN-5 | `app/views/app/billings/_checkout.html.erb:5-10` | **체크아웃 파셜의 채널 키 가드 부재.** 카드 등록 섹션은 `@portone_channel_key_billing.present?` 분기가 있으나 체크아웃은 `channel_key_normal`이 nil이어도 렌더되어(빈 데이터 속성) 클릭 시점에 위젯 오류가 난다. 미설정 환경에서 사전 안내(결제 채널이 설정되지 않았습니다)와 정합성 있는 처리 권장. | 컨트롤러/뷰에서 `channel_key_normal` 부재 시 체크아웃 미노출 또는 안내문 전환 |

### 확인 요청(위양성 방지 — 판단 보류)

| 항목 | 내용 |
|---|---|
| Q1 | **체험 미사용자의 카드 직접 등록 시 첫 1개월 무료** — `activate!`가 선차감 없이 `base+1개월` 주기를 부여한다(base=now). PLAN-2는 "첫 14일 무료 체험"인데, 체험을 건너뛰고 카드를 등록하면 사실상 1개월 무료 Plus가 된다(갱신 잡이 주기 종료 시 첫 차감). 토스 시절과 동일한 **diff 외 사전 존재** 동작이나 이전 리뷰에서도 미지적 — 의도된 정책인지 확인 필요 |
| Q2 | **privacy.html 토스페이먼츠 잔존** — `app/views/pages/privacy.html.erb:85,97` 위탁사 목록 "토스페이먼츠 / 포트원(KG이니시스)". 과거 토스 결제 이력 보존 목적이라면 유효하나, 테스트 단계(실과금 이력 없음)라면 정리 검토 — 법무 확인 영역 |
| Q3 | **`Transaction.PartialCancelled` → 주문 'cancelled' 전환** — 부분 취소 시 주문 상태가 통째로 cancelled가 된다(paid_at은 유지). 수금 패스·구독 모두 전액 환불만 존재한다면 도달 불가라 무해하나, PLAN-6(콘솔 수동 환불) 운영 시 부분 취소가 발생하면 보고서 왜곡 여지 — 정책 확인 |

---

## 결제 무결성 검증표 (검증기준 ①)

| 검증 항목 | 결과 | 근거(File:Line) |
|:---|:---|:---|
| paymentId 멱등 — 서버 채번 | **방어됨** | `pg_order_id` = 서버 UUID(NOT NULL·고유 인덱스, schema.rb:88)를 위젯 paymentId·confirm·차감·웹훅 매칭 공통 키로 사용. 포트원 문서 "같은 paymentId에 결제 성공은 단 한 번"(중복 결제 방지)과 정합 |
| paymentId 멱등 — 단건 동시 콜백 | **방어됨** | `purchase_service.rb:30-37` with_lock + pending 재판정 → 2번째 호출 "이미 처리된 결제입니다"; `fulfill_pass_service.rb:14-22` pending 재판정 + 트랜잭션(콜백·웹훅 경합 1회 발급 — SEC-5 준용) |
| 빌링키 차감 이중 방어 | **방어됨** | 1차 포트원 paymentId 거부 + 2차 `renew`의 with_lock·`renewal_due?` 재판정(업그레이드 서비스 84-96) + 선주문 pending 재사용(`prepare_renewal_order!` 154-160) — 크래시 후 재실행도 같은 paymentId |
| 빌링키 차감 재시도 거절(이미 결제됨) | **방어됨** | 스티키 가드 `metadata["ambiguous"]`(187-196) — 모호 이력 있는 주문의 ALREADY_PAIED 거절은 만료하지 않고 pending 유지→웹훅 `settle_renewal` 회복 |
| 승인 모호 실패(TIMEOUT/CONNECTION) 회복 | **방어됨(단건·갱신)** | `ApiError#ambiguous?`(api_error.rb:22-24) → 재조회 합류·pending 유지·웹훅 회복. **예외: 비모호 `ALREADY_PAID` — 이슈 C1** |
| PendingApprovalError(승인 전) | **방어됨** | `recheck_payment!`가 PAID 아니면 PendingApprovalError → pending 유지 + 지연 안내(74-79,39-41) — 즉시 승인 채널 폴백과 동일 경로 |
| 웹훅 무결성 — 값 미신뢰 | **방어됨** | 이벤트 값 폐기·`get_payment` 재조회 확정(53-59) + `payment[:id] != order.pg_order_id` 결합 차단(56) + paymentId 부재·미지원 type·깨진 JSON 200 흡수(32-38). 공식 문서가 권장하는 재조회 전략과 일치 |
| 웹훅 멱동 | **방어됨** | 같은 상태 무변경(72)·pending 재판정 확정점 공유. dev 러너 실측 "재시도 → 패스 추가 발급 없음"(03 §7) |
| 금액 변조 | **방어됨** | 주문 생성 서버 정가(`Order.amount_for`)·차감 `PLUS_MONTHLY_PRICE` 상수 단일 지점·콜백 파라미터 금액 무시. 포트원 confirm이 위젯 요청 당시 금액 검증 |
| 소유권 격리 | **방어됨** | `orders_controller.rb:34-36` `Current.user.orders.find_by!` — 타인 paymentId 위조 콜백 차단. 빌링 페이지 체크아웃도 본인 pending만(billings_controller 8-10) |
| api_secret 노출 경로 | **없음** | credentials만 참조(client_service 16-17)·Authorization 헤더·로그 미출력. 뷰에는 storeId·channelKey(공개 값)만. ApiError 메시지는 포트원 응답 code/message·PG 원문만 운반 |
| 멱등키 헤더 형식 | **준수** | `Idempotency-Key: "<uuid>"`(82) — 공식 "RFC 8941에 따라 쌍따옴표로 감싸세요"와 일치. 단 요청마다 신규 UUID라 헤더 자체의 재시도 중복 제거는 기대하지 않는 구조(실제 멱등 축은 paymentId — 설계상 문제 없음) |
| 타임아웃 | **준수** | 60초(13, 95-97) — 공식 "최소 60초 읽기 타임아웃 권장" 일치 |

## 래퍼 보안·API 정합 (검증기준 ②)

- 엔드포인트·바디 전항목 공식 문서와 대조 — `POST /payments/{id}/confirm`(storeId·paymentToken = ConfirmPaymentBody)·`POST /billing-keys/confirm`(billingIssueToken = ConfirmBillingKeyBody)·`POST /payments/{id}/billing-key`(billingKey·channelKey·orderName·customer.id·amount.total·currency=KRW)·`GET /payments/{id}?storeId=`·`POST /payments/{id}/cancel` — **전부 일치**.
- 오류 본문 `{ type, message }`(+`pgCode`·`pgMessage`, failure 객체) 정규화·`code = payload[:code] || payload[:type]` — 문서 규격과 일치. `escape()`로 경로 파라미터 인젝션 방지.
- `Authorization: PortOne {secret}` 형식·storeId 필수 포함 — 문서 일치.
- JS SDK 파라미터 — `requestPayment`(storeId·channelKey·paymentId·orderName·totalAmount·payMethod)·`requestIssueBillingKey`(billingKeyMethod:"CARD"·customer.customerId)·응답(paymentId·paymentToken·billingIssueToken·code·message)·`currency:"KRW"`(npm 0.1.13 PaymentCurrency="KRW" 실측 — 문서 예시의 `CURRENCY_KRW`도 허용 타입) — **일치. 단 KG이니시스 필수 파라미터 누락은 B1**.

## 컬럼 rename 완전성 (검증기준 ③)

- 마이그레이션 up/down 대칭·부분 고유 인덱스 SQLite 재정의 순서(선삭제→rename→재생성) 타당 — 스키마에 `pg_*` 전면 반영(schema.rb:81-89,142-148), dev 왕복 롤백 데이터 무손실 실측.
- `app/`·`config/`의 `toss_`/`TossPayments` 잔존: **0건**(라틴 문자열 기준 — routes 주석 1건은 W3). `test/`의 toss 참조는 Phase 7 대기 합의 파일(별칭 헬퍼)·갱신 대상 구테스트로 범위 외. fixtures는 `pg_*`로 갱신(값 무변경).

## 크린 컷오버 (검증기준 ⑤)

- `app/services/toss_payments/`·`webhooks/toss_controller.rb`·`toss_*.js`·`/webhooks/toss` 라우트·동반 테스트 2종 삭제 확인(git 상태 + grep). `TossPayments` 상수 소멸(dev 실측). PRD v0.21 PLAN-5 본문·§6.19 갱신 확인(문서 선행 충족). 잔재: W3 주석·Q2 privacy 표기.

## UI 정합 (검증기준 ⑥)

- SDK 스크립트 `https://cdn.portone.io/v2/browser-sdk.js`(show.html.erb:6) — 공식 CDN 경로 일치. Stimulus 데이터 속성 ↔ values(storeId·channelKey·paymentId·amount:Number·callbackUrl / customerId) 정합, eagerLoad 자동 등록 확인. **단 B1(필수 파라미터)·C2(redirectUrl)가 우선 해결 과제.**

## 이전 이슈 해소 매핑 (vs _workspace_prev/05_review.md)

| 구 이슈 | 해소 확인 |
|---|---|
| #1 모호 실패 미발급·회복 불가 | ambiguous 분류 + 재조회 합류 + pending→웹훅 회복으로 해소 (단 C1 잔존) |
| #2 무한 재체험 / #3 activate! 주기 기준 | `used_trial` 플래그·`base = [now, trial_ends_at, period_end].max`(subscription.rb:55-72) 해소 |
| #4 갱신 이중 결제 | with_lock + 선주문 + paymentId 멱등(포트원 거부) 해소 |
| #5 GET 해지 CSRF | card_callback(GET)은 토큰 수신 전용·해지 PATCH 전용 — 구조 해소 |
| #6 Free 해지 | `plus? && (active?||trialing?)` 가드 해소 |
| #7 패스 미소비 | `monthly_invoice_limit_reached?`의 usable 패스 분기로 연결 |
| #8 웹훅 견고성 | paymentId 가드·JSON 파싱 rescue 해소 — ApiError 500은 W4로 잔존 |
| #10 with_lock 내 HTTP / #11 토큰 URL | 60초로 증가(W5)·issue_token URL 동일 패턴 유지(일회용 토큰, 수용) |

## Rule ID 준수 매핑

| Rule | 구현 반영 | 판정 |
|---|---|---|
| PLAN-5 (결제 PG·빌링키·단건·웹훅 반영) | 래퍼 5 메서드 + 웹훅 재조회 + 빌링키 발급/차감/해지 유지 | 준수 (B1·C1·C2·W1 예외) |
| PLAN-2 (Plus 9,900·14일 체험 1회) | `PLUS_MONTHLY_PRICE`·`TRIAL_DAYS`·used_trial 가드 유지 | 준수 (Q1 확인) |
| PLAN-4 (수금 패스 10건 4,000원) | `PRODUCT_AMOUNTS`·FulfillPassService 10건/90일 유지 | 준수 |
| PLAN-6 (환불 콘솔 수동) | 웹훅 취소는 상태 동기화만 — 정책 유지 | 준수 |
| SEC-5 준용(발송 멱등성 원칙) | 결제 확정점 단일화(with_lock+pending 재판정)·웹훅 멱등 | 준수 (C1 경로 제외) |
| P4(거래 기록 영구) | 갱신·실패·회복 이력 전부 Order로 기록, metadata에 PG 원문 보존 | 준수 |
| ARCHITECTURE §4(외부 API wrapper 캡슐화) | 포트원 API는 `PortOne::ClientService` 경유만 — grep 확인, 도메인 서비스는 주입 | 준수 |
| TIME-1 | 결제 시각 `Time.current`·주기 산정 앱 TZ 기준 유지 | 준수 |

## Tester에게 제안하는 중점 테스트 영역 (Phase 7)

1. **B1 수정 후 위젯 E2E(최우선)** — KG이니시스 테스트 채널로 ① 수금 패스 결제 ② 카드 등록 성공 경로. PC·모바일 각각(customer 필수 항목·offerPeriod 분기 포함). 현재 테스트는 전부 Fake 클라이언트라 이 결함을 잡지 못한다.
2. **C1 시나리오** — ① ambiguous 실패(get_payment도 실패) → 콜백 재시도 → confirm이 `ALREADY_PAID`(401/400, code="ALREADY_PAID") 반환 케이스: 발급 보장 여부 ② 웹훅이 failed 주문에 Transaction.Paid 전달 시 동작.
3. **C2 수정 후 모바일 실측** — 리다이렉트 방식 전환 시 콜백 쿼리(paymentId·paymentToken·code·message·billingIssueToken) 파싱 호환성.
4. **웹훅 시스템 테스트 갱신** — `Transaction.Paid/Cancelled/Failed/PartialCancelled` 본문, 재조회 위조 결합(paymentId 불일치) 흡수, 재발송 멱등(패스 중복 발급 없음), `BillingKey.Issued`·깨진 JSON 200.
5. **래퍼 단위 테스트 갱신** — `FakePortOneClient` 시그니처(payment_id·payment_token·channel_key·customer_id·order_name)로 전환, `PortOne::ApiError`(status·code·pg_code·ambiguous?) 분기, Idempotency-Key quoted UUID·타임아웃 60초 전송 계층 stub 검증.
6. **회귀** — 갱신 멱등(같은 pending 재사용)·스티키 가드·`settle_renewal` 연장 1회·체험만료 잡 `pg_billing_key: nil` 조건.
7. **설정 확인(테스트 전제)** — INIBillTst 채널 수동 승인 ON 여부가 카드 등록 테스트의 하드 전제(W1).
