# 02_prd_update — F-DASH(DASH-5/6) 문서 현행화 (2026-11-09, Phase 2)

PRD v0.27 → **v0.28**. 승인 게이트에서 확정된 해석 3건을 명세에 반영.

## PRD.md 변경 내역

| 위치 | 변경 | 근거 |
|---|---|---|
| 문서 버전 | v0.28 (F-DASH 완성 — DASH-5/6 리포트 구현 확정) | Phase 2 필수 |
| DASH-5 | 구현 확정: 리포트 페이지(/app/report)·지연 = 만기일 대비 실입금일(마감 건·CLIENT-4와 별개)·수금 추이 최근 12개월 CSS 그래프(외부 라이브러리 금지·텍스트 표 병행) | 승인 해석 1·2 |
| DASH-6 | 구현 확정: 1·4·7·10월 = 확정신고 시기 → **직전 분기** 매출(공급가액 INV-1)·부가세·수금액 집계. 예정신고 범위 밖·draft·voided 제외 | 승인 해석 3 |

## AGENTS.md

- "구현 진행 상황" 갱신(완료 목록에 F-DASH 추가)은 **Phase 9**에서 일괄 — 이 단계 미변경

## Developer 지시서에 전달하는 확정 해석

1. Query Object 규약(ARCHITECTURE_CONVENTION §3.2): `app/queries/reports/` 3종 — `.call` Relation 반환·도메인 네임스페이스·zeitwerk 규약
2. 전 쿼리 user_id 스코프 격리(소유권 격리)·KST 기준 Date.current(TIME-1)
3. 지연일 산출: 마감 건 `paid_on − due_on` 평균(음수=조기 허용) — PAY-1/2 잔액 기준 연체 금액과 병기
4. 그래프: div bar 폭 % 계산은 헬퍼(표현 3줄+ 추출)·접근성 — figure/figcaption·텍스트 표 제공
5. 고지문: DASH-6 하단 "본 집계표는 세무 자문이 아닙니다. 신고 자료로 활용 전 세무대리인 확인을 권장합니다" 톤(LP-12·P1)
6. 빈 상태: 청구 0건 사용자에게 안내(기존 ONB-1 CTA 톤 준용)
