# 03_implementation.md — F-INV 청구서 발행 + 대시보드 실데이터 전환

- **일자**: 2026-10-12
- **범위**: 플랜 `_workspace/01_plan.md` (결정 4건 반영) — Invoice·InvoiceItem 도메인 신규, 초안 CRUD + 발행(issue)·무효(void) 상태 전환, 대시보드 DASH-1/4 실데이터·ONB-1 CTA 활성화
- **후속 제외(미구현 확정)**: SHARE-3/4 열람 추적·알림, 뷰어(표면 ③), REM 발송, INV-7 반복, PDF, PAY 전환, 만기일 기본값 설정 UI, 부분입금

---

## 1. 변경 파일

### 신규
| 파일 | 내용 |
|:---|:---|
| `db/migrate/20261012000004_create_invoices.rb` | `invoices` + `invoice_items` 테이블. 컬럼 제약(`null: false`·`default`)·FK·인덱스 명시. `issue_number`·`token` 고유 인덱스(초안 NULL 허용 — 발행 시 채번), `[user_id, due_on]` 복합 인덱스(DASH-4 정렬) |
| `app/models/invoice.rb` | INV-1~6 도메인. enum 8종, 상태 전이 `issue!`/`void!`, 금액 산식(`compute_amounts`), PLAN-1 한도 검증, 파생 연체 판정(`overdue?`·`days_overdue`), 스코프(`unsettled`·`overdue`·`due_within`·`voidable`·`sorted_by_due`) |
| `app/models/invoice_item.rb` | 품목 행. 설명 필수, 수량 1~10,000, 단가 0~`Item::MAX_UNIT_PRICE`(CLIENT-2 상한 공유) |
| `app/controllers/app/invoices_controller.rb` | 초안 CRUD + member `issue`/`void`. 소유권 스코프 겸용 before_action 3종(show=전체, draft=수정·삭제·발행, voidable=무효) |
| `app/helpers/app/invoices_helper.rb` | 상태 뱃지(DESIGN-2 상태색), 라이브러리 JSON 직렬화(CLIENT-2) |
| `app/views/app/invoices/` `index.html.erb` `show.html.erb` `new.html.erb` `edit.html.erb` `_form.html.erb` `_item_fields.html.erb` `_invoice.html.erb` `_table.html.erb` | 목록(연체일 내림차순 표)·상세(품목 표·금액 내역 INV-2 분해)·작성·수정 폼(품목 행 동적 편집·실시간 요약)·행·표 파셜 |
| `app/javascript/controllers/invoice_form_controller.js` | 품목 행 추가·제거, 라이브러리 프리필(CLIENT-2), 금액 실시간 요약 — 서버 산식의 정수 JS 미러 |

### 수정
| 파일 | 내용 |
|:---|:---|
| `app/models/user.rb` | `has_many :invoices, dependent: :destroy`(AUTH-1.5) |
| `app/controllers/app/dashboards_controller.rb` | DASH-1 집계(미수 총액·연체 건수/금액·7일 내 만기) + DASH-4 상위 5건(`DASHBOARD_LIST_COUNT`) |
| `app/views/app/dashboards/show.html.erb` | DASH-1 실데이터 카드(0건 시 기존 빈 상태 유지), DASH-4 목록 표, ONB-1 CTA 실링크(0건→`new`, 이후→목록 링크), DASH-2 빈 상태 유지 |
| `app/helpers/app/base_helper.rb` | 사이드바 「청구서」 활성화, `won()`·`display_date()` 추가, `dash_summary_cards` 제거(빈 카드 헬퍼 — 실데이터 전환으로 소멸) |
| `config/routes.rb` | `resources :invoices` + member `patch :issue`·`patch :void` |
| `config/locales/en.yml` | invoice·invoice_item 검증 문구 한글화. belongs_to required 문구는 연관 속성 `client.required` 키 사용(런타임 실측) |
| `db/schema.rb` | 자동 갱신(version `2026_10_12_000004`) |

---

## 2. 금액 계산 규칙·반올림 명세 (결정 #4 반영)

단일 지점: `Invoice.compute_amounts(row_totals, tax_mode:, withholding_enabled:)` — 저장 전 `before_validation :recalculate_amounts`가 품목 행(삭제 예정 행 제외)에서 재산정. 폼 실시간 요약(`invoice_form_controller.js`)은 동일 산식의 정수 JS 미러이며 **최종값은 서버 계산 기준**(폼 요약 하단 안내 문구 병기).

| 항목 | 산식 (정수 원) | 반올림 |
|:---|:---|:---|
| 행 합계 | `Σ(수량 × 단가)` | — |
| 부가세 **별도** | 공급가액 = 행 합계, 부가세 = `(공급가액 + 5) / 10`의 정수 나눗셈 (= 공급가액의 10%) | 원 단위 반올림(사사오입) |
| 부가세 **포함** | 청구 총액 = 행 합계, 공급가액 = `(총액×10 + 5) / 11` (= `round(총액/1.1)`), 부가세 = 총액 − 공급가액 | 원 단위 반올림(사사오입) |
| 청구 총액 | `공급가액 + 부가세` (양 모드 공통) | — |
| 원천징수 (INV-2) | `공급가액 × 33 / 1000` (= 공급가액의 3.3%) | **내림**(결정 #4) |
| 실수령액 | `청구 총액 − 원천징수` | — |

- 컬럼 매핑: `subtotal`=공급가액, `tax_amount`=부가세, `total_amount`=청구 총액, `withholding_amount`=원천징수, `net_amount`=실수령액 — 전부 integer 원.
- 상한: 수량 ≤ 10,000, 단가 ≤ 1e9(CLIENT-2 상수 공유) → 행당 ≤ 1e13, 64bit 정수·JS 안전 정수(2^53) 범위 내. 수량 상한은 단가 상한(Item)과 같은 RangeError 방지 취지.

### 러너 실측 (dev DB 롤백 트랜잭션, `/tmp` 스크립트 — 저장소 비오염 확인)
0원 행(전부 0) · 단일 행 별도+원천(100,000→총액 110,000·원천 3,300·실수령 106,700) · 복수 행 · 부가세 경계 104→10/105→11(사사오입) · 포함 역분해 1,100,000→공급가액 1,000,000, 109→99 · **포함+원천징수 조합**(110,000→공급 100,000·원천 3,300·실수령 106,700) · 원천 내림 경계(101→3, 10,000→330, 1원→0) · 대량(10,000×1e9 포함+원천 → 공급 9,090,909,090,909·원천 299,999,999,999 내림) · 50행 — **전부 일치 확인**. 스코프 SQL 실측: `overdue` → `status NOT IN (0,6,7) AND due_on < '오늘'`, `due_within` 범위 정상.

---

## 3. 상태 전이 구현 지점 (INV-4)

| 전이 | 구현 | 가드 |
|:---|:---|:---|
| 초안 → 발행 | `Invoice#issue!` (`status=:issued`, `issued_at=Time.current`, 채번·토큰·유효기간 발급) | 컨트롤러 `set_draft_invoice`(draft 스코프 조회, 이외 404) + `issue!` 진입 `draft?` 재확인 + `on: :issue` 검증 컨텍스트 |
| 발행 계열 → 무효 | `Invoice#void!` (`status=:voided`, `voided_at`, **token=nil 즉시 폐기**) | `set_voidable_invoice`(`VOIDABLE_STATUSES` = issued·viewed·overdue·promised·partially_paid) + `voidable?` 재확인. 초안은 삭제, paid는 종결로 무효 불가 |
| 연체 표시 | **파생 판정**(결정 #2): `overdue?` = 미수 && `due_on < Date.current`(KST), `days_overdue` = 경과일 — enum 자동 전환은 F-REM 스케줄러 시점 | DASH-4 목록·뱃지·상세에 표기. `overdue` enum값은 예약 |

- **INV-5** 발행 후 본문 수정 불가: `edit`/`update`/`destroy`/`issue` 진입을 draft 스코프로만 허용 — 발행본 PATCH 실측 404.
- **INV-6** 시퀀스 즉시 중단: REM 부재로 N/A(무효 시 토큰 폐기만 구현 — 보고 명시).
- 성공 303 redirect / 실패 422(Turbo 규약). 무효·발행 버튼은 `button_to` + `turbo_confirm`.

### 채번 규칙 (INV-1)
`BD-YYYYMMDD-NNN` — 발행 시점(KST) 일자 + **서비스 전역 일별 순번**(`issue_number` 단일 고유 인덱스 기준). 트랜잭션 내 `LIKE 'BD-YYYYMMDD-%'` 카운트 + 1, 일별 경합은 고유 인덱스 위반(`RecordNotUnique`) 시 최대 4회 재채번. 999 초과 시 `%03d` 포맷이 자연히 4자리로 확장(고유성 유지). 실측: `BD-20261012-001`.

### 공유 링크 (SHARE-1/2 — 데이터만)
발행 시 `SecureRandom.urlsafe_base64(32)`(≈256bit, 43자 urlsafe) 토큰 생성, `token_expires_at = 만기일 + 60일 end_of_day`(KST). UI 노출은 F-VIEW 시점(플랜 결정 #1) — 상세 화면에 링크·토큰·안내 문구 일절 없음.

### PLAN-1 월 3건
`FREE_MONTHLY_INVOICE_LIMIT = 3`(상수 단일 지점 — `FREE_CLIENT_LIMIT` 패턴). `on: :issue` 검증: 당월 `issued_at` 기준 카운트 ≥ 3이면 차단. **무효 건도 발행 이력으로 포함**(발행은 발행 — 문서화된 해석). 초과 문구: 「Free 플랜은 매월 3건까지 발행할 수 있습니다. Plus로 무제한 이용할 수 있습니다」(LP-12 준칙 — 확정 보장 없이 Plus 안내). 초안은 무제한(결정 #3).

---

## 4. Rule ID 매핑

| Rule ID | 구현 지점 |
|:---|:---|
| **INV-1** | 필수 구성: `issue_number` 채번, 거래처, 품목 행(설명·수량·단가 복수), `tax_mode` 별도/포함, 총액, 만기일, 계좌 스냅샷(프로필 프리필·건별 변경), `issuer_display_name` 스냅샷(생성 시 `Current.user.display_name`) |
| **INV-2** | `withholding_enabled`(new 시 프리랜서 기본 체크) + 상세·폼 요약에 공급가액·원천징수액·실수령액 분해 표기 + 안내 문구 「공급가액의 3.3% 원천징수 후 실수령액 표기」 |
| **INV-3** | `DEFAULT_DUE_IN_DAYS = 30`, new 프리필 `Date.current + 30` |
| **INV-4** | enum 8종 + `issue!`/`void!` 전이 가드, 연체 파생 판정(§3) |
| **INV-5** | draft 스코프 가드(edit/update/destroy/issue) — 발행본 수정 실측 404 |
| **INV-6** | `void!` — voidable 스코프 + 토큰 즉시 폐기 + `voided_at` |
| **SHARE-1** | 발행 시 urlsafe_base64(32) 토큰, 고유 인덱스, 초안 NULL 허용 |
| **SHARE-2** | `token_expires_at = due_on + 60일` (end_of_day, KST) |
| **PLAN-1** | `FREE_MONTHLY_INVOICE_LIMIT = 3` 발행 시점 검사 + 한도 문구(§3) |
| **DASH-1** | 미수 총액(`unsettled` sum), 연체 건수·금액(`overdue` 파생), 7일 내 만기(`due_within`) — 컨트롤러 집계, 뷰는 @변수만 |
| **DASH-4** | `sorted_by_due`(만기일 asc = 연체일 desc 동치) 상위 5건 + 목록 연체일 표시, index 동일 정렬 |
| **ONB-1** | 「첫 청구서 발행하기」 실링크→`new_app_invoice_path`, 준비 중 배지 제거, 청구서 존재 시 목록 링크로 전환 |
| **CLIENT-2** | 품목 라이브러리 select → 행 설명·단가 프리필(Stimulus `prefillFromLibrary`), 라이브러리는 전송값 없는 보조 UI |
| **DESIGN-2/5** | 상태 뱃지 상태색(연체 주황/대기·약속 중립/완료 녹색/초안·무효 회색), 연체일 수치 주황 강조, DASH 큰 숫자 카드·tabular-nums, 범례 유지 |
| **TIME-1** | 전부 `Time.current`·`Date.current`(앱 TZ=Seoul) — 채번·issued_at·한도 카운트·연체 판정 |
| **SURF-3** | `/app` 하위 신규 라우트 — 기존 noindex 접두 정책에 자동 포함(추가 작업 없음) |
| **P4 준합** | 발행 이력 컬럼(`issued_at`·`voided_at`) 기록, 청구 발행 건은 삭제 불가(삭제는 초안만) |

## 5. UI 품질 기준 반영
- 기존 디자인 시스템 재사용: 크림 배경·딥 그린 액센트·rounded-2xl 카드·`form_input_classes`(오류 상태 링)·터치 타깃 min-h-11·focus-visible 아웃라인.
- 폼: 거래처 select(본인 거래처만 — 컨트롤러에서 `@clients` 전달, 뷰 쿼리 없음), 품목 행 grid + `<template>` 기반 행 추가(Stimulus 1개 — 추가·제거·프리필·요약 계산), 부가세 라디오(프로필 radio 패턴), 원천징수 체크+안내 문구, 만기일 date 필드, 계좌 3종(프로필 프리필 + `account-number` 하이픈 컨트롤러 재사용), 우측 sticky 금액 요약.
- 검증 오류: 폼 상단 alert(품목 행 오류 제외 — 행별 인라인 표기로 중복 방지) + 행별 필드 오류.
- 뷰어 미존재로 링크 미노출(결정 #1).

---

## 6. §4 실패 예상 테스트 목록 (기존 테스트 수정 없음 — Phase 7 Tester 갱신 대상)

`bin/rails test` 실측: **156 runs, 2 failures, 0 errors** — 실패 2건 모두 본 Phase가 의도적으로 대체한 「준비 중」 단계의 어설션이다.

| # | 테스트 | 파일:행 | 사유 |
|:---|:---|:---|:---|
| 1 | `ONB-1 첫 발행 CTA는 disabled이며 준비 중 배지를 노출한다` | `test/controllers/app/dashboards_controller_test.rb:55` (어설션 :61) | CTA가 disabled 버튼→`new_app_invoice_path` 실링크로 활성화(ONB-1), 준비 중 배지 제거 |
| 2 | `사이드바는 대시보드 활성 표시·거래처·품목 실링크·청구서 준비 중·설정을 렌더한다` | `test/controllers/app/dashboards_controller_test.rb:75` (어설션 :86) | 사이드바 「청구서」가 준비 중 span→`app_invoices_path` 실링크로 전환 |

유지 확인(통과): DASH-1 빈 카드·「0원 미표기」, DASH-2 빈 상태, DASH-4 빈 상태 문구 — **청구서 0건 사용자(gamma fixture) 분기는 기존 마크업을 그대로 유지**. 나머지 154건 전부 통과(사이드바 aria-current 분기 테스트 등).

---

## 7. 자체 점검 결과

| 항목 | 결과 |
|:---|:---|
| `bin/rubocop` | **0 offenses** (69 files) |
| `bin/rails zeitwerk:check` | 통과 ("Otherwise, all is good!") |
| `bin/rails db:migrate` | 성공 — `db/schema.rb` version `2026_10_12_000004` 갱신 |
| `bin/rails test` | 156 runs, 929 assertions, **2 failures(§6 의도된 것)**, 0 errors, 0 skips |
| 금액 경계 러너 실측 | §2 표 전 케이스 일치(롤백 트랜잭션, 잔존 데이터 0 확인) |
| 뷰·플로우 실측 | 통합 세션(dev 롤백): 대시보드·목록·작성·수정·상세 200, 초안 생성 303(금액 검증), 행 삭제+포함 역산 수정 303, 필수 누락 422(한글 문구), 발행 303(채번·토큰 43자), 발행본 수정 404, 무효 303(토큰 폐기), 월 4번째 발행 422+한도 문구, 상태별 액션 버튼 렌더 |
| 서버 기동 | 수행하지 않음(지시 준수) — 위 실측은 전부 `bin/rails runner` 통합 세션 |
| 테스트 작성 | 하지 않음(지시 준수) — Phase 7 Tester 인계 |

---

## 수정 이력 (Phase 6 — 리뷰 WARNING 7건 처리)

- **일자**: 2026-10-12 · **대상**: `_workspace/05_review.md` 이슈 #1~#7 — 코드 6건(#1·#2·#4·#5·#6·#7) + 문서 1건(#3), 범위 외 변경 없음
- **#2·#3 해석**: 오케스트레이터 확정(#2는 PRD 원문 회귀, #3은 `02_prd_update.md` 「Phase 6 리뷰 후속 정정」 절로 승인 편입)

| # | Rule ID | 수정 | 파일 |
|:--|:--|:--|:--|
| 1 | INV-6 | 상세 부제 분기 순서 변경 — `voided_at` 우선(발행 계열→무효 건에서 무효 일자 미안내 데드 브랜치 해소) | `app/views/app/invoices/show.html.erb` |
| 2 | INV-3 | `issue!` 진입 시 `reset_due_on_if_prefilled` — due_on이 프리필 원값(`created_at.to_date + 30`)과 동일하면 **발행일+30일로 재계산**, 명시 수정값은 존중. 토큰 유효기간(SHARE-2)은 재계산된 만기일 기준 | `app/models/invoice.rb` |
| 3 | PLAN-1 | 문서 정정(코드 변경 없음) — 월 3건 한도 **무효 건 포함** 집계 해석을 02_prd_update.md에 기록 | `_workspace/02_prd_update.md` |
| 4 | 무결성 | 위조 `items_attributes` id 방어 — 할당 전 소속 검증(`item_ids_owned?`)으로 **422** 응답(기존 RecordNotFound 500). create는 품목 행을 검증 통과 후 할당, 불일치 요청은 레코드 생성·수정 없이 `render_forged_items` | `app/controllers/app/invoices_controller.rb` |
| 5 | INV-5 | 모델 레벨 본문 불변 가드 — `before_update :enforce_issued_content_immutable`: 갱신 직전 상태가 draft가 아니면 보호 컬럼(`PROTECTED_CONTENT_COLUMNS`: 거래처·만기·부가세·원천·계좌·표시명·금액 5종) 변경과 품목 행 변경(중첩 attributes 동반분)을 차단. 상태 전이·토큰·token_expires_at·voided_at·`issue!` 중 due_on 재계산(status_was=draft)은 통과 | `app/models/invoice.rb` |
| 6 | INV-1 | 품목 행 수 상한 `Invoice::MAX_ITEMS = 100` — `items_count_within_limit` 검증(초과 시 base 오류) + JS `addRow` 동일 상한(폼에서 `maxItems` 주입, 도달 시 추가 막고 버튼 disabled) | `app/models/invoice.rb`, `app/javascript/controllers/invoice_form_controller.js`, `app/views/app/invoices/_form.html.erb` |
| 7 | 이식성 | 금액 5컬럼(subtotal·tax_amount·total_amount·withholding_amount·net_amount)에 `limit: 8`(bigint) — 기존 마이그레이션 수정 + dev/test DB 재생성 | `db/migrate/20261012000004_create_invoices.rb`, `db/schema.rb` |

### #7 참고 — SQLite schema 표기
SQLite는 정수형이 네이티브 64bit라 `limit: 8`이 DDL·`schema.rb`에 표기되지 않는다(컬럼 `INTEGER`, `limit=nil` 실측). `limit: 8`은 PostgreSQL 이식 시 bigint DDL을 보장하는 마이그레이션 레벨 명시이며, `schema.rb` 재생성 결과는 Phase 5 버전(`2026_10_12_000004`)과 동일 — 이식성 확보 목적은 달성.

### Phase 6 러너 실측 (`bin/rails runner` — 롤백 트랜잭션, 종료 시 invoices/users/clients 0건 확인)

**통합 플로우 21/21 PASS** (`/tmp/phase6_check.rb`):

| 이슈 | 실측 | 결과 |
|:--|:--|:--|
| #6 | 100행 `valid?` 통과 / 101행 → base 오류 「품목 행은 최대 100개까지 입력할 수 있습니다」 | PASS |
| #4 | 위조 id(타인 품목) `_destroy` PATCH → **422**(수정 전 500), 타인 품목 무영향 / 정상 품목 수정 → 303+반영 / 생성에서 위조 id → 422·무레코드 | PASS |
| #5 | 발행본 `update(due_on:)` → false+base 오류 / `update!(bank_name:)` → 예외 차단(`ActiveRecord::RecordNotSaved`, base 오류 동반) / 발행본 품목 행 변경 차단 / **무변경 `save!` 통과** / **`void!` 통과**(status·token nil·voided_at) / 무효 건 본문 차단 유지 | PASS |
| #2 | 10일 전 작성 초안(프리필 원값 유지) 발행 → due_on = **발행일+30**(2026-11-11)·토큰 만료 = 만기+60(2027-01-10 23:59:59 KST) / 명시 수정값(+45일) 발행 → **존중**(2026-11-16) / 당일 발행 프리필(오늘+30) 불변 | PASS |

**뷰 렌더 5/5 PASS** (`/tmp/phase6_views.rb`): 초안·발행·무효 상세 부제 3분기(무효 건 「2026-10-12에 무효 처리했습니다.」 표기·발행 문구 미표기), 폼 `data-invoice-form-max-items-value="100"` 주입·addRowButton 타깃·disabled 스타일 확인.

### Phase 6 자체 점검

| 항목 | 결과 |
|:--|:--|
| `bin/rubocop` | **0 offenses** (69 files) |
| `bin/rails zeitwerk:check` | 통과 |
| `bin/rails db:drop db:create db:migrate` + `db:test:prepare` | 성공 — `schema.rb` version `2026_10_12_000004`(변경 없음 — §SQLite 표기 참고) |
| JS 문법 | Bun.Transpiler 파싱 통과 |
| 기존 테스트 수정 | 하지 않음(지시 준수) — §6의 2건 실패는 Phase 7 갱신 대상 유지 |

### 구현 중 확정한 기술 노트 (Tester 참조)
1. `params.expect`의 중첩 attributes는 **문서형 배열 `items_attributes: [[:id, ...]]`** 이어야 폼 전송 형태(인덱스 키 해시)를 허용한다 — 8.1 런타임 실측(단일 배열형은 키만 허용되고 내용이 파기됨).
2. belongs_to 검증 오류 속성은 `:client`(연관)이며 메시지 키는 `required` — locale `activerecord.errors.models.invoice.attributes.client.required`.
3. 전역 일별 채번이라 사용자 간 채번 연속성이 보인다(고유 인덱스 단일 기준의 귀결) — 민감 정보 아님(일자+순번).
4. 만기일(INV-3): 프리필은 초안 작성일+30일, **발행 시점에 미수정 프리필이면 발행일+30일로 재계산**(Phase 6 #2 — `reset_due_on_if_prefilled`). 만기일 자체 설정 UI는 설정 도메인(후속)에서 다룬다.
5. (Phase 6 추가) 발행 계열 본문 변경 차단(`update!`)은 `ActiveRecord::RecordNotSaved`를 낸다(`throw(:abort)` 경로) — `update`(non-bang)는 false+base 오류. Tester는 `RecordInvalid`가 아닌 `RecordNotSaved`를 기대해야 한다.
6. (Phase 6 추가) 러너에서 통합 세션(ActionDispatch::Integration::Session)을 쓰면 요청마다 `ActiveSupport::ExecutionContext` Record가 파손되어 이후 쿼리의 QueryLogs가 `NoMethodError`로 깨진다 — 요청 후 `IsolatedExecutionState[:active_support_execution_context]`를 신규 Record로 교체하면 회피된다(실측 스크립트의 `req` 헬퍼).

## 수정 이력 (Phase 6-2 — BUG-1 탈퇴 연쇄 삭제 FK 위반)

- **일자**: 2026-10-12 · **대상**: Phase 7 Tester 발견 BUG-1(AUTH-1.5 위반) 1건 — 수정은 BUG-1에 1:1 대응, 범위 외 변경 없음

### 원인

`app/models/user.rb`의 `has_many` 선언 순서가 sessions → clients → items → invoices였다. `dependent: :destroy`는 **연관 선언 순서대로** 실행되므로 탈퇴 시 clients가 invoices보다 먼저 파괴됐고, 이 시점에 아직 삭제되지 않은 invoices의 `client_id`가 `add_foreign_key "invoices", "clients"` 제약(`db/schema.rb:101`)에 걸려 `ActiveRecord::InvalidForeignKey`로 전체 삭제(탈퇴)가 실패했다. 청구서를 보유한 사용자에서만 재현된다(거래처만 있는 사용자는 clients에 자식이 없어 성공).

### 수정

| # | Rule ID | 수정 | 파일 |
|:--|:--|:--|:--|
| 1 | AUTH-1.5 | `has_many :invoices` 선언을 clients·items보다 앞으로 이동(자식→부모 파괴 순서 보장) + FK 의존 순서·순서 변경 금지 주석 추가 | `app/models/user.rb` |
| 2 | AUTH-1.5 | 회귀 테스트 추가 — 「청구서·거래처·품목을 보유한 사용자 삭제가 전부 연쇄 삭제된다 (AUTH-1.5)」: 신규 사용자에 거래처 1·품목 1·청구서 1건(품목 행 1개) 생성 후 `destroy`, users/invoices/clients/items/invoice_items에서 해당 사용자 소유 행 **전부 0건** 확인. fixtures와 무관한 자기완결 시나리오(alpha·beta는 FK 연쇄 검증용으로 청구서 보유 금지 — invoices.yml 운용 규칙 준수) | `test/models/user_test.rb` |

### 회귀 테스트 결과

- 신규 테스트 단건 실행: `bin/rails test test/models/user_test.rb -n "/연쇄 삭제/"` → **1 runs, 5 assertions, 0 failures, 0 errors**
- 전체 스위트: `bin/rails test` → **228 runs, 1356 assertions, 0 failures, 0 errors, 0 skips**(기존 227 + 신규 1)

### Phase 6-2 자체 점검

| 항목 | 결과 |
|:--|:--|
| `bin/rubocop` | **0 offenses** (72 files) |
| `bin/rails zeitwerk:check` | 통과(test/mailers/previews 미포함 안내는 기존 상태 그대로 — 변경 없음) |
| 마이그레이션 | 없음(스키마 변경 없음 — `schema.rb` version `2026_10_12_000004` 유지) |
| 기존 테스트 수정 | 하지 않음(지시 준수) |
