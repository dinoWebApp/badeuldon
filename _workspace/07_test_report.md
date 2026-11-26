# 07 테스트 실행 보고서 — A분 — 쿼리 경계·감사 IP (Tester — 2026-11-26)

대상: 병렬 배치 T1(감사 로그 IP — ADMIN-2·Q32) + T2/T4(`todays_sends_query_test.rb` 커버리지) 테스트 보강.
앱 코드·픽스처 변경 없음 — 테스트 파일만 추가·수정.

## 1. 실행 명령·결과

```
DATABASE_URL=sqlite3:tmp/parallel/TSTC/test.sqlite3 bin/rails test \
  test/queries/dashboards test/services/dashboards test/services/admins \
  test/services/orders/refund_service_test.rb \
  test/controllers/admin/admins_controller_test.rb test/controllers/admin/orders_controller_test.rb \
  test/controllers/app/payments_controller_test.rb test/controllers/app/payments_over_policy_test.rb \
  test/controllers/app/payments_reminders_test.rb
→ 196 runs, 1,142 assertions, 0 failures, 0 errors, 0 skips
  (쿼리+서비스+컨트롤러 묶음 175 runs / dashboards 서비스 21 runs)

bin/rubocop <수정·신규 7개 테스트 파일> → 7 files inspected, no offenses detected
```

외부 API 실호출 0건 — 환불·결제 경로는 전부 기존 `FakePortOneClient` + `with_portone_client` 대역 내 실행.

## 2. 신규·보강 테스트 목록

### A. 쿼리 경계 — `test/queries/dashboards/todays_sends_query_test.rb` (+5)
| 테스트 | Rule ID |
|:---|:---|
| 약속 트랙 포함 경계 — `promised_on = 오늘−4`(promise_overdue nominal+1+소급 창 끝) 포함 | DASH-2·Q31·REM-3 |
| 약속 트랙 포함 경계 — `promised_on = 오늘+1`(promise_d1 nominal 전일) 포함 | DASH-2·Q31·PROMISE-3 |
| `this_week` kind 약속도 후보(금요일 접수 → 서버 산정 약속일=오늘, PROMISE-2 서버 산정 계약 고정) | DASH-2·Q31·PROMISE-2 |
| 링크 만료(`token_expires_at` 경과) 청구는 후보 범위 안이어도 제외(link_valid) | DASH-2·SHARE-2 |
| 시퀀스 종결(`sequence_finished_at` 마킹) 청구의 쿼리 레벨 제외 | DASH-2·REM-12 |

기존 10테스트 회귀 없음. 쿼리가 Relation(후보)만 돌려주는 층 분리 설계(W-5)는 훼손하지 않음 — 전부 후보 모집단만 단언.

### B. 감사 IP — (+8)
| 파일 | 테스트 | Rule ID |
|:---|:---|:---|
| `test/services/admins/member_admin_service_test.rb` | `toggle_suspension!` ip 미지정 → `member_suspend` 감사 ip nil(리뷰 W-1 하위호환) | ADMIN-2·Q32 |
| `test/services/admins/role_service_test.rb` | staff가 `change_role!` ip와 직접 호출 → 내부 denial(`admin_role_denied`) 감사 ip 기록 | ADMIN-2·Q32 |
| `test/services/admins/role_service_test.rb` | staff가 `unlock!`·`create_admin!` ip와 직접 호출 → `admin_unlock_denied`·`admin_create_denied` 감사 ip 기록 | ADMIN-2·Q32 |
| `test/controllers/admin/admins_controller_test.rb` | CF-Connecting-IP 헤더 → `admin_create`·`admin_role_change`·`admin_unlock` 감사 3종 ip E2E | ADMIN-2·Q32 |
| `test/controllers/admin/orders_controller_test.rb` | staff의 환불 실행 시도 → `require_owner` 거부(`admin_console_denied`) 감사 ip + 서비스 미호출(주문 paid 유지·order_refund 0건) | ADMIN-1·ADMIN-2·Q32 |
| `test/controllers/app/payments_controller_test.rb` | CF-Connecting-IP 헤더 → 과다입금 `payment_over_recorded` 감사 ip E2E | ADMIN-2·Q32·Q22 |
| `test/services/orders/refund_service_test.rb` | PG 취소 뒤 확정 실패(PARTIAL_CANCELLED) → `order_refund_failed` 감사 ip 기록(리뷰 4) | ADMIN-2·Q32·PLAN-9 |

## 3. 앱 결함 후보

**없음** — 신규 13건 전부 기존 구현 통과(코드 버그 0). 테스트 오류 2건은 자체 수정(아래 5 참조).

## 4. 확인된 현재 동작(결함 아님)

- `this_week` 약속의 서버 산정 약속일은 접수일 기준 금요일이므로 화요일 접수분은 약속 트랙 창(오늘−4..오늘+1) 밖이다 — 테스트는 금요일 접수 시나리오로 고정(PROMISE-2·TIME-1 계약).
- `Promise` 검증이 과거 약속일(`promised_on < 오늘`)을 date_selected에서 거부 — −4 경계 테스트는 기존 −5 테스트 선례대로 `update_column` 직접 마킹 사용.
- 감사 ip 전수 스캔(균형 괄호 파서 — 멀티라인 호출 포함): `app/` 전체 `AuditLogs::RecordService.call` 30곳 모두 `ip:` 전달 확인 — 누락 0건.

## 5. 플레이크 관찰

- 1차 실행에서 테스트 오류 2건(자체 수정): ① 과거 약속일 검증 거부 → update_column 방식으로 수정 ② this_week 서버 산정 약속일이 화요일 기준 창 밖 → 금요일 접수로 수정. 2차 실행부터 0 failures(동일 시드 무관 3회 연속 통과 확인).
- 시간 고정: 쿼리 테스트는 기존 `TUESDAY`(2026-11-10 KST)·this_week용 금요일 2026-11-13, 날짜 판정 데이터는 전부 테스트 내 팩토리 생성(날짜 폭탄 없음).
