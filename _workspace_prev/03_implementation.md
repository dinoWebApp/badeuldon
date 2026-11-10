# 03_implementation — F-ADMIN 잔여 병렬 배치 (배치 수준)

 fan-out T-C1(관리자 계정 콘솔)·T-C2(쿠폰)·T-C3(회원 삭제) 구현 완료 후 3-S 결선 통합 기록.
 개별 태스크 상세는 `_workspace/parallel/T-C{1,2,3}/03_implementation.md` 참조.

## 3-S 결선 통합 (2026-11-10, 절약 모드)

### 1. 라우트 결선 — `config/routes.rb` admin namespace

계약(`02_prd_update.md` 확정 해석 1) 그대로 적용. 사전 확인 결과 컨트롤러 액션·헬퍼 실명 3종 모두 계약과 일치(불일치·정렬 없음):

- T-C1: `resources :admins, only: %i[index new create]` + `member { patch :change_role; patch :unlock }` — Admin::AdminsController의 index/new/create/change_role/unlock 실존 확인 (ADMIN-1·AUTH-7.2)
- T-C2: `resources :coupons` 표준 CRUD — Admin::CouponsController의 index/show/new/create/edit/update/destroy 실존 확인 (ADMIN-4·Q12)
- T-C3: 기존 `resources :members`를 `only: %i[index show destroy]`로 확장(기존 member patch toggle_suspension·change_plan 유지) — Admin::MembersController#destroy 실존 확인 (ADMIN-3·Q13)
- 주석: ADMIN-1/3/4·AUTH-7.2·Q12·Q13 인용, 상태 전이 member PATCH 정당화 문구 기존 Run B 스타일 준용

### 2. 네비게이션 — `app/views/layouts/admin.html.erb`

nav에 "관리자 계정"(admin_admins_path)·"쿠폰"(admin_coupons_path) 추가 — 기존 `request.path.start_with?` active 판정 문법 준용.

### 3. 마이그레이션 일괄

`bin/rails db:migrate` 1회 실행 — pending 없음, `20261110040001_create_coupons` 적용, `db/schema.rb` 동기 확인(+19/-2).

### 4. 스모크 + 인계 해소

- 서버 부트(3002) 후 curl:
  - `/admin/session/new` → **200**
  - `/admin/admins`, `/admin/admins/new`, `/admin/coupons`, `/admin/coupons/new`, `/admin` → **전부 303**(비인증 가드 정상)
  - `/up` → **200**
  - 서버 정리(pid 포트 kill, 3002 free 확인)
- **T-C3 인계 실행**: `bin/rails test test/controllers/admin/members_controller_test.rb` → **13 runs, 116 assertions, 0 failures, 0 errors** — 마이그레이션 pending으로 미실행됐던 destroy 케이스 결선 후 통과
- **T-C2 coupons 인증 스모크**(Integration, `/tmp` 임시 테스트 후 삭제): 관리자 세션(admin_login 헬퍼·2FA 경유)으로 coupons index 200·new 200·create 303 + 실제 생성 반영 확인 → **통과**
  - 참고: 스모크 과정에서 Coupon 검증(code: 대문자 영숫자 8~16자 형식)으로 인한 초기 422은 테스트 데이터 문제였고 코드 버그 아님 — 8자 이상 코드로 재검증 통과

### 5. 게이트

- `bin/rails zeitwerk:check` → all good
- `bin/rubocop config/routes.rb app/controllers/admin/` → 12 files, no offenses
- 전체 테스트는 Phase 7(지시 준수 — members_controller_test 1파일만 결선 확인용 예외 허용)

### 변경 파일

- `config/routes.rb` (admin namespace 결선)
- `app/views/layouts/admin.html.erb` (nav 2 링크)
- `db/schema.rb` (coupons — migrate 동기)

### 발견 이슈

- 계약 불일치 없음(컨트롤러 액션·헬퍼 실명 3종 전부 일치 — 정렬 불요)
- 없음 외 특이사항 없음. Phase 5 리뷰어 재현은 그대로 진행 가능.

## Phase 6 — 리뷰 수정 통합 (2026-11-10, 재리뷰 루프 1/2)

`05_review.md` CHANGES_REQUESTED(B1·C2·W4) 전건 수정. 게이트: rubocop(수정 5파일) 0 offenses · zeitwerk all good · 연관 스위트 7파일 **80 runs, 509 assertions, 0 failures**.

### B-1 (BLOCKER) — nil admin 감사 행 500 수선
- `app/views/admin/audit_logs/index.html.erb:49`: `log.admin.email` → `log.admin&.email || "사용자"`
- `app/views/admin/members/show.html.erb:139`: 동일 수선
- N+1 제거: `app/controllers/admin/audit_logs_controller.rb` — `scope.includes(:admin)`

### C-1 (CRITICAL) — 무효 롤 생성 500 해소
- `app/services/admins/role_service.rb` create_admin!: 선두에 `Admin.roles.key?(role.to_s)` 검사 추가(change_role!과 동일 기준 — Result 거부·감사 실패 미기록 유지)
- **추가 수선(재현에서 발견)**: 서비스 가드만으로는 422 불가 — 컨트롤러 실패 분기 `Admin.new(role:)`의 enum 할당이 동일 ArgumentError를 냈다. `app/controllers/admin/admins_controller.rb` 실패 분기를 유효 롤 한정 재할당으로 최소 수정(소유권 밖 파일이나 C-1 재현 게이트의 필수 경로 — 보고에 명시)

### C-2 (CRITICAL) — 웹훅 회복 쿠폰 미정산
- `app/services/subscriptions/upgrade_service.rb` settle_renewal: 확정 트랜잭션 내 기존 `consume_first_charge_coupon!(subscription, coupon)` 재사용(used_count 증가·예약 해제) + `coupon_metadata(@payment, coupon)` 병합(덮어쓰기 아님 — P4). 성공 경로와 단일화.

### W-1 — consume! 원자 가드
- `app/models/coupon.rb` consume!: `WHERE used_count < max_redemptions` 조건부 UPDATE 단일 SQL — 영향 행 0이면 false 반환. `upgrade_service.rb` consume_first_charge_coupon!은 false 시 UpgradeError(결제 중단).

### W-2 — 예약 보유 쿠폰 삭제 차단 (마이크로 후속으로 **완전 해소**)
- `app/models/coupon.rb`: `before_destroy :reject_destroy_with_reservations` — 예약(coupon_id 참조) 존재 시 errors("사용 예정인 쿠폰은 삭제할 수 없습니다. 비활성화로 중지해 주세요.") + `throw :abort`. **선언 순서 주의**: `dependent: :nullify`의 before_destroy가 연결 선언 시점에 먼저 등록되므로 가드가 has_many보다 앞에 선언되어야 nullify보다 먼저 실행된다(1차 구현 실측 결함 → 수정). nullify는 도달하지 않는다(방어선 유지).
- `app/controllers/admin/coupons_controller.rb` destroy(마이크로 후속): `@coupon.destroy` 반환값 검사 — 실패 시 `redirect_back` + `errors.full_messages.first` alert, 성공 시 기존 notice. flash 부정확 잔존 해소.
- `test/controllers/admin/coupons_controller_test.rb` 신설: 예약 보유 삭제 차단(alert·예약 유지·Coupon.count 무변화) + 미사용 삭제 통과, 2 runs 0 failures.

### W-3 — 콘솔 생성 폼 비밀번호 강도 안내
- `app/views/admin/admins/new.html.erb`: `minlength: 8` + "8자 이상을 권장합니다" 1행(UI 안내 중심 — 검증 강제 정책과 비충돌)

### W-4 — unavailability_reason 음수 잔여
- `app/models/coupon.rb`: `remaining_count.zero?` → `remaining_count <= 0`(음수 잔여도 "한도 소진" 안내)

### 컨트롤러 경유 재현 결과 (임시 테스트 /tmp — 종료 후 삭제·잔존 0)
- **B-1**: coupon_redeemed(admin nil) 행 생성 → owner 세션 `GET /admin/audit_logs` **200** + "사용자" 라벨 렌더 확인 · members#show 동일 200
- **C-1**: owner 세션 `POST /admin/admins` role=superadmin → **422** + "알 수 없는 롤" 렌더 + Admin.count 무변화
- **C-2**: 첫 차감 할인 주문(7,900) pending → settle_renewal(webhook 회복) → **used_count 1·coupon_id nil·metadata coupon 보존(SAVE2000)·pg_payment_id 확정**, 다음 갱신 charge **9,900 정상가**(중복 할인 없음) — 리뷰어 B3 시나리오 PASS
- 4 runs 28 assertions 0 failures

### 기존 테스트 갱신 (최소)
- `test/models/coupon_test.rb`: W-2 정책 반영 — "nullify된다" 테스트를 "예약 보유 쿠폰 삭제 차단·예약 유지"로 교체

### 변경 파일
- app/views/admin/audit_logs/index.html.erb · app/views/admin/members/show.html.erb · app/controllers/admin/audit_logs_controller.rb · app/services/admins/role_service.rb · app/services/subscriptions/upgrade_service.rb · app/models/coupon.rb · app/views/admin/admins/new.html.erb · app/controllers/admin/admins_controller.rb (C-1 추가 수선) · test/models/coupon_test.rb
