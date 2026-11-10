# 03_implementation — T-B2 ADMIN-2 감사 로그 뷰 + ADMIN-3 회원 관리 (Run B 병렬, 2026-11-10)

## 변경 파일 목록

| 파일 | 변경 |
|---|---|
| `db/migrate/20261110000003_add_status_to_users.rb` | 신규 — `users.status` integer default 0 null:false(ADMIN-3) |
| `app/models/user.rb` | `enum :status, { active: 0, suspended: 1 }, default: :active`(enum이 `suspended?` 제공) |
| `app/models/audit_log.rb` | 스코프 `recent`·`by_action`·`by_admin`·`by_period`(감사 로그 뷰 필터) |
| `app/services/admins/member_admin_service.rb` | 신규 — `change_plan!`·`toggle_suspension!` + Result Struct |
| `app/controllers/admin/audit_logs_controller.rb` | 신규 — index(필터·100행 limit/offset 페이지네이션) |
| `app/controllers/admin/members_controller.rb` | 신규 — index(검색·plan·status 필터)·show·toggle_suspension·change_plan |
| `app/views/admin/audit_logs/index.html.erb` | 신규 — 목록 표·필터 폼·페이지네이션 |
| `app/views/admin/members/index.html.erb` / `show.html.erb` | 신규 — 목록·상세 카드·플랜 변경 폼·정지 버튼 |
| `app/controllers/sessions_controller.rb` | create에 정지 차단 분기(ADMIN-3) |
| `test/controllers/sessions_controller_test.rb` | 정지 로그인 차단 회귀 1건 추가(화이트리스트 허용분) |

## 플랜 수동 변경 규칙 매핑(PRD v0.31 ADMIN-3 확정)

- **활성 Plus 구독 보유 시 체험 전환 금지** — `grant_trial` 가드(`plus? && active?`) → errors 반환
- **체험 연장 = current_period_end 연장** — `extend_trial`: max(period_end, trial_ends_at, now)+N개월, trialing이면 trial_ends_at 동기화
- **구독 해지 = cancel!** — 기간 말까지 유효(PLAN-5), 이미 cancelled면 errors
- **체험 1회 가드** — used_trial 재체험 거부(Subscription#start_trial!의 TrialAlreadyUsedError 포함 rescue)
- **전건 감사 기록** — `member_plan_change`·`member_suspend`·`member_unsuspend`. §4.2 결정: 감사 기록은 서비스 내부에서 AuditLogs::RecordService 경유로 수행(Service→Service 허용, 컨트롤러 얇게 유지 — 주석 명시)
- **정지 시 세션 파기**(02 확정 해석 5) — `user.sessions.destroy_all` transaction 내 수행
- **검증 실패는 errors 반환** — Result Struct(success/errors/message), 예외 없이 결과 반환, 컨트롤러는 303+flash

## 자기 스코프 검증 결과

- 마이그레이션: `db:migrate:up/down VERSION=20261110000003` (down→up 재적용 완료), 전체 migrate 미실행(3-S 위임)
- 서비스 규칙 runner 검증(test env, `verify_service.rb`): 9/9 PASS — 활성 Plus→체험 금지·연장·해지·체험 1회 가드·정지 시 세션 0건+감사 기록·해제·미지 action 거부·감사 스코프
- 정지 로그인 차단: `test/controllers/sessions_controller_test.rb` 신규 1건 포함 12건 전부 통과(기존 세션 미발급·422·전용 문구 검증)
- `bin/rubocop` 소유 파일 0 offense / `bin/rails zeitwerk:check` 통과
- 개발 DB 오염 없음(runner는 test env, 임시 레코드 destroy 완료)

## 미결(3-S·후속)

- routes 미결선 — `resources :audit_logs, only: :index`·`resources :members, only: %i[index show]` + `member { patch :toggle_suspension; patch :change_plan }`(02 확정 해석 1 계약 그대로 사용). 컨트롤러 경유 검증은 Phase 5/7
- nav(레이아웃 admin.html.erb) 링크는 3-S 소유
