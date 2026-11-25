status: CHANGES_REQUESTED

# 05_review — 관리자 환불 실행: 포트원 결제 취소 연동·구독 즉시 Free·수금 패스 차감 (PLAN-9·ADMIN-11·Q27)

2026-11-24 · Reviewer · 대상: 신설 2파일 + 수정 12파일(미커밋) · **코드는 수정하지 않았다.**

**BLOCKER 0 · CRITICAL 2 · WARNING 9(이번 변경분 8 + 범위 밖 1) · 확인 요청 2(W-4c·W-7)**

## 0. 먼저 알려야 할 것 — 리뷰 중 포트원 실호출이 있었다(리뷰어 실수 2건 + 기존 테스트 결함 1건)

지시는 "test·development에서 포트원 실호출 금지, 테스트는 대역만 쓰는 기존 테스트로 제한"이었다. 나는 이를 두 번 어겼다. 숨기지 않고 적는다.

| # | 무슨 일 | 확정된 사실 | 모르는 것 |
|:--|:--|:--|:--|
| R1 | **내 임시 재현 테스트**(`P1`)가 `Subscriptions::DunningRetryJob.perform_now`를 대역 없이 실행 | 포트원 운영 호스트로 빌링키 차감 요청 **1회 전송**(인증 헤더 = 로드된 credentials 시크릿). 가짜 빌링키라 **`BILLING_KEY_NOT_FOUND`로 거부**됨 — `log/test.log` 152579행 구간(`metadata {"code":"BILLING_KEY_NOT_FOUND", …}`). 금전 거래 없음. 큐 어댑터가 `Test`라 재시도 잡은 실제 대기열에 남지 않았고 DB는 롤백됨 | 그 시크릿이 운영 키인지(값은 열어보지 않음). 운영 키라면 포트원 콘솔 로그에 실패 요청 1건이 있을 수 있다 |
| R2 | **내 가드 자가검사**가 가드 미로드 상태에서 실행됨(검증 스크립트를 `-r`로 넘겨 `RUBYOPT`보다 먼저 돌았고, 호스트명으로 실제 주소를 씀) | `Net::HTTP.start("api.portone.io", 443)`(빈 블록) + `TCPSocket.new("api.portone.io", 443)`가 예외 없이 완료 → TCP 연결 2회로 추정. **요청 본문·인증 헤더는 없음** | 연결 성공을 네트워크 수준에서 직접 확인하지는 않음(출력상 예외 없음) |
| R3 | **기존 테스트 결함(내 실행 아님)** — `test/services/subscriptions/dunning_retry_test.rb:135`가 `SubscriptionRenewalJob.perform_now`를 대역 없이 실행 | 전체 스위트를 외부 연결 차단 가드 하에 돌린 결과, 이 테스트에서 `client_service.rb:95`(실제 연결 지점) 호출이 **차단됨**. 잡이 due 구독 전체를 돌므로 fixture Plus 구독(빌링키 보유·주기 종료)에 차감을 시도한다(다음 테스트 146행 주석도 같은 간섭을 언급) | 이 테스트가 평소(가드 없이) 받는 실제 응답은 재실행하지 않아 관찰하지 않음. R1과 같은 요청 형태라 같은 거부(`BILLING_KEY_NOT_FOUND`)로 조용히 통과해 온 것으로 추정 |

- 조치: 임시 테스트 파일(`test/tmp_review_probe_test.rb`)은 **삭제했다**(저장소에 리뷰어가 만든 파일 없음 — `git status`로 확인). 그 뒤의 기존 테스트 실행은 전부 외부 연결 차단 가드를 건 채로 했다(그 안에서 차단 1건 = R3).
- 제안: test 환경에 포트원 아웃바운드를 전역 차단하는 장치가 없다(솔라피·이메일은 2026-11-20 사고 대응 가드 있음). R3은 이번 변경 밖이지만 `bin/rails test`·`bin/ci`를 돌릴 때마다 실요청 1건이 나가는 결함이므로 별도 수정이 필요하다.
- 내가 이후 실행에 쓴 가드(참고): `RUBYOPT=-r`로 미리 로드해 `Net::HTTP#connect`·`TCPSocket.new/open`·`IO.tcp`·`Socket.tcp`에서 비로컬 호스트를 즉시 예외로 막는 작은 스크립트. 대역 전송(식별자 교체)은 통과한다. 단 **스크립트 경로로 실행할 때만** 명령줄 `-r`보다 먼저 로드된다.

## 1. 요약

돈의 안전성에서 가장 중요한 두 기준은 **준수를 확인했다.**
- **이중 처리 없음**: PG는 이미 취소된 결제의 재취소를 거부하고(공식 409 `PaymentAlreadyCancelledError`), 로컬은 `with_lock`으로 직렬화된다. SQLite + Rails 8.1은 `with_lock` 시작 즉시 전역 쓰기 잠금을 잡아 두 번째 요청이 첫 요청 종료까지 대기한다(실험으로 확인).
- **로컬 변경은 PG 확정 뒤에만**: 재조회 판정을 통과해야 `finalize!`에 들어간다. PG 실패·타임아웃·확인 불가는 전부 로컬 무변경.

수정이 필요한 것은 둘이다.
- **C-1** dunning 중인 구독을 즉시 Free로 만들면 재시도 상태가 남는다. 회원이 카드를 재등록하면 예약된 재시도 잡이 **새 카드로 차감을 시도**한다(재현함).
- **C-2** PG 취소는 실행됐는데 로컬 확정이 실패하면 **감사 기록이 0건**이다(ADMIN-2). 재현함.

## 2. 검증 방법

| 항목 | 결과 |
|:---|:---|
| 포트원 V2 공식 스펙 대조 | **성공** — 공식 문서 저장소 `portone-io/developers.portone.io`의 `src/schema/v2.openapi.json`(OpenAPI 3.0.3, version 1.16.0)과 한국어 취소·웹훅 가이드 MDX 원문을 저장소 밖에서 `jq`로 추출. §5 |
| Rails 8.1.4.1 gem 소스 + test runner 실험 | 트랜잭션·`with_lock` 안 `return` → 정상 종료(`open_transactions=0`). `with_lock` 유지 중 다른 연결 쓰기·같은 행 `with_lock` 대기 1.2초(직렬화 확인) |
| 임시 재현 테스트 9건(`FakePortOneClient`) | 9 runs · 1 error — 8건 유효 결과(P1~P6·C1·C2), 1건은 내 스크립트 결함(P7 → 코드 추적으로 대체). **실행 후 삭제. P1에서 R1 사고 발생** |
| 기존 테스트 세트 1(관리자 주문·계정·주문·패스·웹훅·포트원 클라이언트) | 58 runs · 303 assertions · 0 failures |
| 기존 테스트 세트 2(회원 내용증명·세금계산서 정산·세금계산서) | 34 runs · 193 assertions · 0 failures |
| 전체 스위트(외부 연결 차단 가드 하) | 1,529 runs · 9,556 assertions · 0 failures · **1 error** — R3(가드가 기존 테스트의 실제 연결을 막은 것). 이번 변경으로 인한 회귀 없음 |
| `bin/rubocop` 변경 7파일(자동 교정 없음) | 위반 0 |
| `bin/rails zeitwerk:check` / `bin/rails routes` | 통과 / `refund_admin_order PATCH /admin/orders/:id/refund` |

## 3. 이슈 목록

### CRITICAL

#### C-1 · PLAN-9 ① · dunning 중인 구독을 즉시 Free로 만들면 재시도 상태가 남는다 — 재등록 뒤 새 카드로 차감 시도

- 위치: `app/services/orders/refund_service.rb:196-201`(`expire_subscription!`의 잠금 블록), `app/models/subscription.rb:108-111`(`expire!`)
- 문제: `Subscription#expire!`는 `dunning_stage`·`next_retry_at`을 지우지 않는다. 환불이 dunning 중인 구독에 `expire!`를 걸면 `plan=free·status=expired·빌링키=nil`이 되지만 **`dunning_stage≥1·next_retry_at(미래)`이 그대로 남고 `DunningRetryJob`도 예약돼 있다.** 회원이 재등록하면(`activate!`는 dunning을 초기화하지 않음) `dunning_active?`가 다시 true가 되고, 재시도 시각에 재시도 잡이 **재등록한 새 빌링키로 차감**한다.
- 재현(P1 로그): 환불 직후 `dunning_stage=1 next_retry_at 유지·dunning_active?=false` → `activate!` 뒤 `dunning_active?=true` → 재시도 잡 1회 실행에서 새 pending 주문 생성 + 차감 API 호출(내 환경에선 가짜 빌링키라 거부) + `dunning_stage 2·next_retry_at +3일`로 진행.
- 왜 이번 변경의 결함인가: 기존 코드에는 dunning 중인 구독을 `expire!`하는 경로가 없었다(`renew`는 dunning 중이면 무변경, 체험 만료 잡은 빌링키 없는 구독만, 관리자 콘솔은 기간 말 해지만). 이번 변경이 처음으로 "dunning 잔존 + expired" 상태를 만든다. PLAN-9가 "재구독 시 카드 재등록"을 전제하므로 이 경로가 열린다.
- 영향: 회원이 카드 등록만 했는데 예정 밖의 시점에 9,900원(또는 쿠폰가)이 차감되고 주기가 밀린다. 선행 조건은 드물다(dunning 중인 회원의 **이전** paid 주문을 환불하고, 재시도 전에 재등록).
- 수정: `expire_subscription!`의 `with_lock` 안에서 `subscription.reset_dunning!`(멱등)를 `expire!`와 함께 호출한다. `last_payment_failed_at`도 함께 비우는 것이 일관된다. 근본 수정(`activate!`에서 dunning 초기화)은 기존 `activate!` 경로도 같은 약점을 가지므로 별도 과제로 권한다.

#### C-2 · ADMIN-2 · PG 취소를 호출한 시도가 실패로 끝나면 감사 기록이 남지 않는다

- 위치: `app/services/orders/refund_service.rb:131-141`(감사 로그가 확정 트랜잭션 안에서 성공 시에만 기록), `:65-75`(PG 취소 호출은 트랜잭션 밖), `:216-219`
- 근거: PRD ADMIN-2 "회원 데이터 열람·수정·삭제, 플랜 변경, **환불 처리 등 모든 관리 행위를 감사 로그로 기록한다**(일시·대상·행위·사유)". ADMIN-1 선례도 거부된 접근을 감사한다.
- 문제: PG 취소 요청은 트랜잭션 밖에서 먼저 실행된다. 그런데 감사 로그는 로컬 확정 트랜잭션 안에만 있어서, 확정이 실패하면(롤백·422·500 어느 경로든) **"PG 쪽에는 환불이 실행됐는데 우리 감사 로그에는 아무것도 없는" 상태**가 된다. [INFERENCE] 판정이 틀려 재조회에서 실패하는 경우도 같다 — 이때는 재실행해도 같은 판정에서 계속 실패하므로 정산이 코드 수정 전까지 불가능하다.
- 재현(P2): PG 취소 호출 1회(성공) → 로컬 `RecordInvalid` → 실패 Result(422 경로). 주문 `paid`·`refunded? false`·**감사 `order_refund` 0건**·패스 잔여 그대로.
- 영향: 돈의 이중 처리는 아니다. 다만 돈이 실제로 움직인(움직였을 수 있는) 시도를 우리 쪽에서 추적할 수 없고, 권한 되돌리기 누락 상태가 관리자의 재시도에 의존한다 — 이 기능이 메우려던 구멍과 같은 상태다.
- 수정: PG 취소 호출 **직전**에 시도 감사를 별도 트랜잭션으로 기록한다(예: action `order_refund_attempt`, target=주문, detail=사유). 이어서 결과(성공·실패 사유)를 확정 뒤 또는 실패 분기에서 기록한다. 기존 성공 action `order_refund`는 그대로 둔다(기존 감사 화면·테스트와 정합). 사전 가드에서 걸린 시도(이미 환불·blank 사유)까지 남길지는 선택 — PG 호출이 없으므로 필수로 보지 않는다.

### WARNING

#### W-1 · 500 금지 선례 · PG 취소 뒤 로컬 예외가 서비스를 뚫고 나간다

- 위치: `app/services/orders/refund_service.rb:144`(구조 범위가 `RecordInvalid`·`RecordNotSaved`뿐), `app/controllers/admin/orders_controller.rb:24-33`
- 문제: 그 외 예외 — `ActiveRecord::StatementInvalid`(SQLite BUSY는 `StatementTimeout`으로 래핑됨), 감사 기록 중 오류, `metadata`가 해시가 아닌 경우 등 — 는 500이 된다. 이중 제출의 두 번째 요청이 5초를 넘게 기다리거나, 갱신 잡이 트랜잭션을 쥔 채 PG 호출 중일 때 현실적으로 걸린다.
- 재현(P3·C2): PG 취소 호출 1회 뒤 `StatementInvalid`가 컨트롤러까지 전파(운영이면 500). 주문 `paid` 유지.
- 수정: `finalize!`의 구조에 `ActiveRecord::StatementInvalid`·`ActiveRecord::ConcurrencyError`를 추가하고, 컨트롤러에 `rescue_from`(422 재렌더 + "PG 취소 상태를 확인한 뒤 다시 실행" 안내)를 둔다. C-2의 시도 감사가 있으면 이 경로도 기록이 남는다.

#### W-2 · [INFERENCE] 정리 · 취소 내역 금액 키가 공식 스펙과 다르다 · `CONSOLE_CANCELLED`는 스펙에 없다

- 위치: `app/services/orders/refund_service.rb:120-125`(`cancellations_total`), `:25`(`FULL_CANCELLED_STATUSES`)
- 확인(§5): 공식 취소 내역의 금액 필드는 **`totalAmount`**(required)다. 코드의 후보 키 `cancellationAmount`·`amount`는 응답에 없다. 취소 내역 `status`는 `SUCCEEDED`·`REQUESTED`·`FAILED` 세 가지다.
- 영향: 지금은 무해하다 — `amount.cancelled`이 required라 `cancellations_total`은 정상 응답에서 도달하지 않는다. 다만 틀린 키라 **향후 폴백을 쓰게 되면 0을 합산**하고, 키만 고치면 `REQUESTED`·`FAILED` 항목까지 합산할 수 있다.
- `CONSOLE_CANCELLED`는 공식 `PaymentStatus` enum 어디에도 없다(스펙·가이드 0회). 콘솔 취소도 상태는 `CANCELLED`다.
- 수정: 주석의 [INFERENCE]를 확정값으로 바꾸고, 폴백은 `status == "SUCCEEDED"` 항목의 `totalAmount`만 더한다. `CONSOLE_CANCELLED`는 제거하거나 근거를 적는다(웹훅 상수는 변경 없음이라 이번에 건드리지 않아도 된다).

#### W-3 · fail-closed 주석과 실제 동작 · `amount.total` 폴백이 "결제 완료 사실"을 대신한다

- 위치: `app/services/orders/refund_service.rb:102-108`
- 재현(P4-3): `amount.paid` 누락 + `CANCELLED` + `total`만 있는 응답 → **성공**. 주석("결제 완료 사실을 금액 필드로 못 찾으면 절대 성공 처리하지 않는다")과 어긋난다.
- 영향: 낮다. 공식 스펙상 `paid`는 required이고 로컬 `paid_at` 가드가 앞서 있다(미결제 취소는 `paid=0`으로 막힘 — P4-4 논리 확인).
- 수정: `total` 폴백을 제거한다. 재조회 응답의 `payment[:id]`가 `pg_order_id`와 같은지도 확인한다(웹훅 선례 `portone_controller.rb:56`).

#### W-4 · 취소 요청 설계 · 원인 메시지 상실 · 비동기 취소 · 부분 취소 가드의 위치

- 위치: `app/services/orders/refund_service.rb:65-75`, `app/services/port_one/client_service.rb:57-60`(변경 없음)
- (a) 취소 요청 `ApiError`를 전부 흡수해 PG 거절 사유가 사라진다. 권한·스토어 불일치는 재조회가 같은 인증으로 실패해 막힌다. 나머지는 "전액 취소를 확인할 수 없습니다(상태: PAID)"만 남는다. → 흡수한 `ApiError`의 `code`를 실패 메시지에 덧붙인다.
- (b) 공식 문서상 200 응답의 `cancellation.status`가 `REQUESTED`(비동기)일 수 있다. 재조회를 즉시 1회만 하므로 그 경우 실패로 떨어지고 웹훅·재실행에 의존한다. 우리 결제수단(카드)은 동기일 것으로 보이나 확인하지 못했다.
- (c) **[확인 요청]** `PARTIAL_CANCELLED` 가드는 재조회 **뒤**에만 있다. 이미 부분 취소된 결제에 전액 취소를 요청하면 PG가 잔액 전액을 취소해 `CANCELLED`로 바뀔 수 있고, 그러면 가드 없이 성공한다(설계는 "부분 취소 건은 실패"). PG가 이 요청을 허용하는지는 확인하지 못했다(§6). 공식 `currentCancellableAmount`(주문 금액)을 취소 요청에 넣으면 PG가 잔액 불일치를 거부한다. 래퍼 변경이 필요해 권고로 남긴다.

#### W-5 · ADMIN-11 · 확인창·안내 문구의 정확성

- 위치: `app/helpers/admin/orders_helper.rb:12-25`, `app/views/admin/orders/show.html.erb:36, 50`, `app/views/app/tax_invoices/show.html.erb:73-79`
- (a) Plus: "즉시 Free로 바뀝니다"까지는 있으나 **남은 결제 기간은 몰수**된다는 고지가 없다(Q27 사유문이 확인창을 오실행 방지 수단으로 명시). 환불 대상이 아닌 다른 활성 결제는 그대로 남는다는 안내도 없다.
- (b) 수금 패스: "10건 차감"은 있으나 **이 주문의 패스가 아니라 회원 보유 패스 중 만료 임박순**에서 차감된다는 점이 없다.
- (c) 내용증명: "문서는 그대로 유지"라고 하지만 환불 뒤엔 정식 PDF를 다시 내려받을 수 없다(`paid?` 한정). 세금계산서도 마찬가지.
- (d) `show.html.erb:50` "PG 취소 요청 없이 재조회로 확인해 기록합니다"는 사실과 다르다 — 코드는 항상 취소 요청을 먼저 보낸다(이미 취소됨 → 409 흡수). 부분 취소된 선취소 건은 실패한다는 안내도 없다.
- (e) `show.html.erb:36` "상품별 되돌리기와 감사 로그 기록까지 완료되었습니다"가 **레거시 기록 전용 건**(`mark_refunded` 시절의 `refunded_at`, `metadata["refund"]` 없음)에도 뜬다. `@refund_info` 유무로 문구를 나눈다.
- (f) 세금계산서 "다시 발행 요청" 링크는 발행 이력이 있으면 `issue_guard_message`의 "이미 발행 요청된 청구서입니다"로 막혀 청구서 상세로 돌아간다(막다른 길). 바로 위 기존 분기(60-62행)의 "고객지원(문의)으로 연락" 문구를 따르는 것이 일관된다.
- 수정: 확인창 문구에 (a)(b)(c)를 한 문장씩 더하고 (d)(e)(f)를 고친다. `turbo_confirm` 방식 자체는 선례와 같고 실제로 동작한다(turbo-rails 2.0.23이 submitter의 속성을 지원).

#### W-6 · 이미 Free 판정이 좁다

- 위치: `app/services/orders/refund_service.rb:199`
- 재현(P5): 구독이 `free/active`(가입 기본)일 때 Plus 주문을 환불하면 `expire!`이 실행돼 `status=expired`로 바뀌고 메시지는 "구독 즉시 Free 전환"이다. 요금제는 그대로 `free`라 실질 영향은 없고 감사 요약만 부정확하다.
- 수정: `already_free = subscription.free? && (subscription.expired? || subscription.active?)` 또는 메시지를 상태에 맞춘다.

#### W-7 · [확인 요청] 설계상 열린 경합 — 환불 절차 도중 자동 갱신

- 위치: `app/services/orders/refund_service.rb:34-41`(사전 가드와 PG 확정 사이 수 초~60초)
- 그 창에 갱신 잡이 새 주문을 결제하면 새 paid 주문이 남고 구독만 즉시 Free가 된다. 발생 확률은 낮고(갱신은 일 1회 스윕) 관리자가 새 주문도 환불하면 되므로 코드 수정은 요구하지 않는다. 확인창 안내(W-5a)와 운영 주의(§9)로 다룬다.

#### W-8 · 문서·주석 정정 — "fail-closed라 환불 자체는 실패"는 절반만 맞다

- 위치: `_workspace/03_implementation.md` §6-1, `app/services/orders/refund_service.rb:80-84, 145, 186-189`
- 취소 요청은 재조회 판정 **앞에** 실행되므로, 판정이 실패해도 PG에서는 환불이 일어났을 수 있다. "성공 오인은 없다"는 맞지만 "안전한 실패"는 아니다(C-2와 같은 근원). 또 주석 145행·186-189행의 "PG 취소 후 로컬이 실패하면 주문은 cancelled로 남는다"는 롤백되는 경로에는 맞지 않는다(주문은 `paid`로 남고 웹훅 도착 뒤에야 cancelled).

#### W-9 (범위 밖) · 기존 테스트가 포트원 실호출을 시도한다 — §0 R3

- 위치: `test/services/subscriptions/dunning_retry_test.rb:134-136`
- `SubscriptionRenewalJob.perform_now`를 `with_portone_client`로 감싸지 않았다. 잡이 due 구독 전체를 돌므로 fixture Plus 구독에 차감을 시도한다. 개발자 보고의 "0 failures"는 포트원이 가짜 빌링키를 거부해 우연히 통과한 것이다. 이번 변경분은 아니므로 건수에는 넣었다(범위 밖 표기).
- 수정: 그 블록을 `with_portone_client(FakePortOneClient.new(...))`로 감싼다. 더 근본적으로는 test 환경에 포트원 아웃바운드 전역 차단을 둔다.

## 4. 중점 항목 판정 (1~19)

| # | 판정 | 근거 |
|:--|:--|:--|
| 1 | **문제 없음** | `finalize!`의 `with_lock` 뒤 `reload`·`refunded?` 재검사(`refund_service.rb:132-136`). 실험: A가 `with_lock` 유지 중 같은 행 `with_lock`이 1.21초 대기(첫 요청 종료까지 직렬화). 그 뒤 `reload`·`refunded?` 재검사로 422가 되는 것은 코드 논리(`:133-136`)이며 순차 재실행은 기존 테스트 ②로 확인했다. 병렬 실행의 끝까지는 재현하지 못했다(§6). PG는 재취소를 409로 거부(공식 `PaymentAlreadyCancelledError`). 두 번째 요청이 5초를 넘기면 W-1 |
| 2 | **문제 없음** | `call`의 순서(`:34-41`): `confirm_cancellation!`이 nil을 반환해야만 `finalize!`. `get_payment` 실패·판정 실패는 전부 `failure(...)` → 로컬 무변경 |
| 3 | **문제 없음(오탐 없음), 정리 3건** | 상태: 공식 enum `CANCELLED`=완전 취소, `PARTIAL_CANCELLED`=부분 → 명시 실패(`:87-89`). 미결제 취소는 `paid=0`이면 실패(코드 논리 `:107` — 실행 재현은 내 케이스 설계 결함으로 무효)이고 로컬 `paid_at` 가드가 먼저 막는다. 금액: 정수 원 단위·심볼 키(`symbolize_names`)·쿠폰가 주문 통과(P6). 정리: `total` 폴백(W-3), 취소 내역 키(W-2), `CONSOLE_CANCELLED`(W-2) |
| 4 | **대조 성공 → 확정** | §5. `amount.paid/total/cancelled`·`CANCELLED/PARTIAL_CANCELLED` 실제 필드·값. 틀렸을 때 결과: 성공 오인은 없음(실패 방향), 단 "돈은 나가고 기록 없음"은 발생(C-2) |
| 5 | **재조회가 커버함, 사유 상실은 W-4a** | 공식 409(`PaymentNotPaid`·`PaymentAlreadyCancelled`)·502(`PgProvider`)는 재조회에서 PAID/미결제로 판정 실패. 401·403은 재조회도 같은 인증으로 실패(`:73-75`). 타임아웃은 모호 실패 → 재조회 또는 재실행으로 수렴 |
| 6 | **문제 없음** | `payment_pass.rb:31-47`. 스코프 `usable.order(:expires_at, :id)`(만료 임박순), `with_lock` 뒤 `usable?` 재판정, `take = min(잔여, 남은 수량)`, `break`·`[revoked, count - revoked]`. 음수 불가(`remaining_uses >= 0` 검증 + 체크 제약). 만료 직후는 `next`로 건너뜀 |
| 7 | **문제 없음, 단 C-1·W-6** | 활성·해지(cancelled)·체험 → `expire!`(PRD "남은 기간과 무관"). free/expired → 무변경. free/active → `expire!` 실행(W-6, 경미). dunning 중 → 상태 잔존(**C-1**). `update_all`은 `user_id` + `pg_billing_key = 캡처값`으로 한정, 키가 nil이면 실행 안 함 → 타 회원·다른 키 무관(`:202-205`) |
| 8 | **기존 만료 경로와 동일** | `renew`: `active?` false·`current_period_end` nil → 무변경(`upgrade_service.rb:93-99`). `DunningRetryJob`: `dunning_active?` false → no-op(`dunning_retry_job.rb:20`). 체험 만료 잡: `trialing`/`cancelled`만. 갱신 스윕 대상 제외. 반복 발행은 `Subscription` 한도 메서드(`plus?`)로 Free 한도 적용. 예외는 재등록 뒤(C-1) |
| 9 | **SQLite에서는 교착 불가** | Rails 8.1.4.1 SQLite 어댑터 `default_transaction_mode: :immediate`(gem 162행) — 트랜잭션이 첫 쿼리에서 `BEGIN IMMEDIATE`로 **전역 쓰기 잠금을 즉시 획득**. 실험: `with_lock` 유지 중 다른 연결의 무관한 행 쓰기도 1.2초 대기. 잠금이 하나뿐이라 순서 역전이 순환 대기를 만들 수 없다. 기존 코드에도 두 순서가 공존(`renew` 구독→주문, `settle_renewal` 주문→구독). 실제 위험은 교착이 아니라 **5초 초과 실패**(W-1). 행 잠금 DB로 이전 시에는 순서 통일 필요 |
| 10 | **문제 없음** | `within_new_transaction`(gem `transaction.rb:643`)이 `ensure`에서 비지역 반환을 커밋으로 처리. 실험: 반환값 정상·`open_transactions=0`·이후 다른 연결 쓰기 지연 0.0초 |
| 11 | **500 경로 있음 → W-1** | 구조 범위가 `RecordInvalid`·`RecordNotSaved`뿐. P3·C2로 재현. 회복은 재실행(웹훅이 `cancelled`로 바꾼 뒤 안내 노출)이지만 롤백 경로의 주석 서술은 부정확(W-8) |
| 12 | **ADMIN-2에 부합하지 않음 → C-2** | 성공 시·트랜잭션 안에서만 기록. PG 취소를 호출한 시도는 결과와 무관하게 기록해야 한다고 판정 |
| 13 | **웹훅 무변경 판정 타당** | 후행: `apply_status`의 `return if order.status == status`(`portone_controller.rb:72`) → 무동작. 선행: 웹훅이 `cancelled`로만 변경 → 실행 버튼으로 1회 정산(사전 가드 `paid? \|\| cancelled?`). 부분 취소 이벤트는 status만 `cancelled`로 동기화 → 서비스 재조회에서 `PARTIAL_CANCELLED` 명시 실패라 상충 없음. (P7 실행은 내 스크립트 결함으로 못 했고 코드 추적·기존 웹훅 테스트 통과로 확인) |
| 14 | **문제 없음** | 매출·수수료: `Order.paid.not_refunded`·`.plus_monthly.paid.not_refunded` — `status=cancelled`와 `refunded_at`으로 이중 제외. MRR: `Subscription.active.where(plan: :plus)` → expired 제외. 첫 결제 쿠폰: 쿠폰은 첫 차감 시점에 이미 소비되어 재할인 없음. 회원 조회: `find_paid_legal_order`·`tax_invoice_order_for(paid: true)`에서 빠져 재주문 가능(세금계산서는 발행 이력 가드가 남음 — W-5f) |
| 15 | **문제 없음** | `require_owner`는 `Admin::BaseController` protected(`:48-56`), `AdminsController`의 `before_action … except: %i[index]` 유지. 재현(C1): staff `PATCH` → **303**·`admin_console_denied` 1건·PG 호출 0·로컬 무변경. staff `show` 200에 폼 액션 없음·owner 안내 있음. 422 재렌더는 owner만 도달 |
| 16 | **준수** | Service는 `params`·`Current` 미참조(`admin:` 주입). 뷰의 `refunded?`·`paid?`·`pending?`는 DB를 hit하지 않는 인스턴스 판정으로, 규약 §3.6-1·§4.2가 금지하는 "DB 쿼리·모델 클래스 메서드"에 해당하지 않는다(변경 전에도 같은 호출). `PaymentPass::TOTAL_USES`는 상수(기존 뷰 선례 `Subscription::DUNNING_MAX_STAGE`). `order_payment_badge`는 `won`과 같은 자리의 회원 표현 헬퍼라 지적하지 않는다. 액션 9줄·`params.expect`·303/422 준수 |
| 17 | **동작 확인, 문구 보강 필요 → W-5** | 실행 효과 3요소(금액·구독·패스)는 있다. 몰수·차감 대상·재다운로드 불가 고지 부족. `turbo_confirm`은 변경 전(HEAD 44행)과 같은 방식 |
| 18 | **대체로 정확, 1건 부정확 → W-5d·W-5e** | "환불됨/환불 안 됨"은 `refunded_at` 기준으로 정확. "취소·환불"(cancelled)은 미결제 취소도 포함하는 포괄 표기라 무리 없음. 사유·실행자·금액은 모두 `<%= %>` 이스케이프 |
| 19 | **의미 유지·실호출 없음** | ① 303·`refunded?`·감사 1건 + `status cancelled` 확장(대역 `get_payment` 지정) ② 422·감사 미기록(`cancel_payment` raise_on으로 PG 무호출 보증) ③ 422·"환불 사유는 필수입니다". 세트 1 실행에서 외부 연결 0건 |

## 5. PG 응답 필드 대조 결과 (공식 스펙 원문)

출처: `github.com/portone-io/developers.portone.io` `src/schema/v2.openapi.json`(OpenAPI 3.0.3, `info.version 1.16.0`, servers `https://api.portone.io`), `src/routes/(root)/opi/ko/integration/cancel/v2/readme.mdx`, `…/webhook/readme-v2.mdx`. 문서 사이트 본문은 스크립트 렌더링이라 개요만 보였고, 공개 소스 저장소의 원문으로 대조했다. **PG API는 호출하지 않았다.**

| 항목 | 코드(개발자 후보) | 공식 스펙 | 판정 |
|:--|:--|:--|:--|
| 취소 요청 본문 | `{ storeId, reason }` | `CancelPaymentBody`: `reason` 필수, `amount` "값을 입력하지 않으면 전액 취소됩니다" | **정합** |
| 취소 응답 | 신뢰하지 않음(재조회 사용) | 200 = `PaymentCancellation`(`status`: `SUCCEEDED`/`REQUESTED`/`FAILED`) | 설계 타당. `REQUESTED`는 W-4b |
| 취소 오류 | `ApiError` 흡수 | 409 `PaymentNotPaidError`·`PaymentAlreadyCancelledError`·`CancelAmountExceedsCancellableAmountError` 등, 502 `PgProviderError` | 재조회가 커버 |
| `payment.status` | `CANCELLED`·`PARTIAL_CANCELLED`·`CONSOLE_CANCELLED` | enum: `READY`·`PENDING`·`VIRTUAL_ACCOUNT_ISSUED`·`PAID`·`FAILED`·`PARTIAL_CANCELLED`·`CANCELLED` | 앞 둘 일치. **`CONSOLE_CANCELLED` 없음**(W-2). `PAY_CANCELLED`·`CANCEL_PENDING`도 상태값 아님 |
| `amount.paid` | 후보 | `PaymentAmount` required, "실제 결제금액" | **확정** |
| `amount.total` | 폴백 | required, "총 결제금액" | 필드는 확정, 폴백은 W-3 |
| `amount.cancelled` | 후보 | required, "총 취소금액" | **확정** |
| `cancellations[].cancellationAmount` / `.amount` | 후보 | 둘 다 없음. 실제는 **`totalAmount`**(required). 항목 `status` 3종 | **불일치**(W-2) |
| 안전장치 옵션 | 미사용 | `currentCancellableAmount` "잔액이 일치하는 경우에만 취소가 진행" | W-4c 권고 |

## 6. 확인한 것 / 확인하지 못한 것

**확인함(코드·gem 소스·실험·공식 문서)**
- 이중 제출 직렬화, `return` 처리, SQLite 전역 쓰기 잠금(실험). PG 필드·상태 enum·취소 본문(공식 스펙).
- staff 차단·감사·폼 비노출(C1). PG 취소 뒤 로컬 실패 시 감사 0건·500 경로(P2·P3·C2). dunning 잔존·재등록 뒤 차감 시도(P1). `total` 폴백 성공(P4-3). free/active에서 `expire!`(P5). 쿠폰가 주문 통과(P6).
- 전체 스위트에서 이번 변경으로 인한 회귀 없음(1,528/1,529, 1건은 R3).

**확인하지 못함**
- 실제 포트원 응답 본문(전액 취소 뒤 `amount.paid`가 결제 금액으로 유지되는지) — 스펙상 같은 `PaymentAmount` 타입을 쓰므로 유지된다고 추정. **첫 실환불 1건으로 확인 필요.**
- 카드 결제의 취소가 동기(`SUCCEEDED`)로 끝나는지.
- PG가 이미 부분 취소된 결제의 `amount` 미지정 취소를 허용하는지(W-4c).
- 웹훅 선행·후행 도착의 실행 재현(P7 미실행) — 코드 추적과 기존 웹훅 테스트 통과로 갈음.
- 두 요청의 **실제 병렬** 실행(트랜잭션 픽스처가 스레드 간 격리됨) — runner 실험 [3]으로 대체.
- 브라우저에서 확인창이 실제로 뜨는 화면(선례상 시스템 테스트는 대화상자 문구를 검증하지 않음).
- 그 API 시크릿이 운영 키인지.

## 7. Rule ID 준수 매핑

| Rule ID | 판정 | 비고 |
|:--|:--|:--|
| PLAN-9 ① Plus → 즉시 Free | 구현 일치, **C-1** | 빌링키·주문 행 복사본 정리 범위 적정 |
| PLAN-9 ② 수금 패스 10건 차감 | 일치 | 만료 임박순·0에서 종료·음수 불가 |
| PLAN-9 ③ 발행물 그대로 | 일치 | 재다운로드 불고지는 W-5c |
| PLAN-9 확정 절차 | 일치 | PG 취소 → 재조회(결제 완료 + 전액 취소 모두) → `cancelled`·`refunded_at` → 되돌리기 → 감사 |
| PLAN-9 재동기화 | 일치 | 단 판정 자체가 실패하면 재실행으로 회복 불가(C-2) |
| ADMIN-11 owner 전용 | 일치 | staff 거부 + 감사 |
| ADMIN-11 확인창 실행 효과 | 부분 | 3요소 있음, 몰수 등 미고지(W-5) |
| ADMIN-11 미정산·미결제 안내 | 일치(문구 1건 부정확) | W-5d |
| ADMIN-2 감사 | **불일치** | 시도 미기록(C-2) |
| ADMIN-5 매출 제외 | 일치 | 기존 스코프 그대로 |
| Q27 #6 빌링키만 정리 | 일치 | 카드 값 미취급 |

## 8. Tester에게 제안하는 중점 테스트 영역

**실행 전 필수**: 잡·웹훅 경로 테스트는 반드시 `with_portone_client`(또는 서비스에 `client:` 주입)로 감싼다. `DunningRetryJob`·`SubscriptionRenewalJob`은 내부에서 기본 클라이언트를 만들므로 대역 없이 실행하면 실호출이 난다(R1·R3).

1. **C-1 회귀**: dunning 1단계 구독의 이전 paid 주문 환불 → `dunning_stage 0`·`next_retry_at nil` → 재등록(`activate!`) → `dunning_active? false` → 재시도 잡이 차감 API를 호출하지 않음(`fake.calls[:charge_billing_key]` 빈 배열).
2. **C-2 회귀**: PG 취소 성공 + 확정 실패(감사 서비스가 예외) → 시도 감사 1건 이상. PG 오류·확인 불가 각각 → 시도 감사 기록.
3. 상품 4종 각각 정상(Plus·패스·내용증명·세금계산서) + 패스 잔여 부족 → 0에서 종료·`[revoked, ignored]` 값.
4. 예외: `get_payment` ApiError·PARTIAL_CANCELLED·paid=0·REQUESTED 항목·쿠폰가 주문·`paid_at` 없는 cancelled·pending/failed·blank 사유 → 전부 로컬 무변경·PG 취소 호출 0(가드에서 걸리는 경우).
5. 웹훅 선행 도착 → 실행 1회 / 후행 도착 → 무변경 / 부분 취소 이벤트.
6. 권한: staff PATCH 거부·감사·PG 무호출. 소유권(다른 회원 주문 id) — 관리자 화면이라 해당 없음.
7. 회원 표기: 환불된 내용증명·세금계산서 쇼에서 "환불됨"·다운로드 버튼 없음·`download` 직접 접근 시 워터마크 PDF.
8. 집계: 환불 뒤 매출·수수료 집계에서 제외, MRR 감소.

## 9. 운영상 주의 (APPROVED 뒤에도)

- **첫 실환불은 실제 결제 1건(수금 패스)으로** 하고, 그때 `amount.paid`가 유지되는지와 취소가 동기로 끝나는지를 확인한다.
- **실패 메시지가 떠도 PG 쪽에서는 환불이 실행됐을 수 있다.** "전액 취소를 확인할 수 없습니다"·500이 나오면 포트원 콘솔에서 해당 결제의 취소 상태를 먼저 확인한다. 웹훅으로 주문이 "취소·환불"로 보이면 상세 화면의 재실행 버튼으로 정산한다.
- 갱신 스윕 시각(일 1회)에는 환불을 실행하지 않는다(W-1·W-7).
- KG이니시스 콘솔에서 직접 환불하면 포트원 상태가 `PAID`로 남아 이 기능으로 정산할 수 없다(공식 가이드 주의사항).
- 환불은 회원에게 알리지 않는다(PRD 후속 과제).
- PG 수수료는 환불 뒤에도 돌아오지 않을 수 있다.
