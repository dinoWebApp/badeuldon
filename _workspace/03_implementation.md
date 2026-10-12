# 03_implementation.md — Phase 3 구현 보고: 인증 정책 반전 + 랜딩 CTA

- **일자**: 2026-10-12
- **범위**: `_workspace/01_plan.md` B절 구현 범위 (인증 골격 + 랜딩 반영)
- **기반**: `bin/rails generate authentication`(Rails 8.1 표준) 산출물을 프로젝트 규약(ARCHITECTURE_CONVENTION §3.3·§3.6·§3.7)에 맞게 정리·확장

## 1. 변경 파일 목록

### 신규 생성 (generator 산출 + 프로젝트 정리 완료)

| 파일 | 요약 |
|:---|:---|
| `db/migrate/20261011232612_create_users.rb` | `users` — `email`(null: false)·`password_digest`(null: false) + `email` 고유 인덱스 (AUTH-1.4) |
| `db/migrate/20261011232613_create_sessions.rb` | `sessions` — `user` FK(null: false, 인덱스) + `ip_address`·`user_agent` |
| `app/models/user.rb` | `has_secure_password`(bcrypt), `has_many :sessions, dependent: :destroy`, `normalizes :email`(strip+downcase) (AUTH-1·AUTH-1.4). `password_reset_token`은 has_secure_password 내장(15분 만료·재설정 시 무효화) |
| `app/models/session.rb` | `belongs_to :user` |
| `app/models/current.rb` | `Current.session` attribute, `user` delegate |
| `app/controllers/concerns/authentication.rb` | `before_action :require_authentication` 기본 가드 + `allow_unauthenticated_access` 선언형 예외 API. **세션 쿠키 30일**(AUTH-1.6 — generator 기본 permanent→`SESSION_COOKIE_MAX_AGE = 30.days`) |
| `app/controllers/sessions_controller.rb` | 로그인/로그아웃. rate_limit(10회/3분), 실패 422 render, 성공 303 |
| `app/controllers/passwords_controller.rb` | 비밀번호 재설정(AUTH-8) — 요청 시 **사용자 열거 방지 응답**, update 성공 시 타 세션 전체 무효화 |
| `app/controllers/registrations_controller.rb` | **회원가입 신규 작성** — 이메일·비밀번호·확인 폼, 가입 즉시 세션 시작(이메일 인증 링크 없음), `welcome` 임시 안내 화면 |
| `app/controllers/landing_controller.rb` | *(수정 — 하단 참조)* |
| `app/channels/application_cable/connection.rb` | Action Cable 인증 식별(generator 산출 그대로) |
| `app/views/sessions/new.html.erb` | 로그인 폼(한글, 딥 그린 액센트) |
| `app/views/registrations/new.html.erb` | 회원가입 폼 |
| `app/views/registrations/welcome.html.erb` | 가입 완료 임시 안내(/app 후속 전까지) + 로그아웃 |
| `app/views/passwords/new.html.erb` | 재설정 요청(이메일 입력) |
| `app/views/passwords/edit.html.erb` | 새 비밀번호 설정(토큰 진입) |
| `app/mailers/passwords_mailer.rb` | 재설정 안내 메일 — 제목 「[받을돈] 비밀번호 재설정 안내」 |
| `app/views/passwords_mailer/reset{,.text}.html.erb` | 한글 본문 + 1회성 링크·만료 안내 |
| `test/fixtures/users.yml`, `test/models/user_test.rb` | generator 산출 — `email` 컬럼명에 맞게 기계 정리 |

### 수정

| 파일 | 변경 |
|:---|:---|
| `Gemfile` | bcrypt 주석 해제 + `bundle install` |
| `config/routes.rb` | 인증 블록 정리: `resource :session only:[new,create,destroy]`, `resource :registration only:[new,create]`, `get "welcome"`, `resources :passwords param::token only:[new,create,edit,update]`. URL 전부 명사형 리소스(동사 없음, §3.7) |
| `app/controllers/application_controller.rb` | `include Authentication` 삽입(generator) — 모든 컨트롤러 기본 인증 요구 |
| `app/controllers/landing_controller.rb` | `allow_unauthenticated_access` 추가 — 표면 ① 공개 유지(SURF-1) |
| `app/views/landing/index.html.erb` | 주 CTA 전환(§3 아래 상세) |
| `app/views/layouts/application.html.erb` | flash 표시를 레이아웃으로 단일화(규약 §3.6.6) — generator 뷰별 flash 블록 제거 |
| `db/schema.rb` | `db:migrate`로 갱신(users·sessions 테이블) |

## 2. Rule ID 구현 매핑

| Rule ID | 구현 |
|:---|:---|
| **AUTH-1** | 이메일/비밀번호 회원가입·로그인만 제공(Registrations·Sessions 컨트롤러, `has_secure_password` + bcrypt). OAuth 관련 코드 전무. 로그인 실패는 이메일/비밀번호 불일치 단일 안내문 |
| **AUTH-1.4** | `users.email` null: false + 고유 인덱스, `normalizes :email`(strip·downcase) — 이메일이 곧 로그인 아이디 |
| **AUTH-1.6** | `Authentication` concern — 세션 쿠키 `expires: 30.days`(AUTH-1.6 기본 30일), 재인증은 비밀번호 재로그인 |
| **AUTH-8** | `passwords` 리소스 + `PasswordsMailer`. 토큰은 has_secure_password 내장 generator token(15분 만료·비밀번호 변경 시 무효화 = 1회성). 재설정 성공 시 `@user.sessions.destroy_all`로 타 세션 강제 로그아웃. 요청 응답은 가입 여부 무관 동일(열거 방지) |
| **SURF-4** | 랜딩 ①의 가입 CTA가 `new_registration_path`로 실제 링크되는 ①→② 유일 진입점. 로그인 링크는 랜딩에 두지 않음(로그인 화면↔가입 화면 상호 링크만) |
| **LP-1** | 주 CTA 문구 「무료로 시작하기」 + 보조 문구 「무료 · 카드등록 없음 · 3분」 유지 |

보안·계약 준수: 컨트롤러 액션 10줄 이내, `params.expect` private 메서드(§3.3.3), 성공 303/실패 422, rate_limit(로그인·가입·재설정), `filter_parameter_logging` 기본값(`:passw`·`:email`·`:token`)으로 자격증명 로그 미출력.

## 3. 랜딩 CTA 변경 내역

| 이전 | 이후 |
|:---|:---|
| `<button disabled aria-disabled>` 「카카오로 시작하기」 | `<%= link_to new_registration_path %>` 「무료로 시작하기」(hover emerald-900) |
| 보조 문구 「무료 · 카드등록 없음 · 3분」 | 유지 |
| 안내문 「로그인은 곧 오픈됩니다」 | **삭제** |
| 보조 CTA 「작동 방식 보기」 비활성 | 유지(LP-3 미구현, 변경 없음) |

스타일(DESIGN-1/2/3 딥 그린·크림) 유지. `test/controllers/landing_controller_test.rb`는 미수정(삭제 금지 지시) — CTA 비활성 검증은 Tester가 Phase 7에서 갱신.

## 4. 자체 점검 결과

| 점검 | 결과 |
|:---|:---|
| `bin/rubocop` | **0 offenses** (43 files) |
| `bin/rails zeitwerk:check` | **통과** ("all is good") |
| `bin/rails db:migrate` | **성공** — CreateUsers·CreateSessions 마이그레이션, `db/schema.rb` 갱신 확인(`email` null:false + unique index) |
| `bin/rails routes` | 세션·가입·재설정·welcome·root 헬퍼 전부 확인(뷰/컨트롤러가 사용한 헬퍼와 일치) |

서버 기동·테스트 실행은 하지 않음(Phase 4·7·8 인계).

## 5. 후속 인계 노트 (Reviewer/Tester)

1. **generator 산출 컨트롤러 테스트 2개**(`test/controllers/sessions_controller_test.rb`, `passwords_controller_test.rb`)는 Rails 표준 계약(영문 메시지·최상위 `email_address` 파라미터·실패 redirect 가정) 기준이라 현 구현(한글 메시지, `email` 파라미터, 실패 422 render)과 불일치 — Phase 7에서 Rule 변경에 맞게 갱신 필요. fixtures·user_test는 `email`으로 정리 완료.
2. **재설정 메일 실발송 미연결**(계획서 D-2) — Action Mailer 기본 발송. 개발 환경에서는 `raise_delivery_errors = false`로 실패 무시되며, 메일 내용 확인은 `http://localhost:3000/rails/mailers/passwords_mailer` 프리뷰 사용.
3. **AUTH-1.3 최초 프로필 설정·/app 대시보드·AUTH-7 관리자** — 후속 작업(미구현 확정). `welcome` 화면이 임시 착지점.
4. `LandingController`에 `allow_unauthenticated_access` 1행 추가 — ApplicationController가 기본 인증 요구로 바뀌어 공개 표면 선언이 필요하게 됨(동작 변화 없음).

## 수정 이력 (Phase 6)

- **일자**: 2026-10-12
- **범위**: Phase 5 리뷰(`_workspace/05_review.md`, CHANGES_REQUESTED) 이슈 중 수정 대상 4건 최소 수정 — 관련 없는 코드 변경 없음

### 이슈별 수정 내역 (05_review.md 이슈 번호 ↔ 파일·변경 1:1)

| 이슈 | Severity·Rule ID | 수정 파일 | 변경 내용 |
|:---|:---|:---|:---|
| #1 | BLOCKER · AUTH-1.4 | `app/models/user.rb` | `validates :email, presence: true, uniqueness: true` 추가 — 중복 이메일 `save`가 DB 고유 인덱스 위반(`RecordNotUnique` → 500)에 도달하기 전 422 검증 실패로 전환. `normalizes :email`(strip·downcase)이 검증 전 적용되어 대소문자·공백 변형도 고유 인덱스와 정합 |
| #2 | CRITICAL · AUTH-1·AUTH-8 | `app/controllers/sessions_controller.rb:16`, `app/controllers/passwords_controller.rb:28` | `render :new/:edit, status: :unprocessable_entity, alert: "..."` → `flash.now[:alert] = "..."` 선할당 후 `render`로 변경. `:alert` 옵션은 `redirect_to`에서만 flash 처리되어 render에선 무시되던 결함 수정 — 로그인 실패 안내문(「이메일 또는 비밀번호가 올바르지 않습니다.」)·재설정 실패 안내문(「비밀번호를 확인해 주세요.」)이 레이아웃 `flash[:alert]` 블록(§3.6.6 단일 표시)에 실제 렌더됨 |
| #3 | CRITICAL · AUTH-1·규약 §3.3 | `app/views/registrations/new.html.erb`, `config/locales/en.yml` | 뷰 상단에 `@user.errors` 표시 블록 추가(`role="alert"`, 레이아웃 alert 팔레트와 동일한 red-50/red-600) — 422 재렌더 시 실패 원인이 사용자에게 노출됨. 기본 로캘 `:en` 유지, 이 폼에서 노출되는 User 오류 키 5종만 en.yml에 한글 문구 정의(`email.blank` 「이메일을 입력해 주세요.」·`email.taken` 「이미 등록된 이메일입니다」(구체 문구 유지 — 제품 결정)·`password.blank`·`password.password_too_long`·`password_confirmation.confirmation`). 전역 `errors.format`·모델 errors 전체 한글화는 하지 않음 |
| #5 | WARNING · AUTH-8 | `app/views/passwords_mailer/reset.html.erb:11`, `app/views/passwords_mailer/reset.text.erb:6` | `distance_of_time_in_words(0, ...)` 영어 출력(「15 minutes」) 삭제 → 「이 링크는 15분 후 만료되며,」 고정 한글 문구. 리뷰 #5의 File:Line이 HTML·텍스트 양쪽 본문을 가리켜 함께 수정(동일 이슈 범위) |

### 미수정 확정 (리뷰 판정 그대로)

- **이슈 #4**(WARNING, 재설정 토큰 접근 로그 평문) — 코드 수정 불필요 판정. 운영 단계 로그 접근통제·보존기간 관리로 대응, 위험 상승 시 lograge 등 경로 마스킹 검토.
- **이슈 #6**(WARNING 확인요청, 가입 중복 문구 일반화) — 「이미 등록된 이메일입니다」 구체 문구 유지로 제품 결정 확정. 수정 없음.

### 자체 점검 결과 (2026-10-12 실측)

| 점검 | 결과 |
|:---|:---|
| `bin/rubocop` | **0 offenses** (43 files) |
| `bin/rails zeitwerk:check` | **통과** ("all is good") |
| 검증 경로 (`bin/rails runner`) | 중복 이메일(정규화 변형 `  DUP-CHECK@X.Y  ` 포함, 트랜잭션 롤백으로 무흔적 실측) → `valid? = false` + 「이미 등록된 이메일입니다」 — 500(`RecordNotUnique`) 소멸 확인. 신규 이메일+비밀번호 조합은 `valid? = true`(가입 303 경로 회귀 없음) |
| 한글 오류 문구 렌더 | `email.blank` 「이메일을 입력해 주세요.」·`password_confirmation.confirmation` 「비밀번호 확인이 일치하지 않습니다.」·`password.password_too_long` 「비밀번호가 너무 깁니다. 72자 이내로 입력해 주세요.」 출력 확인 |

테스트 작성·서버 기동 없음(Phase 5b 재리뷰 → Phase 7 Tester 순서 준수).
