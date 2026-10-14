# 03 구현 내역 — 로그인 사용자 랜딩→서비스 원클릭 복귀

- 날짜: 2026-10-15
- 담당: LoginUxDeveloper
- 기준: 오케스트레이터 구현 지시서(3건), `_workspace/01_plan.md`
- 관련 규칙: SURF-4(①→② 진입), SURF-1(랜딩 비로그인 공개 유지), AUTH-1

## 1. 변경 파일

| 파일 | 변경 |
|:---|:---|
| `app/views/layouts/landing.html.erb` | 헤더에 `authenticated?` 분기 추가 — 로그인 시 「대시보드로 가기」 링크(`app_root_path`) 표시 |
| `app/controllers/registrations_controller.rb` | `before_action :redirect_if_authenticated, only: %i[new create]` + private 가드 메서드 추가 |
| `app/controllers/sessions_controller.rb` | `before_action :redirect_if_authenticated, only: :new` + private 가드 메서드 추가 |

## 2. 수정 내역 (지시 3건 대응)

### 1) 랜딩 헤더 — `layouts/landing.html.erb`
- `authenticated?` true → 헤더 우측에 「대시보드로 가기」(`app_root_path`). 디자인 톤은 히어로 주 CTA와 동일한 emerald 계열(배경 `emerald-800`·hover `emerald-900`·포커스 링 `emerald-700`).
- false → 기존 그대로(워드마크만 노출, 링크 없음). 비로그인 ①→② 진입은 히어로 가입 CTA 단일(SURF-4) 유지.
- 레이아웃 상단 주석을 조건부 표시에 맞게 갱신.
- **불변 유지 확인**: 히어로 주 CTA(`_hero.html.erb`의 「무료로 시작하기」→`new_registration_path`)는 건드리지 않음. 로그인 사용자가 클릭하면 2)번 가드가 `/app`으로 되돌림.

### 2) 가입 화면 리다이렉트 — `RegistrationsController`
- `new`·`create` 모두 `redirect_to app_root_url, status: :see_other` (303).
- 구현: 액션 초입 분기 대신 `before_action :redirect_if_authenticated, only: %i[new create]` — 액션 본문은 그대로 유지(10줄 이내 규칙).
- `before_action`을 `rate_limit` 선언 **앞에** 배치해 로그인 사용자의 `create` 요청이 rate limit 카운트를 소모하지 않도록 함.
- private 가드: `redirect_to app_root_url, status: :see_other if authenticated?`

### 3) 로그인 화면 리다이렉트 — `SessionsController`
- `new`만 가드. `create`는 불변(재로그인 시도 정상 처리) — `only: :new`.
- 가드 메서드·배치는 2)와 동일 패턴.

## 3. 구현 판단 사항 (지시서 대비 실제 코드 차이)

- 지시서의 `logged_in?` 헬퍼는 코드베이스에 존재하지 않음 → Authentication concern의 기존 `helper_method :authenticated?`를 사용(두 번째 컨벤션 생성 방지). `authenticated?`는 `resume_session`을 반환하므로 쿠키는 있으나 세션이 만료·파기된 경우 falsy → 비로그인 UI 정상 노출.
- 지시서는 헤더에 기존 「무료로 시작하기」·「로그인」 링크가 있다고 기술했으나 실제 헤더는 워드마크만 노출(SURF-4 주석 확인) → 비로그인 분기는 현상 유지, 링크를 새로 추가하지 않음(추가 시 SURF-4 단일 진입 위반이므로).
- 리다이렉트 대상은 지시서대로 `app_root_url` 사용(`after_authentication_url`의 기존 패턴과 일치), 헤더 링크는 `app_root_path`.

## 4. 자체 점검 결과

- `bin/rubocop`: **0 위반** (101 files inspected, no offenses)
- `bin/rails zeitwerk:check`: **통과** (test/mailers/previews 경고는 기존 상태, 무관)
- `bin/rails test`: **366 runs, 2296 assertions, 0 failures, 0 errors, 0 skips**

### 실패 예상 테스트
- **없음 (실측 0 실패)**. 예상 근거: 랜딩·인증 화면 관련 기존 테스트는 전부 비로그인 컨텍스트다.
  - `LandingControllerTest` — 모두 `get root_url` 비로그인 호출. 「a 요소는 가입 진입이 유일」(SURF-4) 테스트도 비로그인 렌더 기준이라 신규 링크가 렌더되지 않아 통과.
  - `SessionsControllerTest` / `RegistrationsControllerTest` — `GET /session/new`, `GET /registration/new` 및 각종 `post` 모두 비로그인. 로그인 상태에서 인증 화면 접근 케이스는 기존 테스트에 없음 → 갱신 대상 0건.
- 테스트 작성은 지시상 금지(수정 없음).

## 5. Rule ID 매핑

| 변경 | 근거 |
|:---|:---|
| 헤더 로그인 분기 | UX 결함 수정 지시 — SURF-4는 비로그인 진입 규칙으로 유지(비로그인 시 링크 없음) |
| 가입·로그인 화면 303 리다이렉트 | UX 결함 수정 지시 — 로그인 사용자 /app 원클릭 복귀 |
| 랜딩 비로그인 접근 유지 | SURF-1 (변경 없음) |
