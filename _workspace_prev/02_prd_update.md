# 02_prd_update.md — Phase 2 문서 현행화 기록

- **일자**: 2026-10-12
- **작업**: F-SHARE 열람 추적 + F-VIEW 채무자 뷰어 (`_workspace/01_plan.md` 승인 플랜)

## PRD.md (v0.18.4 → v0.18.5)

- 버전만 갱신 — **명세 변경 없음**. 근거: SHARE-1/2/3, VIEW-1/2/3/5/6/8, INV-4(viewed), PAY-3 기존 명세의 구현.
- 승인된 구현 해석 기록:
  - **SHARE-4 U1 알림 발송 연기**: 발송 채널이 NOTI-1 알림톡(핵클 미계약)으로 실발송 불가 — viewed 상태 전이 + 대시보드 「열람」 뱃지로 U1 인지 확보, ViewEvent로 발송 근거 데이터 완비. 채널 계약 시 REM/NOTI 파이프라인에서 연결
  - **SHARE-6 발송 방식**: 링크 복사만 제공 (서비스 명의 발송은 REM·핵클 계약 후 옵션 추가)
  - VIEW-4 응답 버튼·PDF는 F-PROMISE/후속 (뷰어에는 미노출)
  - ViewEvent IP 기록: 알림·분석 근거 목적 저장 — SEC-3 최소 수집 준수 여부는 리뷰 검증

## AGENTS.md

- 이번 Phase 변경 없음 — 로드맵 갱신은 Phase 9

## Rule ID 운영

- 신설·폐기 없음
