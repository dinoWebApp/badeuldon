# 01_plan — F-ADMIN 잔여 병렬 배치 (2026-11-10, §6.14 parallel · 절약 모드)

## 범위 분할 (게이트 승인 대상)

| 항목 | 판정 | 근거 |
|---|---|---|
| ADMIN-10 콘텐츠 통합(블로그) | **병렬 배치 제외 — LP-11 블로그와 통합하는 별도 대형 런으로 분리** | 블로그 자체(BLOG 도메인·표면·LP-11)가 미구현 — 새 도메인 신규 구현이라 독립 소규모 묶음이 아니며 PRD에도 "LP-11과 통합 검토" 명시 |
| 롤·계정 콘솔 / 쿠폰·프로모션 / 계정 삭제·데이터 파기 | **이번 병렬 배치 3태스크** | 아래 3조건 전부 통과 |

## 태스크 분해 (병렬 안전 3조건 판정 포함)

### T-C1 · ADMIN 롤·계정 콘솔 (AUTH-7.2·ADMIN-1)
- 내용: ① admins 목록(이메일·role·잠금 상태·최근 로그인) ② **신규 관리자 생성 폼**(이메일·비밀번호·role — AUTH-7.2 "추가 계정은 최고 관리자가 콘솔에서만") ③ **role 승격/강등** ④ **잠금 해제 버튼**(기존 runner 절차의 콘솔화)·전 행위 감사 기록(RecordService 경유)
- 권한 규칙(권고): 목록 조회 = admin 전원, **생성·role 변경·잠금 해제 = owner 전용**(ADMIN-1 문언 "부여·해제는 최고 관리자만") — staff 접근 시 403/안내
- 소유 파일: `app/controllers/admin/admins_controller.rb`(신규)·`app/views/admin/admins/**`(신규)·`app/models/admin.rb`(role 변경·생성 헬퍼 최소)·`app/services/admins/role_service.rb`(신규)·해당 테스트
- 판정: ✓ 3조건(마이그레이션 불요 — admins 테이블 존재)
- 런타임 사유: Run A 잠금 해제·계정 생성의 runner 절차를 콘솔로 승격 — 운영 공수 저감

### T-C2 · 쿠폰·프로모션 (ADMIN-4)
- 내용: ① **쿠폰 모델**(code 고유·discount_type enum percent:0/amount:1·discount_value·max_redemptions·used_count·expires_at·active) ② **Admin CRUD + 사용 통계** ③ **U1 적용**: /app/billing에서 쿠폰 코드 입력 → 검증 → **Plus 구독 첫 결제 1회 할인**(포트원 빌링키 첫 차감 금액 조정 — orders 금액·metadata 기록·used_count 증가) ④ 감사 기록
- **범위 한정(권고)**: 첫 달 1회 할인만 — 재과금(자동 갱신)·수금 패스 미적용(확장 후속). PLAN-2 9,900원 기준 percent/amount 절감, 최소 0원 방지(amount 할인 상한 9,900)
- 소유 파일: `db/migrate/` 신규 1건(coupons)·`app/models/coupon.rb`(신규)·`app/controllers/admin/coupons_controller.rb`(신규)·`app/views/admin/coupons/**`(신규)·`app/models/subscription.rb`(쿠폰 연결 컬럼 또는 orders metadata 활용 — 당신 설계)·`app/services/subscriptions/upgrade_service.rb`(첫 차감 금액 할인 반영 — Run F-PLAN 파일)·`app/views/app/billings/show.html.erb`(코드 입력 UI)·해당 테스트
- 판정: ✓ 3조건 — 단, **결제 플로우 결선이라 규모 최대**(F-PLAN 실서비스 코드 수정 포함)·파생 리스크는 리뷰에서 집중 검증
- 결제 안전: 할인 적용 실패 시 원가 결제 폴백 또는 중단 — 결정은 구현 후 리뷰 판정(지시서에 양안 제시)

### T-C3 · 계정 삭제·데이터 파기 (ADMIN-3·AUTH-1.5 준용)
- 내용: 관리자 주도 U1 계정 영구 삭제 — ① **미수 청구 존재 시 차단**(unsettled 잔액 > 0 → 거부·안내 — 운영 안전·권고) ② 진행 시퀀스·발송 중단 확인 ③ 연쇄 삭제(clients·invoices·items·message_logs·tickets·notice_reads·sessions·orders·payment_passes·subscriptions — user.rb dependent 연쇄 실측) ④ **감사 로그는 보존**(admin_id=admin 본인·detail에 대상 이메일 스냅샷 기록 후 삭제) ⑤ 삭제 전 2중 확인 UI(이메일 타이핑 확인)
- AUTH-1.5 준용: 탈퇴 즉시 데이터 삭제·링크 폐기(토큰 소유 데이터 삭제로 자동)·진행 중 자동 시퀀스 중단
- 소유 파일: `app/services/admins/account_purge_service.rb`(신규)·`app/controllers/admin/members_controller.rb`(destroy 액션 추가 — Run B 파일)·`app/views/admin/members/show.html.erb`(삭제 UI 추가)·해당 테스트
- 판정: ✓ 3조건(마이그레이션 불요 — dependent 연쇄 실측 기반)

### 3-S 직렬 통합 (단일 Developer-lite)
- `config/routes.rb`: T-C1 `resources :admins, only: %i[index new create] + member { patch :change_role; patch :unlock }`·T-C2 `resources :coupons`·T-C3 members destroy(`resources :members`에 destroy 추가)
- admin nav 링크(관리자 계정·쿠폰)·전체 migrate 1회·부트 스모크(303 가드)

## 파일 소유권 표 (§6.14 필수)

| 파일/영역 | T-C1 | T-C2 | T-C3 | 3-S | 비고 |
|---|---|---|---|---|---|
| admin/admins 컨트롤러·views·role_service | **소유** | | | | |
| coupons 마이그레이션·coupon.rb·admin/coupons·upgrade_service·billings 뷰 | | **소유** | | | 결제 플로우 결선 |
| account_purge_service·members 컨트롤러·members show 뷰 | | | **소유** | | |
| config/routes.rb·layouts/admin nav | | | | **소유(3-S)** | |
| PRD·AGENTS·progress.json | ✗ | ✗ | ✗ | ✗ | 오케스트레이터 전용 |

## 파이프라인

✋(이 문서) → 2(문서 현행화 직렬) → 3-P(3태스크 동시, 상한 3) → 3-S(결선·migrate·스모크) → 4(게이트) → 5(Reviewer-lite — **컨트롤러 경유 재현 필수·특히 C-2 결제 플로우 실측**) → 6? → 7(Tester-lite) → 8 → 9

## 리스크·모호점 (게이트 확정 대상)

1. **T-C2 쿠폰 결제 결선** — 첫 차감 금액 조정이 포트원 결제·orders·subscription 주기와 상호작용. 권고: 할인 적용 주문은 **가격 9,900원 → 할인가로 첫 차감**·재과금은 정상가(구독 주기 무변경)·할인 실패 시 결제 중단(원가 폴백은 금액 불일치 혼란 유려)·실제 포트원 호출은 stub 경유만 검증(라이브 실측은 운영 첫 쿠폰 사용 시)
2. **T-C3 삭제 파급** — user dependent 연쇄는 user.rb에 이미 정의(AUTH-1.5 주석)·tickets·notice_reads 포함 확인. 감사 로그 P4 균형: **admin 행위 로그 보존 + 대상 개인정보는 스냅샷 최소화**(이메일 정도)를 권고
3. **T-C1 owner 전용 가드** — staff로 로그인해 role 변경 시도 → 차단 실측을 리뷰에서 필수
4. 쿠폰 코드 형식: 대문자 영숫자 8~16자 권고·중복·만료·한도 초과·비활성 검증 매트릭스

## 관련 Rule ID

ADMIN-1·3·4 · AUTH-7.2 · PLAN-2/5(쿠폰 할인과 결제)·PLAN-4(미적용 경계)·AUTH-1.5(삭제 준용)·P4(감사 보존)·TIME-1·SURF-3
