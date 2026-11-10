# T-B1 구현 산출물 — ADMIN-5 운영 대시보드 (2026-11-10, Run B 병렬 배치)

## 변경 파일 목록

| 파일 | 구분 | 내용 |
|---|---|---|
| `app/queries/admins/signup_stats_query.rb` | 신규 | 가입 지표(총·7일·30일) |
| `app/queries/admins/collection_stats_query.rb` | 신규 | 발행·수금 마감 통계 + 북극성 |
| `app/queries/admins/plan_funnel_query.rb` | 신규 | 가입→체험→Plus 전환 퍼널 |
| `app/queries/admins/message_stats_query.rb` | 신규 | 메시지 발송 통계(최근 30일) |
| `app/queries/admins/revenue_stats_query.rb` | 신규 | 매출·MRR |
| `app/controllers/admin/dashboards_controller.rb` | 확장(Run A 파일) | `load_metrics` private 위임 — show 본문 1줄 유지 |
| `app/views/admin/dashboards/show.html.erb` | 확장(Run A 파일) | Run A 카드 3개 유지 + 가입/청구수금/퍼널/매출MRR/메시지 섹션 추가 |

소유권 화이트리스트 준수 — routes.rb·layouts·다른 컨트롤러·models·마이그레이션·문서 미수정(git status로 확인: 내 소유 파일 외 변경 없음).

## 쿼리 정의 (집계식)

1. **SignupStatsQuery.call** → `{total, last_7d, last_30d}` — `users.created_at` 기준. "활성"은 세션·활동 컬럼 부재로 단순화(지시서대로 최근 30일 가입을 후보 지표로 반환).
2. **CollectionStatsQuery.call** → 발행 계열 = `Invoice.where.not(status: [:draft, :voided])`, 당월은 `issued_at >= 당월 1일(KST Date.current)`. 수금 마감 = `status: :paid` + 청구별 최종 입금일(`payments MAX(paid_on)` 서브쿼리 조인 — 부분입금 행 가중 방지, v0.28 DASH-5 패턴). **북극성** = `julianday(마감 paid_on) − julianday(issued_at) <= 30` 건 ÷ 전체 마감 건 ×100(round 1). **분모 0(마감 없음)이면 nil** — 뷰는 "-" 표기.
3. **PlanFunnelQuery.call** → 가입=User.count · 체험 시작=`subscriptions.used_trial: true`(PLAN-2 — 만료 후에도 플래그 유지) · Plus 전환=`plan: :plus, status: [:active, :cancelled]` distinct user(해지는 기간 말까지 Plus — PLAN-5). 주석에 "ADMIN-5·Q4 퍼널 측정용" 명시.
4. **MessageStatsQuery.call** → 최근 30일 MessageLog. sent/failed/skipped 건수, 실패율 = failed ÷ (sent+failed)(분모 0이면 nil), skip 사유 = `skipped.group(:error_code)` 건수 내림, 수신자별 발송량 = `sent.group(:recipient_role)` — **enum group 키를 정수/문자열 양쪽에서 정규화**(실측 발견: 어댑터가 문자열 키 반환). 솔라피 크레딧 API는 [INFERENCE] 기술 부채 — 뷰에도 명시.
5. **RevenueStatsQuery.call** → 당월·누적 = `Order.paid` amount 합(paid_at 기준) · **MRR = `Subscription.active.where(plan: :plus).count × Subscription::PLUS_MONTHLY_PRICE`(PLAN-2 상수 인용)**. cancelled 제외(01_plan 권고 채택). 02_prd_update 해석 2에 따라 refunded_at 제외는 3-S 통합 항목 — 쿼리 주석에 계약 명시.

## 자기 스코프·검증 결과

- **`bin/rubocop`** (쿼리 5 + 컨트롤러): 6 files, 0 offenses.
- **`bin/rails zeitwerk:check`**: "Otherwise, all is good!"
- **`bin/rails runner` 시드 검증**(dev DB, `ActiveRecord::Base.transaction` + `raise ActiveRecord::Rollback` — 사후 잔존 레코드 0 확인):
  - 5쿼리 전부 델타 기준 어설션 통과("ALL QUERIES OK") — 가입 +2, 마감 +2(30일 내 1/초과 1 → 북극성 가중 평균 일치), 금액 +150,000, 퍼널 +2/+2/+1, 메시지 sent+1/failed+1/skipped+1·skip사유 분포, MRR = (기존 active plus + 1) × 9,900.
  - 시드: users 2(sub 자동 생성 확인 후 update!), client, paid 청구 2(발행 40일 전+10일 전, 각 1건 입금), issued 청구 1, MessageLog 3종(sent/failed/skipped+error_code), Order paid+pending.
- **컨트롤러 HTTP 검증은 3-S 이전 라우트 미결선으로 생략** — 02_prd_update 확정 6(컨트롤러 검증은 Phase 5 리뷰 재현·Phase 7 테스트)에 따름. Run A의 admin root 라우트 재사용이라 라우트 추가 0건.

## 실측에서 발견·수정한 사항

- `group(:recipient_role)` count 키가 환경에 따라 정수가 아닌 enum 문자열로 반환 — 쿼리에서 키 정규화 추가(정수면 `recipient_roles.key`, 문자열이면 `to_s`).
- MessageStats의 skip 사유 분포는 **skipped 행만**의 error_code 분포(실패 행 error_code는 실패율에만 반영) — 뷰 라벨 "보류 사유"로 명확화.

## 남은 것 (3-S / 후속)

- 3-S: T-B3 refund 마이그레이션 적용 후 RevenueStatsQuery에 `where(refunded_at: nil)` 1줄 추가(계약 확정).
- 기술 부채: 솔라피 크레딧 잔액 API([INFERENCE] — 라이브 실측 후), 뷰어 단위 테스트·컨트롤러 테스트는 Phase 7 Tester 소관(기존 Run A 테스트 파일 미수정 — 회귀 없음 확인용이나 신규 작성 금지 준수).
