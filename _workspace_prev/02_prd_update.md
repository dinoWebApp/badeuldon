# 02_prd_update — F-ADMIN 잔여 병렬 배치 문서 현행화 (2026-11-10, Phase 2)

PRD v0.33 → **v0.34**. 배치 승인(T-C1~C3 전부)에 따른 구현 확정 반영.

## PRD.md 변경 내역 요약

| 위치 | 변경 요지 |
|---|---|
| 문서 버전 | v0.34 (F-ADMIN 잔여 구현 확정) |
| AUTH-7.2 | 콘솔 생성 UI 동일 요건 제공 — 최초 계정만 runner, 추가 계정은 콘솔(owner 전용) |
| ADMIN-1 | admins 목록·생성·role 승강·잠금 해제 콘솔 — owner 전용 경계·전 행위 감사 |
| ADMIN-3 | ④ 계정 삭제·데이터 파기 **구현 확정(Q13)** — 미수 차단·연쇄 삭제·감사 보존·이메일 스냅샷·2중 확인 |
| ADMIN-4 | 쿠폰 **구현 확정(Q12)** — Plus 첫 결제 1회 할인·percent/amount·한도·만료·CRUD+통계·재과금·수금 패스 미적용 |
| 결정 기록 | Q12(쿠폰 범위)·Q13(계정 삭제 조건) 신설 |
| ADMIN-10 | 기존 "후속 분리" 유지 — LP-11 블로그와 통합하는 별도 대형 런(이번 배치 제외 확정) |

## fan-out 전달 확정 해석 (각 지시서에 첨부)

1. **라우트 계약(3-S 결선용 — fan-out routes 금지)**:
   - T-C1: `resources :admins, only: %i[index new create]` + `member { patch :change_role; patch :unlock }` (admin namespace)
   - T-C2: `resources :coupons` (admin namespace, 표준 CRUD)
   - T-C3: 기존 `resources :members, only: %i[index show] + member{...}` → `only: %i[index show destroy]` 확장 + 기존 member 유지
2. **T-C2 쿠폰 불변식**: 코드 검증은 서버(코드·만료·활성·한도)·적용 1회·used_count는 **결제 성공 시점**만 증가(멱등)·첫 차감 orders.amount=할인가·metadata에 coupon_code·재과금 정상가·amount 할인 상한 9,900(0원 방지)·구현 구조(사용자 컬럼/세션/메타데이터)는 당신 설계 — 리뷰어가 불변식 전수 재현
3. **T-C3 삭제 불변식**: 미수(invoice remaining>0) 존재 → 차단·감사 기록은 삭제 트랜잭션과 원자(detail에 이메일 스냅샷)·admin 행위 감사는 절대 삭제되지 않음(audit_logs.admin_id는 admin 본인)
4. **T-C1 owner 경계**: staff 세션으로 생성·role 변경·잠금 해제 시도 → 차단+안내(403 계열)·감사에 시도 기록
5. **컨트롤러 경유 검증 공백(Run A/B 교훈)**: fan-out은 라우트 미결선 — runner 중심 자기검증(서비스·모델·쿼리), 컨트롤러 검증은 Phase 5(리뷰어 재현 필수)·7
6. 마이그레이션: T-C2 coupons 신규 1건만 — 자기 버전 `db:migrate:up/down` 개별 검증, 전체 migrate은 3-S
