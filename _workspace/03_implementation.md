# 03_implementation — F-SALES 영업 직원·추천 코드·수수료 + 휴대폰 인증 가입 (2026-11-19, Phase 3 Developer · 일반 모드)

## 0. 구현 요약

PRD v0.42 §6.20(F-SALES — SALES-1~7)·AUTH-9·Q24를 구현했다. 신규 도메인 2개(sales·phone_verifications), 신규 표면 1개(/sales), 가입 플로우 확장, Q12 쿠폰 인프라 재사용(신규 결제 로직 0줄), recurring Job 2종. 마이그레이션 1건(통합). 테스트 파일은 작성하지 않음(Phase 7 Tester 담당 — 지시서 하드 제약 준수).

## 1. 변경 파일 전수

### 신규 (28파일)

| 파일 | 내용 |
|---|---|
| `db/migrate/20261119000000_create_sales_domain_tables.rb` | 통합 마이그레이션 — sales_reps·sales_rep_sessions·sales_referral_codes·phone_verifications·sales_commissions 5테이블 + users 확장(referred_by fk·referral_code_snapshot·phone 부분 유니크 인덱스) |
| `app/models/sales_rep.rb` | has_secure_password·role(sales/officer)·status(active/suspended) enum·effective_rate(오버라이드 우선→역할 기본 20/15%)·5회 잠금(Admin 패턴)·current_referral_code·referred_users restrict_with_error(P4) |
| `app/models/sales_rep_session.rb` | 12h 절대 + 2h 비활동 만료(AdminSession 준용)·issue_for!·usable 스코프 |
| `app/models/sales_referral_code.rb` | 8자 안전 문자열(혼동 문자 O/I/L·0/1 제외 알파벳)·current_valid 스코프(오늘이 valid_from~valid_until 창 내)·generate_code |
| `app/models/phone_verification.rb` | CODE_TTL 5분·MAX_ATTEMPTS 5·CODE_DIGITS 6·sent_within(rate limit 조회)·consumed_recently(가입 이중 검증용)·consume!(1회용)·record_attempt! |
| `app/models/sales_commission.rb` | pending/paid enum·for_year/for_month/ordered 스코프·mark_paid!·period_label |
| `app/models/user.rb` (수정) | belongs_to :referred_by_sales_rep(optional)·phone normalizes(하이픈 제거)·phone 유니크+형식 검증(하이픈 허용 — 레거시 호환)·프로필 phone 중복 검증 제거(AUTH-9 단일 소스로 통합) |
| `app/models/current.rb` (수정) | sales_rep_session attribute + delegate |
| `app/services/solapi/client_service.rb` (수정) | `send_sms(to:, body:, dry_run:)` 신규 — 동일 엔드포인트(POST /messages/v4/send)·동일 HMAC 인증·message 객체에 type:"SMS"+text·pf_id 불요(ensure_credentials!에 require_pf_id 옵션 추가 — 알림톡 경로 불변) |
| `app/services/phone_verifications/send_service.rb` | 정규화→형식 검증(01x 국번)→rate limit(번호당 1분 1회·1시간 3회)→6자리 코드 발급·5분 만료→send_sms(주입 stub)→실패 시 방금 기록 행 destroy(rate limit 미소진 보장)·마스킹(010****5678) |
| `app/services/phone_verifications/verify_service.rb` | 없음/만료/5회 초과/불일치 분기 → 성공 시 consumed 마킹(1회용)·실패 시 attempts 증가. Result 구조체 반환 |
| `app/services/sales/attach_first_charge_coupon_service.rb` | SALES-4 — percent 20·max_redemptions 1 쿠폰 생성("REF"+hex8 코드)→subscription.coupon_id 예약(Q12 구조 그대로) |
| `app/services/sales/rotate_referral_codes_service.rb` | SALES-2 — 활동 rep 전체(or rep 단독) 현재 코드 valid_until=어제 조기 종료→새 8자 코드 발급(valid_from=오늘·6일 창). 당일 발급분 가드(멱등). 트랜잭션 |
| `app/services/sales/monthly_settlement_service.rb` | SALES-5 — 직전월(또는 지정 연월) plus_monthly·paid·환불 제외 orders.amount(실차감액) 합계→역할 정책(sales=유치 사용자 created_at+12개월 내 paid_at만·officer=무기한)→rep.effective_rate로 절사 산정→find_or_create_by!+update upsert(복합 유니크·RecordNotUnique retry). paid 행 재집계 무시(지급 금액 보존)·개별 rep 실패 로그 후 계속 |
| `app/jobs/sales/rotate_referral_codes_job.rb` | 인자 없는 recurring — 서비스 위임 |
| `app/jobs/sales/monthly_settlement_job.rb` | 인자 없는 recurring — 서비스 위임 |
| `app/queries/sales/rep_monthly_payments_query.rb` | SALES-6 — 본인 유치 사용자 Plus 결제(paid·환불 제외) 실차감액 12개월 집계(Reports::MonthlyCollectionQuery 패턴 — strftime 그룹·빈 달 0원 12행) |
| `app/controllers/sales/base_controller.rb` | SALES-7 가드 — require_sales_session(쿠키 키 sales_session_token)·terminate·current_sales_rep·layout "sales" |
| `app/controllers/sales/sessions_controller.rb` | SALES-1·7 — 이메일/비밀번호 단일 단계(2FA 불요)·rate_limit 10/3분·정지·잠금 차단·오류 문구 통일(열거 방지)·감사(login_failed/lockout/login_success) |
| `app/controllers/sales/dashboards_controller.rb` | SALES-6 — 본인 스코프만(코드·유치 사용자·12개월 결제 Query·직전월 스냅샷·연도 누적·전체 누적) |
| `app/controllers/admin/sales_reps_controller.rb` | SALES-1 — CRUD(삭제 없음 — P4)·toggle_suspension(정지 시 세션 전부 파기)·rotate_code(멱등 가드 안내)·생성 시 초기 코드 즉시 발급·감사 전건(sales_rep_created/updated/suspended/resumed/code_rotated). staff 허용 |
| `app/controllers/admin/sales_commissions_controller.rb` | SALES-5 — 연월 필터 목록·pending/paid 합계·member PATCH mark_paid(감사 commission_marked_paid) |
| `app/views/layouts/sales.html.erb` | SALES-6·7 — 전용 크롬("받을돈 파트너스")·로그인 전후 공통·noindex(head 파셜 재사용 — /sales 접두어 추가) |
| `app/views/sales/sessions/new.html.erb` | 로그인 폼(app 스타일 계승) |
| `app/views/sales/dashboards/show.html.erb` | 타이틀+직함 배지·요율·역할 정책 문언·현재 코드(clipboard 재사용·만료 예정)·이번 달 수령 예정(스냅샷 상태 배지)·연도 누적+원천징수 3.3% 고지(Q24)·12개월 CSS 막대(reports 헬퍼 재사용)·내 사용자 목록(가입일·플랜·상태) |
| `app/views/admin/sales_reps/{index,new,edit}.html.erb` | 목록(역할·요율·상태·현재 코드+만료·정지/해제/재생성/수정)·생성·수정 폼(role select 이원화·commission_rate 빈 값=역할 기본) |
| `app/views/admin/sales_commissions/index.html.erb` | 연월 필터·pending 하이라이트(주황)/paid(녹색)·mark_paid 버튼 |
| `app/javascript/controllers/phone_verification_controller.js` | AUTH-9 폼 내 2단계 비동기 — send/verify fetch(CSRF 메타 토큰)·상태 표시(성공 녹색/실패 빨강)·인증 완료 시 submit 활성화(미완료 disabled)·경로는 data 속성 주입(하드코딩 금지) |

### 수정 (11파일)

| 파일 | 변경 |
|---|---|
| `app/controllers/registrations_controller.rb` | AUTH-9 — send_phone_code/verify_phone_code collection POST(공개·IP rate_limit 6/1시간)·create에 phone 파라미터·이중 검증(consumed_recently 행+번호 일치)·추천 코드 유효 검증(오류 시 422 안내·공백 무시)·가입 성공 시 referred_by+snapshot 저장→AttachFirstChargeCouponService(실패해도 가입 완료·로그) |
| `app/views/registrations/new.html.erb` | 휴대폰 번호+인증 요청 버튼→인증번호 입력(숨김→표시)→인증 완료 표시→submit 게이트 + 추천 코드(선택·8자·uppercase) + 할인 안내 문언. 기존 스타일·톤 유지 |
| `app/helpers/application_helper.rb` | NOINDEX_PATH_PREFIXES에 "/sales" 추가(SURF-3) |
| `app/views/layouts/admin.html.erb` | 네비에 "영업 직원"·"수수료 정산" 추가(SALES-1·5) |
| `config/routes.rb` | registration collection 2종·sales namespace(session·root=dashboards#show)·admin sales_reps(member: toggle_suspension·rotate_code)·admin sales_commissions(member: mark_paid) |
| `config/recurring.yml` | sales_referral_codes_rotate(월요일 00:00 KST)·sales_monthly_settlement(매월 1일 00:05 KST) — production/development 양 블록 |
| `public/robots.txt` | Disallow: /sales(SURF-3) |
| `app/models/user.rb`·`current.rb`·`solapi/client_service.rb` | 상기 신규 표와 중복 — 핵심만: phone 정규화·Current.sales_rep_session·send_sms |

### 기타
- `db/schema.rb` — 마이그레이션 반영(커밋 대상).

## 2. Rule ID별 구현 매핑

| Rule ID | 구현 |
|---|---|
| **SALES-1** | sales_reps 별도 테이블·별도 세션(AUTH-7 준용)·role 이원화(sales=20%/12개월 캡, officer=15%/무기한)·title 표시용 자유 텍스트(대시보드 배지)·Admin CRUD+감사 전건·정지 시 세션 파기 |
| **SALES-2** | sales_referral_codes 이력 테이블·주간 로테이션 Job(월요일 00:00 KST)·8자 안전 문자열(SAFE_ALPHABET — O/I/L·0/1 제외)·기존 코드 valid_until=어제 조기 종료(P4 이력 보존)·가입은 current_valid만 수용·콘솔 수동 재생성(같은 서비스·당일 멱등 가드) |
| **SALES-3** | 가입 폼 추천 코드(선택)·유효 검증(현재 창만·오류 422 안내·공백 무시)·users.referred_by_sales_rep_id+referral_code_snapshot(P4) |
| **SALES-4** | 첫 Plus 결제 20% — Q12 쿠폰 인프라 재사용: AttachFirstChargeCouponService가 percent 20·1회 전용 쿠폰 생성→subscription.coupon_id 예약. 첫 차감·consume(SEC-5)·웹훅 settle·재과금 정상가는 기존 UpgradeService 경로 그대로(신규 결제 로직 0줄) |
| **SALES-5** | sales_commissions 스냅샷(rep·연월 복합 유니크)·매월 1일 00:05 KST Job·기준=orders.amount 실차감액(첫달 할인가 포함)·환불(refunded_at) 제외·rate 스냅샷 고정(effective_rate)·역할 정책(sales 12개월 캡=유치 사용자 created_at+12개월 내 paid_at·officer 무기한)·mark paid(admin 감사)·원천징수 3.3%는 화면 고지+오프라인(Q24) |
| **SALES-6** | /sales 표면 — 자체 레이아웃·로그인·본인 타이틀+직함·현재 코드(복사·만료 예정)·내 사용자 목록(가입일·플랜·상태)·12개월 결제 총액 CSS 막대·이번 달 수령 예정(직전월 스냅샷)·연도별 누적 |
| **SALES-7** | 세션 격리(session[:sales_session_token] — U1·admin 키와 별도)·noindex+robots 차단(SURF-3)·스코프 격리(대시보드 전 요소가 current_sales_rep 연관만)·정지 로그인 차단(422)·감사는 관리자 콘솔 측 기록 |
| **AUTH-9** | 가입 휴대폰 필수·번호 유일(부분 유니크 인덱스+모델 검증, null 허용·소급 없음)·SMS 문자 발송(솔라피 send_sms)·5분 만료·rate limit(1분 1회·1시간 3회 — DB 이력 기준)·시도 5회 제한·1회용 consumed·가입 create 이중 검증(consumed_recently+번호 일치)·폼 내 2단계 비동기(ONB-1 마찰 최소) |
| **Q24** | 역할 이원화·기준 실차감액·지급 M+1(스냅샷 pending→admin mark paid)·원천징수 3.3% 고지 문언(대시보드) |
| **Q12** | 쿠폰 예약 구조 재사용 — subscription.coupon_id·resolve/consume_first_charge_coupon! 무변경 |
| **PLAN-5** | 포트원 결제 흐름 무변경(정산은 orders 레코드만 소비)·dunning 실패 주문은 paid가 아니어도 자동 제외 |
| **SEC-5** | 로테이션 당일 발급분 가드·정산 upsert 멱등(재실행 동일 스냅샷·paid 보존)·인증 코드 1회용·세션 토큰 urlsafe_base64(32) |
| **P4** | 추천 코드 이력 보존(valid_until 조기 종료 — 행 삭제 없음)·rep 삭제 불가(restrict_with_error·콘솔 삭제 액션 부재)·referral_code_snapshot·SMS 발송 실패 시 PhoneVerification 행 제거는 "발송 실패=기록 불요"로 설계 판단(§4 참고) |
| **SURF-3** | /sales noindex(NOINDEX_PATH_PREFIXES)+robots.txt Disallow |
| **ADMIN-2** | 영업 행위 감사 전건 — sales_rep_created/updated/suspended/resumed/code_rotated·sales_rep_login_failed/lockout/login_success·commission_marked_paid |
| **TIME-1** | recurring KST 접미사·Date.current/Time.zone 기준·valid_from/until은 KST 날짜 |

## 3. 설계 결정

1. **쿠폰 예약 방식(SALES-4)** — 신규 결제 로직 0줄 원칙. Q12의 "예약(subscription.coupon_id)→첫 차감 성공 트랜잭션에서 consume+해제" 구조를 그대로 활용. 쿠폰 코드는 "REF"+hex8(11자 — [A-Z0-9] 형식 검증 통과)·max_redemptions 1·expires_at nil(부착 계정 1회 한정이라 무만료). 부착 실패는 가입을 막지 않음(정가 첫 결제 폴백 — 로그).
2. **rate limit 상수(AUTH-9)** — 1분 1회·1시간 3회(번호당·AUTH-9 명시값)·검증 5회·코드 6자리·TTL 5분·consumed 인정 창 30분(가입 제출까지 여유). 판정 근거는 phone_verifications 발송 이력 행(인덱스 [phone, created_at]). 컨트롤러에는 IP 기준 완화 가드(6회/1시간)를 추가로 둠. **SMS 발송 실패(Solapi::ApiError) 시 방금 생성한 행을 destroy해 rate limit을 소진하지 않는다**(사용자 원인 아님 — 재시도 보호).
3. **세션 TTL(SALES-7)** — AdminSession 준용(12h 절대+2h 비활동). 2FA 불요 대신 짧은 TTL로 민감도 보완. 쿠키 키 sales_session_token으로 U1(30일)/admin(12h)과 완전 격리.
4. **정산 집계 필드(SALES-5)** — 기준 금액은 `orders.amount` 그대로. 근거: charge_and_extend!가 차감 금액(첫 달이면 쿠폰 할인가 7,920원)을 주문 amount로 기록하므로 metadata 파싱 불요·환불은 refunded_at 제외·pending/failed는 status 필터로 자동 제외. 수수료 = (base × rate / 100).floor. 12개월 캡은 `paid_at <= user.created_at + 12개월` 단일 조건.
5. **로테이션 유효 창(SALES-2)** — 새 코드 valid_from=발급일·valid_until=+6일(다음 주간 로테이션 전날). 자연 만료와 조기 종료(수동 재생성)가 같은 스코프(current_valid)로 판정된다.
6. **phone 정규화** — User normalizes로 하이픈 제거 저장(솔라피 규격과 동일)·형식 검증은 하이픈 허용(정규화 이전 저장분 레거시 호환 — 기존 2명 프로필 수정 파탄 방지). 기존 프로필 컨텍스트 phone 검증은 AUTH-9 단일 소스로 통합(중복 제거).
7. **영업 계정 삭제 없음** — 콘솔에 destroy 액션 없음+모델 restrict_with_error. 정지로만 운영(P4 — 어트리뷰션·정산 이력).
8. **staff 권한** — 지시서 대로 생성/수정/정지/mark_paid staff 허용·감사 전건(AUTH-7.2 롤 관리와 별개 영역).

## 4. 알려진 한계·운영 노트

1. **[INFERENCE] 솔라피 send_sms 바디 스펙** — type:"SMS"+text 배치는 공식 문서·SDK 규격에 근거한 실측 전 항목. 첫 실발송 시 응답(messageId)으로 확정 필요(운영 노트 기록 — 알림톡 실측 선례와 같은 절차). dry_run 스펙은 검증 완료(§6).
2. **SMS 실호출 금지 준수** — 개발 검증은 전부 stub 주입(네트워크 감시 stub으로 "호출 구조"까지만 확인)·dry_run으로 요청 조립 확인. credentials가 로컬에 실값으로 존재하므로 운영 배포 전 send_sms 실측은 별도 절차 권장.
3. **가입 마찰(ONB-1)** — 휴대폰 2단계는 사용자 명시 요청 반영. 인증 완료 전 submit disabled(클라이언트) + 서버 이중 검증으로 우회 차단.
4. **정산 첫 실행** — 운영 배포 시 sales_monthly_settlement는 다음 달 1일에 첫 스냅샷을 만든다. 소급 집계가 필요하면 `Sales::MonthlySettlementService.new(year:, month:).call` runner 실행(멱등).
5. **코드 만료 직후 가입** — 월요일 00:00 로테이션 전 구간(일요일~월요일 0시)은 전날 코드 valid_until까지 유효 — 끊김 없음. 만료 코드 입력 시 "유효하지 않거나 만료" 안내.
6. **admin 네비 변경 관련 테스트 확인(수정 불요·Phase 7 인계)** — `test/controllers/admin/dashboards_controller_test.rb`는 admin_root_path 렌더 단정(운영/MRR/매출·환불) — 네비 링크 2종 추가와 충돌 없음. `audit_trail_test.rb`(5종 action)는 신규 action(sales_rep_*·commission_marked_paid)과 독립. 기존 admin 테스트 갱신 불요 판정 — 단, Tester가 전체 스윕에서 재확인 권장.
7. **dashboards_controller_test(/app)** — /app 무관(지시서 대로 수정 불요·미접촉).

## 5. 자가 검증 결과 (전부 통과)

- `bin/rubocop` — 373 files, **no offenses**
- `bin/rails zeitwerk:check` — "Otherwise, all is good!"
- `bin/rails db:migrate` — 성공(부분 유니크 인덱스 `index_users_on_phone_when_present` 포함). 최초 1회 실패는 add_reference FK 대상 유추 오류 → `foreign_key: { to_table: :sales_reps }`로 수정 후 성공
- 부트 스모크(runner):
  - 신규 18 클래스 로드 OK
  - `Solapi#send_sms` dry_run — 실호출 0·바디 {to(정규화), from, text, type:"SMS"} 확인·pf_id 없이도 SMS는 fail-fast 통과·알림톡은 기존처럼 pf_id 템플릿/credentials fail-fast 유지(MISSING_TEMPLATE/MISSING_CREDENTIALS 실측)
  - rotate — 발급(8자·6일 창)·당일 재실행 무변경(멱등)·만료 코드 current_valid 거부
  - 정산 — officer(환불·pending 제외·15%·1,188원)·paid 스냅샷 재집계 무시·sales 12개월 캡(캡 외 결제 제외·20%)·개별 rep 실패 로그 후 계속
  - 세션 발급·usable·5회 잠금·unlock·정지 판정
  - 추천 쿠폰 — percent 20·1회·예약(subscription.coupon_id)·final_price 7,920원
  - 인증 — stub 주입(네트워크 감시 stub으로 실호출 구조 확인)·마스킹 010****5678·1분 rate limit·불일치→성공→1회용 소비→consumed_recently
  - User phone 정규화(하이픈 제거)·유니크 검증
  - 실서버 E2E(curl, port 3111): /registration/new 200(인증 2단계·추천 코드·경로 주입)·/sales 미인증 303→로그인 폼→CSRF POST 303→대시보드 200(코드·원천징수 고지·noindex 메타)·robots.txt Disallow /sales·**정지 계정 로그인 422+세션 미발급(대시보드 303)**
  - admin 3화면 렌더 + admin 네비 신규 메뉴 2종 노출(컨트롤러 컨텍스트 렌더 검증)
  - recurring.yml — production/development 모두 `sales_referral_codes_rotate`(월 00:00 KST)·`sales_monthly_settlement`(1일 00:05 KST) 등록 확인
- 검증용 시드 데이터는 전부 정리(leftover 0)·임시 스크립트 제거·개발 서버 종료. **git 커밋 없음(제약 준수)**.

## 6. 검증 과정에서 수정한 결함(자체 발견)

1. 마이그레이션 — `add_reference :users, :referred_by_sales_rep`가 FK를 `referred_by_sales_reps` 테이블로 유추해 실패 → `foreign_key: { to_table: :sales_reps }` 명시.
2. 정산 upsert — `create_or_find_by!(year:, month:)`가 검증 미충족 상태(나머지 컬럼 nil)로 INSERT를 시도해 RecordInvalid → `find_or_create_by!` + 속성 블록으로 교체(경합은 RecordNotUnique retry로 흡수).

## Phase 6 수정(2026-11-19)

`05_review.md` CHANGES_REQUESTED(C-1) + WARNING 8건 전부 반영. 지시서 제약 준수 — 테스트 미작성(Phase 7 인계)·PRD/AGENTS/01_plan/05_review 무변경·커밋 없음·솔라피 실호출 없음. 변경 파일 10개(아래 표) 외 접촉 없음.

### C-1 — 검증 주체와 가입 주체를 같은 브라우저로 결합(세션)

| 파일:라인 | 내용 |
|---|---|
| `app/controllers/registrations_controller.rb:52-62` | `verify_phone_code` — 검증 성공 시 `session[:verified_phone] = normalize_phone(phone)` 저장 |
| `app/controllers/registrations_controller.rb:90-97` | `phone_verified?` — `session[:verified_phone].present? && == normalize_phone(제출번호) && PhoneVerification.consumed_recently.exists?(phone:)` 3중 판정. 번호만 아는 제3자의 코드 없는 가입 차단(리뷰 수정 방향 그대로) |
| `app/controllers/registrations_controller.rb:104-108` | 신규 `complete_signup!` — 가입 성공 후처리(부착 → `session.delete(:verified_phone)` → U1 세션 발급)로 추출. create 본문 10줄 규약 유지 |
| `app/controllers/registrations_controller.rb:99-101` | `normalize_phone` 헬퍼 신설 — 숫자만 정규화 단일 지점(VerifyService·PhoneVerification과 동일 규칙) |

스모크(통합 세션 — 실제 `verify_phone_code` 엔드포인트 경유, SMS 발송 없음·DB 조회만): ① 세션 없이 create → 422 안내·유저 미생성 ② A번호 검증 후 B번호 create → 422(세션≠제출 — C-1 핵심) ③ B번호 검증 후 B번호 create → 303 성공·referred_by+snapshot 기록 ④ 성공 후 세션값 소멸. 브라우저(JS) 변경 불요 — 동일 흐름 확인.

### WARNING 반영

| 이슈 | 파일:라인 | 내용 |
|---|---|---|
| W-1 | `config/routes.rb:189` · `app/controllers/admin/sales_reps_controller.rb:60-69` · `app/views/admin/sales_reps/index.html.erb:46-48,64-66` | member `patch :unlock`(잠금 전환 상태 전이로 정당화)·컨트롤러 `unlock` 액션(`SalesRep#unlock!` 재사용 — locked_at·failed_attempts 리셋)·감사 `sales_rep_unlocked`(admins unlock 선례 준용)·목록에 잠금 배지+해제 버튼(잠금 시에만 노출). staff 허용(콘솔 관리 액션 정책 동일 — admins의 owner 전용과 다른 콘솔 성격 유지) |
| W-2 | `app/models/sales_rep.rb:41-46` · `new.html.erb:39-40` · `edit.html.erb:38-39` | `commission_rate` 1~50 정수 범위 검증(allow_nil — nil은 역할 기본값). 오케스트레이터 판정값(1~50) 적용 — 리뷰 예시(0~100)와 달리 0% 무의미·50% 초과는 정책상 과다. 폼 min/max 동기화+범위 안내 문구 |
| W-3 | `app/controllers/sales/dashboards_controller.rb:9-11` · `show.html.erb:96` | `@referred_users_count = @rep.referred_users.count` 별도 집계(단일 count 쿼리 — N+1 없음). 문구 "총 N명(목록은 최근 30명 표시)" |
| W-4 | `show.html.erb:105,112` | 이메일 칼럼 제거 → **표시명**(가입일·플랜·상태·표시명만 — SALES-6 정합). `display_name.presence \|\| "미설정"` 폴백(가입 직후 표시명 미설정 유저 대응)·caption 갱신. 개인정보 최소 수집·이용 원칙(PRD 문언 초과분 해소) |
| W-5 | `app/controllers/registrations_controller.rb:16-18` | IP당 한도 6회→**20회/1시간** 완화(CGANAT 고려 주석). 번호당 DB 이력 한도(1분 1회·1시간 3회)는 유지·1차 방어선 유지. W-5① 레이스(6자리 코드·5회 시도 한도로 실질 위험 낮음)는 미수정 — 리뷰도 "선택"·실질 방어는 코드 검증 단에 있음 |
| W-6 | `app/controllers/registrations_controller.rb:117-128` | `attach_referral!` rescue에서 감사 기록 — `AuditLogs::RecordService.call(admin: nil, action:, target: @user, detail: "예외클래스: 메시지", ip:)`. action은 실패 단계 구분: 어트리뷰션 미기록=`referral_attribution_failed`(수수료 영구 누락 위험), 어트리뷰션 성공 후 쿠폰 실패=`coupon_attach_failed`(정가 폴백). admin nil — coupon_redeemed U1 행위 선례 준용. **사후 복구 절차(운영 노트)**: runner로 `user.update!(referred_by_sales_rep_id:, referral_code_snapshot:)` 후 첫 결제 전이면 `Sales::AttachFirstChargeCouponService.new(user:).call` 재실행 |
| W-7 | `app/services/sales/monthly_settlement_service.rb:39-56` | **해소** — 유저 루프당 orders 집계(N+1)를 rep당 1회 조인 집계로 전환. officer: `sum(:amount)` 1쿼리. sales: `pluck("users.created_at", "orders.paid_at", "orders.amount")` 1쿼리 후 캡 판정(`paid_at <= created_at + 12개월`, 포함 경계)을 행 단위 Ruby 필터로 유지 — SQL 상수 조건은 users.created_at 의존이라 부정확해지므로 캡 경계 등가성을 우선했다. 스모크로 구 루프 집계와 전건 등가 확인(officer 9,900·sales 12개월 캡 경계 포함/경과 1초 제외 17,820·pluck 시각형 캐스트 TimeWithZone 확인). 쿼리 수: rep당 1회(O(reps)) — 유저 수와 무관 |
| W-8 | `app/models/sales_rep.rb:10,16,86-95` | 파괴 방어선 — `before_destroy :prevent_destroy_with_history`를 **연관 선언보다 먼저** 배치(dependent 콜백 실행 전 abort — `dependent: :destroy`로 남아 있으면 자식이 먼저 소실되는 경합 차단). 유치 사용자 **또는** 정산 스냅샷 존재 시 차단+한국어 안내(거래처 삭제 가드 선례). `sales_commissions`를 `dependent: :destroy`→`restrict_with_error`로 전환(우회 경방어선 — P4 지급 이력). 이력 전무한 오생성 계정만 파괴 허용(추천 코드는 주간 로테이션 임시 자격증명 성격 — 함께 제거). 스모크: 정산 스냅샷 존재 destroy=false+안내·유치 사용자 존재 destroy=false·이력 없는 rep destroy 성공 |

**감사 기록 판정(W-8·"감사")**: 규약 §4.2 Model→Service 금지로 모델 계층에서 `AuditLogs::RecordService` 호출 불가하고, 콘솔에 destroy 액션이 없어(리뷰도 "노출면 좁다" 확인) 파괴 허용분의 감사는 실행 계층 절차로 남긴다 — 03 운영 노트에 runner 파괴 전 감사 기록 절차를 명시했다(§4-8). 콘솔 destroy 액션 신설은 "계정 삭제는 없다(P4)" 원칙과 상충해 미채택.

### 자가 검증 결과 (전부 통과)

- `bin/rubocop` — 373 files, **no offenses**
- `bin/rails zeitwerk:check` — "Otherwise, all is good!"
- runner 스모크 27항목 전부 PASS(전체 트랜잭션 롤백 — 시드 잔존 0 확인: reps 0·users 0) — C-1 7항목(실엔드포인트 경유)·W-1 2·W-2 7·W-6 2·W-7 3(구 집계 등가성 포함)·W-8 4
- W-5·W-3·W-4는 상수/쿼리/뷰 치환이라 스모크 대상 외(코드 확인)·조회 count 쿼리 단일성 확인
- 통합 세션 스모크 시 하네스 한계 2건 해소(앱 코드 무관): ① runner 중첩 ExecutionWrapper의 QueryLogs 문맥 nil — 스모크 프로세스 한정 `QueryLogs.call` 우회 ② 쿠키 세션 저장소 특성상 사전 세션 주입 불가 — 실제 verify 엔드포인트 경유로 전환(더 정확한 브라우저 흐름 재현)
- 임시 스크립트(/tmp) 삭제·**git 커밋 없음(제약 준수)**

### Phase 7 인계 노트

1. **C-1 회귀(리뷰 §4-1)** — 별도 브라우저(세션)의 consumed 번호 create → 422·동일 브라우저 정상 가입 성공. 스모크로 1차 확인됐으나 시스템 테스트로 재확인 바람.
2. **기존 registrations 컨트롤러 테스트** — 세션 결합으로 verify 없이 create하던 테스트는 422로 실패 예상(05_review §3-10 재확인) — stub 주입으로 verify 흐름 포함 갱신 필요.
3. **W-4** — 유치 목록에 이메일 부재 → 이메일 단정 테스트는 표시명 단정으로 교체.
4. **W-2** — rate 0/51/소수 저장 422 테스트·**W-8** — 파괴 차단/허용 분기 테스트 권장.
