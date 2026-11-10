# 01_plan — F-ADMIN Run B 병렬 배치 (2026-11-10, §6.14 parallel · 절약 모드)

## 배치 목표

Run A(완료·APPROVED — 선행 산출 참조 허용) 위에서 ADMIN-5·2·3·4를 3태스크 병렬 fan-out으로 구현.
§6.14 3조건 판정 통과(아래 표). 라우트·nav 결선과 전체 마이그레이션은 3-S 직렬 통합.

## 태스크 분해 (병렬 안전 3조건 판정 포함)

### T-B1 · ADMIN-5 운영 대시보드
- 내용: Run A 골격 대시보드를 실데이터로 확장 — ① 가입·활성 지표(최근 가입·U1 세션) ② 청구 발행·수금 마감 통계(당월·누적 — 북극성: 발행 후 30일 내 수금) ③ 플랜 전환 퍼널(Free→체험→Plus) ④ 알림톡 발송량·실패율·skip 사유 분포(MessageLog 집계) ⑤ MRR(active plus × 9,900 — PLAN-2 상수 인용) ⑥ 이번 달 매출(Orders paid)
- **범위 한정**: 솔라피 크레딧 잔액 API는 [INFERENCE](라이브 실측 전) — 이번 배치는 message_logs **로컬 집계만**, 잔액 API 연동은 기술 부채 명시
- 소유 파일: `app/controllers/admin/dashboards_controller.rb`(Run A 파일 확장), `app/queries/admin/**`(신규), `app/views/admin/dashboards/**`, `test/controllers/admin/dashboards_controller_test.rb`
- 판정: ✓ 3조건 통과(신규 routes 불요 — 기존 admin root 유지)

### T-B2 · ADMIN-2 감사 로그 뷰 + ADMIN-3 회원 관리
- 내용: ① 감사 로그 목록·필터(action·관리자·기간) ② 회원 목록·검색(이름/상호·이메일·플랜·가입일·상태) ③ 회원 상세(프로필·청구 건수·미수 요약·발송 이력·문의 이력) ④ 플랜 수동 변경(체험 연장·구독 해지) ⑤ 계정 정지/해제 — **`users.status` 신규 마이그레이션**(suspended 시 로그인 차단 — authentication concern에 정지 체크)
- 소유 파일: `app/controllers/admin/audit_logs_controller.rb`·`members_controller.rb`(신규), `app/views/admin/{audit_logs,members}/**`, `db/migrate/` 신규 1건(users.status — 독립 추가), `app/models/user.rb`(status enum·scope), `app/models/audit_log.rb`(scope), `app/services/admins/member_admin_service.rb`(플랜 수동 변경·정지 — 감사 기록은 RecordService 경유), 해당 테스트
- 판정: ✓ 3조건 통과(독립 마이그레이션 1건 — 체인 수정 아님, 3-S에서 전체 migrate 1회)
- ADMIN-2 경계(01_plan Run A 확정) 준수 — 관리 행위 기록은 각 컨트롤러가 RecordService 경유로

### T-B3 · ADMIN-4 결제·매출
- 내용: ① 플랜 분포·체험 만료 예정 목록 ② 결제(주문) 이력 목록·상세 ③ 결제 실패 건 관리(재시도 현황 — dunning 미구현 명시) ④ **환불 사유 기록**(PLAN-6 환불 불가 정책의 CS 예외 절차 — `orders`에 refunded_at·refund_reason 컬럼 신규 마이그레이션, 실제 PG 환불은 포트원 콘솔 수동(PLAN-5) — 사유 기록+매출 집계 제외만)
- **범위 한정**: 쿠폰·프로모션 코드는 F-PLAN 결제 플로우 결선 필요 — **Run C 이관**(이유 명시)
- 소유 파일: `app/controllers/admin/orders_controller.rb`(신규), `app/views/admin/orders/**`, `db/migrate/` 신규 1건(orders refund 컬럼 — 독립 추가), `app/models/order.rb`(scope·refund 기록 메서드), 해당 테스트
- 판정: ✓ 3조건 통과

### 3-S 직렬 통합 (단일 Developer-lite 재위임)
- `config/routes.rb`: 플랜 확정 라우트 계약으로 결선 — T-B2 `resources :audit_logs, only: :index`·`resources :members, only: %i[index show] + member { patch :toggle_suspension; patch :change_plan }`·T-B3 `resources :orders, only: %i[index show] + member { patch :mark_refunded }`
- `app/views/layouts/admin.html.erb`: nav 링크 추가(대시보드·회원·결제·감사 로그)
- 전체 `db:migrate` 1회 + 각 신규 경로 부트 스모크

## 파일 소유권 표 (§6.14 필수)

| 파일/영역 | T-B1 | T-B2 | T-B3 | 3-S | 비고 |
|---|---|---|---|---|---|
| admin/dashboards_controller·queries/admin·views/dashboards | **소유** | | | | |
| admin/audit_logs·members 컨트롤러·views·member_admin_service | | **소유** | | | |
| users.status 마이그레이션·user.rb·audit_log.rb | | **소유** | | | 독립 신규 마이그레이션 |
| admin/orders 컨트롤러·views·orders refund 마이그레이션·order.rb | | | **소유** | | 독립 신규 마이그레이션 |
| config/routes.rb·layouts/admin.html.erb | | | | **소유(3-S)** | fan-out 태스크 접근 금지 |
| PRD·AGENTS·progress.json | ✗ | ✗ | ✗ | ✗ | 오케스트레이터 전용 |

## 파이프라인 (§6.14)

✋(이 문서) → 2(문서 현행화 직렬 1회) → 3-P(T-B1·T-B2·T-B3 동시, 상한 3) → 3-S(결선·migrate·스모크) → 4(게이트) → 5(Reviewer-lite — **컨트롤러 경유 runner 재현 필수**, Run A 교훈 반영) → 6? → 7(Tester-lite — 3-S 후 라우트 존재 상태에서 컨트롤러 테스트) → 8 → 9

## 리스크·모호점

- 3-S 전까지 fan-out 컨트롤러는 라우트 미결선 — 개발자 자기검증은 runner(서비스·쿼리·모델) 중심, 컨트롤러 검증은 5(리뷰 재현)·7(테스트)에서 수행(Run A 교훈 반영 구조)
- ADMIN-3 플랜 수동 변경이 Subscription을 직접 조작 — U1 결제 상태와 충돌 방지 규칙(활성 구독 보유 시 체험 전환 금지 등)을 Phase 2 확정 해석에 명시
- users.status 정지 시 기존 세션 파기 여부(파기 권고)·탈퇴 처리(AUTH-1.5)는 본 배치에서 정지까지만, 삭제·데이터 파기는 Run C 재검토(파급 범위 큼)
- MRR 산정: cancelled는 기간 말까지 포함 여부 — 권고: active만(해지는 기간 말 자동 만료 — PLAN-5)
- B3 마이그레이션(orders 컬럼)이 F-PLAN 서비스와 무충돌인지 — 컬럼 추가라 안전(기본값 null)

## 관련 Rule ID

ADMIN-2·3·4·5 · AUTH-7(운영 맥락) · PLAN-2/5/6 · REM-10(발송량 집계) · TIME-1 · SURF-3 · P5
