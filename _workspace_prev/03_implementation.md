# 03_implementation — 3-S 결선 통합 (Run B 병렬 배치, 2026-11-10)

## 결선 내역

| # | 파일 | 변경 |
|---|---|---|
| 1 | `config/routes.rb` | admin namespace에 3 resources 결선 — 계약(02 확정 해석 1) 그대로 |
| 2 | `app/views/layouts/admin.html.erb` | nav 링크 행 추가(대시보드·회원·결제·감사 로그) — active 판정 `request.path.start_with?`(대시보드는 ==). Run A 레이아웃의 실용 톤 유지, 로그인 상태에서만 표시 |
| 3 | `app/queries/admins/revenue_stats_query.rb` | `Order.paid` → `Order.paid.not_refunded` + 주석("환불 기록 주문 제외 — ADMIN-4·3-S 통합"). T-B3의 `not_refunded` 스코프 사용 |
| 4 | `bin/rails db:migrate` | 전체 1회 적용 |

## 라우트 최종 목록 (admin namespace 추가분)

```
admin_audit_logs            GET  /admin/audit_logs                     # ADMIN-2
admin_members               GET  /admin/members                        # ADMIN-3
admin_member                GET  /admin/members/:id
toggle_suspension_admin_member PATCH /admin/members/:id/toggle_suspension
change_plan_admin_member    PATCH /admin/members/:id/change_plan
admin_orders                GET  /admin/orders                         # ADMIN-4
admin_order                 GET  /admin/orders/:id
mark_refunded_admin_order   PATCH /admin/orders/:id/mark_refunded
```

- 컨트롤러 액션명·파라미터 실측 확인 결과 3개 컨트롤러 모두 계약과 일치 — **컨트롤러 측 정렬 불필요**.

## migrate 결과

`db:migrate:status` — 20261110000001(Create admin infrastructure)·**20261110000002(Add refund columns to orders)·20261110000003(Add status to users)** 전부 up. `db/schema.rb` 갱신.

## 쿼리 재검증

`RevenueStatsQuery.call` runner 재실행 — 환불 제외 반영 정상 동작(`{month_revenue: 0, total_revenue: 0, mrr: 0}`, 빈 dev DB 기준 에러 없음).

## 스모크 결과 (dev 서버 :3002)

| 경로 | 기대 | 실측 |
|---|---|---|
| `/up` | 200 | **200** |
| `/admin/session/new` | 200 | **200** |
| `/admin` | 303 가드 | **303 → /admin/session/new** |
| `/admin/members` | 303 가드 | **303 → /admin/session/new** |
| `/admin/orders` | 303 가드 | **303 → /admin/session/new** |
| `/admin/audit_logs` | 303 가드 | **303 → /admin/session/new** |

- 라우트 존재 + `Admin::BaseController` 가드 동작 실측 완료(관리자 미로그인). 로그인 상태 렌더링 검증은 Phase 5(리뷰어 재현)·Phase 7(테스트) 소관 — 02 확정 해석 6.
- 서버 정지 + `tmp/pids/server_3002.pid` 삭제 완료.

## 검증 게이트

- `bin/rails zeitwerk:check`: all is good
- `bin/rubocop` (routes.rb·revenue_stats_query.rb): 0 offense. (admin.html.erb는 RuboCop이 ERB를 Ruby로 파싱하는 기존 한계로 오탐 83건 — 본 결선이 추가한 nav 줄과 무관한 파일 전체 파싱 오류. 런타임 렌더링은 스모크에서 세션 페이지 200으로 부트·ERB 구동 확인)
- 전체 테스트·문서(PRD/AGENTS) 금지 항목 — 미수행

## Phase 6 — 리뷰 반영(B-1 + W-1~W-5, 2026-11-10)

05_review.md(CHANGES_REQUESTED — BLOCKER 1·WARNING 5) 통합 수정.

| 이슈 | 수정 내용 | 파일 |
|---|---|---|
| B-1 | 환불 폼 `form_with`에 `scope: :order` 추가(1줄·컨트롤러 무변경) — 필드가 `order[refund_reason]`로 생성 | `views/admin/orders/show.html.erb` |
| W-1 | mark_refunded에 `rescue ArgumentError → 422 render show + flash`(500 금지) | `admin/orders_controller.rb` |
| W-2 | `by_period`을 scope → 클래스 메서드 전환, `safe_boundary`(Time.zone.parse 실패/nil 시 해당 필터 생략) | `models/audit_log.rb` |
| W-3 | members index `includes(:subscription)`·orders index `includes(:user)`·expiring_trials `includes(:user)` | `members_controller.rb`·`orders_controller.rb` |
| W-4 | `Admin.order(:email).pluck`를 뷰에서 제거 → 컨트롤러 `@admins` 로드·@변수 전달 | `audit_logs_controller.rb`·`views/admin/audit_logs/index.html.erb` |
| W-5 | `extend_trial!`에 `(1..12).cover?(months)` 검증 — 위반 시 Result failure("연장 개월은 1~12개월…"), 감사 미기록 | `services/admins/member_admin_service.rb` |

### 컨트롤러 경유 재검증 (test env, Integration::Session + 관리자 로그인 플로우 — B-1 재현 방식 동일)

| 검증 | 결과 |
|---|---|
| B-1: 폼과 동일 페이로드 `order: { refund_reason }` PATCH → 303 + refunded? + `order_refund` 감사 | PASS |
| W-1: blank 사유 PATCH → 422 + 미기록(500 없음) | PASS |
| W-2: `from=garbage`·`to=2026-13-45` → 200(필터 생략), 유효 날짜 → 200 | PASS |
| W-5: months=0 컨트롤러 PATCH → 303 alert + period 무변경 / 서비스 0·13 거부 / 3 수락 / "0개월 연장" 감사 오염 없음 | PASS |
| W-3·W-4: members·orders·audit_logs index 200 | PASS |
| 재현 후 정리: users/orders/audit_logs 잔존 0 | PASS |

게이트: rubocop 수정 5파일 0 offense · zeitwerk all is good · 전체 테스트는 Phase 7 소관(미실행).

### Run C 이관 항목 (리뷰어 확인 요청 답변 — ADMIN-3·ADMIN-4)

- **ADMIN-3 롤 부여·해제 콘솔**(staff↔owner — AUTH-7.2): Run B 미포함, ADMIN-1 runner 절차로 운영. Run C에서 관리자 관리 콘솔로 구현 필요.
- **ADMIN-4 쿠폰·프로모션 관리**: PRD §275 표기대로 Run C 이관(결제 플로우 결선).
- **ADMIN-3 ④ 계정 삭제·데이터 파기**(AUTH-1.5 재검토 포함): Run C.
