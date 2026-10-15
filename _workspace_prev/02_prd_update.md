# 02_prd_update.md — Phase 2 문서 현행화 기록

- **일자**: 2026-10-15
- **작업**: F-PLAN 구독·과금 (`_workspace/01_plan.md` 승인 플랜)

## PRD.md (v0.19 → v0.20)

- 버전만 갱신 — 명세 변경 없음(기존 PLAN-1~8 구현)
- 승인된 구현 해석 기록:
  - **토스 테스트 키** 사용(`Rails.application.credentials.dig(:toss, ...)`) — 라이브 전환 시 키만 교체
  - 빌링키 DB 평문 저장(테스트) — 라이브 시 암호화 검토
  - 체험 종료 카드 없음 → Free 강등(매일 Job)
  - 자동 갱신: 결제일 Job → 빌링키 차감 → 주기 연장
  - 가입 시 Subscription(free) 자동 생성
  - 수금 패스 10건·90일·with_lock 동시 방어
  - 환불 불가 정책 고지문만 표시(처리는 토스 콘솔 수동)

## AGENTS.md
- 로드맵 갱신은 Phase 9

## Rule ID 운영
- 신설·폐기 없음
