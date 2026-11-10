# T-B3 — ADMIN-4 결제·매출 관리 구현 산출물

## 변경 파일 목록 (소유권 화이트리스트 내 전부)

| 파일 | 종류 | 내용 |
|:---|:---|:---|
| `db/migrate/20261110000002_add_refund_columns_to_orders.rb` | 신규 | orders에 `refunded_at datetime`·`refund_reason text` add_column(null 허용) |
| `app/models/order.rb` | 수정 | scope 4종 + `refunded?` + `mark_refunded!(reason)` |
| `app/controllers/admin/orders_controller.rb` | 신규 | index·show·mark_refunded(member PATCH) |
| `app/views/admin/orders/index.html.erb` | 신규 | 플랜 분포 카드·체험 만료 예정 표·주문 목록(필터 폼) |
| `app/views/admin/orders/show.html.erb` | 신규 | 주문 상세 + 환불 사유 기록 폼 |

**건드리지 않음(위반 0)**: routes.rb·layouts·user.rb·audit_log.rb·dashboards·Gemfile·Subscription 모델·기존 테스트.

## 환불 기록 설계 (ADMIN-4 · PRD v0.31 확정 해석 2·3·4 반영)

- **실 PG 환불은 포트원(KG이니시스) 콘솔 수동(PLAN-5)** — mark_refunded는 그 결과의 서비스 측 기록 절차. 컨트롤러·뷰·모델 주석에 명시, 뷰 폼에 확인 문구(turbo_confirm)와 사유 textarea(required).
- **상태 enum과 분리**: `refunded_at` 존재로 환불 판정(`refunded?`) — status는 `paid` 이력을 보존(매출 집계용 `Order.paid`와 정합). `refunded`/`not_refunded` 스코프도 refunded_at 기준.
- **`mark_refunded!(reason)`**: reason blank → ArgumentError(거부), 이미 환불 기록 → `false`(거부), 성공 → `update!(refunded_at: Time.current, refund_reason:)` + `true`. KST 기준 `Time.current`(TIME-1). 실 환불이 아니므로 단순 기록 — transaction 불요.
- **감사 로그는 컨트롤러 책임(§4.2)** — mark_refunded 성공 시 `AuditLogs::RecordService.call(admin:, action: "order_refund", target: order, detail: reason)`.
- **매출 집계 제외**: 3-S에서 `Order.paid` 합계에 `not_refunded` 1줄 추가 예정(02_prd_update.md 해석 2의 계약).

## 컨트롤러 상세

- `index`: `filtered_orders`(status: paid/failed·refund: refunded/not_refunded 화이트리스트 → `scope.send` 방지용 include? 검증).order(created_at desc).limit(100). 플랜 분포 `Subscription.group(:status).count`(@plan_counts — active/trialing/cancelled/expired 카드). 체험 만료 예정: `Subscription.trialing.where(trial_ends_at: Time.current..7.days.from_now)` — trialing 행의 만료는 trial_ends_at 기준(current_period_end는 active 시점부터 채워짐 — subscription.rb 구현 확인).
- `show`: pg_order_id·pg_payment_id·user·product·amount·status·metadata·환불 기록 표시. (orders 테이블에 subscription_id 없음 — schema.rb 확인, subscription 직접 참조 생략)
- `mark_refunded`: `params.expect(order: [:refund_reason])` — reason 필수 textarea. 성공 303 redirect + 감사 기록, 실패 422 render(show) + flash.
- 액션 본문 10줄 이내, `Admin::BaseController` 상속(ADMIN 세션 가드 재사용), view에서 쿼리 없음(@변수만), 전 출력 이스케이프(raw/html_safe 없음).

## 자기 스코프 검증 결과

- 마이그레이션: `db:migrate:up VERSION=20261110000002` → up·down·재up 전부 성공(컬럼 2종 생성/제거 확인). 전체 migrate 미실행(3-S 예정 — 해석 3 준수).
- runner(임시 레코드 생성 후 destroy — DB 오염 없음):
  - `Order.paid/failed/not_refunded/refunded` 스코프 전부 기대 동작
  - `mark_refunded!("테스트 사유")` → true, refunded scope 포착
  - 이중 환불 → false 거부 / blank reason → ArgumentError 거부
  - `Subscription.group(:status).count` 집계 정상(dev DB 비어 {} — 코드 로직 문제 없음)
- `bin/rubocop` 소유 3파일: **0 offense**
- `bin/rails zeitwerk:check`: **all is good**
- 컨트롤러 HTTP 검증: 라우트 미결선으로 미수행(해석 6 — Phase 5 리뷰어 재현·Phase 7 테스트 예정). 라우트 계약: `resources :orders, only: %i[index show]` + `member { patch :mark_refunded }`.

## 게이트 요약

| 항목 | 결과 |
|:---|:---|
| 마이그레이션 up/down(자기 버전만) | PASS |
| Order 스코프·mark_refunded!(정상/이중/blank) | PASS |
| 플랜 분포 집계 | PASS |
| rubocop(소유 파일) | 0 offense |
| zeitwerk:check | PASS |
| 전체 테스트·routes·nav·문서 | 금지 항목 — 미수행 |
