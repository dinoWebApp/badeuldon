# 01_plan — F-SALES 영업 직원 추천 코드·수수료 시스템 + 휴대폰 인증 가입 (2026-11-19, Full · 일반 모드 · Sequential)

## 규모 판별 — Full

신규 도메인 2개(sales_reps·phone_verifications)+정산 도메인·신규 표면(/sales)·가입 플로우 변경·결제 연결·마이그레이션 다수·신규 Job 2종 — 순차 의존 사슬(마이그레이션→가입→결제→정산→대시보드)로 §6.14 병렬 불리.

## 기획 검토 결론 (업계 표준 기준)

| 요청 항목 | 검토·표준안 | 근거 |
|---|---|---|
| 수수료 정책 — **역할 이원화(2026-11-19 사용자 확정)** | 같은 `sales_reps` 테이블에 **role enum**으로 두 정책 공존: ① `sales`(영업 직원) = **20%·12개월 캡**(가입 후 12개월 내 결제분만 집계) ② `officer`(임원·감투용 — 지인에게 CEO/CTO 등 타이틀 부여) = **15%·무기한** 지급 | 시장 조사(20~30%·12개월 캡이 지배 구조) 기반의 이원화 — 영업 역할은 표준형(B안), 지인·감투 계정은 관계 유지형 무기한(A안). per-rep 요율 오버라이드로 운영 유연성 유지 |
| 첫 결제 **20%** 할인 | **쿠폰 인프라 재사용**(Q12) — 추천 가입 시 **percent 20**·1회 전용 쿠폰 자동 생성·예약 → 기존 첫차감 경로(consume_first_charge_coupon) 그대로·다음달 정상가(첫달 7,920원) | Q12가 이미 "첫 결제 1회 할인·재과금 정상가·웹훅 settle 멱등·metadata"를 검증 완료 — 신규 결제 로직 0줄 |
| 추천코드 주기 재생성 | `sales_referral_codes`(이력 테이블)·**매주 월요일 00:00 KST recurring Job**로 활동 직원 전체 재생성(기존 코드 만료)·가입은 현재 코드만 수용 | 코드 로테이션이 남용 방지의 핵심 — 이력 보존으로 과거 어트리뷰션 감사(P4) |
| 휴대폰 인증 | 인증번호 **SMS 문자 발송**(솔라피 messages API SMS 타입 — 알림톡 템플릿 검수 불필요)·5분 만료·발송 rate limit(전화번호당 1분/3회-시간)·시도 5회 제한·`users.phone` **unique(null 허용)** | 알림톡 신규 템플릿 검수 대기 없이 즉시 구현·기존 2명 유저 중복 0 실측 → 마이그레이션 안전 |
| 영업직원 계정 | `sales_reps` + `sales_rep_sessions` **별도 테이블·별도 세션**(admins 패턴 재사석)·이메일/비밀번호(**2FA 불요** — 민감도: 본인 실적 열람만)·Admin CRUD(T-C1 콘솔 패턴) + 감사 | 관리자와 동일한 격리 원칙(AUTH-7 준용)·역할 혼재 금지 |
| 정산 스냅샷 | `sales_commissions`(rep·연월·기준 결제액·수수료율·액수·status) — **매월 1일 00:05 KST Job**이 직전월 paid plus_monthly 실차감액(환불 제외·첫달 할인가 기준=실제 매출) 집계·20% 산정 | 스냅샷 고정이어야 "이번달 수령액(=직전월 실적)" 표기가 안정·지급 처리(admin mark paid) 포함 |

## 구현 범위

### 1. 마이그레이션 (통합 1건 + 개별)
- `sales_reps`(email unique·password_digest·name·status active/suspended·**role enum sales/officer default sales**·**title string(표시용 — "CEO"·"영업 이사" 등 admin 자유 부여)**·commission_rate default 20(sales)/15(officer)는 역할 기본값+개별 오버라이드)·`sales_rep_sessions`(admins 패턴)
- `sales_referral_codes`(sales_rep_id fk·code unique·valid_from·valid_until·현재 여부 스코프)
- `phone_verifications`(phone·code·expires_at·attempts·consumed_at·sent_at — rate limit 조회용 인덱스)
- `users` 확장: `phone` **unique index(null 허용)** + `referred_by_sales_rep_id` fk + `referral_code_snapshot`
- `sales_commissions`(sales_rep_id·year·month·base_amount·rate·amount·status pending/paid·집계 실행 시각) 복합 유니크(rep·연월)

### 2. 가입 플로우 (AUTH-9)
- 가입 폼 확장: 휴대폰 번호(필수)·인증번호 요청/확인(폼 내 2단계 — 번호 입력→전송→코드 입력·검증 통과 시에만 가입 진행)·추천 코드(선택 — 유효 검증: 현재 코드만 수용·오류 안내)
- `PhoneVerifications::SendService`(SMS 발송 — 솔라피 래퍼 `send_sms` 신규·문구 상수·stub 주입)·`VerifyService`(만료·시도 초과·불일치 분기)
- 가입 시: phone 저장(유니크 위반 → 이미 가입된 번호 안내)·유효 추천 코드 → referred_by 설정 + **20% 쿠폰 자동 생성·예약**(Sales::AttachFirstChargeCouponService — Q12 예약 경로 재사용)
- 기존 유저 phone 소급 인증 요구 없음(정책: 신규 가입부터)

### 3. Admin 콘솔 (SALES-1~3)
- 직원 CRUD(목록·생성·수정·정지 — T-C1 admins 콘솔 패턴·감사 전건·**role 선택·title 입력 포함**)·추천 코드 현황 표시(현재 코드·만료 예정)·수동 재생성 버튼
- 정산 목록(연월별·지급 처리 mark paid — 감사)

### 4. 추천 코드 로테이션 (SALES-4)
- `SalesReferralCodes::RotateJob` — recurring 월요일 00:00 KST·활동 직원 전체 새 코드(8자 유니크 안전 문자열)·기존 만료·멱등
- 수동 재생성(Admin)도 동일 서비스 재사용

### 5. 수수료 정산 (SALES-5·Q24)
- `SalesCommissions::MonthlySettlementJob` — 매월 1일 00:05 KST·직전월 Plus 월결제(plus_monthly·paid·환불 제외) 실차감액을 referred_by별 집계·**역할 정책 적용(sales=해당 사용자 가입일로부터 12개월 내 결제만·20% / officer=무기한·15%)** 스냅샷 생성(upsert 멱등·rate는 스냅샷에 고정)
- 첫달 할인가(실차감액) 기준 — 실제 매출 기준이 업계 관행

### 6. 영업직원 대시보드 (SALES-6·7) — 신규 표면 /sales
- 자체 레이아웃·로그인(이메일/비밀번호)·noindex(SURF-3)·**본인 타이틀 표시(title — 감투용 계정의 직함 노출)**
- 내 사용자 목록(가입일·플랜·상태)·월별 결제 총액(내 사용자 합산·그래프)·**이번달 수령 예정(직전월 스냅샷)**·연도별 누적 수수료·내 추천 코드(현재 유효·만료 예정 — 복사 버튼)

### 7. 문서
- PRD v0.42: §6 신규 절(6.20 영업 직원·F-SALES — SALES-1~7)·AUTH-9(휴대폰 인증 가입)·PLAN 연결(쿠폰 재사용 명시)·Q24 결정 기록(수수료율 20% recurring·기준 실차감액·지급 M+1·원천징수 3.3%는 지급 시 오프라인 처리 명시)·§6.19 EXT 변화 없음(SMS는 솔라피 기존 계약)·AGENTS Rule ID 색인·표면 구조도 /sales 추가

## 대상 파일 (예상)

- 신규: 마이그레이션 2건(통합 스키마+인덱스)·`app/models/{sales_rep,sales_rep_session,sales_referral_code,phone_verification,sales_commission}.rb`·`app/services/phone_verifications/{send,verify}_service.rb`·`app/services/sales/{attach_first_charge_coupon_service,rotate_referral_codes_service,monthly_settlement_service}.rb`·`app/jobs/sales/{rotate_referral_codes_job,monthly_settlement_job}.rb`·`app/controllers/sales/*.rb`(session·dashboard)·`app/controllers/admin/sales_reps_controller.rb`·`app/views/sales/**`·`app/views/admin/sales_reps/**`·가입 뷰 확장·`config/recurring.yml` 2종·테스트 다수
- 수정: `app/models/user.rb`(전화 검증·referred_by)·`app/controllers/registrations_controller.rb`(가입 파라미터·인증 검증)·`app/views/registrations/new.html.erb`·`app/services/solapi/client_service.rb`(send_sms 신규)·`app/controllers/admin/*`(네비·정산)·`config/routes.rb`(/sales·admin/sales_reps)·사이드바 관련 없음(영업은 자체 표면)

## 게이트 확정 대상 (Q24)

1. **역할 이원화 확정**: sales=20%·12개월 캡 / officer(감투)=15%·무기한 — rep별 요율 오버라이드 유지. 타이틀(title)은 대시보드 표시용 자유 텍스트(대외 명함 등 용도 아님을 운영 인지)
   - **첫결제 할인 20% 확정**(2026-11-19 — 시장 최빈값 20% first-month 채택·다음달 정상가·Q12 인프라 설정값)
2. **정산 기준 = 실차감액**(첫달 20% 할인가 포함·환불 제외)·지급 시점 M+1·원천징수(3.3%)는 오프라인 처리(화면에 고지만)
3. 인증번호 **SMS 문자 발송**(알림톡 템플릿 불필요 — 즉시 구현)

## 리스크·모호점

1. **가입 마찰 상승** — 휴대폰 인증 2단계는 "3분 온보딩"(ONB-1)과 상충 — 사용자 명시 요청이므로 반영하되 인증 UX를 폼 내 비동기로 최소 마찰 설계
2. 기존 유저 2명 phone 중복 0 실측 — unique 인덱스 안전(운영 배포 시에도 소규모)
3. 추천 코드 만료 후 가입 시도 → 명확한 안내(코드 만료·직원에게 문의) — 코드 재발급은 월요일 자동
4. SMS 실발송 비용(∼9원/건) — 인증 요청 rate limit로 남발 방지·운영 발송은 배포 후 실측(솔라피 라이브 패턴 준용·테스트는 stub만)
5. 수수료 지급 처리(계좌 이체)는 오프라인 — 시스템은 스냅샷+mark paid까지만

## Rule ID

**SALES-1~7 신설**(직원 계정 CRUD·**role 이원화(sales/officer·타이틀)**·추천 코드 발급/로테이션·가입 어트리뷰션·첫결제 20%·월 정산(**역할별 요율·기간**)·대시보드·격리/보안) + **AUTH-9 신설**(휴대폰 인증 가입·유일성) + **Q24 신설** — 기존 Q12(쿠폰)·PLAN-5(결제)·SEC-5(멱등)·P4(기록)·SURF-3(noindex) 연결
