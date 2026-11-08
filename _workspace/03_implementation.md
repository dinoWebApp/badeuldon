# 03_implementation — F-DASH(DASH-5/6) 리포트 구현 (2026-11-09, Developer-lite)

## 변경 파일 목록

| 파일 | 구분 | 내용 |
|---|---|---|
| `app/queries/reports/client_delay_query.rb` | 신규 | `Reports::ClientDelayQuery.call(user_id)` — 거래처별 Row Struct 배열(거래처명·진행 청구수·연체 건수·연체 금액(잔액 기준)·평균 지급 지연일) |
| `app/queries/reports/monthly_collection_query.rb` | 신규 | `Reports::MonthlyCollectionQuery.call(user_id)` — 최근 12개월(이번 달 포함) 월별 수금액, 빈 달 0원으로 12행 고정 |
| `app/queries/reports/tax_period_query.rb` | 신규 | `Reports::TaxPeriodQuery.call(user_id)` — 최근 4분기 [확정신고 라벨·기간·매출(subtotal)·부가세·수금액] |
| `app/controllers/app/reports_controller.rb` | 신규 | `App::ReportsController#show` — 3쿼리 위임 + `@this_month_collected`(DASH-3 문구 정합). 본문 7줄 |
| `app/helpers/reports_helper.rb` | 신규 | bar 높이 %·지연일 표기(+N일/N일 조기/당일)·상태색·분기 타이틀 — 표현 로직 추출 |
| `app/views/app/reports/show.html.erb` | 신규 | 3섹션(aria-labelledby) + 빈 상태(ONB-1 CTA 톤) + 고지문 |
| `app/helpers/app/base_helper.rb` | 수정 | app_nav_items에 "리포트" 추가(요금제·설정 사이, start_with? 활성 판정·locked 규칙 준용) |
| `config/routes.rb` | 수정 | `/app` namespace에 `resource :report, only: :show` — DASH-5/6 주석 |
| `test/controllers/app/dashboards_controller_test.rb` | 수정 | 잠금 내비 개수 5→6(리포트 메뉴 추가에 따른 회귀 최소 수정) |

## Rule ID 매핑

- **DASH-5**: 거래처별 지연 리포트(만기일 대비 실입금일 — CLIENT-4와 정의 구분, 섹션 부제로 명시) + 월간 수금 추이(CSS bar chart·외부 JS 금지·figure/figcaption + sr-only 텍스트 표 병행)
- **DASH-6**: 신고 주기 집계표(1·4·7·10월 확정신고 = 직전 분기 매핑) + 고지문 "본 집계표는 세무 자문이 아닙니다. 신고 자료로 활용하기 전 세무대리인 확인을 권장합니다."(02_prd_update 확정 5 — LP-12·P1 톤)
- **TIME-1**: 전 쿼리 `Date.current`(KST)
- **INV-1**: 매출 = 공급가액(subtotal)·부가세(tax_amount) 별도 집계, issued 계열(draft·voided 제외, issued_at 기준)
- **PAY-2**: 연체 금액 = 잔액 기준(총액 − 입금 합계)
- **규약 §3.2**: 첫 `app/queries/reports/` — `.call` 진입점, 컨트롤러는 @변수 조립만, 뷰는 쿼리 호출 없음

## 쿼리 행 구조

- `ClientDelayQuery::Row`: `client_name, unsettled_count, overdue_count, overdue_amount, avg_delay_days` (avg는 nil 가능 — 마감 이력 없음, 뷰에서 "—")
- `MonthlyCollectionQuery::Row`: `month(Date), label("YYYY.MM"), amount`
- `TaxPeriodQuery::Row`: `label("4월 확정신고" 등), period_label, revenue, tax_amount, collected, start, finish`

## 설계 결정 (구현 시 확정)

1. 평균 지급 지연일 = 수금완료(paid) 청구의 Payment `paid_on − due_on` 평균(SQLite julianday 차, Ruby에서 round) — 음수는 조기
2. 분기 매핑 라벨: `1~3월→"4월 확정신고", 4~6→"7월", 7~9→"10월", 10~12→"익년 1월 확정신고"`
3. 매출 기간 기준 = `issued_at`(발행 시점) — 수금은 별도 `paid_on` 기준 집계(컬럼 미혼용)

## 자기 스코프 검증 결과

- `bin/rails runner` fixture 대입(user 2인 격리 시나리오): **전 어설션 통과** — 스코프 격리(타인 유저 데이터 비포함)·연체 잔액 220,000·평균 지연 +5일·12개월 0원 채움·분기 라벨 4종·매출/부가세/수금 분리
- `bin/rails test test/controllers/app/dashboards_controller_test.rb`: 14 runs, 0 failures(잠금 내비 count 갱신 후)
- `bin/rubocop`(자기 파일 7종): no offenses(ERB 파일은 기존 프로젝트 전반의 Ruby 파서 직접 검사 노이즈로 제외 — bin/ci 기준 아님)
- `bin/rails zeitwerk:check`: 통과
- 실행 중 발견·수정한 버그: ① 월 소급 `-(일수)` → `<<(개월)` ② 분기 라벨이 종료월(3·6·9·12월)을 잘못 내보내던 것 → 신고월(4·7·10·1월)로 수정

## Phase 6 후속 수정 (2026-11-09 — 05_review.md CHANGES_REQUESTED 중 C-1·W-1만)

| 항목 | 조치 | 파일 |
|---|---|---|
| C-1 (CRITICAL) | 평균 지급 지연일을 Payment 행 단위 → **청구 건 마감(최종) 입금일 기준**으로 수정. `MAX(paid_on)` 서브쿼리(`invoice_id, MAX(paid_on) AS paid_on` group by invoice_id)로 청구별 최종 paid_on 한정 후 청구 단위 평균 — 부분입금 행 가중·조기 입금 혼입 제거(PRD v0.28 DASH-5). 주석에 "마감 건 기준 — 부분입금 행 가중 방지(PRD v0.28 DASH-5·리뷰 C-1)" 명시 | `app/queries/reports/client_delay_query.rb` |
| W-1 (WARNING) | 월간 수금 추이 금액 라벨: 모바일(터치) 항상 표시 → sm 이상 hover 전환(`sm:opacity-0 sm:group-hover:opacity-100`). figcaption "마우스를 올리면" → 터치 포함 표현으로 수정. 위계·tabular-nums 유지 | `app/views/app/reports/show.html.erb` |

- **C-1 재검증**(RAILS_ENV=test runner, rollback): 리뷰어 재현 시나리오(청구 A: 조기 부분입금 −7 → 마감 +5 / 청구 B: 단일 +7) → 기대값 **+6일 일치 PASS**
- **W-2 수용 사유**: Query Object 반환형이 규약 문언("Relation 반환")과 Struct 배열로 편차 — 집계 리포트의 행 구조(라벨·0원 채움·매핑)는 Relation으로 표현할 수 없어 의도된 설계이며 01_plan·02_prd_update 확정 해석의 범위. 구조 변경 시 리포트 3종 전면 재작성 필요해 본 Phase에서 수용
- **C-2 인계**: DASH-5/6 전용 테스트(model/query/controller)는 Phase 7 Tester 스코프로 인계 — C-1 시나리오(부분입금 2회 이상 청구·부호 검증)를 리뷰어 권고 시나리오 목록 1번으로 테스트화할 것
- 게이트: `bin/rubocop`(client_delay_query) 0 offenses · `bin/rails zeitwerk:check` 통과 · 전체 테스트 미실행(Phase 7)
