# 03_implementation — T-C1 ADMIN 롤·계정 콘솔 (AUTH-7.2·ADMIN-1)

2026-11-10 · 절약 모드 병렬 배치 · 소유권 화이트리스트 준수

## 변경 파일 목록

| 파일 | 신규/수정 | 내용 |
|---|---|---|
| `app/services/admins/role_service.rb` | 신규 | 계정 생성·롤 변경·잠금 해제 + 감사(RecordService 경유) |
| `app/controllers/admin/admins_controller.rb` | 신규 | index(new/create/change_role/unlock)·owner 전용 가드 |
| `app/views/admin/admins/index.html.erb` | 신규 | 목록 표(이메일·롤 배지·2FA·잠금·최근 로그인·액션) |
| `app/views/admin/admins/new.html.erb` | 신규 | 생성 폼(이메일·비밀번호·롤 select) |
| `test/services/admins/role_service_test.rb` | 신규 | 서비스 계약 고정 11케이스 |
| `test/controllers/admin/admins_controller_test.rb` | 신규 | 가드·303/422·감사 10케이스 |

수정 파일 없음(admin.rb `owner?`는 enum 자동 제공이라 불요 — 지시서 예상대로). 라우트·마이그레이션·레이아웃 미접촉.

## 설계 요약

- **Admins::RoleService**(MemberAdminService 선례 — Result Struct·transaction·Service→RecordService 주석 명시):
  - `change_role!` — staff actor 거부(`admin_role_denied`)·자기 자신 staff 강등 금지(최고 관리자 유일성 보장 주석)·무효 롤 거부(ArgumentError 방지 — `Admin.roles.key?` 검사)·성공 시 `admin_role_change`
  - `unlock!` — owner 전용(`admin_unlock_denied`)·`locked?` 아님 거부(감사 미기록)·`Admin#unlock!` 재사용(AUTH-7.3)
  - `create_admin!` — owner 전용(`admin_create_denied`)·ProvisionService 선례로 otp_secret 미발급(최초 로그인 2FA 등록)·검증 실패 Result(`admin_create` 감사 미기록)
  - `record_denied!` — 컨트롤러 `require_owner`용 감사 경유점(`admin_console_denied`) — 컨트롤러 직접 AuditLog create 금지 유지
- **Controller**: index 전원 공개, 나머지 `before_action :require_owner` — staff는 `admin_console_denied` 감사 후 `admin_root_path` 303 리다이렉트+alert(403 계열 안내). index의 최근 로그인은 `AdminSession.group(:admin_id).maximum(:created_at)` 1쿼리(N+1 방지). create 실패 422 재렌더, 성공/변경 액션 303 see_other. `params.expect(admin: [:email, :password, :role])`
- **뷰**: Run B members 톤(admin-card·stone 팔레트·배지)·owner만 생성 버튼·액션 열 렌더·전부 `<%= %>` 이스케이프

## 권한 매트릭스

| 액션 | owner | staff | 비인증 |
|---|---|---|---|
| index(목록) | O | O(액션 버튼 비노출) | 로그인 리다이렉트 |
| new/create | O | 차단 + `admin_console_denied` 감사 | 로그인 리다이렉트 |
| change_role(PATCH) | O(자기 강등만 금지) | 차단 + `admin_role_denied` | 로그인 리다이렉트 |
| unlock(PATCH) | O | 차단 + `admin_unlock_denied` | 로그인 리다이렉트 |

## 라우트 계약(3-S 결선 대기)

`resources :admins, only: %i[index new create]` + `member { patch :change_role; patch :unlock }` — 컨트롤러·뷰·테스트가 사용하는 헬퍼: `admin_admins_path`·`new_admin_admin_path`·`change_role_admin_admin_path(a)`·`unlock_admin_admin_path(a)`. **routes.rb 미결선 상태라 컨트롤러 HTTP 테스트는 3-S 결선 후 유효**(테스트 파일에 주석 명시).

## 자기 스코프 검증 결과

- [3-S 결선 후 수정] `self.record_denied!`가 private 인스턴스 `record_denial`을 암시적 호출 → staff 차단 3건 NoMethodError. RecordService 직접 경유로 수정(옵션 A·최소 변경) — 컨트롤러+서비스 테스트 21케이스 0 errors 통과.
- `bin/rubocop`(소유 4 Ruby 파일): no offenses
- `bin/rails zeitwerk:check`: 통과
- runner 자체검증(RAILS_ENV=test·transaction rollback — 임시 레코드 0 잔존): **PASS** — owner 가드 3종(r2·r4·r7)·자기 강등 금지(r3)·잠금 해제 초기화(r5)·롤 승격/강등 왕복(r1·r1b)·정상 생성(r6)·중복 거부(r8), 감사 action 6종(`admin_create`·`admin_role_change`·`admin_unlock`·`admin_role_denied`·`admin_unlock_denied`·`admin_create_denied`) 기록 확인
- 미수행(지시서 금지): 전체 테스트·마이그레이션(불요 — admins 테이블 기존)·문서 수정

## 리뷰어 확인 권고

1. staff 로그인 → 관리자 계정 메뉴: index는 보이되 new/change_role/unlock 차단 실측(플랜 리스크 3)
2. owner가 자기 자신 staff 강등 차단(유일성)
3. staff가 index에서 액션 폼/버튼 미노출 확인(뷰 가드는 current_admin.owner? 분기 — 서버 가드와 이중)
