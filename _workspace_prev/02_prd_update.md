# 02_prd_update — F-ADMIN Run B 문서 현행화 (2026-11-10, Phase 2)

PRD v0.30 → **v0.31**. 배치 승인(T-B1~T-B3 전부)에 따른 구현 확정 해석 반영.
(미커밋 Run A·템플릿 문서·credentials는 이번 런 커밋에 포함)

## PRD.md 변경 내역 요약

| 위치 | 변경 요지 |
|---|---|
| 문서 버전 | v0.31 (F-ADMIN Run B 구현 확정) |
| ADMIN-3 | users.status enum(정지 시 로그인 차단+세션 파기)·플랜 수동 변경 규칙(활성→체험 금지·연장=period 연장·해지=cancel!·전건 감사 기록)·staff 변경 가능(롤만 owner)·삭제·파기는 Run C |
| ADMIN-4 | 환불 기록 = orders.refunded_at·refund_reason(실 PG 환불은 포트원 콘솔 수동 — PLAN-5)·감사 필수·**쿠폰·프로모션은 Run C 이관**(결제 플로우 결선) |
| ADMIN-5 | MRR=active Plus×9,900·매출=환불 제외·북극성=30일 내 수금 완료율·MessageLog 로컬 집계·**솔라피 크레딧 API는 기술 부채([INFERENCE])** |

## fan-out 전달 확정 해석 (각 지시서에 첨부)

1. **라우트 계약(3-S 결선용 — fan-out 태스크 routes 금지)**:
   - T-B2: `resources :audit_logs, only: :index` · `resources :members, only: %i[index show]` + `member { patch :toggle_suspension; patch :change_plan }`
   - T-B3: `resources :orders, only: %i[index show]` + `member { patch :mark_refunded }`
   - T-B1: 신규 라우트 없음(admin root 유지·확장)
2. **의존 회피 규칙**: T-B1의 매출 집계는 이번 배치에서 `Order.paid` 합계로 구현 — `refunded_at: nil` 제외는 **3-S 통합 항목**(T-B3 마이그레이션 적용 후 1줄 추가, 계약은 본 문서로 확정)
3. **마이그레이션**: T-B2(users.status)·T-B3(orders refund) 각자 독립 신규 파일 — 자기 마이그레이션만 `db:migrate:up VERSION=<자기 버전>` 적용 검증, 전체 migrate는 3-S
4. **감사 기록**: 모든 관리 행위는 컨트롤러가 `AuditLogs::RecordService` 경유(Run A 교훈 W-4 — 모델→서비스 호출 금지 §4.2)
5. **정지 시 세션 파기**: user.sessions 전부 destroy + authentication 로직에 suspended 차단(T-B2가 sessions_controller 수정 — 소유권에 포함)
6. **컨트롤러 경유 검증 표준**(Run A 교훈): fan-out 개발자는 라우트 미결선이라 서비스·쿼리·모델 runner 검증만, 컨트롤러 검증은 Phase 5(리뷰어 재현 필수)·7(테스트)에서
