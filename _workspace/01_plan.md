# 01_plan — CLIENT-3/4·PROMISE-5 (2026-11-10, Standard · 절약 모드)

## §6.14 병렬 배치 판정 (사용자 명령 parallel — 3조건 대조)

**결론: 불리 — 단일 공유 파일 중심 + 의존 사슬. Sequential Standard 런으로 전환**(Run A 선례·§6.14 적용 판단 문언 준용).

| 분해 시도 | 판정 | 사유 |
|---|---|---|
| 카드(CLIENT-3) vs 성적표(CLIENT-4) | ✗ 공유 파일 | 둘 다 `app/views/app/clients/show.html.erb`에 섹션 추가 — 동일 파일 |
| 성적표 vs PROMISE-5 판정 | ✗ 의존 위반 | 성적표(이행률·지연일)가 PROMISE-5 이행 판정 산출을 참조 — 선행 필요 |
| 성적표 vs 발행 직전 노출 | ✗ 공유 파일 | invoices new/edit 폼 삽입 — 성적표 산출 인터페이스 참조 |

→ 단일 Developer-lite 1회 위임(Sequential · 절약).

## PROMISE-5 이행 판정 정의 (PRD 미명시 — 결정 기록 Q14 제안, 게이트 확정 대상)

**파생 계산 방식 채택 권고**(별도 기록 컬럼 없음 — 데이터 이중화 방지·과거 소급 정합):
- **이행**: 해당 청구가 수금 완료(paid)이고 **마감 입금일(payments MAX paid_on) ≤ 약속일(promised_on)**
- **미이행**: 약속일 도과(약속일+1 이후) 시점에 미수였던 기록 — 현재 기준 파생 판정(promised_on < today && invoice 미수)
- **판정 중**: 약속 유효·아직 도과 전(unsettled + promised_on ≥ today)
- 거래처 카드·성적표는 위 파생 판정의 집계로 "자동 기록" 충족(PRD 문언) — 리마인더 promise_overdue 발송 이력과 무관하게 파생 정합 유지

## CLIENT-4 지표 정의 (권고 — 게이트 확정)

1. **평균 지급 지연일**: 마감 건 중 **약속이 있었던 청구**의 (마감 입금일 − promised_on) 평균 — 약속 없던 청구 제외(참고: 만기 대비는 DASH-5와 별개 — 화면 구분 표기)
2. **약속 이행률**: 약속 건 중 이행 비율(위 판정 기준)
3. **최근 6개월 지급 경향**: 월별 평균 지급 지연일 추이(CSS·외부 라이브러리 금지)
4. **비교 배지**: 동일 사용자의 전체 거래처 평균 지연일과 비교 — 차이 ≥ 1일 시 "평균보다 N일 빠른/느린 거래처" 배지(PRD 예시 문구 준용)

## 구현 범위

| 구분 | 파일 |
|---|---|
| 쿼리 | `app/queries/clients/` 신규 — PaymentScorecardQuery(거래처별 4지표+비교)·PromiseComplianceQuery(이행/미이행/판정 중 목록 — CLIENT-3 이력) 또는 단일 클래스 내 2메서드(당신 판단·규약 §3.2) |
| 모델 | Promise·Invoice 최소 scope 추가만(파생 판정) — 마이그레이션 불요 |
| 컨트롤러 | `app/clients_controller.rb` show 확장(@scorecard 로드) + **`app/invoices_controller.rb` scorecard 엔드포인트**(발행 폼 거래처 선택 시 Turbo 갱신 — 신규 1액션) |
| 뷰 | `app/views/app/clients/show.html.erb`(카드 CLIENT-3+성적표 CLIENT-4 섹션)·`app/views/app/invoices/_form.html.erb`(발행 직전 요약 삽입)·scorecard 요약 파셜(신규) |
| 라우트 | invoices scorecard 1건(app namespace — `get "scorecard" => "invoices#scorecard"` 계약·3-b 결선 아님 — sequential이라 당신 결선) |
| 테스트 | 쿼리(판정 3상태·경계 — 입금일==약속일·월말·약속 없는 청구 제외)·컨트롤러(scorecard 엔드포인트 소유권·렌더)·시스템(발행 폼 요약) — Phase 7 |

## 진행 (Standard: 2→3→4→5→6?→7→8→9 · 절약)

단일 Developer-lite 1회 → Reviewer-lite(컨트롤러 경유 재현 필수) → Tester-lite(전체 게이트) → Phase 8(부트·경로) → 완료 보고.

## 리스크·모호점

- 약속 없는 청구만 있는 거래처: 성적표 지표 null 처리("-" 표기)·비교 배지 제외
- 발행 폼 거래처 변경 시 갱신 UX(Turbo fetch vs 페이지 로드 기본 거래처) — 개발자 최소 구현 선택·PRD 요건("발행 직전 화면 요약 노출") 충족이 기준
- payment MAX paid_on = 마감 입금일 정의(PAY-1 — 부분입금 합산 시 최종 입금일 기준)
- DASH-5(만기 대비)와의 지표 혼동 — 화면 부제로 구분(DASH-5 구현 시 확정 해석 준용)

## 관련 Rule ID

CLIENT-3·CLIENT-4·PROMISE-5·PAY-1/2(마감 입금일·잔액)·INV-4·DASH-5(경계 구분)·TIME-1·P1(문구 톤)
