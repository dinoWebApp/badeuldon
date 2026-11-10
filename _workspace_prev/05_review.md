# 05_review — F-ADMIN Run B 병렬 배치(T-B1~B3 + 3-S) 코드 리뷰 (2026-11-10, Phase 5 · 절약 모드)

**종판 상태: `APPROVED`** — Phase 6 재리뷰(2026-11-10) 완료: BLOCKER 1건(B-1)·WARNING 5건(W-1~W-5) 전부 해소 확인. 최초 리뷰 기록은 §1~5, 재리뷰 기록은 §6.

- 검증 방식: **A절 전 항목을 test 환경 rails runner + `ActionDispatch::Integration::Session` HTTP 요청 수준으로 실행 재현**(Run A 교훈 반영 — 서비스 계층 자기검증 종판 없음). 총 4회 세션 + 1회 진단, 관리자 실제 로그인 플로우(비밀번호→TOTP 검증→세션 발급) 경유.
- 전체 테스트(668건)·rubocop(211 files)은 오케스트레이터 확인치(0실패·0 offenses)로 재실행하지 않음.
- 재현 종료 후 임시 레코드 전량 정리 확인(users/orders/clients/audit_logs/admin 잔존 0)·임시 스크립트(/tmp) 삭제 완료·tracked 파일 무변경(리뷰는 읽기 전용).

---

## 1. 이슈 목록

### BLOCKER

**B-1 · ADMIN-4 · `app/views/admin/orders/show.html.erb:34` ↔ `app/controllers/admin/orders_controller.rb:20` — 환불 기록 폼이 컨트롤러 파라미터 계약과 불일치. UI에서 환불 기록 제출 시 100% 실패(400)**
- 재현(test env, 관리자 로그인 세션): `PATCH /admin/orders/:id/mark_refunded`에 **폼이 실제로 생성하는 페이로드**(최상위 `refund_reason`)를 전송 → `ActionController::ParameterMissing` 발생(운영 환경에서는 400 Bad Request). 주문은 환불 기록되지 않음(데이터 손상 없음 — 기능이 UI 경로에서 동작 불능).
- 원인: `form_with url: mark_refunded_admin_order_path(@order), method: :patch`에 `scope`/`model`이 없어 `form.text_area :refund_reason`이 `name="refund_reason"`(최상위)을 생성. 컨트롤러는 `params.expect(order: [:refund_reason])`로 `order[refund_reason]`를 기대.
- 교차 검증: 동일 요청을 `order: { refund_reason: "..." }` 네임스페이스로 보내면 303 + 기록 + 감사(order_refund)까지 정상 — 폼↔컨트롤러 접착만의 결함(Run A 컨트롤러 접착 BLOCKER와 동일 유형).
- 수정 권고(택1, 전자 권장 — 컨트롤러 무변경):
  1. 뷰: `form_with scope: :order, url: mark_refunded_admin_order_path(@order), method: :patch`로 변경 → 필드가 `order[refund_reason]`로 생성됨.
  2. 또는 컨트롤러: `params.expect(:refund_reason)`로 최상위 키를 읽도록 변경(뷰 그대로).
- Developer 자기검증 문서(T-B3 03)의 "컨트롤러 HTTP 검증: 라우트 미결선으로 미수행(해석 6)" 대로라면 Phase 5에서 반드시 잡혔어야 하는 결함 — Run A 교훈 재확인 사례.

### CRITICAL

(없음 — 명세 불일치·집계 오류·감사 누락 모두 재현 결과 미발견. 상세는 §3 통과 커버리지)

### WARNING

**W-1 · ADMIN-4 · `app/controllers/admin/orders_controller.rb:19-27` — blank 사유 요청 시 `ArgumentError` 미변환 → 500**
- 재현: `order: { refund_reason: "" }` PATCH → `Order#mark_refunded!`가 `ArgumentError` raise → test env에서 예외 전파(운영에서 500). 데이터는 오염되지 않음(미기록 확인).
- 정상 폼 경로에는 `required: true` 클라이언트 가드가 있어 도달 불가하나, T-B3 문서의 "실패 422 render(show)" 명세와 어긋나는 방어 결여.
- 권고: 컨트롤러에서 `rescue ArgumentError` → 422 render(show) + flash. 또는 `mark_refunded!`가 blank 때 ArgumentError 대신 `false`를 반환해 이중 거부와 동일한 422 경로로 통일(모델 계약 변경 시 Run C에서 상속되는 호출부는 컨트롤러 1곳뿐 — 영향 범위 확인 후).

**W-2 · ADMIN-2 · `app/models/audit_log.rb` by_period — 무효 날짜 파라미터 → 500**
- 재현: `GET /admin/audit_logs?from=garbage` → `Time.zone.parse`가 nil 반환 → `nil.beginning_of_day` NoMethodError. `from=2026-13-45` → ArgumentError. 둘 다 test env 예외 전파(운영 500).
- 권고: `Time.zone.parse(from) rescue nil` 후 nil이면 해당 필터 생략(또는 flash 안내 + 전체 목록). 감사 로그 뷰는 읽기 전용이므로 데이터 위험 없음 — 가용성 방어만.

**W-3 · ADMIN-3/4 · members index·orders index N+1**
- 정적 확인: `app/controllers/admin/members_controller.rb:36-42` `left_joins(:subscription)` 후 뷰(`index.html.erb:40`)에서 행마다 `user.subscription` — left_joins는 preload가 아니므로 최대 100행 = 100질의. `app/views/admin/orders/index.html.erb:29` `subscription.user.email`, `:73` `order.user.email` — 행마다 질의(limit 20/100).
- 운영 영향은 관리자 전용·행 수 상한으로 경미하지만 규약 성능 관점 권고: `filtered_users`에 `includes(:subscription)`, orders index에 `includes(:user)` / `@expiring_trials`에 `includes(:user)`.

**W-4 · ADMIN-2 · `app/views/admin/audit_logs/index.html.erb:18` — 뷰에서 DB 쿼리(컨벤션 위반)**
- `Admin.order(:email).pluck(:email, :id)`가 뷰 템플릿에서 직접 실행됨 — AGENTS.md "뷰에서 DB 쿼리/모델 클래스 메서드 호출 금지" 위반(관리자 목록 select 옵션용).
- 권고: `Admin::AuditLogsController#index`에서 `@admins = Admin.order(:email).pluck(:email, :id)`로 로드해 @변수로 전달(컨트롤러 액션 10줄 이내 유지 가능).

**W-5 · ADMIN-3 · `app/services/admins/member_admin_service.rb:27` — extend_trial months 0·음수 허용**
- 재현: `plan_change: { action: "extend_trial", months: "0" }` → "이용 기간을 0개월 연장했습니다" 303 + `member_plan_change` 감사 기록(실질 무변경 행위의 감사 오염). 음수는 period_end를 과거로 이동 가능(관리자 신뢰 전제라 위험 낮음).
- 권고: 서비스 진입에서 `months = months.clamp(1, 12)` 또는 `months < 1`이면 failure("연장 개월은 1~12개월") 반환. 뷰 number_field의 min:1은 클라이언트 전용.

---

## 2. PRD v0.31 Rule ID 1:1 대조 (§6~7)

| 규칙(PRD v0.31 확정문) | 구현 위치 | 재현 결과 |
|---|---|---|
| ADMIN-3 ① users.status enum — 정지 시 로그인 차단+기존 세션 전부 파기, 해제 가능 | `20261110000003_add_status_to_users.rb`·`user.rb:23`·`member_admin_service.rb:36-52`·`sessions_controller.rb:18-21` | PASS — 정지 PATCH→suspended+세션 0건, 기존 쿠키로 /app 접근 302 차단(세션 파기로 resume 실패), 재로그인 422 전용 문구("이용이 정지된 계정입니다"), 해제 후 재로그인 303 성공. 자격 증명 확인 후에만 정지 문구 노출(계정 열거 방지 유지) |
| ADMIN-3 ② 활성(Plus) 구독 보유 시 체험 전환 금지 | `member_admin_service.rb:59` | PASS — 활성 Plus에 grant_trial 303+거부 문구, 구독 active plus 유지 |
| ADMIN-3 ② 체험 연장 = current_period_end 연장 | `member_admin_service.rb:69-79` | PASS — base(period_end·trial_ends·now 최대)+3개월, trialing이면 trial_ends_at 동기화 실측(2027-02-13) |
| ADMIN-3 ② 구독 해지 = cancel!(기간 말까지 유효 — PLAN-5) | `member_admin_service.rb:81-89` | PASS — cancelled 전환, plan은 plus 유지(기간 말 자동 만료 설계와 정합), 재해지 거부 |
| ADMIN-3 ② 전건 감사 기록(ADMIN-2) | `member_admin_service.rb:45-47,95-97` | PASS — 성공 4건(체험 전환·연장 3개월·연장 0개월·해지) 전건 `member_plan_change`, 정지·해제 `member_suspend`/`member_unsuspend` 1쌍. 실패 4건(활성→체험·재체험·재해지·미지 action) 미기록 — "변경"만 기록하는 설계로 적정 |
| ADMIN-3 ② 체험 1회 가드 | `member_admin_service.rb:60,65-67` + `Subscription#start_trial!` | PASS — 재체험 요청 "무료 체험은 계정당 1회입니다" 거부(TrialAlreadyUsedError rescue 포함 이중 가드) |
| ADMIN-3 ③ staff도 플랜 수동 변경 가능(롤 부여·해제만 owner — AUTH-7.2) | `members_controller.rb` change_plan — 롤 게이트 없음(=staff 가능) | PASS(정합). **확인 요청**: 롤 부여·해제 콘솔은 01_plan Run B 범위 밖(ADMIN-1 runner 절차 유지) — Run C 범위 표기가 PRD에도 필요한지 오케스트레이터 확인 권장 |
| ADMIN-3 ④ 계정 삭제·데이터 파기는 Run C | 미구현(문서 표기) | PASS — 정지까지만 구현(범위 준수) |
| ADMIN-4 환불 기록 = orders.refunded_at·refund_reason, PG 콘솔 수동 명시(PLAN-5) | `20261110000002`·`order.rb:25-36`·컨트롤러/뷰 확인 문구 | PASS(로직) — refunded_at 존재 기준 판정, status는 paid 이력 보존, 콘솔 수동 안내 문구 뷰+모델+컨트롤러 3중 명시. 단 UI 경로 파탄은 B-1 |
| ADMIN-4 환불 기록 시 감사 로그 필수 | `orders_controller.rb:21-22` | PASS — 성공 시 `order_refund` 감사 기록 재현(target Order·detail 사유) |
| ADMIN-4 쿠폰·프로모션 Run C 이관 | PRD §275 표기 | PASS — 구현 미포함·문서 이관 일치 |
| ADMIN-4 결제 실패 건 관리 | `orders/index.html.erb` failed 필터 + dunning 미구현 명시 | PASS — 실패 필터 동작, "재시도(dunning)는 미구현" 주석 명시(범위 한정 문서화) |
| ADMIN-5 ① MRR = active Plus × 9,900(cancelled 제외 — PLAN-2 상수 인용) | `revenue_stats_query.rb:14` | PASS — 독립 SQL과 일치 렌더(active plus 1명 → 9,900₩), `Subscription::PLUS_MONTHLY_PRICE` 상수 인용 |
| ADMIN-5 ② 매출 집계는 환불 기록 주문 제외(refunded_at 기준 — 3-S 통합) | `revenue_stats_query.rb:10` `Order.paid.not_refunded` | PASS — 환불 전 19,800₩ → mark_refunded 후 재렌더 9,900₩ 실측(제외 반영 확정) |
| ADMIN-5 ③ 북극성 = 발행 후 30일 내 수금 완료율 | `collection_stats_query.rb:22-34` | PASS — 시드(30일 내 2건/초과 0건)에서 100.0% 렌더, 마감 0건 → "-"(nil) 설계, 부분입금 가중 방지(MAX(paid_on) 서브쿼리 — v0.28 DASH-5 패턴) |
| ADMIN-5 ④ MessageLog 로컬 집계(발송량·실패율·skip 사유) | `message_stats_query.rb` | PASS — sent/failed/skipped·실패율 분모 sent+failed·skip 사유 분포·recipient_role 키 정규화(정수/문자열 양쪽) 렌더 확인 |
| ADMIN-5 ⑤ 솔라피 크레딧 API [INFERENCE] 기술 부채 | `message_stats_query.rb:4`·`dashboards/show.html.erb:128` | PASS — 쿼리 주석+뷰 하단 안내 문구 이중 명시 |
| TIME-1 집계·기록 KST 고정 | `config/application.rb:25`(Seoul) + Date.current/Time.current | PASS — 당월 마감(paid_on ≥ 월초)·paid_at 월 매출·환불 기록 시각 전부 KST 기준 재현 |
| §4.2 감사 기록 경로(모델→서비스 호출 금지) | grep 확인: order/user/audit_log 모델에 서비스 호출 없음 | PASS — orders는 컨트롤러 경유, members는 서비스→RecordService(Service→Service 허용) — T-B2가 02 확정 해석 4의 문구("컨트롤러가 경유")와 다른 방식을 채택했으나 Run A W-4의 실질 금지(모델→서비스)는 위반하지 않으며 산출물 문서에 결정 사유 명시됨. 수용 |
| 라우트 계약(02 확정 해석 1) | `config/routes.rb:73-83` | PASS — `audit_logs only:index`·`members only:%i[index show]+member patch 2`·`orders only:%i[index show]+member patch 1` 계약 그대로. 상태 전이 member PATCH 정당화 주석 존재 |
| 마이그레이션 2건 독립·null/default 명시·schema 동기 | `db/schema.rb`(orders.refunded_at/refund_reason·users.status), `db:migrate:status` 3건 up | PASS |

---

## 3. 통과 커버리지 (A절 HTTP 재현 — 요청 수준)

| # | 검증 | 결과 |
|---|---|---|
| 1 | 비인증 `/admin`·`/members`·`/orders`·`/audit_logs` → 303 → /admin/session/new | PASS(4경로) |
| 2 | **U1 세션으로 /admin/members → 303 /admin/session/new**(상호 격리 — Run A 유지) | PASS |
| 3 | 관리자 실제 로그인 플로우(1단계 303→totp_setup→코드→totp_verify 303→/admin·AdminSession 발급) | PASS |
| 4 | 관리자 로그인 상태 대시보드 200 — 6 섹션 렌더, 응답 5ms/sql 27(타임아웃 없음), 수치 전부 독립 SQL 일치(당월 수금 금액·MRR·당월 매출) | PASS |
| 5 | 북극성 시나리오: 30일 내 마감 2건 → 100.0% 렌더 | PASS |
| 6 | members index 200·검색(q=이메일 → 해당 회원만)·plan=plus 필터·status=active/suspended 필터 | PASS |
| 7 | members 무효 enum 필터(status=hacked) → 200 빈 목록(500 없음) | PASS |
| 8 | members show 200 — 프로필·청구/미수·플랜 변경 폼·발송 10건·문의 5건·감사 10건 섹션 | PASS |
| 9 | change_plan 4규칙 + 재체험 가드 + 재해지 거부 + 미지 action 거부 | PASS(전건) |
| 10 | toggle_suspension 정지→세션 전부 파기→기존 세션 /app 차단→재로그인 422→해제→재로그인 303 | PASS |
| 11 | orders index 200·플랜 분포 카드 4종·체험 만료 예정(7일 window 실측)·주문 목록 | PASS |
| 12 | orders 필터 status=paid·refund=refunded/not_refunded(화이트리스트), 비화이트리스트(status=DROP TABLE·refund=ZZZ) 무시 → 전체 | PASS |
| 13 | orders show 200 상세(pg_order_id·금액·상태) | PASS |
| 14 | mark_refunded(order 네임스페이스) 303+기록+감사+flash / 이중 거부 422 render show | PASS |
| 15 | audit_logs index 200·총건수 == SQL·action_filter 총건수 == SQL·admin_id·기간(당일)·페이지네이션 | PASS |
| 16 | RevenueStats 환불 제외 — 환불 전/후 당월 매출 렌더 변화 | PASS |
| 17 | 정지 계정 로그인 차단 회귀 테스트(`sessions_controller_test.rb` 신규 1건) 존재·성공(오케스트레이터 확인치) | PASS |

비고: 뷰 통화는 ko 로케일(`%n%u` — "9,900₩")으로 렌더된다. 금액이 단위 앞이 아닌 뒤에 붙는 것은 rails-i18n ko 표준 포맷으로 결함이 아님(재현 중 어설션 아티팩트였음을 확인).

---

## 4. Tester 중점 테스트 제안 (Phase 7)

1. **B-1 회귀(최우선)**: 시스템 테스트로 관리자 로그인 → 주문 상세 → 환불 사유 입력 → 제출 → 303·`order_refund` 감사·`Order.not_refunded` 집계 제외까지 E2E. B-1 수정 커밋에 필수.
2. mark_refunded 경계: blank 사유(W-1 수정 후 422)·이중 기록 422· refunded 건 재요청.
3. 정지 시나리오 시스템 테스트: 정지 → 기존 세션 만료(로그인 리다이렉트) → 재로그인 422 문구 → 해제 → 재로그인 성공.
4. change_plan 각 action의 성공/실패 + `AuditLog` assertion(성공 전건·실패 미기록) — months 경계(W-5 수정 시 0·13 거부 포함).
5. audit_logs 필터 경계: 무효 from/to(W-2 수정 후 500 아님)·기간 조합·페이지네이션 100건 경계.
6. 대시보드 집계 경계: 북극성 issued_at+30일 경계값(30일 23:59 vs 31일 00:00)·마감 0건 "-"·실패율 분모 0(nil).
7. members 필터 조합(검색+플랜+상태 동시)·무효 enum 값 → 빈 목록.

---

## 5. 결론

- **BLOCKER 1건(B-1)** — Run A와 동일한 "fan-out 컨트롤러 접착 미검증" 유형. 3-S가 라우트를 결선한 지금, UI 폼 경로의 최소 재현(runner + Integration::Session PATCH)이 원인 특정에 결정적이었다. B-1 수정은 1줄(scope: :order)로 종결 가능.
- 서비스·쿼리·모델 계층(T-B1 집계 5종·T-B2 서비스·T-B3 모델)과 라우트·마이그레이션·감사 체계는 **명세 1:1 정합 + 요청 수준 재현 통과** — 로직 자체의 재작업은 불필요.
- B-1 수정 후 재리뷰 범위: `app/views/admin/orders/show.html.erb`(또는 orders_controller) 1파일 + 환불 폼 경로 재현 1회면 충분.

~~**status: CHANGES_REQUESTED**~~ → **status: APPROVED**(§6 Phase 6 재리뷰 — 하단)

---

## 6. Phase 6 재리뷰 (2026-11-10 — 축소 범위: B-1 환불 폼 경로 재현 + W-1~W-5 코드 확인·회귀 스폿)

**검증 방식**: test 환경 rails runner + `ActionDispatch::Integration::Session` — 최초 리뷰와 동일하게 관리자 실제 로그인 플로우(비밀번호→TOTP→세션 발급) 경유로 HTTP 요청 수준 재현. 총 2회 세션(B-1·회귀 스폿 + W-5 보완), 종료 후 임시 레코드 잔존 0 확인·/tmp 스크립트 삭제.

### 6.1 해소 확인 표

| 이슈 | 수정 위치(코드 확인) | 재검증 결과 |
|---|---|---|
| **B-1** | `views/admin/orders/show.html.erb:34` — `form_with scope: :order` (1줄·컨트롤러 무변경) | **PASS** — 주문 상세 렌더에 `name="order[refund_reason]"` 필드 생성 확인, **폼 그대의 페이로드 PATCH → 303 + refunded? + order_refund 감사 + 성공 flash**(최초 리뷰에서 400이던 경로 소멸), 이중 기록 422 유지 |
| **W-1** | `admin/orders_controller.rb` mark_refunded에 `rescue ArgumentError → 422 render show + flash` | **PASS** — blank 사유 PATCH → 422 + "환불 사유는 필수입니다" 문구·미기록(500 소거), 정상·이중 경로 회귀 없음 |
| **W-2** | `models/audit_log.rb` — `by_period`을 클래스 메서드로 전환, `safe_boundary`(파싱 실패·nil → nil, rescue ArgumentError, private_class_method) | **PASS** — `from=garbage`·`from=2026-13-45` 모두 200(필터 생략), 유효 날짜 필터 정상 |
| **W-3** | `members_controller.rb` index `includes(:subscription)` / `orders_controller.rb` index `includes(:user)`·`@expiring_trials.includes(:user)` | **PASS** — members GET에서 subscriptions 관련 질의 1회(preload)·orders GET에서 users 질의 0회(14 users·13 orders 기준), 목록 렌더 정상 |
| **W-4** | `audit_logs_controller.rb` `@admins = Admin.order(:email).pluck(...)` / 뷰에서 `@admins` 사용 | **PASS** — 뷰의 `Admin.` 직접 쿼리 제거 확인, 관리자 select 옵션이 `@admins`로 렌더(`<option value="{id}">` 확인) |
| **W-5** | `member_admin_service.rb` extend_trial! 선두 `(1..12).cover?(months)` → Result failure | **PASS** — months=0·13 → 303 + "연장 개월은 1~12개월 사이로 입력해 주세요." + period 불변, months=12 → 성공 + trialing trial_ends_at 동기화(base+12개월), 감사 delta=1(거부 2건 미기록) |

### 6.2 회귀 스폿 검사

- **by_period → safe_boundary 전환**: `by_period`의 유일 호출처는 `Admin::AuditLogsController#filtered_audit_logs`(grep 확인 — members#show는 `recent`만 사용). 무효 날짜 2종 200 확인 — 스코프→클래스 메서드 전환의 체인 인터페이스 변경 없음(인자 순서 동일).
- **@admins 전달 경로**: 컨트롤러 로드 → 뷰 `options_for_select([["전체",""]] + @admins, params[:admin_id])` — 필터 기능(params[:admin_id]) 재확인 200.
- **includes 전환**: members의 `left_joins`(검색용) + `includes(:subscription)` 병용 시에도 목록·필터(q·plan·status) 정상 렌더 확인.
- 재현 중 내 스크립트 어설션 1건이 nil base 참조로 예외를 냈으나(제품 코드 아님), base를 명시 설정한 보완 세션에서 W-5 전항목 재확인 완료.

### 6.3 Run C 이관 목록(리뷰어 확인 요청 답변 — 수용)

03_implementation.md Phase 6 절에 정리됨: ① ADMIN-3 롤 부여·해제 콘솔(AUTH-7.2 — Run B 미포함·ADMIN-1 runner 절차 운영) ② ADMIN-4 쿠폰·프로모션 ③ ADMIN-3 ④ 계정 삭제·데이터 파기(AUTH-1.5 재검토 포함). PRD 문서와 정합 — 수용.

### 6.4 재리뷰 결론

- BLOCKER 0 · CRITICAL 0 · WARNING 미해소 0 — B-1은 제안된 최소 수정(scope: :order 1줄)로 종결, W-1~W-5는 전부 명시 권고 방향과 일치하게 구현됨.
- 개발자 자기 재검증 보고(Integration 세션·관리자 실로그인 동일 방식)와 리뷰어 독립 재현이 일치.

**status: APPROVED**
