# 01_plan — F-DASH 나머지(DASH-5/6) 구현 (2026-11-09, Full · 절약 모드)

## 목표

PRD §6.9의 미구현 2규칙을 단일 리포트 페이지로 구현한다. DASH-1/2/3/4는 구현 완료 상태.

- **DASH-5**: 거래처별 지연 리포트 + 월간 수금 추이 그래프
- **DASH-6**: 신고 주기별(1·4·7·10월) 매출·수금 집계표 + **세무 자문 아님 고지**(PRD 명시)

## 설계 결정 (게이트 확정 대상 — 권고안)

1. **단일 페이지 `/app/report`** — `resource :report, only: :show` + `App::ReportsController#show`(3섹션: 거래처별 지연 · 월간 수금 추이 · 신고 주기 집계). 사이드바 "리포트" 메뉴 추가(기존 6항목 — 준비 중 배지 아닌 활성 링크)
2. **Query Object 도입**(프로젝트 첫 `app/queries/` — 규약 §3.2: 집계·조인 2+는 Query Object, `.call`로 Relation 반환):
   - `Reports::ClientDelayQuery` — 거래처별 [진행 청구수·연체 건수·연체 금액(잔액 기준)·평균 지급 지연일]
   - `Reports::MonthlyCollectionQuery` — 최근 12개월 월별 수금액
   - `Reports::TaxPeriodQuery` — 1·4·7·10월 확정신고 시즌 매핑의 **분기별** [매출(공급가액)·부가세·수금액]
3. **지연 정의**: 마감 건 기준 `paid_on − due_on`(만기 대비 실입금일; 음수=조기). CLIENT-4(약속일 대비·거래처 카드)는 별도 미구현 스코프로 경계 유지 — PRD 문구로 구분
4. **매출 기준**: 공급가액(subtotal)·부가세 별도(INV-1) — draft·voided 제외(issued 계열만)
5. **그래프**: CSS bar chart(외부 JS 차트 라이브러리 금지 — importmap 최소 의존)·접근성 aria + 텍스트 표 병행
6. **KST 기준**(TIME-1) — 월·분기 경계 `Date.current` 기준

## 대상 파일

| 구분 | 파일 |
|---|---|
| 라우트 | `config/routes.rb` (resource :report — /app 네임스페이스) |
| 컨트롤러 | `app/controllers/app/reports_controller.rb` (신규 — 얇게, @변수만) |
| 쿼리 | `app/queries/reports/` 3종 (신규 디렉터리) |
| 뷰 | `app/views/app/reports/show.html.erb` (신규 — 3섹션·고지문·빈 상태) |
| 헬퍼 | `app/helpers/app/base_helper.rb` (nav 1항목 추가) + `app/reports_helper.rb`(신규 — 표현 로직) |
| 테스트 | `test/controllers/app/reports_controller_test.rb`·`test/queries/reports/` (신규) |

## 진행 (Full: 2→3→4→5→6?→7→8→9, 절약 프로필)

Developer-lite 1회(단일 위임 — queries·컨트롤러·뷰·라우트 결선은 한 사슬) → Reviewer-lite → Tester-lite → 실행 검증.

## 리스크·모호점

- **DASH-6 신고 주기 해석**: 1·4·7·10월을 "확정신고 시기"로 보고 **직전 분기(1~3월→4월 등) 집계**로 해석(권고). 부가세 예정신고(중간 5·11월)는 범위 밖 — PRD 문언은 시기 나열뿐이라 분기 매핑이 가장 단순·명확
- 지연 리포트의 "지연" 정의가 CLIENT-4(약속 대비)와 다름 — 화면 부제로 "만기일 대비" 명시해 혼동 방지
- SQLite group by month — date 컬럼이라 strftime/단순 그룹핑으로 해결 가능
- 사용자 스코프 격리: 전 쿼리 `user_id` 스코프 필수(소유권 격리 — 리뷰 기준)

## 관련 Rule ID

DASH-5·DASH-6·TIME-1·INV-1(공급가액)·PAY-1/2(수금·잔액)·DASH-3(이번 달 수금 — 기존)·CLIENT 경계(CLIENT-4 별도)·P1(톤 — 세무 고지 톤)
