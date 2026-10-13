# 03_implementation.md — F-PAY 입금 처리 (원클릭 마감·부분입금·DASH 잔액 재계산)

- **일자**: 2026-10-13
- **플랜**: `_workspace/01_plan.md` (승인) / 해석 기록 `_workspace/02_prd_update.md` (PRD v0.18.7)
- **결과**: 구현 완료 — `bin/rubocop` 0 offenses · `zeitwerk:check` 통과 · `db:migrate` 성공 · `bin/rails test` **323 runs, 0 failures, 0 errors** · 러너 실측 12/12 PASS

## 1. 변경 파일

| 파일 | 구분 | 내용 |
|:---|:---|:---|
| `db/migrate/20261013000002_create_payments.rb` | 신규 | `payments` 테이블 — invoice FK(+인덱스), `amount int null:false`, `paid_on date null:false`, `amount > 0` CHECK 제약(`payments_amount_positive`) |
| `app/models/payment.rb` | 신규 | 금액 정수 원(>0, 상한 `MAX_AMOUNT = 1e9`), `paid_on` 당일·과거 허용(미래 차단), `belongs_to :invoice` |
| `app/models/invoice.rb` | 수정 | `has_many :payments, dependent: :destroy`·`PAYABLE_STATUSES` 상수·`mark_paid!`/`mark_partially_paid!`(조건부 원자 전이)·`payments_total`/`remaining_amount` |
| `app/services/payments/record_service.rb` | 신규 | 마감·부분입금 단일 진입점 — 트랜잭션+`with_lock`+잔액 재검증+전이 |
| `app/controllers/app/payments_controller.rb` | 신규 | `create` — 소유권 스코프, 성공 303 / 실패 422(상세 재렌더·입력 보존) |
| `app/controllers/app/invoices_controller.rb` | 수정 | `set_payments` before_action(show·issue·void·regenerate_token — 422 재렌더 대응) |
| `app/controllers/app/promises_controller.rb` | 수정 | `load_invoice_show`에 입금 이력·폼 @변수 추가(show 템플릿 공용 — §4 참고) |
| `app/controllers/app/dashboards_controller.rb` | 수정 | DASH-1 잔액 기준 집계(`remaining_total`), DASH-4 목록 `unsettled` 스코프 적용 |
| `app/views/app/invoices/show.html.erb` | 수정 | 입금 섹션 — 총액/누계/잔액(tabular)·입금 이력(내림차순)·원클릭 마감 폼·부분입금 폼·paid 확정 배너 |
| `app/views/app/dashboards/show.html.erb` | 수정 | 미수 총액 카드 보조 문구를 잔액 기준으로 갱신 |
| `config/routes.rb` | 수정 | `resources :invoices do resources :payments, only: :create end` |
| `db/schema.rb` | 자동 | v2026_10_13_000002 — payments 테이블·CHECK·FK 반영 |

## 2. 전이·멱등 방어 구현 지점 (리뷰·테스트 집중 지점)

1. **`with_lock`(청구서 행 직렬화)** — `Payments::RecordService#call`. 행 잠금 획득 시 최신 상태·잔액이 재조회된다. SQLite(개발)는 쓰기 자체가 직렬화되며, MySQL/Postgres에서는 `FOR UPDATE`가 동일 순서를 보장한다.
2. **`guard_payable!`** — 잠금 하 최신 상태로 미수 계열만 통과. 초안·voided는 「입금을 기록할 수 없는 상태의 청구서입니다」, paid 재요청(이중 클릭 두 번째)은 **「이미 수금이 마감된 청구서입니다」** 422.
3. **잠금 하 잔액 재검증** — `remain = total_amount − payments.sum(:amount)`를 잠금 후 재조회 → 직전 트랜잭션 등록이 반영된 최신 잔액 기준으로 초과 차단(422, `:amount` 필드 오류).
4. **`mark_paid!`/`mark_partially_paid!`(INV-4)** — `mark_viewed!`/`mark_promised!`와 동일 패턴의 status 단일 컬럼 조건부 UPDATE(`PAYABLE_STATUSES` 가드). `update_all`이라 INV-5 본문 불변 가드·콜백과 무충돌(status는 PROTECTED 컬럼 아님). overdue enum 예약값 포함(F-REM 저장화 대비 — 러너 실측 §5-9).
5. **전이 판정** — 생성 직후 합계 재조회: `total − Σ ≤ 0 → mark_paid!`(PAY-1), `> 0 → mark_partially_paid!`(PAY-2). with_lock 직렬화로 두 트랜잭션이 동시에 "도달" 판정에 성공할 수 없다.
6. **컨트롤러 소유권 격리** — `Current.user.invoices.find(params[:invoice_id])` (404 수렴). `params.expect(payment: [:amount, :paid_on])`.
7. **폼 객체 분리 규약(중요)** — 화면용 미완성 Payment는 반드시 `Payment.new(invoice_id:)`로 **컬렉션 외부**에서 빌드한다. `@invoice.payments.new`는 컬렉션에 추가되어 부모 저장(issue!/void!) 시 자동 저장 대상이 되어 「Payments is invalid」로 발행이 막힌다(§4 참고).

## 3. 잔액 계산 명세

- **단건**: `Invoice#remaining_amount` = `total_amount − payments.sum(:amount)` (호출 시마다 최신 조회 — 캐시 없음). 초과 등록 차단으로 음수 불가.
- **집계(DASH-1)**: `App::DashboardsController#remaining_total(scope)` = `scope.sum(:total_amount) − Payment.where(invoice_id: scope.select(:id)).sum(:amount)`. 미수 총액·연체 금액 모두 잔액 기준.
- **전액 마감(원클릭)**: `amount`가 **nil**일 때만 잔액 기준값을 서버가 계산(폼에 금액 필드 부재). **빈 문자열**은 전액으로 승격하지 않고 모델 검증 422 — 부분입금 폼 미입력이 전액 마감으로 바뀌는 사고를 차단한다.
- **DB 이중 방어**: `amount > 0` CHECK 제약. 상한 1e9·미래 날짜는 모델 검증(Payment).

## 4. 기존 테스트 영향(§4) — 결과: **기존 스위트 전부 통과(갱신 불요)**

- **DASH-1 집계 변경(잔액 기준)**: 기존 시드·픽스처는 Payment가 0건 → `Σtotal − 0 = Σtotal`로 기존 어설션과 산술 동치. 따라서 예고된 "기존 카드 테스트 실패"는 **발생하지 않았다**(323 runs 0 failures). Phase 7 Tester가 부분입금 반영 시나리오를 신규 추가해야 잔액 기준이 검증된다.
- **구현 중 발견·수정한 회귀 2건(기존 테스트가 잡아 준 것 — 이미 수정 완료)**:
  1. `issue`/`void`/`regenerate_token`이 303→422로 회귀: `set_payments`가 `@invoice.payments.new`로 컬렉션에 미완성 Payment를 추가 → 부모 저장 시 자동 저장 검증 실패(「Payments is invalid」). → 컬렉션 분리형 빌드로 수정.
  2. `App::PromisesController#answer` 422 재렌더에서 `Passed nil to the :model argument`(템플릿 오류): show 템플릿 공용 @변수에 입금 변수 누락. → `load_invoice_show`에 추가.
- **DASH-2 마감 대기 소멸**: `unsettled` 스코프가 paid를 이미 제외 → 구조적으로 보장. 기존 테스트 「마감 확정 후에는 마감 대기 카드가 소멸한다」가 무수정 통과로 재확인됨. 신규 코드 불요.
- 참고(범위 외 메모): DASH-2 마감 대기 카드 금액 표기는 기존대로 `total_amount`(부분입금 반영 표기는 플랜 범위 외).

## 5. 러너 실측(권장 시나리오 — 임시 스크립트 실행 후 삭제, 개발 DB 정리 완료)

| # | 시나리오 | 결과 |
|:---|:---|:---|
| 1 | 부분입금 40,000 → `partially_paid`·잔액 70,000·입금일 기록 | PASS |
| 2 | 잔액 도달 70,000 → `paid`·잔액 0·마지막 입금일 = 마감일 | PASS |
| 3 | 마감 후 재마감 → 「이미 수금이 마감된 청구서입니다」 422 | PASS |
| 4 | 원클릭(amount nil) → 잔액 전액 1건 기록·`paid` | PASS |
| 5 | 초과 200,000 → 422(`:amount` 안내문)·미기록 | PASS |
| 6 | 0·음수 → 모델 검증 422 | PASS |
| 7 | 미래 입금일 → 422(`:paid_on` 안내문)·미기록 | PASS |
| 8 | draft·voided → 「입금을 기록할 수 없는 상태…」 422 | PASS |
| 9 | overdue enum 상태 원클릭 → `paid`(PAYABLE_STATUSES 포함 확인) | PASS |
| 10 | DASH-1 잔액 집계 = 110,000−10,000 = 100,000 | PASS |
| 11 | 청구서 파괴 → payments 연쇄 삭제(FK) | PASS |
| 12 | **동시 이중 마감(스레드 2개)** → 1건 기록·마감, 1건 가드 422 | PASS |

## 6. Rule ID 매핑

| Rule ID | 구현 |
|:---|:---|
| **PAY-1** 원클릭 마감·입금일 자동 기록 | 상세 화면 「입금 확인하고 마감」(turbo_confirm 「마감하면 되돌릴 수 없습니다…」)·날짜 기본 오늘(선택 편집) → Service가 잔액 전액 1건 기록 + `mark_paid!` 원자 전이. 마감 입금일 = 마감 Payment.paid_on |
| **PAY-2** 부분입금·잔액 자동 재계산 | 「부분입금 기록」 폼(금액·날짜) → `mark_partially_paid!` + `remaining_amount` 잔액 기준 유지. 시퀀스 잔액 기준 계속은 REM 부재로 데이터 축적만(플랜 A-2 범위) |
| **INV-4** 상태 전이 | 미수 계열(issued·viewed·overdue·promised·partially_paid)→paid/partially_paid만, 조건부 UPDATE로 원자화. draft/paid/voided 진입 차단(422) |
| **DASH-1** | 미수 총액·연체 금액 = 잔액 기준(`remaining_total`). 7일 내 만기·DASH-4 목록은 unsettled(잔액>0 계열) 유지·paid 제외 |
| **DASH-2** | paid 전환 시 마감 대기 카드 소멸(unsettled 스코프 — 기존 구조 재확인, 테스트 무수정 통과) |
| **PROMISE-7** | 마감 경로는 표면 ② U1 전용 — 뷰어(③) 무변경, `paid_report`는 상태 불변(RegisterService 기존 구조 유지) |
| **DESIGN-2** | paid 상태 「수금이 완료되었습니다」 녹색 확정 배너 + 헤더 수금 완료 녹색 배지(기존)·잔액 수치 tabular-nums |
| **SEC(멱등)** | with_lock + 최신 상태·잔액 재검증 + 조건부 UPDATE — 동시 이중 마감 실측 PASS(§5-12) |
| **TIME-1** | `paid_on` 기본·미래 판정 모두 `Date.current`(KST) |
| **PAY-5** | 미구현 = 규칙 준수(비목표 11) — 자동 입금확인 코드 없음 |
| 후속 제외 확인 | PAY-4 감사 알림(결정 #1 — 채널 계약 후), PAY-6 PDF, PROMISE-5(CLIENT-3/4와 함께) 미구현. 뷰어(③) 변경 없음 |

## 7. 자체 점검 결과

- [x] `bin/rubocop` — 96 files, no offenses
- [x] `bin/rails zeitwerk:check` — 통과
- [x] `bin/rails db:migrate` — 성공, `db/schema.rb` 갱신(version 2026_10_13_000002)
- [x] `bin/rails test` — 323 runs, 1913 assertions, **0 failures, 0 errors**
- [x] 러너 실측 12 시나리오 PASS(§5) — 서버 기동·테스트 파일 작성 없음(금지 준수)
- [x] 뷰어(③)·발송 로직 변경 없음 — REM-3/REM-12/SEC-5 발송 규칙 해당 없음
- [x] 기존 테스트 파일 수정 없음

## 수정 이력 (Phase 6) — Phase 5 리뷰 WARNING 대응

- **일자**: 2026-10-13 · **입력**: `_workspace/05_review.md` 이슈 #1·#2 (#3은 현행 유지 확정 — 미수정)
- **결과**: 이슈 2건 수정 완료 — `bin/rubocop` 0 offenses · `zeitwerk:check` 통과 · `bin/rails test` **323 runs, 0 failures, 0 errors**(기존 스위트 무수정 통과) · 러너 실측 4항목 PASS

### 이슈 #1 (PAY-1 UX) — 부분입금 폼 paid_on 오류 문구 미표시

| 파일 | 변경 |
|:---|:---|
| `app/views/app/invoices/show.html.erb:358-360` | 부분입금 폼 `paid_on` 필드 아래에 원클릭 박스(329-331행)와 동일한 3줄 에러 표시 추가(`@payment.errors.key?(:paid_on)` 분기 + `form_error_message`) |

- 두 폼이 같은 `@payment` 객체를 공유하므로 어떤 폼에서 제출해도 자신의 필드 아래에서 원인을 확인할 수 있다(리뷰 제안안 그대로 — 원클릭 측 기존 표기는 유지).
- 실측: 뷰 전체를 Rails ERB 핸들러(`ActionView::Template::Handlers::ERB`)로 컴파일 → 통과. (참고: `erb -x` CLI·순수 Erubi는 Rails 블록 폼 `<%= form_with do %>`를 지원하지 않아 기존 영역에서 오탐 — 검증 도구 오류로 기각)

### 이슈 #2 (0원 청구서 마감 불가 → 발행 차단) — `:issue` 컨텍스트 총액 양수 검증

| 파일 | 변경 |
|:---|:---|
| `app/models/invoice.rb:74` | `validate :total_amount_must_be_positive, on: :issue` — 발행 시점만 검사, 초안 저장은 계산 중 상태로 허용 |
| `app/models/invoice.rb:281-287` | 비공개 검증 메서드 — `recalculate_amounts`가 저장 직전 재산정한 `total_amount` 기준, 0 이하면 `errors.add(:base, :total_amount_must_be_positive)` |
| `config/locales/en.yml:92-95` | 문구 관리 — `activerecord.errors.models.invoice.attributes.base.total_amount_must_be_positive: "청구서 총액은 1원 이상이어야 합니다"` |

- 422 경로: `issue!` → `save!(context: :issue)`가 RecordInvalid → false → 컨트롤러가 `flash.now[:alert] = errors.full_messages_for(:base).first`로 표시(기존 PLAN-1 한도 문구와 동일 경로 — 신규 렌더 분기 없음).
- 상태 공간 정리: 0원 청구서는 원클릭(`amount=0` 422)·부분입금(잔액 0원 422) 어떤 경로로도 paid 전이 불가한 PAY-1 교착이므로 발행 단계 차단이 잔액 0 마감 분기보다 단순(오케스트레이터 결정). 초안은 저장·수정·삭제 가능.
- 러너 실측(임시 스크립트 — 실행 후 삭제, 신규 유저 생성으로 PLAN-1 간섭 차단, 생성 데이터 전량 정리 확인):

| # | 시나리오 | 결과 |
|:---|:---|:---|
| A1 | 품목 단가 0원 초안 저장 → `save=true`·`total_amount=0`·`draft` | PASS |
| A2 | 0원 초안 발행 → `issue!=false`·DB status `draft` 유지·`"청구서 총액은 1원 이상이어야 합니다"`(en.yml 심볼 해석 확인) | PASS |
| B1 | 단가 1원 초안 저장 → `save=true`·`total_amount=1` | PASS |
| B2 | 1원 이상 발행 → `issue!=true`·`issued`·채번 `BD-20261013-001` | PASS |

### 미수정 확정 (기록)

- **이슈 #3** 부분입금 오기록 정정 경로: 현행 유지(무효→재발행으로 정리, P4 정합) — 후속 제품 결정 대상. 코드 변경 없음.

### 자체 점검 (Phase 6)

- [x] `bin/rubocop` — 96 files, no offenses
- [x] `bin/rails zeitwerk:check` — 통과
- [x] `bin/rails test` — 323 runs, 1913 assertions, **0 failures, 0 errors**(기존 테스트 파일 무수정 — 0원 발행 케이스 부재 확인: `create_and_issue!` 기본 rows 10만원·카탈로그 Item 단가 0원 테스트는 발행 경로 아님)
- [x] 러너 실측 4항목 PASS(위 표) — 서버 기동·테스트 파일 작성 없음(금지 준수)
- [x] 마이그레이션 없음 — `db/schema.rb` 무변경
- [x] 뷰어(③)·발송 로직 무관 — Phase 5 변경분 대비 Phase 6 신규 delta는 상기 3개 파일뿐
