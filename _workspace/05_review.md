# 05_review — F-DASH(DASH-5/6) 리포트 구현 (2026-11-09, Reviewer-lite · 절약 모드)

## 종판

**status: CHANGES_REQUESTED** — BLOCKER 0 · CRITICAL 2 · WARNING 2 (재리뷰 대상: C-1·C-2 수정분 + 권고 W-1·W-2)

이전 리뷰 산출물 없음(신규 파이프라인 — 이슈 추적 대상 없음).

## 이슈 목록

### C-1 · CRITICAL · DASH-5 — 평균 지급 지연일이 PRD 정의(마감 입금일 기준)와 불일치 — 부분입금 행 가중·조기 입금 혼입

- **파일**: `app/queries/reports/client_delay_query.rb:21-24`
- **근거**: PRD v0.28 DASH-5 ② "지연은 **만기일 대비 실제 입금일**(마감 건 기준)". 마감 건의 실제 입금일은 **마감(최종) 입금일**이므로 청구 건당 지연일은 `마감 paid_on − due_on` 1개여야 한다. 구현은 Payment **행 단위** `julianday 차` 평균이라 ① 부분입금 건이 입금 행 수만큼 가중되고 ② 마감 전 조기 입금 행이 음수로 평균을 끌어내린다.
- **재현(rails runner, test 환경 — 임의 데이터, rollback)**:
  - 청구 A(부분입금 10-25 −7일 → 마감 11-06 +5일) + 청구 B(단일 +7일) → PRD 기대 **+6일**, 구현 결과 **−1일("1일 조기" 표시)** — 부호 반전.
  - 극단 시나리오(조기 부분입금 −233일 + 마감 +15일 등 5입금 3청구): 구현 **−43일** vs 마감 기준 **+9일**.
- **수정 권고**: 청구별 마감 입금일(최종 paid_on)로 한정한 뒤 청구 단위 평균. 예:
  ```ruby
  closing = Payment.select("invoice_id, MAX(paid_on) AS paid_on")
                   .where(invoice_id: Invoice.where(user_id:, status: :paid).select(:id))
                   .group(:invoice_id)
  avg_delays = Invoice.joins("INNER JOIN (#{closing.to_sql}) closing_payments ON closing_payments.invoice_id = invoices.id")
                      .where(user_id:)
                      .group(:client_id)
                      .average("julianday(closing_payments.paid_on) - julianday(invoices.due_on)")
  ```
  (상수 SQL 보간 — 파라미터 없음, 인젝션 없음. user_id 스코프는 내부 where에 존재.)

### C-2 · CRITICAL · 테스트 전략 — DASH-5/6 신규 기능 전용 테스트 전무

- **파일**: (부재) `test/controllers/app/reports_controller_test.rb` · `test/queries/reports/`
- **근거**: 01_plan 대상 파일 표에 두 테스트 명시 → 미구현, 03_implementation에 누락 사유 미기술. PRD 테스트 전략 "Rule ID별 정상/경계/예외 시나리오 도출이 원칙" 위반이며, C-1 버그가 게이트를 통과한 원인(기존 647건 전부 회귀만 확인).
- **수정 권고**: ① Query 테스트 3종 — 스코프 격리(타 사용자 데이터 비포함)·부분입금 잔액(PAY-2)·만기일=오늘 연체 배타·연간 경계(12월→1월)·분기 경계(3/31 vs 4/1)·draft/voided 매출 제외·빈 사용자(12행 0원·4행 0원) ② 컨트롤러 테스트 — 미인증 리다이렉트·렌더 200·빈 상태 CTA·고지문 존재.

### W-1 · WARNING · DESIGN-6/접근성 — 월간 수금 추이 금액이 hover 전용(터치 기기에서 확인 불가)·figcaption 문구 터치 부적합

- **파일**: `app/views/app/reports/show.html.erb:86-88, 96`
- **내용**: 금액 라벨이 `opacity-0 group-hover:opacity-100` — 모바일(/app U1 다수 접속)에선 금액을 볼 수 없고, sr-only 표는 스크린리더 전용이라 시각 사용자 대체 불가. figcaption "막대에 마우스를 올리면"은 터치 기기 부적합 문구.
- **수정 권고**: 금액 상시 표시(세로 여유 충분) 또는 터치에서도 노출되는 토글. 문구는 "최근 12개월 월별 수금액입니다"(동작 의존 문구 제거)를 권한다.

### W-2 · WARNING · 규약 §3.2-4 — Query Object 반환형이 규약 문언("Relation 반환")과 불일치

- **파일**: `app/queries/reports/` 3종 전체
- **내용**: 규약 §3.2-4 "Query Object는 .call로 Relation을 반환한다 — 컨트롤러/서비스 어디서도 체인 가능" / 02_prd_update 확정 1도 동일 문언. 구현은 집계 완료 Row Struct 배열 반환(체인 불가). 집계 쿼리의 실용적·무해한 선택이나 **계획서·규약 문언과의 불일치**라 기록한다.
- **수정 권고**: 코드 유지 시 ARCHITECTURE_CONVENTION §3.2에 "집계 Query는 행 구조체 배열 반환 허용" 단서 추가로 문언 정합(문서 우선). 코드 정합을 택한다면 Relation 계약 위반이므로 문서 갱신이 최소 변경이다.

### 기록(지적 아님)

- `average`에 raw SQL 문자열(Arel.sql 미사용) — 집계 함수는 허용 범위·상수 문자열이라 인젝션 없음. C-1 수정 시 일관성 차원에서 Arel.sql 정리 권장.
- TaxPeriodQuery 매출이 행당 1쿼리 × 4 — 상수 4건으로 성능 무의미. 인덱스(user_id·due_on 복합, user_id, payments.invoice_id) 기존 인덱스로 충분 — **마이그레이션 불요 판정 타당**.
- 뷰 내 "거래처가 등록되지 않았습니다" 분기는 실질 도달 불가(청구 존재→거래처 존재·CLIENT 삭제 가드) — 방어 코드로 유지 무방.

## Rule ID 준수 매핑 (재현으로 검증한 항목 포함)

| Rule | 판정 | 검증 방법 |
|---|---|---|
| DASH-5 (리포트 페이지·지연 정의 구분·12개월·CSS 그래프·텍스트 표) | 부분 통과 — 지연 정의 구분 표기·그래프·텍스트 표 OK, 평균 지연일 산출 C-1 | 코드 대조 + runner |
| DASH-6 (분기 매핑·공급가액·draft/voided 제외·기준 분리·고지문) | 통과 | runner: 3/31→Q1·4/1→Q2 경계, 라벨 4종(4·7·10·익년1월), voided/draft 제외, 고지문 원문 일치 |
| PAY-2 (연체 금액 잔액 기준) | 통과 | runner: 부분입금 100,000 차감 230,000 (=total−paid, Invoice#remaining_amount 동치) |
| TIME-1 (KST 고정) | 통과 | SQL 바인딩 `BETWEEN '2026-09-30 15:00:00'...` = KST 10-01 00:00 — KST 새벽(02:00) 발행도 올바른 분기 소속 |
| 소유권 격리 | 통과 | runner: 2사용자 교차 — Client·Invoice·Payment join 경로 전부 user별 분리, 누출 0 |
| AUTH-1.3·인증 | 통과 | App::BaseController 상속(require_authentication·프로필 가드), 뷰 `@user.display_name`은 가드 후 보장 |
| SQL 인젝션·이스케이프 | 통과 | 그룹 키 상수 문자열(Arel.sql)·뷰 `<%= %>`만(raw/html_safe 없음) |
| 규약 §3.2·§4 | 부분 통과 | 네임스페이스·`.call`·컨트롤러 7줄·뷰 쿼리 금지·의존 방향 OK — 반환형 문언만 W-2 |
| SURF-3 (noindex) | 해당 없음 | /app 공통 레이아웃 정책 상속(기존 구현) |
| PLAN 게이트 | 해당 없음 | 리포트는 플랜 한도 대상 아님(PRD 미규정) — nav locked는 AUTH-1.3 프로필 잠금 규칙 준용 |
| UI(DESIGN-2·6·8) | 부분 통과 | h1→h2 위계·상태색 3종·tabular-nums·figure/figcaption·min-h-11·focus-visible·ONB-1 톤 빈 상태 OK — W-1만 |

## Tester 중점 테스트 제안

1. **부분입금 2회 이상 청구의 평균 지급 지연일** — C-1 수정 검증용 시나리오(조기 부분입금 + 지연 마감 조합, 부호 검증)
2. 두 사용자 교차 데이터 리포트 — 각 섹션 수치가 자기 데이터만 반영하는지(연체 금액·월별 추이·분기 매출)
3. 분기 경계일 발행(3/31 23:59 vs 4/1 00:05 KST) 소속 분기 + 라벨 "익년 1월 확정신고" 연말 케이스
4. voided·draft 청구가 매출·부가세·진행 집계에서 빠지는지 / 부분입금 청구의 연체 금액 잔액 일치(DASH-1 미수 총액과 동치)
5. 신규 가입(청구 0건) — 빈 상태 CTA 노출·3섹션 미노출·12개월 그래프 0원 렌더
6. 모바일 폭에서 그래프 금액 가시성(W-1) — 터치 기기에서 월별 금액 확인 가능 여부

## 검증 커버리지 (Reviewer 자체 재현 — RAILS_ENV=test runner, 종료 시 rollback)

- 스코프 격리(u1/u2 교차 3쿼리) · PAY-2 잔액 · 만기일=오늘 배타 · 12행 고정 · 연간 경계(2025.12) · 월 경계 · 분기 시작월 경계(3/31·4/1·12/31) · 라벨 4종 · 분기 순서 · Q3/Q4 매출·부가세·수금 분리 · voided/draft 매출 제외 · draft 집계 제외 · KST 분기 경계 바인딩 · 빈 사용자 3쿼리 — 전부 구현 동작 확인(PASS).
- `bin/rails test` 전체·rubocop·zeitwerk:check은 오케스트레이터 게이트 확인(0실패·0 offenses·통과) 기반 — C-2는 존재 테스트의 '커버리지' 문제다.
