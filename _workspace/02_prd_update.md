# 02_prd_update.md — Phase 2 문서 현행화 기록

- **일자**: 2026-10-15
- **작업**: 토스 → 포트원(KG이니시스) 결제 게이트웨이 전환

## PRD.md (v0.20 → v0.21)

- **PLAN-5 갱신**: 결제 PG사를 토스페이먼츠에서 **포트원(KG이니시스)** 으로 변경 — 포트원 통합 API 레이어 경유. 구독 정기결제(빌링키)·건당 단건 결제 모두 포트원 V2 API 사용
- Order 모델 컬럼명 범용화: `toss_order_id`→`pg_order_id`·`toss_payment_key`→`pg_payment_id`·`toss_billing_key`→`pg_billing_key`

## AGENTS.md
- 로드맵 갱신은 Phase 9

## Rule ID 운영
- 신설·폐기 없음 — PLAN-5 내용 갱신
