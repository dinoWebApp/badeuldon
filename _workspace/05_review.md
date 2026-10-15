# 05_review.md — F-PLAN 구독·과금 리뷰

- **일자**: 2026-10-15 · **리뷰어**: PlanReviewer
- **대상**: `_workspace/03_implementation.md` 변경분 전수(마이그레이션 1·모델 4·서비스 4·잡 2·컨트롤러 4·뷰 4·라우트·recurring.yml·한도 전환 4파일)
- **기준**: PRD v0.20 §6.10(PLAN-1~8) · §6.19(EXT) · 검증 우선순위 ①결제 무결성 ②한도 전환 ③토스 래퍼 보안 ④구독 생명주기 ⑤웹훅 ⑥UI

## Status: CHANGES_REQUESTED

**BLOCKER 1건** — 결제 무결성(유료 결제·미발급·회복 불가 경로). 수정 후 해당 경로 재리뷰 대상.
코드 스타일은 Phase 4 통과(116파일 0오펜스) 전제로 제외했다. 이하 지적은 전부 비즈니스 정합성·보안·금전 무결성 영역이다.

---

## 이슈 목록

| # | Severity | Rule ID | File:Line | 설명 | 수정 제안 |
|---|----------|---------|-----------|------|-----------|
| 1 | **BLOCKER** | PLAN-5 (SEC-5 준용) | `app/services/orders/purchase_service.rb:27-30,53-60` · `app/controllers/webhooks/toss_controller.rb:30` | **승인 모호 실패(TIMEOUT 등) 시 결제 성공·패스 미발급·회복 불가.** `confirm_payment`가 Read Timeout으로 실패해도 실제로는 토스에서 승인 완료일 수 있다(요청 도달 후 응답 유실). 현재는 이를 즉시 `failed`로 확정하며, `record_failure!`는 `toss_payment_key`를 저장하지 않는다(pending 승인 성공 시에만 `mark_paid!`에서 저장). 따라서 ① 사용자는 4,000원 결제 후 패스 미발급 ② 토스 웹훅(DONE)이 와도 `find_by!(toss_payment_key:)`로 주문을 찾을 수 없어(`RecordNotFound`→200 흡수) 자동 회복 불가 ③ 재구매 시 신규 주문으로 이중 결제. 웹훅의 DONE→paid 매핑은 `toss_payment_key`가 이미 저장된(paid) 주문만 매칭 가능해 사실상 도달 불가한 코드가 됨. | (a) `TIMEOUT`/`CONNECTION` 코드는 모호 실패로 확정 취급 금지 — `get_payment(payment_key:)`로 실제 상태 재확인 후 DONE이면 정상 발급 경로로 합류 (b) 실패 기록 시에도 `toss_payment_key`·원문 응답을 metadata에 보존해 웹훅/CS 조사 경로 확보 (c) 웹훅에서 pending→paid 전이 시(수금 패스) 발급 멱등 로직 수행 — 3자 중 최소 2개 적용 |
| 2 | **CRITICAL** | PLAN-2 | `app/models/subscription.rb:47-49,66-69` · `app/services/subscriptions/upgrade_service.rb:33-38` | **체험 무한 반복(14일 무료 Plus 영구 이용).** 가드가 `subscription.free?`(plan)만 검사한다. 체험 만료 후 `expire!`는 plan을 free로 돌리며 `trial_ends_at`까지 nil로 소각해 체험 이력이 남지 않는다. 만료 직후(매일 06:00 Job) 다시 「체험 시작」 → 즉시 재체험 가능. 카드 등록 없이 무한 14일 Plus(무제한 청구·거래처) 이용. PLAN-2 "첫 14일 무료 체험"·01_plan "재가입: 새로운 체험 아님" 위반. | 체험 이력을 남긴 상태로 가드: `trial_used_at`(또는 만료 시 `trial_ends_at` 유지 + `trial_used?` 판정) 컬럼 추가 후 `start_trial`에서 `raise` — 1인 1회. 마이그레이션 수반 |
| 3 | **CRITICAL** | PLAN-2 | `app/models/subscription.rb:53-56` | **`activate!` 주기 기준점 오류 — 두 방향 금전 부정합.** 주기 시작을 항상 `Time.current`로 잡는다. ① 체험 중 조기 카드 등록: 유료 주기가 즉시 시작해 첫 차감일이 등록시점+1개월 = 체험 잔여일만큼 사용자가 유료 기간에 편입(뷰 안내문 "체험이 끝난 뒤 자동 결제"와 모순 — 사용자 손해). ② 해지 잔여 기간 중 카드 재등록(수동 PATCH 경로로 도달 가능): 기존 결제 주기 말(`current_period_end`)이 무시되고 now+1개월로 리셋 — 기존 결제 기간과 새 주기가 겹치는 일수만큼 무료 연장(사업자 손해, 최대 약 1개월). | 주기 기준을 `base = [Time.current, trial_ends_at, current_period_end].compact.max`로 잡고 `trial_ends_at`은 activate 시 정리(또는 준수). `extend_period!`와 동일한 원칙으로 통일 |
| 4 | **CRITICAL** | PLAN-5 (SEC-5 준용) | `app/services/subscriptions/upgrade_service.rb:68-75,90-107` · `app/jobs/subscription_renewal_job.rb:9-15` | **자동 갱신 이중 결제 방어 부재.** (a) `renew`의 판정(주기 종료)→차감→연장이 `with_lock` 없음 — 잡 동시 수동·스케줄 병렬 시 같은 구독 2회 차감 가능 (b) `order_id`를 차단 성공 후에야 생성·기록 — 토스 차단 성공 직후 프로세스 종료/DB 실패 시 주기가 미래화되지 않아 익일 잡이 새 UUID로 재차감(선(先)주문 기록 부재로 멱등키 상실) (c) `TIMEOUT`/`CONNECTION` 모호 오류도 `record_failed_charge!`+`expire!` 확정 — 차단이 실제 성공했을 수 있는 상태에서 강등·실패 처리(차감 성공+Free 강등 동시 발생). 단건(PurchaseService)은 with_lock+pending 재판정으로 방어한 것과 대조됨. | `subscription.with_lock` 하에서 주기 종료 재판정 후 차단; 차단 전 `Order(pending, toss_order_id)` 선기록 → 성공 시 paid 전환·재실행 시 동일 주문으로 멱등; 모호 오류(TIMEOUT/CONNECTION)는 확정 실패 처리 금지(재조회 또는 재시도 대상으로 분리). `retry_on` 명시도 함께(체크리스트 §6) |
| 5 | **CRITICAL** | SEC(CSRF) / PLAN-5 | `config/routes.rb:33` · `app/controllers/app/subscriptions_controller.rb:14-20,33-39` | **GET 요청으로 Plus 해지 실행 가능(상태 변경 GET + CSRF).** `get :card_callback → subscriptions#update`인데 `update`는 `auth_key` 부재 시 `cancel`로 분기한다. GET은 Rails CSRF 검증 대상이 아니고 SameSite=Lax 쿠키는 최상위 링크 이동에 전송되므로, 로그인 사용자가 악성 링크(예: `<a href="/app/subscription/card_callback">`) 클릭만으로 Plus가 해지된다. 토스 successUrl(GET)은 authKey 수신이 목적 — cancel이 같은 경로를 타는 것이 구조적 결함. | `update`에서 `request.get? && auth_key.blank?`면 no-op 리다이렉트(또는 card_callback을 authKey 전용 액션으로 분리). 해지는 PATCH 폼(토큰 검증)만 허용 |
| 6 | **CRITICAL** | PLAN-2(생명주기) | `app/services/subscriptions/upgrade_service.rb:50-55` | **Free 구독 해지 가능 — 넌센스 상태.** `cancel` 가드가 `subscription.active?`만 검사해 Free(free/active) 사용자의 PATCH 해지가 통과된다. 결과 `free/cancelled`: 주기 nil인데 "…까지 Plus로 이용할 수 있습니다" 문구(빈 날짜), 갱신 잡도 제외(`current_period_end nil`)돼 영구 방치. INV-4가 상태 전이를 강제하는 것과 같은 수준의 생명주기 무결성 결함. | 가드를 `subscription.plus? && subscription.active?`로 — Free 해지 시 `UpgradeError` |
| 7 | **CRITICAL** | PLAN-4 | `app/models/payment_pass.rb:26-33` · `app/views/app/billing/show.html.erb:121-138` | **수금 패스 소비 지점 미연결 — 효력 없는 상품 판매.** `use!`/`usable`의 앱 내 호출부가 전혀 없다(grep 전수 확인: 컨트롤러·서비스·모델 어디서도 차감하지 않음). 01_plan §A는 "사용 차감: 발행 시 remaining_uses -= 1"을 명시했고 후속 제외 목록(dunning·LEGAL·환불·어드민)에도 없다. 현재 4,000원 결제 UI만 존재하고 구매 결과물이 어떤 기능도 열지 않음(자동 시퀀스는 F-REM 미구현 상태). 테스트 키 마일스톤이라 실과금은 없으나 출시 시 금전 직결. | (a) F-REM 연동 전 판매 버튼·체크아웃 비노출, 또는 (b) 소비 규칙(발행 시 차감 등)을 F-REM 설계와 함께 확정해 PRD·플랜에 명시 후 구현. 현재 플랜-구현 불일치는 최소한 03_implementation에 명시돼야 했음 |
| 8 | WARNING | PLAN-5 | `app/controllers/webhooks/toss_controller.rb:19-25,29-36` | **웹훅 견고성 2건.** ① 이벤트 `data.paymentKey` 부재 시 `find_by!(toss_payment_key: nil)`이 `IS NULL` 매칭으로 임의 미승인 주문을 집어 `get_payment(nil)` → 토스 404 → 미처리 `ApiError`로 500(재시도 유발). ② 파일 상단 "응답은 항상 200" 명세와 달리 `get_payment` 실패(ApiError)는 500을 반환 — 과도 재시도는 없으나 명세·구현 불일치. 또한 `parse`에서 2xx·비JSON 응답 시 `JSON::ParserError`가 `ApiError`로 정규화되지 않아 호출부 rescue를 우회한다(client_service.rb:78-85). | ① `paymentKey` presence 가드 후 `head :ok` ② 명세를 "파싱·조회 실패는 5xx로 재시도 유도"로 정정하거나 rescue 추가 ③ `parse`에 `JSON::ParserError` → `ApiError` 정규화 |
| 9 | WARNING | PLAN-6 | `app/controllers/webhooks/toss_controller.rb:33-35` | **환불(CANCELED) 웹훅이 주문 상태만 동기화** — 수금 패스 잔여 회수·Plus 구독 중단 없음. 구현 판단 기록 #6으로 문서화된 범위(토스 콘솔 수동·ADMIN-4 후속)라 위반으로 보지 않으나, 콘솔 환불 시 무상 이용이 지속되는 갭은 어드민 화면 이전에도 운영 매뉴얼·추적 수단이 필요. | ADMIN-4(F-ADMIN)에서 환불 동기화·회수 정책 구현 시 본 항목 이관. 그 전에 03_implementation 후속 목록에 명시 유지 |
| 10 | WARNING | 성능/구조 | `app/services/orders/purchase_service.rb:16-25` | **외부 HTTP(최대 10초)가 `with_lock` 트랜잭션 내부에서 실행** — 승인 지연 시 주문 행 잠금·DB 커넥션 점유. 경합 방어 목적은 유효하나(잠금 덕에 pending 재판정이 원자적) 대규모 동시 구매 시 커넥션 풀 압박 여지. | 잠금은 pending 재판정에만 쓰고 승인 호출은 잠금 밖으로 내보내는 구조 검토(승인 후 재잠금·재판정). 현 규모에서는 수용 가능 |
| 11 | WARNING | SEC | `app/controllers/app/subscriptions_controller.rb:41-44` | **authKey가 URL 쿼리로 전달** — 카드 인증 위젯 successUrl이 토스 규격이라 불가피하나 액세스 로그에 일회용 단기 토큰이 남는다. 위변조 위험은 낮음(고객키-인증키 불일치 시 토스가 발급 거부 — 러너 실측 "존재하지 않는 빌링 결제 인증 정보" 확인). | 수용 가능. 라이브 전환 시 로그 스크러빙 또는 토큰 교환 페이지 방식 검토 기록만 유지 |
| 12 | WARNING | 프로세스 | `test/` 전체 | **신규 도메인 테스트 0건** — Subscription·Order·PaymentPass·서비스 2·잡 2·웹훅·한도 전환에 대한 테스트 파일이 전혀 없음(366 runs는 기존 테스트만, 러너 실측은 트랜잭션 롤백 스크립트로 대체). 금전 도메인 특성상 Phase 5(Tester)에서 시스템 테스트가 사실상 유일한 검증 계층이 됨. | 아래 Tester 중점 영역 전항 목록으로 보완. 최소한 모델 생명주기(체험 1회 포함)·PurchaseService 멱등은 모델/서비스 테스트로 상시 회귀 방어 권고 |

### 확인 요청(위양성 방지 — 판단 보류)

| 항목 | 내용 |
|---|---|
| Q1 | 토스 빌링 차단 API의 동일 `orderId` 재요청 동작(오류 vs 멱등 반환) — [INFERENCE] 공식 문서 확인 후 이슈 #4 수정안 (b)의 멱등키 전략 확정 필요 |
| Q2 | 결제 승인(confirm) 성공 시 `paymentStatusChanged` 웹훅 발송 조건 — [INFERENCE] 발송된다고 가정하고 이슈 #1 회복 경로를 설계했으나, 콘솔 웹훅 URL 등록 여부와 함께 확인 필요(로컬 실측 불가 영역) |
]

---

## 결제 무결성 검증표 (검증기준 ①)

| 검증 항목 | 결과 | 근거(File:Line) |
|---|---|---|
| 단건 이중 결제 — 동시 콜백 | **방어됨** | `purchase_service.rb:17-19` — `with_lock` + pending 재판정. 두 번째 호출은 토스 승인 호출 자체 전에 `PurchaseError`로 차단(미승인 결제는 토스에서 자동 만료) |
| 단건 이중 결제 — 주문 적체 | **방어됨** | `orders_controller.rb:8-11` — pending 재사용으로 주문 누적 없음. `toss_order_id` 서버 UUID 고유 인덱스 |
| 금액 변조 — 클라이언트 amount 조작 | **방어됨** | 주문 생성은 서버 정가(`Order.amount_for`·`PRODUCT_AMOUNTS`)만 사용; `confirm_payment`에 `@order.amount`(서버 원값)만 전달(`purchase_service.rb:34-38`); 콜백 파라미터 금액 무시. 위젯 data-amount 변조 시 승인 단계에서 금액 불일치로 토스가 거절 |
| 금액 변조 — 갱신 차감액 | **방어됨** | `upgrade_service.rb:92-95` — `Subscription::PLUS_MONTHLY_PRICE` 상수 단일 지점 |
| 승인 모호 실패(TIMEOUT/CONNECTION) | **미방어 — 이슈 #1(단건)·#4c(갱신)** | 실패 확정·회복 불가 |
| 갱신 이중 결제(병렬·크래시) | **미방어 — 이슈 #4a·#4b** | with_lock 부재·선주문 기록 부재 |
| Order status 전이 매트릭스 | **양호** | pending→paid(`mark_paid!`)·pending→failed(`record_failure!`)·paid→cancelled(웹훅 CANCELED). 역방향 전이 없음. 단 READY→pending 매핑은 도달 불가(미승인 주문은 paymentKey 미보관 — 이슈 #1과 동일 근원) |
| 수금 패스 remaining 0 차단 | **방어됨(차감 API 한정)** | `payment_pass.rb:26-33` — `with_lock` 재판정 + `UsesExhausted`; DB 체크 제약 `remaining_uses >= 0`(마이그레이션:64). **단 소비 호출부 부재 — 이슈 #7** |
| 소유권 격리 | **방어됨** | `orders_controller.rb:32-34` — `Current.user.orders.find_by!`; 빌링·구독은 `Current.user` 경유 `UpgradeService`. 웹훅은 비인증이나 값 미신뢰·재조회 방식 |
| 비밀키 노출 | **없음** | `secret_key`는 credentials만(`client_service.rb:14`), Basic Auth 헤더(로그 미출력), 뷰에는 `client_key`(공개)만 전달. ApiError 메시지는 토스 응답 code/message만 포함 |

## 한도 전환 검증표 (검증기준 ②)

| 시나리오 | 기대 | 실측/코드 근거 | 판정 |
|---|---|---|---|
| Free 거래처 6번째 등록 | 차단 | `subscription.rb:31-35` — `count >= Client::FREE_CLIENT_LIMIT(5)`; 러너 실측 12번 항목 | **준수** |
| Free 당월 4번째 발행 | 차단 | `subscription.rb:37-41` — `>= Invoice::FREE_MONTHLY_INVOICE_LIMIT(3)`; `invoice.rb` 발행 시점 검증 유지(무효 포함 산정 — 기존 해석); 러너 실측 13번 | **준수** |
| Plus 거래처·청구 | 무제한 | `plus? → false` 반환; 러너 실측 14-15번 | **준수** |
| 구독 행 없는 기존 사용자(픽스처) | Free 상수 폴백 | `user.rb` — `subscription` 부재 시 상수 비교. 미인증 무제한 우회 경로 없음 | **준수** |
| 구독 없는 사용자의 Client/Invoice 등록 | 정상 동작(폴백 한도 적용) | `client.rb`/`invoice.rb` — `user.nil?`·폴백 판정 통합. 기존 366 테스트 통과로 회귀 없음 | **준수** |
| 컨트롤러 @limit_reached 3곳 전환 | 구독 판정점 사용 | `clients_controller.rb` diff — 3곳 모두 `Current.user.client_limit_reached?` | **준수** |
| 한도 배너 → Plus 유도 | 링크 존재 | `clients/index.html.erb` — 「요금제 알아보기」 `app_billing_path` | **준수** |
| 만료(expired) 후 재체험으로 한도 우회 | 차단되어야 함 | 체험 재시작 허용 — **이슈 #2** | **위반** |
| Plus 해지 잔여 기간 중 한도 | 유지되어야 함 | `cancel!`은 plan 유지 — 만료 시점까지 plus 판정 | **준수** |

## 구독 생명주기 매트릭스 (검증기준 ④)

| 현재 상태 | 이벤트 | 결과 상태 | 판정 |
|---|---|---|---|
| (가입) free/active | User 생성 콜백 | 자동 생성 | ✓ `user.rb after_create` — 모든 생성 경로 1인 1구독(고유 인덱스 이중 방어) |
| free/active | 체험 시작 | plus/trialing(+14일) | ✓ PLAN-2 |
| plus/trialing | 만료+카드 없음 | free/expired | ✓ `TrialExpiryJob`(매일 06:00 KST) — 멱등 |
| plus/trialing | 카드 등록 | plus/active | ✗ 주기 기준 오류 — **이슈 #3①**(체험 잔여일 유료 편입, `trial_ends_at` 잔존) |
| free/active | 카드 직접 등록 | plus/active(후불 월 단위) | ✓ 설계 의도와 일치(첫 차감 = 주기 말) |
| plus/active | 주기 종료+카드 | 차감→plus/active+1개월 | ✗ 이중 방어 부재 — **이슈 #4** |
| plus/active | 차단 확정 실패 | free/expired + failed 주문 | ✓ 원자적(주문+강등 동일 트랜잭션). ✗ 모호 오류 포함 — **이슈 #4c** |
| plus/active | 해지 | plus/cancelled | ✓ 기간 종료까지 유지(PLAN-2/5). 빌링키 유지(재등록 UI 비노출로 재활용 경로 차단 — 선결제 재개는 만료 후) |
| plus/cancelled | 주기 종료 | free/expired | ✓ `RenewalJob` due 조건 `status IN (active,cancelled)` |
| free/active | 해지(PATCH) | free/cancelled | ✗ 넌센스 상태 — **이슈 #6** |
| free/expired | 카드 등록(재가입) | plus/active, 체험 없음 | ✓ 플랜 "재가입은 체험 아님" 준수 |
| free/expired | 체험 재시작 | plus/trialing | ✗ 체험 반복 — **이슈 #2** |
| cancelled | 체험 시작 | 차단("이미 Plus") | ✓ `free?` 가드 |
| 스케줄 | recurring.yml | 06:00/06:05 KST·fugit TZ 접미사 | ✓ TIME-1. 기존 production 키 병합 확인. test 미등록 |

## 웹훅 검증 (검증기준 ⑤)

| 항목 | 판정 | 근거 |
|---|---|---|
| 이벤트 값 미신뢰·get_payment 재조회 | **준수** | `toss_controller.rb:29-36` — 상태 확정은 재조회 응답만 사용. 위조 이벤트(값 변조)는 재조회 불일치로 무효 |
| 항상 200 | **부분** | JSON 파싱 오류·주문 미발견은 200 흡수. `get_payment` ApiError·비JSON 응답은 500 — 이슈 #8 |
| CSRF 면제 범위 | **영향 없음 확인** | `Webhooks::TossController < ActionController::Base` + `skip_forgery_protection`는 해당 컨트롤러 한정. `/webhooks/toss` 라우트도 이 컨트롤러만 pointing — 다른 경로 무관 |
| 상태 매핑 | **양호** | DONE→paid·CANCELED/PARTIAL_CANCELED→cancelled·ABORTED/EXPIRED→failed·기타→pending. 멱등(동일 상태 무변경) |
| 회복 경로 | **결함** | 미승인·실패 주문은 paymentKey 미보관으로 웹훅 매칭 불가 — 이슈 #1 |

## 토스 래퍼 보안 (검증기준 ③)

- **자격증명**: secret_key credentials 보관·서버 전용, 뷰 노출 없음(client_key만 공개 전달), 에러 메시지·metadata에 시크릿 미포함 ✓. 빌링키 DB 평문은 02_prd_update에 기록된 테스트 키 마일스톤 결정(라이브 시 암호화 검토) — 추적 가능 ✓
- **타임아웃**: 10초(open/read) ✓. **재시도 없음** — 모호 실패 즉시 확정과 결합해 이슈 #1·#4c의 근원
- **캡슐화**: 4 API 단일 래퍼·AR 무의존(stub 가능)·`ApiError` 명시적 예외 ✓ 아키텍처 준수
- **에러 처리**: Net 계열 오류 정규화 ✓. JSON 파싱 예외 누락 — 이슈 #8③

## UI 검증 (검증기준 ⑥)

- 플랜 비교 카드: Free 0원(3건·5거래처·수동 발송) / Plus 9,900원·부가세 포함·무제한·자동 시퀀스 — PLAN-1/2 수치 원문 일치 ✓. 발송 상한 5통 고지(PLAN-3/REM-12) ✓
- 배지 색: Plus emerald-800·Free 무채색 — DESIGN-2 준용 ✓. 체험/이용/해지예정/만료 문구 분기 ✓
- 버튼 UX: 해지 `turbo_confirm` ✓·303 리다이렉트 ✓·터치 타깃 min-h-11 ✓
- 수금 패스 구매 플로우: 주문→303→체크아웃(서버 원값)→위젯→콜백 승인 — 구조 ✓, 효력 없음(이슈 #7)
- PLAN-6 환불 불가 고지 ✓ (`show.html.erb:156-159`)
- noindex: `/app` 기존 `_head` 정책 적용 범위 내(`noindex?`) — 이번 변경 무관·이상 없음
- 사이드바 「요금제」·한도 배너 링크 — 표면 ② 요소, VIEW-8/SURF-4 무관 ✓

## Rule ID 준수 매핑

| Rule ID | 준수 | 비고 |
|---|---|---|
| PLAN-1 (Free 한도) | ○ | 한도 전환·상수 폴백·배너 모두 준수(위 검증표) |
| PLAN-2 (Plus 9,900·14일 체험) | △ | 금액·기간·해지 유지 준수. **체험 1회 위반(#2)·주기 기준 오류(#3)** |
| PLAN-3 (5통 상한) | ○ | 기존 유지·과금 UI 고지문 반영 |
| PLAN-4 (수금 패스) | △ | 발급(10건·90일)·차감 방어 준수. **소비 미연결(#7)** |
| PLAN-5 (토스·웹훅·BILLING) | △ | 빌링키 정기결제·웹훅 재조회·해지 기간 유지 준수. **결제 회복 경로(#1)·갱신 멱등(#4)** |
| PLAN-6 (환불 불가 고지) | ○ | 고지문 표시. 환불 처리 수동 정책 문서화 |
| PLAN-8 / PAY-5 | — | 계좌조회 자동입금 미구현 유지 — 준수(비목표 11) |
| SEC-5 준용(발송 멱등 원칙) | △ | 단건 결제 멱등 ✓. 갱신·모호 실패 미방어(#1·#4) |
| TIME-1 (KST) | ○ | 크론 `Asia/Seoul` 접미사·표기 헬퍼 KST |
| P4 (기록 영구) | ○ | 주문(성공·실패 스냅샷)·구독 이력 보존, 사용자 임의 삭제 경로 없음 |

## Tester에게 제안하는 중점 테스트 영역

1. **[B1] 승인 타임아웃 회복** — fake client가 `ApiError(TIMEOUT)` 반환 후 실제 DONE 상황 재현: 수정안 적용 뒤 (a) get_payment 재확인으로 paid+패스 발급 (b) 재구매 시 이중 결제 없음 (c) 실패 주문 metadata에 paymentKey 보존
2. **[B1] 웹훅 자가회복** — pending 주문 + 정상 DONE 웹훅 수신 시 패스 발급 멱등(동일 웹훅 2회 → 패스 1개)
3. **[#2] 체험 1회** — 만료 후 체험 재시작 거부(422/알림). 체험 이력이 강등·재가입 후에도 유지
4. **[#3] 체험 중 카드 등록** — 체험 2일차 등록 시 첫 차감일 = 체험 종료일+1개월(잔여 무료일 유지). 해지 잔여 기간 중 재등록 시 주기 = max(기존 종료일, now)+1개월
5. **[#4] 갱신 동시성·크래시** — `RenewalJob` 병렬 perform 2회 → 차단 1회; 차단 성공 후 DB 실패 주입 → 재실행 시 재차감 없음(선주문 멱등)
6. **[#4c] 갱신 모호 실패** — TIMEOUT 시 즉시 강등되지 않음(재시도/재조회 대기 상태) 확인
7. **[#5] GET 해지 CSRF** — 로그인 상태에서 `GET /app/subscription/card_callback`(파라미터 없음) → 해지 발생 안 함
8. **[#6] Free 해지 거부** — Free 사용자 PATCH 해지 → 오류·상태 불변(free/active 유지)
9. **[한도] 회귀** — Free 6번째 거래처·4번째 발행 차단 / Plus 무제한 / 구독 행 없는 사용자 폴백 / 발행-무효-재발행 한도 산정(무효 포함)
10. **[금액 변조]** — 위젯 data-amount 변조·콜백 amount 파라미터 위조 → 승인 거부 확인
11. **[웹훅 위조]** — 변조 이벤트(다른 paymentKey·빈 paymentKey) → 상태 무변경·200 (W1 수정 후)
12. **[체크아웃 UX]** — 구매 버튼 연타(주문 1개)·결제 취소(failUrl)·이미 처리된 결제 재콜백 안내문

## 재리뷰 범위 (수정 후)

이슈 #1(BLOCKER) 우선. #2~#7(CRITICAL)은 결제·구독 정합성이라 동일 수정 주기 권장. #8~#12(WARNING)은 후속 반영 가능.
