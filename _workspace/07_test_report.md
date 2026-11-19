# 07_test_report — F-SALES 영업 직원·추천·수수료 + 휴대폰 인증 가입 (2026-11-19, Phase 7 Tester · 일반 모드)

- **최종 게이트**: `bin/rails test` — **1,385 runs · 8,557 assertions · 0 failures · 0 errors · 0 skips** · `bin/rubocop` — **393 files, no offenses**
- **코드 버그: 0건** — 실행 과정의 전 실패(초기 5건 + 수동 발송 1건)는 전부 테스트 측 오류였고 자체 수정 후 재실행으로 해소했다. Developer 소스(app/)는 1줄도 접촉하지 않았다.
- 신규 테스트 **141건(테스트 파일 18개 + fixtures 2 + 헬퍼 2)** + 기존 갱신 5파일(테스트 신설 +2건 → **순증 143건**: 기저 1,242 → 1,385 — PRD v0.41 기록 1,241과 정합). 시스템 테스트는 미작성 — C-1 세션 결합은 통합 테스트의 `open_session`(별도 쿠키 자르기)으로 실세션 경로를 재현해 검증했다(§3-1).
- 솔라피 실호출 0건 — `FakeSolapiClient`에 `send_sms(to:, body:)` 최소 확장(기록·실패 주입)하고, 컨트롤러 경로는 `with_solapi_client` 생성자 주입으로 검증.

---

## 1. 신규 테스트 파일 (18파일 · 141건)

| 파일 | 건수 | 커버 |
|---|---|---|
| `test/models/sales_rep_test.rb` | 12 | SALES-1·Q24 effective_rate(역할 기본 20/15%·오버라이드 우선)·W-2 rate 1~50 정수 검증(0·51·100·소수·음수 거부)·AUTH-7.3 5회 잠금 경계·W-1 unlock!·W-8 파괴 가드(유치 사용자·정산 이력 차단/오생성 계정 허용/DB FK 최후 방어선) |
| `test/models/sales_referral_code_test.rb` | 8 | SALES-2 8자 안전 문자열(O·I·L·0·1 제외·31자 알파벳)·current_valid 양끝 포함·만료/미발효 경계·정규화·전역 유니크·valid_until≥valid_from |
| `test/models/phone_verification_test.rb` | 7 | AUTH-9 5분 TTL ±1초 경계·attempts 5회·consume! 1회용(SEC-5)·consumed_recently 29분/31분 창 경계·sent_within rate limit 조회·정규화 |
| `test/models/sales_commission_test.rb` | 5 | SALES-5 mark_paid! 전이+재호출 false·period_label·rate 0~100(2차 방어선)·복합 유니크(DB RecordNotUnique·타 rep 같은 연월 허용) |
| `test/models/sales_rep_session_test.rb` | 5 | SALES-7 12h 절대+2h 비활동 TTL 경계±1초·urlsafe_base64(32)·touch_activity!(절대 만료 불변)·usable |
| `test/services/phone_verifications/send_service_test.rb` | 7 | AUTH-9 정상 발송(6자리 코드·SMS 본문 코드·마스킹 010\*\*\*\*5678·TTL)·형식 검증(국번/자릿수)·1분 1회·1시간 3회·61분 후 재허용·**발송 실패 시 행 destroy로 rate limit 미소진 + 즉시 재시도 허용** |
| `test/services/phone_verifications/verify_service_test.rb` | 9 | AUTH-9 성공(consumed)·no_request·만료 ±1초·불일치 attempts 증가·4회→5회→정확한 코드도 차단·**소비된 코드 재사용 실패**·만료 후 재발급 신규 코드 수용 |
| `test/services/sales/attach_first_charge_coupon_service_test.rb` | 3 | SALES-4 percent 20·1회·무만료·"REF"+hex8 쿠폰 생성·subscription.coupon_id 예약(Q12)·구독 부재 폴백·**E2E: 예약→첫차감 7,920원(orders.amount)→2회차 9,900원·used_count 1(SEC-5)** |
| `test/services/sales/rotate_referral_codes_service_test.rb` | 7 | SALES-2 전체/단독 로테이션·기존 코드 어제 조기 종료·P4 이력 보존·**당일 재실행 멱등(SEC-5)**·정지 rep 제외·**주간 경계(일요일 valid_until=월요일 valid_from-1일 — 끊김 없음)**·발급 규격 |
| `test/services/sales/monthly_settlement_service_test.rb` | 12 | SALES-5·Q24 officer 15%·13개월째 무기한·**sales 12개월 캡 ±1초(정각 포함/+1초 제외)**·캡 외 미생성·실차감액 7,920 포함·환불/pending/failed/pass 제외·절사+오버라이드 30%·**upsert 멱등(재실행 동일)**·pending 재집계 갱신(환불 회복)·**paid 스냅샷 보존(updated_at 불변)**·무실적 미생성·개별 rep 실패(rate 101 주입) 후 계속·기본 직전월 |
| `test/queries/sales/rep_monthly_payments_query_test.rb` | 3 | SALES-6 12행 고정(빈 달 0원)·월별 합산·환불/미결제/타 상품/타 rep 제외 |
| `test/jobs/sales_recurring_test.rb` | 3 | TIME-1 recurring.yml 2종(production+development·KST 접미사 cron)·RotateJob(활동만)·SettlementJob(직전월 스냅샷) |
| `test/controllers/registrations_phone_referral_test.rb` | 16 | **C-1 4건(미검증 create 422·A검증→B가입 차단·세션≠제출 422·가입 후 세션 소멸)**·SALES-3 유효/소문자+공백/만료/미지 코드/공백 무시·스냅샷·SALES-4 예약·AUTH-9 재가입 422·정규화 저장·**코드 네트워크 비노출**·1분 1회 422·**IP 20회/1h→429(W-5)**·W-6 coupon_attach_failed 감사(admin nil·target User) |
| `test/controllers/sales/sessions_controller_test.rb` | 8 | SALES-1·7 비인증 303·정상 로그인(세션+감사)·통일 문구 422(열거 방지)+실패 감사·미지 이메일 감사 없음·**5회 잠금+lockout 감사·잠금 후 정확한 비밀번호도 거부**·정지 422+세션 미발급·10회/3분 rate limit·로그아웃 파기 |
| `test/controllers/sales/session_isolation_test.rb` | 8 | SALES-7 U1→/sales 차단·sales→/app·/admin 차단·**3세션 공존(쿠키 키 3원 분리)**·U1 로그아웃 후 /sales 유지·sales 로그아웃 후 U1·admin 유지·비활동 2h 만료(갱신 기준점 이동 포함)·**절대 12h 만료(활동 유지해도)**·무효 토큰 파기 |
| `test/controllers/sales/dashboards_controller_test.rb` | 10 | SALES-6 본인 타이틀·직함 배지·요율·역할 정책 문구·officer 15%·현재 코드+만료·직전월 스냅샷+지급 예정/완료 배지·연도 누적+전체 누적·**원천징수 3.3% 고지(Q24)**·**W-4 표시명 노출/이메일 미노출(css_select 섹션 단정)**·**W-3 총 31명+30행(limit(30).size 수정 검증)**·**타 rep 사용자·스냅샷 미노출(2계정 교차)**·noindex+robots(SURF-3)·가입 폼 색인 허용 유지 |
| `test/controllers/admin/sales_reps_controller_test.rb` | 12 | SALES-1 비인증 차단·목록 렌더·생성(초기 코드+감사)·role 조작 입력 강제 sales·**W-2 rate 0·51·-5 422**·수정(요율·직함+감사)·비밀번호 공백 유지·**정지(세션 전량 파기+suspended/resumed 감사)**·코드 재생성(이전 코드 즉시 무효+재실행 멱등 안내)·**W-1 unlock(리셋+감사+해제 후 자력 로그인)**·staff 허용·destroy 404(P4) |
| `test/controllers/admin/sales_commissions_controller_test.rb` | 6 | SALES-5 목록+pending/paid 합계·연월 필터·**mark paid(감사 detail·paid 전환)**·재 mark paid alert 흡수(paid_at 불변)·staff 허용·비인증 차단 |

## 2. 시나리오 ↔ Rule ID 매핑

| Rule ID | 시나리오(위 표 근거) |
|---|---|
| **SALES-1** | role 이원화·effective_rate 단일 판정점·W-2 rate 검증·잠금/unlock·정지(세션 파기)·콘솔 CRUD+감사 전건·destroy 부재(P4) |
| **SALES-2** | 8자 안전 문자열·current_valid 양끝 포함·주간 로테이션+조기 종료(P4)·당일 멱등(SEC-5)·정지 제외·주간 경계 끊김 없음·만료 코드 가입 422 |
| **SALES-3** | 가입 어트리뷰션+스냅샷(P4)·유효/만료/미지/공백/소문자 분기·오류 422 안내(조용한 무시 금지) |
| **SALES-4** | percent 20·1회 쿠폰 자동 생성·Q12 예약 구조 재사용·첫차감 7,920→재과금 9,900·used_count 1회(SEC-5)·부착 실패 정가 폴백 |
| **SALES-5** | 매월 1일 00:05 KST Job·역할 정책(20%·12개월 캡 ±1초 경계/15% 무기한)·실차감액(7,920 포함)·환불 제외·upsert 멱등(SEC-5)·paid 보존·mark paid 감사·개별 rep 실패 후 계속 |
| **SALES-6** | 자체 레이아웃("받을돈 파트너스")·본인 타이틀·직함·코드·직전월 스냅샷·연도/전체 누적·원천징수 3.3% 고지·W-3 총원·W-4 표시명 |
| **SALES-7** | 별도 세션(12h+2h)·쿠키 3원 격리·무효 토큰 파기·정지 422·스코프 격리(2계정 교차)·noindex+robots(SURF-3) |
| **AUTH-9** | 5분 TTL·5회 시도·1회용 consumed·1분 1회·1시간 3회·IP 20회/1h 429(W-5)·발송 실패 rate 미소진·마스킹·코드 비노출·번호 유일·정규화 저장·**C-1 세션 결합 4건** |
| **Q24** | 역할 이원화·12개월 캡 경계·무기한 13개월째·M+1 스냅샷·mark paid·원천징수 고지 |
| **Q12** | 첫차감 7,920·재과금 9,900·used_count 1·웹훅 경로 무변경(E2E 재확인) |
| **SEC-5** | 로테이션 당일 가드·정산 upsert 멱등·paid 보존·코드 1회용·쿠폰 원자 소비·세션 토큰 엔트로피 |
| **P4** | 코드 이력 보존(행 삭제 없음)·rep 삭제 차단(3중 방어선)·referral_code_snapshot·발송 실패 행 destroy는 "미발송 요청" 설계 재확인 |
| **SURF-3** | /sales noindex 메타·robots Disallow /sales·가입 폼 색인 허용 유지 |
| **TIME-1** | recurring KST 접미사 2종·KST 날짜 경계(current_valid·정산 month_range) |
| **ADMIN-2** | 감사 9종 단정(created/updated/suspended/resumed/code_rotated/unlocked/login_failed/lockout/login_success·commission_marked_paid) |

## 3. 리뷰 12항목 커버 표 (05_review §4)

| # | 지시 | 결과 | 테스트 |
|---|---|---|---|
| 1 | **C-1 결합 회귀** | 통과 — 미검증 세션 422·A검증→B 422·세션≠제출 422·동일 브라우저 성공·가입 후 세션값 소멸(로그아웃 후 재가입 차단) | registrations_phone_referral 4건 |
| 2 | AUTH-9 상태 전이 | 통과 — 만료±1초·5회 초과(정확한 코드도)·consumed 재사용·만료 후 재발급 수용·attempts 추적 | verify_service 7건 + phone_verification 모델 |
| 3 | rate limit | 통과 — 1분 1회·1시간 3회·61분 재허용·IP 20회 429·**stub ApiError 시 행 destroy·즉시 재요청 허용** | send_service 4건 + 컨트롤러 2건 |
| 4 | phone 유일 | 통과 — 재가입 422·정규화 저장(하이픈→숫자)·null 다수 허용(모델). 하이픈 레거시 간 중복은 §5 관찰 2 참조 | registrations_phone_referral 2건 + user_test |
| 5 | 가입 E2E(추천) | 통과 — 유효/만료/공백/소문자·referred_by+snapshot·쿠폰 예약·**첫차감 7,920→2회차 9,900·used_count 1** | registrations_phone_referral 6건 + attach service E2E |
| 6 | 쿠폰 부착 실패 폴백 | 통과 — 서비스 실패 주입 → 가입 303·어트리뷰션 유지·**coupon_attach_failed 감사(admin nil·User target)**. referral_attribution_failed 분기는 §5 관찰 3 참조 | registrations_phone_referral 1건 |
| 7 | /sales 격리·세션 | 통과 — 3중 공존·상호 침투 없음·U1 로그아웃 후 유지·비활동 2h/절대 12h 만료·무효 토큰 파기 | session_isolation 8건 |
| 8 | 잠금·정지 | 통과 — 5회 실패+lockout 감사·정지 422+미발급·**admin toggle 시 세션 전량 파기+303**·W-1 unlock 복구 | sales sessions 3건 + admin sales_reps 2건 |
| 9 | 정산 경계 | 통과 — 캡 ±1초(정각 포함/1초 제외)·officer 13개월째·환불 제외·upsert 멱등·paid 불변·오버라이드 30%·(W-2는 rate 101 주입 실패 흡수로도 검증) | monthly_settlement 12건 |
| 10 | 로테이션 | 통과 — 주간 재실행 멱등·만료 코드 가입 422·수동 재생성 후 이전 코드 즉시 무효+재실행 멱등 안내·**일요일 valid_until→월요일 valid_from 맞닿음** | rotate service 7건 + admin 1건 + 가입 1건 |
| 11 | noindex·robots | 통과 — /sales noindex 메타·robots Disallow /sales·가입 폼 색인 허용 유지 | dashboards 2건 |
| 12 | 대시보드 스코프·표기 | 통과 — 타 rep 사용자/스냅샷 미노출(2계정 교차)·스냅샷 상태 배지·W-3 총원 31명·원천징수 3.3% 문언 | dashboards 6건 |

## 4. 기존 테스트 갱신 목록 (정책 변경·결함 근거 기록)

| 파일 | 변경 | 근거 |
|---|---|---|
| `test/controllers/registrations_controller_test.rb` | ① 전 가입 시나리오를 AUTH-9 전체 플로우(SMS stub → verify → create) 전제로 갱신 — sign_up 헬퍼 교체 ② rate limit 테스트는 verify 없는 raw create 반복으로 분리(send/verify를 섞으면 IP 20회/1h가 먼저 발화) ③ 가입 폼 2단계 UI 단정 1건 신설 | PRD AUTH-9 "가입 시 휴대폰 번호 필수·검증 통과 시에만 가입 진행"(2026-11-19 구현 확정) — 리뷰 §3-10·03 문서 Phase 7 인계 2 |
| `test/models/user_test.rb` | ① 형식 위반 표본 "abc"→"010123456789"(12자리) — normalizes(AUTH-9)가 "abc"를 공백화해 기존 표본이 무의미 ② 번호 유일(null 허용) 신설 ③ 계좌번호 커버는 별행 테스트로 보존 | User normalizes :phone(AUTH-9)·validates phone 유일 |
| `test/controllers/app/profiles_controller_test.rb` | ① 위반 표본 동일 교체 ② 6필드 저장 단정 "010-1234-5678"→"01012345678"(정규화 저장) | AUTH-9 정규화 저장 정책(03 문서 §3-6) |
| `test/controllers/app/invoices_reminders_test.rb` | C-2 수동 발송 테스트의 `get`을 `travel_to(2026-11-10)` 블록 안으로 이동 | **기존 테스트 잠복 결함(시간 의존)** — 블록 밖 GET은 실제 오늘 기준 판정이라 약속일(11-20 고정)이 내일이 되는 구간(11-13~11-20)에 항상 실패. 본 작업과 무관하게 2026-11-19 실행에서 발현(테스트 오류 분류) |
| `test/test_helpers/fake_solapi_client.rb` | `send_sms(to:, body:)` 기록·실패 주입(sms_error:) 최소 확장 — 기존 알림톡 경로 무영향 | 솔라피 send_sms(AUTH-9) stub 방어선 — 실호출 금지 준수 |
| `test/test_helper.rb` + 신규 헬퍼 2종 | `sales_session_test_helper`(sales_login)·`memory_rate_limit_helper`(기존 registrations private 헬퍼의 공유 추출) require 추가 | /sales 세션·rate limit 시나리오 공용 |

- admin 네비 2종 추가에 대한 기존 admin 테스트: `dashboards_controller_test`(admin_root 렌더 단정)·`audit_trail_test`(5종 action)는 전체 스위트에서 회귀 없음 확인 — 갱신 불요(03 문서 §4-6 판정과 일치).

## 5. 코드 버그 — 0건 (관찰 사항 5건, 조치 불요·기록 목적)

1. **format 검증 inline 문언이 ko.yml에 shadowed** — `User` phone format의 inline `message: "은(는) 휴대폰 번호 형식이어야 합니다"`는 Rails 8의 i18n 키 우선 참조로 ko.yml `user.phone.invalid`(연락처 형식이...)에 밀려 실노출되지 않는다(실측: errors[:phone]). 사용자 노출 문언에는 영향 없음 — 03 문서 "ko.yml phone invalid는 사실상 데드 문언" 기술과 상반되므로 문서 정합화 권장(소스 수정 불요).
2. **레거시 하이픈 번호 간 유일성 공백** — fixture 레거시("010-1234-5678")와 신규 정규화("01012345678")는 문자열이 달라 모델 검증·부분 유니크 인덱스 모두 미발화. PRD AUTH-9 "기존 유저 소급 없음" 범위로 수용하되, 레거시 유저가 프로필에서 번호를 재저장하면 정규화값으로 수렴해 공백은 해소된다(관찰 기록).
3. **`referral_attribution_failed` 감사 분기 미단정** — 어트리뷰션 update! 실패를 통합 테스트에서 안전하게 주입할 수 없다(인스턴스 단일 stub은 컨트롤러 내부 생성 객체에 불가·전역 콜백 주입은 병렬 실행에 위험). coupon_attach_failed 분기는 주입 검증했고 두 분기는 동일 rescue 코드 경로다. 커버리지 공백으로 기록.
4. **`SalesRep#record_failed_attempt!`의 인스턴스 stale** — 5회째 `update_all(locked_at:)` 후 in-memory `locked_at`은 nil이라 `rep.locked?`가 false를 반환한다. 로그인 컨트롤러는 매 요청 DB 재조회라 실영향 없음(모델 단위 직접 호출 시 reload 필요 — 테스트에 명시).
5. **`resources :sales_reps`가 destroy 경로를 포함** — 액션 부재로 404 흡수되어 P4는 유지되지만, 라우트 정합성 관점에서 `except: :destroy`가 더 단단하다(소스 수정 불요 제약으로 미조치 — 제안).

## 6. 테스트 측 자체 수정 이력(실패 분류 — 전부 테스트 오류)

| 건수 | 분류 | 내용 |
|---|---|---|
| 5건 | Duration→travel_to 직접 전달·lambda 반환값 착오·fixture after_create 미고려·label 형식 착오·assert 단정 논리 반전 등 | §3-2 시나리오 진행 중 자체 수정 — 재실행 해소 |
| 1건 | 기존 테스트 잠복 결함(시간 의존) | invoices_reminders C-2 — travel 범위 수정(§4) |
| — | **코드 버그** | **0건 — 오케스트레이터에게 Developer 수정 위임 대상 없음** |

## 7. 게이트

- `bin/rails test` — **1,385 runs · 8,557 assertions · 0 failures · 0 errors · 0 skips**(전체 회귀 0)
- `bin/rubocop` — **393 files inspected, no offenses**
- `bin/rails zeitwerk:check` 불요(소스 무접촉) · 솔라피 실호출 0건(FakeSolapiClient·with_solapi_client 주입만) · 포트원 실호출 0건(FakePortOneClient)
- git 커밋 없음(제약 준수)
