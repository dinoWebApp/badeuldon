# 01_plan — 관리자 환불 실행: 포트원 결제 취소 연동·구독 즉시 Free·수금 패스 차감 (2026-11-24, 일반 모드·Full)

## 배경·목표

**사용자 요청(2026-11-24)**: 관리자 페이지에서 결제된 결제건을 취소할 때 ① **실제 환불을 포트원 결제 취소와
연동**하고 ② **바로(즉시 전액) 환불**하며 ③ **회원 구독 정보도 즉시 Free**로 바꾼다. ④ 건별 결제 상품(수금
패스)은 **결제한 수만큼 차감**하되 0이 되면 나머지는 신경 쓰지 않는다.

**현 상태(코드 확인)**:
- 관리자 "환불 사유 기록"(`Admin::OrdersController#mark_refunded`)은 **기록만** 한다 — 실제 PG 환불은
  포트원 콘솔에서 수동(PLAN-5·PLAN-6). 구독·패스는 바뀌지 않는다.
- `PortOne::ClientService#cancel_payment`(전액 취소, `POST /payments/{paymentId}/cancel`, 본문
  `{ storeId, reason }`)는 **이미 구현·단위 테스트 있음** — 앱에서 호출하는 곳은 없다.
- 관리자 "구독 해지"(`Admins::MemberAdminService#cancel_subscription!`)는 기간 말까지 유효한 해지다.
  즉시 Free 전환은 `Subscription#expire!`(plan free·빌링키·주기 삭제)이 하지만 관리자 화면에 노출돼
  있지 않다.
- `payment_passes`는 **주문과 연결되지 않는다**(user_id·total_uses·remaining_uses·expires_at만) —
  "그 주문으로 발급된 패스"를 특정할 수 없어 차감은 회원 단위로 한다.
- 웹훅(`Webhooks::PortOneController#apply_status`)은 `Transaction.Cancelled`를 받으면 주문 상태만
  `cancelled`로 바꾼다(이미 같은 상태면 아무 일도 하지 않는다). 패스 회수·환불 기록은 하지 않는다 —
  포트원 콘솔에서 수동 환불하면 **돈은 돌아갔는데 구독·패스는 그대로 남는 상태**가 된다(이번 작업의 구멍).
- 주문 구분: Plus 월 구독은 `product: plus_monthly`. 수금 패스·내용증명·세금계산서는 모두
  `product: collection_pass`이고 **`item_type`(pass / legal_doc / tax_invoice)으로만 구분**한다
  (`Order` 주석 참조).
- 포트원 결제 ID: 앱 전체가 `pg_order_id`를 포트원의 paymentId로 쓴다(confirm·get_payment·빌링키 차감).
- 카드 관련 저장 값: 카드번호·유효기간·CVC를 다루는 코드는 없다(포트원·KG이니시스가 보관). 우리 DB에는
  **빌링키**(자동결제용 식별자)만 있다 — `subscriptions.pg_billing_key`(결제에 사용)와 그 값이 복사된
  Plus 주문 행 `orders.pg_billing_key`(쓰기만 있고 읽는 곳은 없다).

**해석 확정(2026-11-24 사용자 — Q27)**:
1. 수금 패스: **구매 수량(10건)만큼 차감**, 모자라면 0에서 끝내고 나머지는 무시.
2. 발행물(내용증명·세금계산서): **환불만 하고 이미 생성·발행된 것은 건드리지 않는다**(세금계산서 취소 요청 없음).
3. 실행 권한: **최고 관리자(owner)만**. staff는 주문 조회만 가능하고 실행 폼이 보이지 않는다.
4. 카드 정보: 카드 번호 등은 저장하지 않는다. 환불 시 비우는 것은 **빌링키**다 — 구독의 키와 주문 행의
   복사본을 함께 비운다.

## 규모·파이프라인

- **Full** — 0→1→✋→2→3→4→5→6?→7→8→9. 외부 API 연동·새 서비스·컨트롤러·뷰·테스트.
- 호출 프로필(일반): `badeuldon-developer` → `badeuldon-reviewer` → `badeuldon-tester`.

## 관련 Rule ID

| Rule ID | 내용 | 이번 작업 |
|:---|:---|:---|
| PLAN-5 | 포트원 결제(빌링키·단건)·웹훅 | 기존 — 취소 연동이 이 규칙의 확장 |
| PLAN-6 | 이용권·패스권 환불 불가 정책(운영 예외 절차) | 관리자 환불 실행 절차 명문화 |
| ADMIN-1 | owner 전용 가드·거부 감사 | 환불 실행을 owner 전용으로 |
| ADMIN-2 | 감사 로그(환불 처리 포함) | 환불 실행 감사 |
| ADMIN-4 | 결제·매출 관리 — 환불 처리 | "사유 기록" → "환불 실행"으로 변경 |
| ADMIN-5 | 매출 집계는 환불 주문 제외(refunded_at) | 기존 그대로 적용 |
| **PLAN-9(신설)** | 관리자 환불 실행 — 즉시 전액 취소 + 상품별 되돌리기 | 신규 |
| **ADMIN-11(신설)** | 관리자 환불 실행 콘솔(owner 전용) | 신규 |

결정 기록: **Q27**(관리자 환불 실행 — 사용자 확정 4건 요청 + 해석 확정 3건 + 카드 저장 확인 1건).

## 설계 (Developer 지시 기준)

### 1. 환불 실행 서비스 `Orders::RefundService` (신설, `app/services/orders/`)

`call(admin:, order:, reason:, client: PortOne::ClientService.new)` → Result(
`Admins::MemberAdminService::Result` 선례 — success/errors/message). **전액·즉시 취소만** 취급한다
(부분 취소·예약 취소 없음).

순서:
1. **사전 가드**: `refunded?`면 실패("이미 환불 처리된 주문") / 상태가 `paid`·`cancelled`가 아니면(pending·
   failed) 실패 / **`paid_at`이 없으면** 실패(결제 완료 적이 없는 주문 — 가상계좌 말소 등) / `pg_order_id`
   없으면 실패 / 사유 blank면 실패.
2. **PG 취소** `client.cancel_payment(payment_id: order.pg_order_id, reason:)` — 트랜잭션 밖(외부 호출).
3. **PG 서버 재조회로 확정** `client.get_payment` — 취소 응답 본문이 아니라 재조회 결과를 신뢰한다(웹훅
   무결성 원칙과 동일). **전액 환불 확정 조건은 두 가지를 모두 만족해야 한다** — ① 재조회 결과에 결제 완료
   사실이 있다(결제 금액 ≥ 주문 금액), ② 전액 취소(결제 상태 `CANCELLED` 또는 취소 합계 ≥ 주문 금액).
   - 2에서 `ApiError`가 나도 **재조회를 먼저** 한다: 이미 전액 취소돼 있으면(포트원 콘솔에서 먼저 환불한
     건·우리 요청은 성공했는데 응답이 유실된 건) **성공으로 수렴**해 로컬 상태를 맞춘다(재동기화 경로).
   - 부분 취소(`PARTIAL_CANCELLED`)·결제 완료 사실이 없는 취소는 **실패** — PG 상태 문구와 함께 반환,
     로컬 변경 없음. (부분 취소 건은 콘솔에서 나머지를 환불한 뒤 다시 실행한다.)
4. **로컬 확정 트랜잭션**(`order.with_lock` + `ActiveRecord::Base.transaction`): 다시 1의 가드를
   검사해 통과한 쪽만 한 번 실행한다(이중 제출·경합 방지).
   - 주문 확정: `refunded_at`·`refund_reason`(기존 `mark_refunded!` 재사용) + **`status: :cancelled`** +
     `metadata`에 환불 실행 정보 병합(실행자·일시·환불 금액 — B-1 병합 선례). status를 바꾸는 이유: 포트원의
     결제가 취소됐다는 사실을 반영하고(콘솔 수동 환불 때 웹훅이 하던 것과 같은 결과) 웹훅 도착 순서와
     무관하게 같은 상태로 수렴시킨다. `refunded_at`이 "정산 완료"의 판정 기준이다.
   - 상품별 되돌리기(`product` + `item_type` 기준):
     - `plus_monthly` → 구독을 **즉시 Free**로(`Subscription#expire!` — plan free·status expired·빌링키·
       주기 삭제). 자동 갱신 잡와의 경합을 막기 위해 `subscription.with_lock` 안에서 실행한다. 이미
       Free·만료면 변경 없음(별도 상태 값은 없음 — 감사 로그로 구분).
       **빌링키 정리**: 비워진 구독의 키와 같은 값이 복사돼 있는 그 회원의 주문 행(`orders.pg_billing_key`)도
       함께 비운다.
     - `collection_pass` + `item_type pass`(수금 패스) → `PaymentPass`에 회원 단위 차감 메서드 신설(예:
       `PaymentPass.revoke_uses!(user:, count: 10)`) — **유효한 패스(만료 전·잔여 1 이상) 중 만료
       임박순**으로 **구매 수량(10건)만큼** 차감. 모자라면 **0에서 끝내고 나머지는 무시**한다. 건별 차감은
       `with_lock`·DB 체크 제약(`remaining_uses >= 0`) 이중 방어 유지.
     - `item_type legal_doc`·`tax_invoice` → 되돌릴 권한이 없다. 환불·기록만 한다(이미 생성·발행된 것은
       건드리지 않는다).
   - 감사 로그 `AuditLogs::RecordService.call(admin:, action: "order_refund", target: order,
     detail: 사유 + 실행 요약)`.
5. Result 메시지에 실행 요약을 담는다(환불 금액·구독 Free 전환 여부·패스 차감 N건/잔여 M건).

### 2. 관리자 콘솔

- 라우트: `resources :orders, only: %i[index show]`의 member를 `patch :mark_refunded` →
  **`patch :refund`**로 교체(기록 전용 경로는 폐기 — 콘솔 수동 환불건도 3의 재조회 경로로 같은 버튼으로
  수렴한다).
- 컨트롤러 `Admin::OrdersController#refund`: 서비스 호출 → 성공 303 + flash 요약 / 실패 422 재렌더.
  기존 W-1(500 금지 — ArgumentError→422) 유지.
- 권한: `refund` 액션은 **owner 전용**(`before_action :require_owner, only: :refund`). `require_owner`는
  지금 `Admin::AdminsController` private에만 있어 **`Admin::BaseController`로 올려** 두 컨트롤러가 같이
  쓴다(거부 시 `Admins::RoleService.record_denied!` 감사 + 303 안내 — 선례 동작 그대로). `index`·`show`는
  staff도 조회 가능. 뷰는 staff에게 실행 폼을 감춘다.
- 뷰 `admin/orders/show.html.erb`: "환불 사유 기록" 폼을 **"결제 취소(환불) 실행"** 폼으로 교체 —
  사유 필수, 제출 전 확인 대화창에 **실행 효과 요약**(환불 금액·구독 즉시 Free·패스 10건 차감)를
  보여준다. 환불 완료 건(`refunded_at`)에는 실행자·일시·금액·사유를 보여주고 폼을 감춘다. 콘솔에서 먼저
  환불돼 `cancelled`인데 정산이 안 된 건(`refunded_at` 없음)에는 "포트원에서 이미 취소됨 — 정산을 완료하세요"
  안내 + 같은 버튼. pending·failed·결제 완료 적 없는 건에는 버튼 없이 안내.
- `admin/orders/index.html.erb`: 환불 상태 표기는 기존 필터·`refunded_at` 기준 유지. 환불·취소 주문이
  기본 목록에서 보이는지 확인한다.
- 회원 쪽 표기: `app/legal_documents/{index,show}`·`app/tax_invoices/show`의 상태 표기에 **"환불됨"**을
  추가한다(지금은 `paid?`가 아니면 "결제 실패·취소"로만 보인다).

### 3. 웹훅 — 변경 없음(검증만)

`Webhooks::PortOneController#apply_status`은 현행 그대로 둔다. 우리 환불 실행 뒤 주문이 이미 `cancelled`라서
뒤따라오는 `Transaction.Cancelled`는 `return if order.status == status`에서 아무 일도 하지 않는다. 웹훅이
먼저 도착해 status만 바꾼 경우(우리 확정 전)에도 4의 재검사를 통과해 **한 번만** 실행된다. PG 취소는
성공했는데 로컬 확정이 실패한 주문(`cancelled`인데 `refunded_at` 없음)은 웹훅으로 회복되지 않으므로 2의
안내 + 재실행 버튼으로 처리한다.

### 4. 포트원 래퍼

`cancel_payment`는 전액 취소 본문(`storeId`·`reason`) 그대로 사용한다. 응답·오류 형태는 포트원 문서
화면을 직접 가져오지 못해([INFERENCE] — 아래 리스크 1) **서비스가 응답 본문에 의존하지 않고 재조회로
확정**하도록 설계했다. 재조회 응답의 필드명(결제 상태·결제 금액·취소 내역 `cancellations[]`)도 미확정이라
래퍼/서비스에서 관대하게 읽되, **결제 완료 사실을 못 찾으면 실패** 쪽으로 떨어지게 한다(fail-closed).

## 변경 예상 파일

| 영역 | 파일 | 내용 |
|:---|:---|:---|
| Service | `app/services/orders/refund_service.rb` (신설) | 환불 실행 전체 |
| Model | `app/models/payment_pass.rb` | 회원 단위 수량 차감 메서드 |
| Controller | `app/controllers/admin/orders_controller.rb` | `refund` 액션(`mark_refunded` 교체) |
| Controller | `app/controllers/admin/base_controller.rb`·`admins_controller.rb` | `require_owner` 공용 이동 |
| Route | `config/routes.rb` | member `patch :refund` |
| View | `app/views/admin/orders/show.html.erb` | 실행 폼·확인 대화창·결과 표시(staff 감춤) |
| View | `app/views/admin/orders/index.html.erb` | 환불·취소 주문 노출 확인 |
| View | `app/views/app/legal_documents/{index,show}.html.erb`·`app/views/app/tax_invoices/show.html.erb` | "환불됨" 표기 |
| Webhook | `app/controllers/webhooks/portone_controller.rb` | **변경 없음** — 회귀 테스트만 |
| Test | `test/services/orders/refund_service_test.rb` (신설)·`test/models/payment_pass_test.rb`·`test/controllers/admin/orders_controller_test.rb`·`test/controllers/webhooks/portone_controller_test.rb`·`test/controllers/admin/admins_controller_test.rb`(가드 이동 회귀)·기존 `mark_refunded` 테스트 갱신 | Tester |
| Docs | `PRD.md`·`AGENTS.md` | Phase 2·9 (오케스트레이터) |

마이그레이션: 없음(환불 실행 정보는 기존 `refunded_at`·`refund_reason`·`metadata`로 보관).
보류(승인 질의에서 확정): 개인정보처리방침 결제 정보 문구에 빌링키 보관 명시 여부.

## 에이전트 지시 요약

- **Developer**: 위 설계 기준 구현. 레이어 순서 — Model → Service → Controller → Route → View.
  `_workspace/03_implementation.md`에 파일 목록·Rule ID별 매핑·PG 응답 해석 근거 기록.
- **Reviewer**: 중점 — ① 돈의 이중 처리 방지(이중 제출·경합·PG 요청 뒤 로컬 실패·재동기화 경로) ② 로컬
  변경은 PG 확정 뒤에만 ③ 부분 취소 없음(전액) — 부분 취소·미결제 취소가 성공으로 판정되지 않는지
  ④ 차감이 음수가 되지 않음 ⑤ 웹훅 선·후 도착 모두 한 번만 실행 ⑥ 감사 로그 ⑦ 권한(owner 전용·가드 이동
  회귀) ⑧ 재조회 응답 해석의 관대함(미확정 필드)이 오탐을 일으키지 않는지 ⑨ 빌링키 정리 범위.
- **Tester**: PLAN-9 정상(상품 4종 각각)·경계(패스 잔여 부족 → 0에서 종료·이미 Free인 구독·이미 환불된
  주문 재실행·콘솔 선취소건 재동기화)·예외(PG 실패 → 로컬 무변경·pending/failed 주문·`paid_at` 없는
  cancelled 주문·부분 취소·사유 blank·PG 타임아웃)·웹훅(선행 도착 → 실행 시 정산 1회 / 후행 도착 →
  무변경)·권한(staff 실행 → 거부·감사·로컬 무변경)·회원 표기("환불됨")·기존 회귀. 외부 API는 전부 stub.

## 리스크·모호점

1. **포트원 취소 API 명세 미실측** — 공식 문서 페이지가 스크립트 렌더링이라 원문 대조 실패(재검색도
   시간 초과). 검색 요약 기준: 전액 취소는 `cancellation` 금액 생략으로 가능, 응답은 갱신된 결제 객체
   (`cancellations[]`), 일부 결제수단(가상계좌·일부 간편결제)은 환불 계좌 정보가 필요하거나 비동기 처리.
   → 재조회 확정 + fail-closed 설계로 흡수하고, **첫 실환불 1건으로 실측**해 확정한다([INFERENCE] 유지·
   최종 보고에 명시).
2. **실제 돈이 움직인다** — 운영에서 첫 실행은 반드시 실제 결제 1건(예: 실결제 검증용 수금 패스)으로.
   PG 수수료는 환불 후에도 환급되지 않을 수 있다(운영 비용 — 사용자 인지).
3. **즉시 Free의 즉시성** — 실행 즉시 해당 회원의 Plus 기능이 끊긴다(결제 기간이 남아도). 확인 대화창·
   감사 로그로 방지.
4. **패스는 회원 단위 차감** — 주문↔패스 연결이 없어 "그 주문의 패스"만 무효화할 수 없다. 사용자 지시
   ("결제한 수만큼 차감, 0에서 끝")와 일치.
5. **환불된 건별 상품은 앱에서 다시 내려받을 수 없다** — 주문 상태가 `cancelled`가 되어 `paid?` 판정을
   통과하지 못한다(지금까지 포트원 콘솔 환불 때와 같은 결과). 이미 내려받은 파일과 국세청에 발행된
   세금계산서는 그대로다.
6. **기존 집계와의 정합** — `refunded_at` 기준 매출 제외(ADMIN-5)·영업 수수료 환불 제외는 기존 로직이
   그대로 적용된다. **이미 지급된 수수료는 소급하지 않는다**(월 정산 스냅샷 paid 보존 — 기존). 첫 결제
   쿠폰은 첫 차감 시점에 예약이 해제되므로 환불 뒤 재구독은 정가다(주문 상태와 무관).
7. **사용자 알림 없음** — 환불·구독 종료를 회원에게 따로 알리지 않는다(요청 범위 밖 — 후속 가능).
8. **포트원 서버에 남은 빌링키** — 우리 DB에서만 비운다. 포트원 쪽 키를 무효화하는 API가 있는지는
   확인하지 못했다(문서 조회 실패). 비운 뒤에는 어떤 경로로도 그 키로 청구할 수 없다.
9. **콘솔에서 먼저 환불한 건** — 웹훅이 status만 `cancelled`로 바꾼다. 버튼을 누르기 전까지는 구독·패스가
   그대로다(운영 절차: 환불은 반드시 관리자 페이지에서).
