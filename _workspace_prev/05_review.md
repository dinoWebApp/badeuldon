# 05_review — F-ADMIN 잔여 병렬 배치 T-C1~C3+3-S (Phase 5)

- **리뷰어**: badeuldon-reviewer (절약 모드) · **일시**: 2026-11-10
- **대상**: T-C1 관리자 롤·계정 콘솔 / T-C2 쿠폰(ADMIN-4·Q12) / T-C3 계정 삭제·데이터 파기(Q13) / 3-S 라우트·nav 결선
- **기준**: PRD v0.34 (AUTH-7.2·ADMIN-1/2/3④/4·Q12/Q13), ARCHITECTURE_CONVENTION v1.0.0, Run A/B 교훈(컨트롤러 경유 통합 재현)
- **재현 방식**: 임시 통합 테스트(test/review_repro_tmp_test.rb — 13 runs 199 assertions, 종료 후 삭제·잔존 0) + 기존 관련 스위트 9파일 95 runs 0 failures + 정적 전수 분석. PortOne은 FakePortOneClient 주입(실호출 없음), 레코드는 트랜잭션 롤백으로 정리.

---

## 종판 판정

```
status: CHANGES_REQUESTED   (BLOCKER 1 · CRITICAL 2 · WARNING 4)
```

BLOCKER 1건(B-1 — 기존 /admin/audit_logs 페이지 500 파탄)과 CRITICAL 2건(C-1 무효 롤 500·C-2 웹훅 회복 경로 쿠폰 불변식 위반)은 수정 후 재리뷰 대상. T-C1·T-C3·3-S의 권한 매트릭스·삭제 불변식은 HTTP 수준 재현에서 전부 통과 — 결함은 이번 배치가 만든 새 상태(nil-admin 감사·nullable 완화)와 웹훅 회복·조작 입력이라는 우회 경로에 집중된다.

---

## 1. 이슈 목록

### B-1 · BLOCKER · ADMIN-2 — nil admin 감사 행으로 /admin/audit_logs 전면 500

- **파일**: `app/views/admin/audit_logs/index.html.erb:49` (`<%= log.admin.email %>`)
- **원인**: 이번 배치의 `change_column_null :audit_logs, :admin_id, true` + `belongs_to :admin, optional: true`(audit_log.rb)로 `coupon_redeemed`(U1 행위 — admin nil) 행이 신규 생성된다. Run B의 감사 로그 뷰는 nil 분기 없이 `log.admin.email`을 렌더 — 첫 coupon_redeemed 기록 직후 관리자 감사 로그 페이지가 통째로 파탄한다.
- **재현(HTTP, 실측)**: U1 쿠폰 예약 → 카드 등록 성공(=정상 UX 플로우 한 번) → owner 세션으로 `GET /admin/audit_logs` → `ActionView::Template::Error: undefined method 'email' for nil` 발생(관찰 프로브 D1에서 예외 클래스·메시지 캡처).
- **영향**: ADMIN-2 감사 로그 열람 불가(운영 가용성 상실)·Run B 기능 회귀. 정상 U1 행위 하나로 트리거 — Run A/B 교훈(컨트롤러/뷰 경유 통합 재현)이 다시 요구한 정확한 결함 유형.
- **수정 권고**: `log.admin&.email` 또는 `log.admin&.email || "사용자(U1)"` 라벨 렌더 + `@audit_logs = scope.includes(:admin)...`(행당 N+1 동시 제거). 같은 패턴의 `app/views/admin/members/show.html.erb:139`(`log.admin.email`)는 현재 도달 불가(target_type "User" 한정)지만 동일 수선을 권한다.
- **테스트**: nil-admin 감사 행 존재 시 audit_logs index 200 통합 테스트 신설(회귀 고정).

### C-1 · CRITICAL · AUTH-7.2 — create_admin! 무효 롤 파라미터에서 무처리 ArgumentError(500)

- **파일**: `app/services/admins/role_service.rb:71-86` (create_admin!), `app/controllers/admin/admins_controller.rb:17-29`
- **재현(HTTP, 실측)**: owner 세션으로 `POST /admin/admins` with `admin[role]=superadmin`(폼 select 우회·조작 요청) → `ArgumentError: 'superadmin' is not a valid role` — enum 할당 시점 예외가 서비스 어디에서도 rescue되지 않아 운영 환경 500. 계정 생성은 차단됨(데이터 오염 없음 — 관찰 프로브 A4에서 created=false 확인).
- **명세 불일치**: 같은 서비스의 `change_role!`은 `Admin.roles.key?(role.to_s)`로 무효 롤을 Result 거부로 처리(구현 문서에도 "ArgumentError 방지" 명시) — create_admin!만 이중 기준.
- **수정 권고**: create_admin! 선두에 동일 검사 `return failure("알 수 없는 롤입니다: #{role}") unless Admin.roles.key?(role.to_s)` — 422 재렌더로 귀착. 컨트롤러·서비스 테스트에 조작 롤 케이스 1건씩 추가.
- **심각도 근거**: 런타임 파탄이나 정상 플로우가 아닌 권한 보유자(owner)의 조작 입력 한정·무결성 영향 없음 — BLOCKER가 아닌 CRITICAL.

### C-2 · CRITICAL · Q12(ADMIN-4) — 웹훅 회복(settle_renewal) 경로에서 used_count 미증가·metadata 쿠폰 기록 소실

- **파일**: `app/services/subscriptions/upgrade_service.rb:101-117` (settle_renewal) — 쿠폰 연동 미반영
- **시나리오(불변식 위반)**: 첫 차감(할인가 7,900 선기록) → 포트원 모호 실패(TIMEOUT) → 주문 pending·쿠폰 예약 유지 → 웹훅 Transaction.Paid → settle_renewal이 **실제 성공한 할인 차감**을 paid 확정하되 ① `used_count` 미증가 ② `subscriptions.coupon_id` 미해제 ③ `metadata: @payment` 덮어쓰기로 성공 경로가 남기던 `coupon{code,discount_type,discount_value}` 기록 소실.
- **재현(실측)**: FakePortOneClient TIMEOUT 실패 → settle_renewal → `used_count=0, coupon_id=유지, metadata_keys=["id","status"], metadata_coupon=nil`(관찰 프로브 B3). 다음 갱신 시 resolve_first_charge_coupon!이 paid Plus 주문 감지로 coupon_id=nil·정상가 — **이중 할인은 없음**(완화 확인), 그러나 ②의 예약 잔존은 1개월간 유효.
- **위반 Rule**: Q12/ADMIN-4 불변식 3("used_count는 결제 성공 시점 1회 증가")·4("첫 차감 orders.metadata에 coupon_code") — 웹훅 회복도 "결제 성공 시점"이다. ADMIN-4 사용 통계·한도 집계가 실제보다 과소 계수(예산 초과 허용의 원인).
- **수정 권고**: settle_renewal의 확정 트랜잭션 안에서 (a) 주문이 첫 차감 할인 건임을 판정(주문 amount < PLUS_MONTHLY_PRICE 또는 subscription.coupon 존재)해 `consume_first_charge_coupon!(subscription, coupon)` 호출 (b) metadata는 `coupon_metadata(@payment, coupon)` 병합 — 기존 consume!·coupon_metadata 재사용으로 성공 경로와 단일화.
- **테스트**: B3 시나리오 회귀 테스트 신설(TIMEOUT→웹훅 회복→used_count 1·coupon_id nil·metadata coupon 보존).

### W-1 · WARNING · Q12 — 쿠폰 한도 TOCTOU 경합(redeemable? 판독 후 무한도 consume!)

- **파일**: `app/models/coupon.rb:58-61` (consume!), `upgrade_service.rb:167-177`
- **내용**: redeemable?의 used_count 판독과 consume!의 원자 증가 사이에 한도 검사가 없다(`WHERE used_count < max_redemptions` 가드 부재). 잔여 1칸 쿠폰으로 서로 다른 구독의 첫 차감이 병렬 실행되면 used_count가 max_redemptions를 초과한다. 완화 요건: 갱신 잡이 매일 06:05 단일 스케줄·find_each 순차라 현실 노출폭이 좁음 — 그러나 수동 재트리거·잡 병렬화 확장 시 열린다. PaymentPass의 with_lock 선례와 정합 권장.
- **수정 권고**: `update_all("used_count = used_count + 1 WHERE used_count < max_redemptions")` 후 affected rows 0이면 UpgradeError(결제 중단) — 단일 SQL로 원자화.

### W-2 · WARNING · Q12/P4 — 미사용·예약 보유 쿠폰의 삭제가 사용자 예약을 조용히 소멸시킨다

- **파일**: `app/controllers/admin/coupons_controller.rb:52-60` (destroy), `app/models/coupon.rb:12` (`has_many :subscriptions, dependent: :nullify`)
- **내용**: used_count==0이면 삭제 허용 — 그러나 예약(subscriptions.coupon_id)이 걸린 쿠폰도 이 조건에 해당하며, 삭제 시 nullify로 예약이 소멸해 해당 사용자가 할인 안내를 받은 상태에서 첫 차감에 정가가 청구된다(금액 불일치 UX). P4 관점에서도 예약 소멸이 기록에 남지 않는다.
- **수정 권고**: `subscriptions.exists?` 예약 보유 시 삭제 차단(alert으로 "비활성화로 중지" 유도 — used_count 차단 문구와 병기) 또는 show/삭제 확인 문구에 예약 건수 표시.

### W-3 · WARNING · AUTH-7.2 — 콘솔 생성 UI에 비밀번호 강도 안내·최소 길이 부재

- **파일**: `app/views/admin/admins/new.html.erb:16`, `role_service.rb:71-86`
- **내용**: AUTH-7.2는 강도 요건을 "ProvisionService/재설정 화면 안내"에 위임한다고 명시 — runner·재설정 화면과 달리 신규 콘솔 폼은 minlength·안내 문구가 없어 1자 비밀번호 owner 계정이 생성 가능(모델 최소 검증 정책 상 통과). 위임 대상 화면이 콘솔에 미반영.
- **수정 권고**: `minlength: 8` + "8자 이상 권장" 안내 문구 1행(검증 강제가 문서 정책과 충돌하지 않게 UI 안내 중심).

### W-4 · WARNING · ADMIN-4 — unavailability_reason의 음수 잔여 fall-through

- **파일**: `app/models/coupon.rb:48-54`
- **내용**: remaining_count가 음수(W-1 경합 발생 시)면 "0원" 사유 메시지가 나온다 — 실제 사유(한도 초과)와 불일치. `remaining_count <= 0` → "한도 소진" 분기로 1행 수선 권장.

---

## 2. Rule ID 준수 매핑 (PRD v0.34 1:1)

| Rule | 요구 | 판정 | 근거(재현 포함) |
|---|---|---|---|
| AUTH-7.2 | 추가 계정은 콘솔(owner 전용)만 | ✅ | staff create 차단+감사 실측, owner 생성 303+admin_create 감사, 2FA 미등록 생성 확인. 단 조작 롤 500 = C-1 |
| AUTH-7.1/7.3 | 콘솔 진입 2FA 필수·잠금 해제 | ✅ | admin_login 2단계 전 플로우 재현, unlock 실제 잠금 계정 해제+감사, 비잠금 거부 감사 미기록 |
| ADMIN-1 | 목록 전원·변경 owner 전용·전 행위 감사 | ✅ | staff index 200(액션 폼 미노출 실측)·new/create/change_role/unlock 전부 303 차단+admin_console_denied, owner 행위 감사 4종(admin_create/role_change/unlock/console_denied)+서비스 denied 3종. 자기 staff 강등 거부 실측 |
| ADMIN-2 | 단일 진입점 감사 기록 | ✅ (단 B-1) | RecordService 경유 유지(컨트롤러 직접 create 없음)·감사 원자성(트랜잭션 내). nil-admin 렌더 파탄만 B-1로 |
| ADMIN-3 ③ | staff도 회원 관리(롤만 owner) | ✅ | purge를 staff 세션으로 수행 실측(문서화된 권한 판단과 일치) |
| ADMIN-3 ④·Q13 | 미수 차단·연쇄 삭제·감사 보존·2중 확인 | ✅ | 이메일 불일치 거부(무쓰기 실측)·미수 차단(건수·합계)·삭제 성공 시 10테이블 0건 전수(users 파생 dependent+DB FK cascade 실측: sessions·invoices·clients·items·subscription·orders·payment_passes·notice_reads·tickets·message_logs)·audit_logs 보존+이메일 스냅샷·invoice 파생(view_events·promises·payments) dependent: :destroy 확인 |
| ADMIN-4·Q12 | 첫 결제 1회·재과금 정상가·수금 패스 미적용·0원 방지·CRUD+통계 | ⚠️ (C-2) | HTTP 적용 검증 4종 거부+예약·첫 차감 amount/metadata·실패 미소비+재시도 동일 할인가·[7,900,9,900] 시퀀스·중복 적용 차단(paid Plus 감지)·used_count params 조작 불가(A-7 실측)·admin CRUD 전수(중복 422·used 삭제 차단·미사용 삭제). 웹훅 회복 경로만 C-2 위반. 수금 패스·재과금 경로 미접촉 확인 |
| PLAN-5 | 결제 플로우 무결성(포트원 stub) | ✅ | 전 재현 FakePortOneClient 주입 — 실호출 0 |
| P4 | 모든 발신/행위는 기록 | ⚠️ (C-2) | order metadata 쿠폰 기록은 성공 경로만 — settle 경로 소실 |
| SURF-3 | /admin noindex | ✅ | 재현 응답 헤더에 robots noindex 확인(admin 레이아웃 meta) |
| §4 아키텍처 | 의존 방향·얇은 컨트롤러·뷰 쿼리 금지 | ✅ | Service→RecordService 허용 경유·컨트롤러 10줄 내·params.expect+private xxx_params(admins/coupons 모두)·뷰는 @변수만(admins index 집계 1쿼리 N+1 방지)·`@invoice.client` 선례와 동일한 연관 읽기만 존재 |
| 3-S 라우트 | 계약 1:1 | ✅ | `resources :admins only[index new create]+member{change_role,unlock}`·`resources :coupons`·`members only[index show destroy]+기존 member patches` — 헬퍼 실명·컨트롤러 액션 전부 일치, 비인증 303 전수(new/create/delete 포함)·U1 세션 차단(세션 격리) 실측 |

## 3. 통과 커버리지 (재현 완료 항목)

- **T-C1 권한 매트릭스 전수(HTTP)**: owner/staff/비인증 × index/new/create/change_role/unlock 15조합 + 감사 6종 + 자기 강등 거부 + 잠금 해제(실제 잠금 계정) + 무효 롤(change_role은 Result 거부 확인).
- **T-C2 불변식 6건**: 서버 검증(존재·활성·만료·한도·0원)·적용 1회·used_count 성공 시점(성공/실패/재시도)·orders.amount=할인가+metadata·재과금 정가 시퀀스·amount 상한(검증 매트릭스 12건) — 단 settle 경로 예외(C-2).
- **T-C2 admin CRUD(HTTP)**: 생성(정규화·303)·중복 422·형식 위반 422·수정(used_count 편집 제외 확인)·used 삭제 차단·미사용 삭제·staff 관리 허용.
- **T-C3 삭제 불변식 4건(HTTP)**: 이메일 불일치·미수 차단·연쇄 전수 10테이블+감사 보존·owner/staff 양 롤 실행.
- **3-S**: 라우트 계약·nav 2링크 렌더·비인증 303·U1 세션 차단.
- **기존 스위트 95 runs 0 failures**(관련 9파일)·임시 재현 13 runs(삭제 완료·레코드 잔존 0).

## 4. Tester 중점 테스트 제안 (수정 반영 후)

1. **B-1 회귀**: coupon_redeemed(admin nil) 행 존재 상태에서 `/admin/audit_logs`·`/admin/members/:id` 200 렌더(관리자 라벨 표기 확인).
2. **C-2 회귀**: TIMEOUT→웹훅 settle 시나리오 — used_count 1·coupon_id nil·metadata.coupon 보존·다음 갱신 정상가.
3. **C-1 회귀**: 서비스+컨트롤러에서 조작 롤("superadmin"/빈값) → Result 거부·422.
4. **W-1 경합**: 병렬 스레드에서 consume! 동시 호출 — used_count가 max를 넘지 않는 원자성 테스트(선택).
5. **W-2**: 예약 보유 쿠폰 삭제 시도 → 차단 안내·예약 유지 확인.

## 5. 비고

- `audit_log.rb`의 W-3 후속 주석("관리자보다 오래 살아야 하므로 restrict/nullify 재검토 필수") — 이번 배치에서 admin 삭제 경로가 신설되지 않아 여전히 미도달. 다음 admin 콘솔 확장 시 상기 재검토 필요(이번 배치 결함 아님·기술 부채 유지).
- 다중 owner 상호 강등으로 극단적 동시 요청 시 owner 0명 이론 경로 존재 — 실제 운영(단일 owner 운영 전제·자기 강등 금지)에서 수용 가능 수준으로 판정, 이슈 미기록.

---

# 재리뷰 (루프 1/2) — Phase 6 수정 통합 검증

- **일시**: 2026-11-10 · **대상**: 1차 리뷰 이슈 7건(B-1·C-1·C-2·W-1~W-4) 전건 수정분
- **방법**: 임시 통합 테스트 10 runs 80 assertions(종료 후 삭제·잔존 0) + 관련 기존 스위트 10파일 **97 runs 591 assertions, 0 failures** + 수정 파일 전수 리딩

## 재현 결과 (원 이슈 해소 확인)

| 이슈 | 수정 내용(실측) | 판정 |
|---|---|---|
| B-1 | nil-admin 행 존재 상태에서 `GET /admin/audit_logs` **200** + "사용자" 라벨 렌더 + members#show 200 · `includes(:admin)`로 N+1 동시 제거 | ✅ 해소 |
| C-1 | role=superadmin POST → **422** + "알 수 없는 롤" 렌더 + Admin.count 무변화 + admin_create/감사 미기록(정책 유지) — 서비스 가드+컨트롤러 실패 분기 유효 롤 한정 재할당의 2중 수선 | ✅ 해소 |
| C-2 | TIMEOUT→웹훅 settle → used_count **1**·coupon_id **nil**·metadata에 coupon 병합(SAVE2000 + @payment 원문 공존 — P4)·**다음 갱신 9,900 정상가**(중복 할인 없음) | ✅ 해소 |
| W-1 | consume! 단일 조건부 UPDATE(`used_count < max_redemptions`) — 잔여 0 → false·used_count 불변, 잔여 있음 → true·증가 | ✅ 해소 |
| W-2 | 예약 보유 쿠폰 HTTP DELETE → 303 alert "사용 예정인 쿠폰은 삭제할 수 없습니다"·Coupon.count 무변화·**예약 유지(nullify 미도달 — before_destroy 선언 순서 수선 실측)** + 컨트롤러 destroy 반환값 검사로 flash 정확화 | ✅ 완전 해소 |
| W-3 | 생성 폼 `minlength="8"` + "8자 이상을 권장합니다" 렌더 실측 | ✅ 해소 |
| W-4 | 음수 잔여(used 60/max 50) → "한도가 모두 소진" 안내 | ✅ 해소 |

## 회귀 확인 (재리뷰 지시 2·3)

1. **role_service 단일 기준 전환**: 무효 롤 create → 감사 실패 미기록 유지 실측(R-C1)·정상 생성 303+admin_create 감사 회귀 없음(R-C1b)·change_role 무효 롤 기존 Result 거부 유지. role_service_test 11케이스 통과.
2. **consume! 조건부 UPDATE 상호작용**: coupon_test 소비 원자성 테스트 통과 + C-2 settle 경로에서 정상 소비 실측. upgrade_service_coupon_test 7케이스(성공·실패 미소비·재시도 동일 할인가·재과금 정가) 통과.
3. **settle_renewal 기존 경로(쿠폰 없는 회복)**: metadata가 순수 @payment 유지(쿠폰 키 부재) — upgrade_service_test 기존 settle 테스트 통과(R-C2b 재현으로 보강 확인).
4. **W-2 선언 순서 수선**: `before_destroy`가 `has_many dependent: :nullify` 선언보다 앞 — 예약 유지 실측으로 nullify 미도달 확인(지시 3의 flash 가드 포함 완전 해소).

## 신규 이슈

- **없음** (BLOCKER 0 · CRITICAL 0 · WARNING 0).
- 비고(이슈 미기록 — 관찰 노트): ① settle_renewal에서 consume 가드 실패(W-1 경합 도달 시)는 트랜잭션 롤백으로 order pending 잔존 — 웹훅 응답 실패·PG 재시도와의 상호작용은 W-1 경합이 전제라 현실 희박, 다음 dunning 런에서 재확인 권장. ② admins create 422 재렌더 시 무효 롤 입력의 select가 enum 기본값(owner)으로 표시될 수 있음 — 경고 문구로 실용상 문제 없음.

## 종판

```
status: APPROVED   (재리뷰 루프 1/2 — 원 이슈 7건 전건 해소·신규 이슈 0)
```
