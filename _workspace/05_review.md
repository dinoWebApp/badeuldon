# 05_review — F-SALES 영업 직원·추천 코드·수수료 + 휴대폰 인증 가입 (2026-11-19, Phase 5 Reviewer · 일반 모드)

status: CHANGES_REQUESTED

- BLOCKER 0 · CRITICAL 1 · WARNING 8
- 리뷰 범위: `git status --short` 전수(신규 28 + 수정 11 + 통합 마이그레이션 1 + schema.rb)·PRD v0.42 §6.20 SALES-1~7·AUTH-9·Q24·Q12·PLAN-5·SEC-5·P4·SURF-1/3/4 문언 대조
- BLOCKER 없음 — 데이터 정합성 훼손·런타임 에러·/sales 무단 접근 경로는 확인되지 않았다. CRITICAL 1건 수정 후 재리뷰 대상.

---

## 1. 이슈 목록

### CRITICAL

#### C-1. AUTH-9 이중 검증이 "번호"에만 결합 — 검증 통과 주체와 가입 주체가 다를 수 있음
- **위치**: `app/controllers/registrations_controller.rb:84-87`(`phone_verified?`)·`:48-56`(`verify_phone_code`)
- **근거**: PRD AUTH-9 "**검증 통과 시에만 가입 진행**·인증 코드는 **1회용**(consumed)". 현재 `create`의 이중 검증은 `PhoneVerification.consumed_recently.exists?(phone: 제출번호)` — 판정 근거가 번호뿐이고 세션(브라우저)과 무결결합돼 있지 않다.
- **시나리오**: 피해자가 자신의 번호로 인증을 통과(consumed 행 생성, 30분 창) → 공격자가 그 번호를 알고 있으면 **코드 없이** 같은 30분 창 내에 `create`를 제출(공격자 이메일 + 피해자 번호)해 "인증된" 계정을 만들 수 있다. 결과: ① 피해자 번호가 부분 유니크 인덱스로 선점돼 본인 가입이 차단(지원 비용) ② 코드를 받지 않은 주체가 번호 소유를 위장한 계정 확보(AUTH-9의 남용 방지 목적 — SALES-3 연계 — 일부 무력화).
- **현실적 완화 요인**(솔직 평가): 피해자 번호 + "인증 진행 중" 타이밍을 아는 표적 공격이어야 하며, 30분 창으로 좁혀져 있다. 그러나 결함 자체는 명확하고 수정이 저렴하다.
- **수정 방향**: `verify_phone_code` 성공 시 서버 세션에 `session[:verified_phone] = phone` 저장 → `create`의 `phone_verified?`를 `session[:verified_phone] == 정규화(제출번호) && consumed_recently.exists?(phone:)`로 판정(가입 성공 후 세션값 파기). 검증을 수행한 브라우저만 가입할 수 있게 결합된다. JS는 변겨 없이 동작(동일 브라우저 흐름).

### WARNING

#### W-1. 잠긴 영업 계정의 콘솔 unlock 경로 부재 — 비밀번호 변경으로도 잠금이 풀리지 않음
- **위치**: `app/controllers/sales/sessions_controller.rb:18`(`rep.locked?` 차단)·`app/controllers/admin/sales_reps_controller.rb`(unlock 액션 부재)
- **내용**: 5회 실패 잠금(AUTH-7.3 준용) 계정은 `reset_failed_attempts!`가 로그인 성공 시에만 호출되므로 자력 복구 불가. Admin 콘솔에는 `edit`(비밀번호 변경)이 있으나 `locked_at`을 초기화하지 않아 **비밀번호를 바꿔도 여전히 로그인 거부**(문구는 "이메일 또는 비밀번호가 올바르지 않습니다"라 운영자 오해 유발). admins 선례(`Admins::RoleService.unlock!` + `require_owner` member 액션, AGENTS runner 절차)와 달리 복구 수단이 전무하다.
- **수정 방향**: admin 콘솔에 `unlock` member 액션 추가(admins 패턴 — 감사 `sales_rep_unlocked`)하거나, 최소한 AGENTS에 `bin/rails runner 'rep.unlock!'` 운영 절차 문서화. 잠금 상태를 목록에 표시하면 운영성 향상.

#### W-2. `SalesRep#commission_rate` 무검증 — 서버 측 범위(0~100 정수) 보장 없음
- **위치**: `app/models/sales_rep.rb:16`(enum들)·`:36-38`(`effective_rate`)
- **내용**: 폼은 `min:0 max:100 step:1`이나 조작 요청으로 999·음수·소수가 저장될 수 있다. `effective_rate`가 100 초과면 `SalesCommission`의 `rate 0..100` 검증에서 `find_or_create_by!`가 RecordInvalid → `call`의 rescue가 로그만 남기고 해당 rep 정산이 **조용히 누락**된다.
- **수정 방향**: `validates :commission_rate, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true` 추가.

#### W-3. 대시보드 "내 사용자 N명"이 `limit(30).size` 표시 — 실제 총원 아님
- **위치**: `app/controllers/sales/dashboards_controller.rb:8`·`app/views/sales/dashboards/show.html.erb:96`
- **내용**: 31명 이상 유치 시 "30명(최근 순)"으로 과소 표시 — 실적 표면의 수치 부정확(SALES-6).
- **수정 방향**: `@referred_users_count = @rep.referred_users.count` 별도 집계 후 표기(목록은 최근 30명 유지·"최근 30명 표시" 문언).

#### W-4. 유치 사용자 이메일 노출 — PRD SALES-6 명세(가입일·플랜·상태)를 초과 (확인 요청)
- **위치**: `app/views/sales/dashboards/show.html.erb:102-112`
- **내용**: PRD SALES-6 "내 사용자 목록(**가입일·플랜·상태**)" — 구현이 이메일 칼럼을 추가했다. 유치자가 개인적으로 아는 지인이라는 운영 전제라면 식별 편의가 있으나, 유치 사용자는 자신의 이메일이 영업 직원에게 제공됨에 동의한 적이 없다(개인정보 최소 수집·이용 원칙).
- **수정 방향**: 이메일 칼럼 제거(가입일·플랜·상태만)하거나, 노출이 필요하면 PRD SALES-6 문언 갱신 + 개인정보 처리 절차(제3자 제공 고지) 확인 후 유지. 오케스트레이터 판정 항목으로 남긴다.

#### W-5. SMS 발송 rate limit 경합 우회 + IP 결합 한도의 CGNAT 영향 (확인 요청)
- **위치**: `app/services/phone_verifications/send_service.rb:44-47`(조회 후 INSERT)·`app/controllers/registrations_controller.rb:14-15`(IP 6회/1시간, send+verify 합산)
- **내용**: ① 두 동시 요청이 `rate_limited?` 조회를 통과한 뒤 각자 INSERT하면 "1분 1회"가 우회된다(레코드 삽입 경쟁 — 예상 리스크 5번 지적). 6자리 코드·5회 시도 제한이 있어 실질 위험은 낮다. ② 국내 이동통신은 CGNAT로 다수 사용자가 IP를 공유한다 — 인증 요청 다수가 같은 IP로 몰리면 정상 가입이 6회/1시간에 걸릴 수 있다.
- **수정 방향**: ① 부분 유니크 인덱스 `(phone, created_at)` 유니크화는 과하고, `rate_limited?` 통과 후 `create!`에서 `RecordNotUnique` 무시 재시도 수준이면 충분(선택). ② 한도 상향(예: 20/1시간) 또는 send/verify 분리 판단 — 운영 데이터 없이 단정 불가하므로 확인 요청.

#### W-6. 추천 어트리뷰션·쿠폰 부착 실패가 Rails 로그에만 기록 — 감시·재시도 경로 없음
- **위치**: `app/controllers/registrations_controller.rb:91-97`(`attach_referral!` rescue)
- **내용**: `referred_by` 설정 실패 시 어트리뷰션이 소리 없이 소실되면 해당 사용자의 수수료가 영구 누락된다(SALES-5 원천). 가입은 완료돼 재시도 창구가 없다. 발생 확률은 매우 낮으나(검증 없는 컬럼 update) P4·ADMIN-2 정신상 콘솔에서 보이는 기록이 바람직하다.
- **수정 방향**: rescue에서 `AuditLogs::RecordService.call(action: "referral_attach_failed", target: @user, ...)` 기록(admin nil — coupon_redeemed 선례). 사후 복구는 admin 콘솔 또는 runner로 가능함을 03 문서 운영 노트에 명시.

#### W-7. 정산 집계 N+1 — rep별 유저 루프당 집계 쿼리 1회
- **위치**: `app/services/sales/monthly_settlement_service.rb:39-43`(`sum_base_amount`)
- **내용**: `rep.referred_users.sum do … end`이 유저마다 `orders.sum(:amount)`을 실행한다. 월 1회 잡이라 실영향은 작으나 유치자 수백 명 규모에서 쿼리 수백 회.
- **수정 방향**: 단일 그룹 집계로 전환 권장 — `Order.joins(:user).where(users: { referred_by_sales_rep_id: rep.id }, paid_at: month_range).paid.plus_monthly.not_refunded`에 12개월 캡은 `users.created_at` 조인 조건(`orders.paid_at <= (users.created_at, '+12 months')` 또는 Ruby side 필터)으로. 대안으로 현행 유지도 허용(월 1회·트래픽 무관) — 비차단.

#### W-8. rep 파괴 방어선이 부분적 — referred_users 없는 rep은 이력 연쇄 삭제 가능
- **위치**: `app/models/sales_rep.rb:8-14`
- **내용**: `sales_referral_codes`/`sales_commissions`가 `dependent: :destroy`라, 유치 사용자가 없는 rep을 콘솔 등에서 파괴하면 코드 이력·정산 이력이 함께 사라진다(P4 위반 소지). `referred_users`의 restrict는 유치자가 있는 경우에만 발화한다. 콘솔에 destroy 액션은 없으므로 노출면은 좁다.
- **수정 방향**: 두 연관도 `dependent: :restrict_with_error`로 전환하거나 `before_destroy`에서 항상 차단(삭제 금지 원칙의 완전한 방어선).

---

## 2. Rule ID 준수 매핑 (판정)

| Rule ID | 판정 | 근거 |
|---|---|---|
| SALES-1 | 통과 | 별도 테이블·별도 세션(`sales_rep_sessions`)·role 이원화(sales 20%/officer 15% — `ROLE_DEFAULT_RATES`·`effective_rate` 단일 판정점)·title 표시용·Admin CRUD+감사 전건·삭제 없음(정지 운영). 단 W-1(unlock 부재)·W-2(rate 무검증)·W-8(파괴 방어선) 보강 권장 |
| SALES-2 | 통과 | 주간 로테이션 recurring(월 00:00 KST — production/development 양 블록)·8자 안전 문자열(O/I/L 제외 — 31^8 공간)·기존 코드 valid_until 조기 종료로 이력 보존(P4)·가입은 `current_valid`(오늘 포함 양끝)만 수용·당일 발급분 멱등 가드(SEC-5). 일요일→월요일 0시 끊김 없음(전날 valid_until=일요일·신규 from=월요일) 확인 |
| SALES-3 | 통과 | 가입 폼 선택 입력·공백 무시·오류 시 422 안내(조용한 무시 아님)·`referred_by_sales_rep_id`+`referral_code_snapshot`(P4) 기록. 코드 무차별 대입: 전용 검증 엔드포인트 없음 — 코드 유효성 탐침은 create 필요(이메일·비밀번호·휴대폰 인증 전제 + IP 10회/3분) — 31^8 대비 실무적으로 비탐색 가능. 별도 이슈 없음 |
| SALES-4 | 통과 | **Q12 경로 0줄 수정 재사용 확인** — `subscription.coupon_id` 예약 → `resolve_first_charge_coupon!`(재검증·정가 폴밑 금지) → 첫차감 성공 트랜잭션에서 `consume!`(원자·SEC-5)·예약 해제 → 이후 재과금 정상가. 쿠폰 생성값 percent 20·max 1·active·무만료·"REF"+hex8(11자 — Coupon 형식 통과)·final_price 7,920원. 웹훅 settle 경로(C-2 선례)도 예약 쿠폰 소비 정합 |
| SALES-5 | 통과 | 매월 1일 00:05 KST Job·직전월 plus_monthly·paid·`not_refunded` **실차감액**(orders.amount)·역할 정책(sales `paid_at <= created_at+12개월` 포함 경계 / officer 무필터)·`effective_rate` 스냅샷·복합 유니크 upsert(재실행 동일·paid 보존 가드)·RecordNotUnique retry·mark paid 감사. W-7(N+1) 비차단 |
| SALES-6 | 통과(조건부) | 자체 레이아웃("받을돈 파트너스")·본인 스코프 전 요소(referred_users·RepMonthlyPaymentsQuery rep_id 조인·SalesCommission rep 연관)·직전월 스냅샷·연도/전체 누적·원천징수 3.3% 고지·12개월 CSS 막대(reports 헬퍼 재사용 — include_all_helpers로 해석됨·렌더 실측 03 §5). W-3(총원 표기)·W-4(이메일 노출) 보완 |
| SALES-7 | 통과 | 세션 키 `session[:sales_session_token]` — U1은 `cookies.signed[:session_id]`(별도 쿠키), admin은 `session[:admin_session_token]`과 키·토큰 테이블 모두 분리(교차 사용 불가 확인). U1 로그아웃(`terminate_session`)이 쿠키 삭제 방식이라 /sales 세션 무관 확인. 정지 시 세션 전량 파기 + 로그인 차단(422 통일 문구 — 열거 방지). noindex+robots(§3 참조) |
| AUTH-9 | **C-1** | SMS(솔라피 `send_sms` — 동일 엔드포인트·HMAC·pf_id 불요 검증 분기)·5분 만료·시도 5회·1회용 consumed·rate limit 1분 1회·1시간 3회(DB 이력·발송 실패 시 행 제거로 미소진)·phone 부분 유니크 인덱스+모델 이중 검증·코드 네트워크 응답 비노출(마스킹만)·폼 2단계 비동기(submit 게이트+서버 재판정). 이중 검증의 주체 결합 결함만 C-1 |
| Q24 | 통과 | 역할 이원화·실차감액 기준·지급 M+1(스냅샷 pending→admin mark paid)·원천징수 3.3% 화면 고지+오프라인. 해석 노트: 정지 rep도 정산 대상에 포함(PRD 무침 — 지급은 mark_paid 수동 게이트로 통제되므로 수용 가능하나 운영 인지 권장) |
| Q12 | 통과 | `resolve/consume_first_charge_coupon!`·`coupon_metadata`·웹훅 settle 무변경 — diff 미포함 확인 |
| PLAN-5 | 통과 | 결제 흐름 무변경·dunning 실패 주문은 status paid가 아니어서 자동 제외 |
| SEC-5 | 통과 | 로테이션 당일 가드·정산 upsert 멱등·인증 코드 1회용(`consume!` 가드)·쿠폰 used_count 원자 증가(기존)·세션 토큰 urlsafe_base64(32) |
| P4 | 통과(권장 보강) | 코드 이력 조기 종료식 보존·스냅샷·감사 8종 action(`sales_rep_created/updated/suspended/resumed/code_rotated`·`login_failed/lockout/login_success`·`commission_marked_paid`)·발송 실패 행 destroy는 "발송 안 된 요청"이라 판단 타당(03 §3-2). W-6(부착 실패 감사)·W-8 보강 권장 |
| SURF-1/3 | 통과 | 표면 ⑤ /sales namespace 분리·`NOINDEX_PATH_PREFIXES "/sales"`(head 파셜 noindex? 재사용)·robots.txt Disallow /sales·뷰어→랜딩 간섭 없음 |
| TIME-1 | 통과 | recurring KST 접미사(`0 0 * * 1 Asia/Seoul`·`5 0 1 * * Asia/Seoul`)·`Date.current`/`Time.zone.local` 기준·valid_from/until KST 날짜 |
| ADMIN-2 | 통과 | 콘솔 행위 감사 전건·세션 감사 3종·AuditLog action 자유 확장 설계(모델 무검증) — target polymorphic(target_type/target_id) 정상 기록 |

### 아키텍처·컨벤션 판정

- 계층·의존 방향: Model→Service/Current 호출 없음·Service가 params/Current 직접 접근 없음·뷰 DB 쿼리 없음(@변수+헬퍼만)·Job은 Service만 호출 — 준수.
- 컨트롤러 얇게: 전 액션 10줄 내외 준수(registrations#create 12줄 — 흐름상 허용 범위, 비지적).
- `params.expect` 전 액션 적용·폼 성공 303 see_other·실패 422 재렌더·JSON 엔드포인트 422/429 — 준수.
- Query Object(app/queries/sales)·도메인 네임스페이스(app/services/{phone_verifications,sales}) — 규약 §3.2·도메인 분할 준수. Registrations(인증 도메인)→Sales::AttachFirstChargeCouponService(판매 도메인 공개 진입점) 호출은 §4.3 허용 형태.
- 마이그레이션: null/default/인덱스 명시·부분 유니크 인덱스 `index_users_on_phone_when_present`·복합 유니크 `index_sales_commissions_on_rep_year_month` — 준수·schema.rb 반영 확인.
- Stimulus: CSRF 메타 토큰·경로 data 속성 주입(하드코딩 없음)·상태 색 DESIGN-2 — 준수.

---

## 3. 통과 근거 (집중 검증 항목)

1. **가입 인증 우회 점검** — ① consumed 여부와 무관하게 `create`는 consumed_recently(30분)+번호 일치로만 판정 → 만료 후 재사용/타 번호 스와핑은 차단. ② `send_code`·`verify` 응답에 코드 미포함(마스킹 번호·ok만). ③ submit disabled는 클라이언트 게이트일 뿐 서버 이중 검증이 최종 권위 — 우회 불가 구조 확인. ④ 단 세션 결합 결함 → C-1.
2. **추천 코드 무차별 대입** — 전용 유효 검증 엔드포인트 없음. 탐침 경로는 가입 create뿐(휴대폰 인증 전제·IP 10회/3분) — 31^8(≈8.5×10^11) 코드 공간 대비 비실용적. 별도 차단 불요 판정.
3. **12개월 캡 경계** — `orders.where(paid_at: ..user.created_at + 12.months)` 포함 경계("12개월 내"의 합리적 해석). 스냅샷 rate는 집계 시점 `effective_rate` 고정·역할 전환 소급은 수동 재집계(연월 지정 runner) 시 pending만 갱신·paid 보존 — Q24 "스냅샷 고정" 문언 정합.
4. **정산 upsert** — 기존 pending은 재집계 값으로 갱신(환불 반영 회복 경로)·paid는 `return if commission.paid?`로 불변(지급 확정 보존)·경합 RecordNotUnique retry 흡수. 기준 금액 orders.amount(첫달 할인가 7,920원 포함) — 실차감액 문언 정합.
5. **쿠폰 부착 실패** — 가입 완료 우선·정가 폴백·로그(03 §3-1 설계 판단) 확인. 단 감시 기록 부재 → W-6.
6. **/sales 세션 고립** — 쿠키 키 3원 분리(U1 서명 쿠키 / admin·sales 세션 스토어 키 분리)·토큰 테이블 분리·토큰 유추 불가(urlsafe_base64 32)·CSRF 폼/`button_to`(member PATCH 전부) 적용·정지 시 `sales_rep_sessions.destroy_all` 즉시 파기 확인. 잔여 이슈 없음(정지-로그인 경합 시 12h 잔존 이론상 가능하나 U1·admin 선례와 동일 설계 — 비지적).
7. **대시보드 겸제** — 컨트롤러 전체 @변수가 `current_sales_rep` 연관·Query는 `users.referred_by_sales_rep_id = rep.id` 조인 — 타 rep 경로 성립하지 않음.
8. **SMS 발송 남발** — 비인증 경로이나 번호당 1분 1회·1시간 3회(DB)+IP 6/1시간·발송 실패 시 rate 미소진 처리 확인. 잔여: 레이스(W-5①)·CGNAT(W-5②).
9. **마이그레이션·스키마** — 5테이블+users 확장 통합 1건·`foreign_key: { to_table: :sales_reps }` 명시·schema.rb 버전 2026_11_19 반영·부분 유니크 인덱스 확인.
10. **기존 기능 회귀 위험** — registrations 기존 컨트롤러 테스트는 phone 인증 전제로 **실패 예상**(개발 단계 테스트 미작성은 지시서 제약 — Phase 7 갱신 필수). admin 네비 추가는 기존 admin 테스트와 무충돌(03 §4-6 판정 타당).

---

## 4. Tester 중점 지시 (Phase 7)

아래 12항 + 기존 회귀 스윕. 특히 **1·9번은 C-1 수정 회귀 포함**이므로 수정 커밋 후 실행할 것.

1. **AUTH-9 결합 회귀(수정 반영 후)** — 검증 통과 브라우저 A의 consumed 번호로 브라우저 B(별도 세션)가 create → 422 차단 확인. 정상 동일 브라우저 가입은 성공.
2. **AUTH-9 상태 전이** — 코드 만료(5분 경과)·5회 불일치 초과·정확 코드 재사용(이미 consumed)·만료 후 신규 발급→이전 코드 거부·attempts 증가 추적.
3. **rate limit** — 동일 번호 1분 내 2회 요청 차단·1시간 3회 상한·IP 6회/1시간(429 JSON)·send 실패 시(stub ApiError) 재요청 즉시 허용(행 제거 검증).
4. **phone 유일** — 가입된 번호 재가입 422·phone null 다수 기존 유저 호환(레거시 프로필 저장)·하이픈 입력 정규화 저장.
5. **가입 E2E(추천 코드)** — 유효/만료/공백/소문자 코드 각 분기·성공 시 referred_by+snapshot 기록·쿠폰 예약(percent 20·max 1)·첫차감 7,920원·orders.amount=7920·2회차 정상가 9,900원·쿠폰 used_count 1에서 증가 없음(Q12 E2E 재사용).
6. **쿠폰 부착 실패 폴백** — AttachFirstChargeCouponService 실패 주입 시 가입 완료·정가 첫차감·(W-6 반영 시 감사 로그 기록).
7. **/sales 격리·세션** — U1·admin·sales 3중 로그인 공존 브라우저에서 상호 세션 침투 없음·U1 로그아웃 후 /sales 유지·세션 12h/2h 만료·무효 토큰 리다이렉트.
8. **잠금·정지** — 5회 실패 잠금+감사(lockout)·정지 계정 로그인 422·정지 즉시 기존 세션 파기(대시보드 접근 303)·(W-1 반영 시 unlock 회복).
9. **정산 경계** — sales 캡 경계(paid_at = created_at+12개월 ±1초 포함/제외)·officer 무기한·환불(refunded_at) 제외·upsert 재실행 동일 스냅샷·mark paid 후 재집계 시 금액 불변·rate 오버라이드 반영(W-2 반영 시 100 초과 거부).
10. **로테이션** — 주간 Job 재실행 무변경(멱등)·만료 코드 가입 422 안내·수동 재생성 후 이전 코드 즉시 무효·일요일 23:59→월요일 00:01 코드 전환 끊김 없음(valid_until 경계).
11. **noindex·robots** — /sales 전 경로 noindex 메타·robots.txt Disallow /sales·가입 폼(공개 표면)은 색인 허용 유지.
12. **대시보드 스코프·표기** — 타 rep 유치 사용자·수수료 미노출(2계정 교차 확인)·스냅샷 상태 배지·(W-3 반영 시 총원 표기)·원천징수 고지 문언.

**회귀 스윕**: 기존 `registrations`·`sessions`·profile(문맥 검증 변경)·admin 대시보드 테스트 전체 — phone 필수 전환으로 인한 기존 가입 테스트 실패분 갱신 포함. 솔라피 실호출 금지(stub 주입)·`bin/ci` 게이트 통과까지.

---

## 5. 재리뷰 범위

C-1 수정 + 권장(W-1~W-8 중 수용분) 반영 후 **변경 파일 한정 재리뷰**. W-4(이메일 노출)·W-5②(CGNAT 한도)는 제품 판정 필요 — 오케스트레이터 질의 권장.
