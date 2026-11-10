# 07_test_report — F-ADMIN Run B 병렬 배치 테스트 작성·실행 (2026-11-10, Phase 7 · 절약 모드)

**최종 결과: 총 783건(기존 668 + Run B 신규 85 + 개발자 사전 추가 30) · 0실패 · 0에러 · 0스킵 — `bin/rails test` 전체 통과**
**RuboCop: 테스트 파일 31 files · 0 offenses — 통과** (autocorrectable 1건 자가 수정 후 재확인)

---

## 1. 산출 테스트 파일 (신규 10 + 확장 4)

| 계층 | 파일 | 건수 | 검증 Rule ID |
|---|---|---|---|
| 쿼리 | `test/queries/admins/signup_stats_query_test.rb` | 3 | ADMIN-5·TIME-1 |
| 쿼리 | `test/queries/admins/plan_funnel_query_test.rb` | 3 | ADMIN-5·PLAN-2·PLAN-5·Q4 |
| 쿼리 | `test/queries/admins/revenue_stats_query_test.rb` | 4 | ADMIN-5·ADMIN-4·PLAN-2·PLAN-5 |
| 쿼리 | `test/queries/admins/collection_stats_query_test.rb` | 4 | ADMIN-5(북극성)·부분입금 가중 방지 |
| 쿼리 | `test/queries/admins/message_stats_query_test.rb` | 4 | ADMIN-5·REM-10(솔라피 로컬 집계) |
| 서비스 | `test/services/admins/member_admin_service_test.rb` | 12 | ADMIN-3·ADMIN-2(감사 전건/미기록)·W-5 |
| 컨트롤러 | `test/controllers/admin/orders_controller_test.rb` | 7 | ADMIN-4·**B-1 회귀**·W-1·표면 격리 |
| 컨트롤러 | `test/controllers/admin/members_controller_test.rb` | 12 | ADMIN-3·W-5·PLAN-5·ADMIN-3① 정지 |
| 컨트롤러 | `test/controllers/admin/audit_logs_controller_test.rb` | 5 | ADMIN-2·W-2·W-4 |
| 컨트롤러 | `test/controllers/admin/dashboards_controller_test.rb` | 5 | ADMIN-1·ADMIN-5 |
| 모델(확장) | `test/models/order_test.rb` (+4) | | ADMIN-4 mark_refunded!·스코프 4종 |
| 모델(확장) | `test/models/user_test.rb` (+2) | | ADMIN-3 status enum |
| 공용 | `test/test_helper.rb` (+`clear_domain_tables`) | | Run B 시드 격리 전용 — 기존 스위트 미사용 |

## 2. 리뷰 7건(05_review.md §4) 처리 맵

| # | 리뷰 제안 | 처리 | 위치 |
|---|---|---|---|
| 1 | **B-1 환불 폼 E2E 회귀(최우선)** | ✅ 폼 계약 페이로드 `order: { refund_reason }` PATCH → 303 + refunded? + `order_refund` 감사 1건(B-1에서 400이던 경로). 이중 기록 422·감사 미추가도 함께 고정 | orders_controller_test 1~2번째 test |
| 2 | mark_refunded 경계(blank·이중·재요청) | ✅ blank → 422 "환불 사유는 필수입니다"(W-1 변환 경유)·감사 미기록·데이터 무오염, 이중 → 422·사유 불변, 모델 계약(ArgumentError·false) 별도 고정 | orders_controller_test + order_test |
| 3 | 정지 시나리오(세션 파기→재로그인 422→해제→성공) | ✅ toggle_suspension 정지 → sessions 0건 → 파기 쿠키 /app 차단 → 재로그인 422 "이용이 정지된 계정입니다" → 해제 → 재로그인 303, member_suspend/unsuspend 감사 | members_controller_test |
| 4 | change_plan 성공/실패 + 감사 assertion + months 경계 | ✅ 활성 Plus→체험 금지·0/13 거부+미기록·12 성공+감사·trial_ends_at 동기화·해지=cancelled(plus 유지)·재해지 거부·1회 가드·미지 action·구독 없음 — 서비스·컨트롤러 이중 고정 | member_admin_service_test + members_controller_test |
| 5 | audit_logs 필터 경계(무효 from/to)·페이지네이션 100 | ✅ from=garbage·2026-13-45 → 200 필터 생략(W-2), 101 시드 → 2페이지 1행(recent 최신순 검증) | audit_logs_controller_test |
| 6 | 대시보드 집계 경계(북극성 30일·마감 0건·실패율 분모 0) | ✅ 북극성 100.0% 렌더→Payment 소거 후 소멸("-"), 실패율 50%(sent+failed 분모)·0건 nil, 쿼리 수학은 queries/admins 5종에서 시드 델타로 고정 | dashboards + collection/message/revenue 쿼리 테스트 |
| 7 | members 필터 조합·무효 enum → 빈 목록 | ✅ q·plan·status 단독 + 3중 조합, status=hacked → 200 빈 목록 | members_controller_test |

## 3. 시나리오 커버 요약 (Rule ID별 정상/경계/예외)

- **ADMIN-3**: 정지/해제 왕복(세션 파기·U1 로그인 차단·감사 쌍), change_plan 4규칙 전건(성공 감사 1:1·실패 미기록), 체험 1회 가드, 미지 action·구독 없음 방어, status enum 기본값.
- **ADMIN-4**: B-1 폼 계약 회귀, 환불 기록 3분기(정상/blank/이중), 스코프 4종(refunded_at 기준 — failed 이력 환불 포함), 환불 제외 매출(전/후 델타), 콘솔 수동 안내는 뷰 렌더로 간접 확인.
- **ADMIN-5**: 5쿼리 전종 시드 델타 검증 + 빈 데이터 0/nil, MRR cancelled 제외, 북극성 MAX(paid_on) 부분입금 가중 방지·30일 경계, 실패율 분모 sent+failed, recipient_role 키 문자열 정규화, PLAN-2 상수 인용(9,900).
- **ADMIN-2**: 감사 단일 경유(컨트롤러 order_refund·서비스 member_*), 성공 전건/실패 미기록, 필터 3종·무효 날짜 방어·100행 페이지네이션.
- **TIME-1**: travel_to KST 고정(쿼리/모델) — 컨트롤러는 중첩 travel_to 금지 가드(Rails 7.1+ RuntimeError) 회피를 위해 상대 시간 기반으로 재구성.
- **표면 격리**: 비인증·U1 세션의 /admin 전 경로 303 차단(Run A 헬퍼 준용).

## 4. 실행 게이트

- 개별 실행(쿼리+모델+서비스 56건 → 컨트롤러 29건) 후 전체 `bin/rails test` **1회**: 783 runs · 4,534 assertions · **0 failures · 0 errors · 0 skips** — 기존 스위트 회귀 0.
- `bin/rubocop`(신규·수정 테스트 파일 31 files): **0 offenses**.
- 외부 API 실호출 0건(솔라피·포트원 stub 계승 — 대상 기능이 집계·관리이므로 stub 불요).
- test DB 잔존: 트랜잭션 롤백 + `clear_domain_tables` 경유 — 전체 스위트 통과로 상호 오염 없음 확인.

## 5. 테스트 오류 수정 이력(자체 수정 — 코드 버그 0건)

1. fixture 적재는 `after_create`(Free 구독 자동 생성)를 우회 → alpha 등 구독 행 수동 보장(`Subscription.create!` — Run A encrypts 교훈과 동일 계열).
2. `User.delete_all` FK 제약(sessions·invoices 등 non-cascade) → `test_helper#clear_domain_tables`(FK 역순 일괄 정리) 도입.
3. Rails 중첩 `travel_to` 블록 가드(RuntimeError) → 컨트롤러 테스트는 admin_login 내부 travel_to와 충돌하지 않도록 상대 시각(`Time.current + 1.day`·`Date.current`) 기반으로 재구성, 쿼리 테스트는 순차 `travel_to`+`travel_back`.
4. 어설션 오타 3건(퍼널 trialing은 설계상 전환 집계 제외 — 테스트 기대 수정, message skip 사유 키, enum `:plus` vs "plus" 비교).
5. audit_logs 필터 판정을 본문 문자열 매치에서 `assert_select td` 행 수 기준으로 교정(필터 select 옵션에도 action 문자열이 렌더됨).

**코드 버그 발견: 0건** — B-1·W-1~W-5 전부 수정 확인(회귀 테스트로 고정).
