# 07_test_report — F-DASH(DASH-5/6) 테스트 작성·실행 (2026-11-09, Tester-lite · 절약 모드)

**최종 결과: 신규 21건 전부 통과 · 전체 회귀 668건 0실패 · RuboCop 0 offenses · 코드 버그 0건**

## 신규 테스트 파일

| 파일 | 건수 |
|---|---|
| `test/queries/reports/client_delay_query_test.rb` | 6 |
| `test/queries/reports/monthly_collection_query_test.rb` | 4 |
| `test/queries/reports/tax_period_query_test.rb` | 7 |
| `test/controllers/app/reports_controller_test.rb` | 4 |

실행: `bin/rails test test/queries/reports/ test/controllers/app/reports_controller_test.rb` → **21 runs, 83 assertions, 0 failures, 0 errors**
전체: `bin/rails test` → **668 runs, 3,892 assertions, 0 failures, 0 errors, 0 skips** (기존 647 + 신규 21)
`bin/rubocop`(신규 4파일) → **4 files inspected, no offenses detected**

## 시나리오·Rule ID 커버 맵

### ClientDelayQuery (DASH-5·PAY-2)
| 시나리오 | 종별 | Rule/근거 |
|---|---|---|
| ① 부분입금 2회 청구 평균 지연일 = 마감 입금일 기준(조기 −7 + 마감 +5, 단일 +7 → **+6**) | 정상 | 리뷰 C-1 재현·PRD v0.28 DASH-5 |
| 조기 단일 마감 → 음수(−3) 부호 유지 | 경계 | DASH-5 "음수는 조기" |
| 마감 0건 거래처 → avg nil + 진행 청구수 채움 | 예외 | DASH-5 Row 계약 |
| 연체 금액 = 부분입금 차감 잔액(110,000 − 10,000 = 100,000) | 정상 | PAY-2 |
| 만기일=오늘 청구는 연체 배타(unsettled 1·overdue 0) | 경계 | overdue 스코프 `due_on: ...Date.current` |
| 2사용자 교차 — 거래처 목록·평균 지연일(+6 vs +1)·연체 카운트 상호 비포함 | 예외 | 소유권 격리 |

### MonthlyCollectionQuery (DASH-5)
| 시나리오 | 종별 | Rule/근거 |
|---|---|---|
| 12행 고정·첫 행 2025.12·마지막 = 이번 달 2026.11 | 정상 | DASH-5 그래프 축 고정 |
| 빈 달 0원 11행 + 이번 달 실측 | 정상 | DASH-5 |
| 연간 경계(2025-12-01·12-31 포함) + 창 바깥 2025-11-30 제외(월말 1일 차 경계) | 경계 | TIME-1·02_prd_update |
| 타 사용자 입금 미포함(u1 10,000 vs u2 777,000) | 예외 | 소유권 격리 |

### TaxPeriodQuery (DASH-6·INV-1·TIME-1)
| 시나리오 | 종별 | Rule/근거 |
|---|---|---|
| 최근 4분기 2026 Q1~Q4 오름차순·기간 일치 | 정상 | DASH-6 |
| 라벨 4종(4·7·10월 + **익년 1월 확정신고**) | 정상 | DASH-6 라벨 매핑 |
| 분기 경계 발행 3/31 23:59→Q1 · 4/1 00:05→Q2 · 10/1 00:05→Q4(KST) | 경계 | TIME-1·리뷰 Tester 3번 |
| 매출(issued_at Q2)과 수금(paid_on Q3) 분기 분리 귀속 | 정상 | DASH-6 기준 분리 |
| 부가세 별도(공급가액 100,000 / 부가세 10,000) | 정상 | INV-1 |
| voided·draft 매출·부가세 전 행 0원 | 예외 | DASH-6 제외 규칙 |
| 타 사용자 매출·수금 미포함 | 예외 | 소유권 격리 |

### ReportsController (/app/report)
| 시나리오 | 종별 | Rule/근거 |
|---|---|---|
| 비인증 → 로그인 리다이렉트 | 예외 | AUTH-1 |
| 청구 0건 → 빈 상태 CTA만·3섹션 미노출·거짓 0원 없음 | 경계 | ONB-1·DASH-5/6 |
| 3섹션(aria-labelledby 3종) + 세무 고지문 원문 + 실데이터 행(+4일)·12개월 라벨 | 정상 | DASH-5/6·LP-12 고지 |
| 타인 거래처명·담당자 미노출 + 거래처 테이블 자기 행 1개만 | 예외 | 소유권 격리 |

## 리뷰(05_review.md) Tester 중점 제안 처리 결과

| 제안 | 처리 |
|---|---|
| 1. 부분입금 2회 이상 청구 평균 지연일 부호 검증(C-1) | **구현·통과** — C-1 수정분(MAX(paid_on) 마감 기준)이 기대 +6일을 산출. 행 단위 가중이 남아 있었다면 (−7+5+7)/3=+2로 검출되는 재현 시나리오 |
| 2. 두 사용자 교차 데이터 리포트 | **구현·통과** — 쿼리 3종 격리 테스트 + 컨트롤러 미노출 테스트 |
| 3. 분기 경계일(3/31 vs 4/1 KST) + 익년 1월 라벨 | **구현·통과** — 경계 발행 3건 + 라벨 4종 테스트 |
| 4. voided/draft 제외·부분입금 잔액 일치 | **구현·통과** — TaxPeriodQuery 제외 테스트·PAY-2 잔액 테스트 |
| 5. 신규 가입 빈 상태 | **구현·통과** — 컨트롤러 빈 상태 테스트(gamma 0건 fixture) |
| 6. 모바일 폭 그래프 금액 가시성(W-1) | 테스트 범위 외(시각 렌더링 — 시스템 테스트·실기 QA 영역). W-1 수정분은 코드 확인: `sm:opacity-0 sm:group-hover:opacity-100`으로 모바일 상시 표시 전환 확인 |

## 코드 버그 발견

**없음** — 신규 21건 전부 최초 실행에서 시맨틱 통과. 실행 중 수정한 것은 테스트 코드 자체 오류 3건뿐(부재 fixture명 `beta_client_1`→`beta_secret` 3파일, `find_by(...)!, kwargs` 파서 오류 → 지역변수화, `th[scope=row]` 셀렉터가 sr-only 표까지 매칭 → 섹션 스코프 한정).

## 비고

- 모든 날짜 의존 시나리오는 `travel_to(Time.zone.parse("2026-11-09 09:00"))`로 KST 고정(TIME-1) — 기존 fixture 운용 규칙(기준일 2026-10-12)과 무충돌: 신규 시나리오는 전부 테스트 내 시딩(fixture 축적 없음).
- Payment 모델 검증(`paid_on ≤ 오늘`) 하에서 마감 +N일 시나리오는 travel 기준일을 마감일 이후로 설계해 충족.
- 시딩 헬퍼는 각 파일에 지역 `private` 메서드로 두었다(test_helper 전역 추가 없음 — 기존 계약 불변).
