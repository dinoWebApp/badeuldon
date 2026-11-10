# 02_prd_update — CLIENT-3/4·PROMISE-5 문서 현행화 (2026-11-10, Phase 2)

PRD v0.34 → **v0.35**. Standard 런(Sequential 전환 — §6.14 판정 불리) 구현 확정 반영.

## PRD.md 변경 내역 요약

| 위치 | 변경 요지 |
|---|---|
| 문서 버전 | v0.35 (CLIENT-3/4·PROMISE-5 구현 확정) |
| CLIENT-3 | /app/clients/:id 카드 섹션·약속 이행 이력은 PROMISE-5 파생 판정 목록 |
| CLIENT-4 | 평균 지급 지연일 = 마감 건 중 약속 있던 청구의 (마감 입금일 − 약속일) 평균·6개월 경향 CSS·발행 폼 거래처 선택 시 Turbo 갱신·약속 없는 거래처 null 처리·DASH-5(만기 대비)와 구분 표기 |
| PROMISE-5 | **파생 계산 판정 확정(Q14)** — 이행 = paid + 마감 입금일 ≤ 약속일 / 미이행 = 도과 후 미수 / 판정 중 = 유효·도과 전 |
| 결정 기록 | Q14(파생 계산 방식) 신설 |

## Developer 지시서 전달 해석

1. 마감 입금일 = payments MAX(paid_on) — PAY-1/2 정의 준용(DASH-5·C-1 리뷰 선례와 동일)
2. 이행 판정 3상태는 Promise·Invoice 조인 파생 — 쿼리 객체 규약(§3.2)·user 스코프 격리
3. 비교 배지: 사용자의 모든 거래처 평균 지연일 대비 — 거래처 1개뿐이면 배지 없음
4. 발행 폼: 거래처 선택 변경 시 scorecard 엔드포인트 Turbo fetch — 거래처 미선택 시 비노출·타인 scorecard 접근 불가(소유권)
5. 표기: "약속일 대비" 부제·DASH-5와 구분 문구(PRD 명시)
