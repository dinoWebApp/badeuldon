# 05_review.md — Phase 5 코드 리뷰: 이메일/비밀번호 인증(OAuth 폐기 반전) + 랜딩 CTA

- **일자**: 2026-10-12
- **Reviewer**: AuthReviewer
- **리뷰 대상**: Phase 3 변경분(git status 기준) — 마이그레이션 2건(+schema), 모델 3건(user/session/current), 컨트롤러 5건(authentication concern·sessions·passwords·registrations·application/landing 수정), 뷰 8건(sessions·registrations·passwords·passwords_mailer·landing·layouts), routes, Gemfile(bcrypt), 케이블 connection, 테스트 산출물
- **기준**: PRD v0.18 §6.1(AUTH-1, 1.4, 1.6, 8)·§7(SURF-4)·§7.1(LP-1) 원문 > ARCHITECTURE_CONVENTION §3.3·§3.6·§3.7 > 승인 플랜 `_workspace/01_plan.md`. 코드 스타일은 Phase 4(RuboCop 0에러·43파일)가 처리했으므로 제외.
- **검증 방법**: 정적 리뷰 + Rails 8.1.4 gem 소스 대조(generator 원본 템플릿·`actionpack` render 옵션 처리·`activerecord` authenticate_by·`activemodel` secure_password 토큰 API) + 테스트 환경 통합 리퀘스트 실증(트랜잭션 롤백·테스트 DB 원상복구 확인)

## Status: CHANGES_REQUESTED

**BLOCKER 1건 · CRITICAL 2건 · WARNING 3건(중 1건 확인 요청)** — BLOCKER는 정상 사용자 입력 경로의 런타임 에러(500)로, 수정 후 재리뷰 대상이다. 나머지 전 항목 리뷰는 완료했으므로 본 보고서 전체를 인계한다.

---

## 이슈 목록

| # | Severity | Rule ID | File:Line | 설명 | 수정 제안 |
|---|----------|---------|-----------|------|-----------|
| 1 | **BLOCKER** | AUTH-1.4 | `app/models/user.rb:2-8` (유발 지점 `app/controllers/registrations_controller.rb:12-13`) | **이미 가입된 이메일로 회원가입 시 500 에러.** User 모델에 `validates :email, presence: true, uniqueness: true`가 없다. DB 고유 인덱스(`20261011232612_create_users.rb:8`)만 존재하므로, 중복 이메일 `save`가 모델 검증을 통과(`valid? => true` 실측)한 뒤 INSERT에서 `ActiveRecord::RecordNotUnique` 발생(실측: 모델 저장·`POST /registration` 중복 요청 모두 예외 발생 → 운영 환경 500). Rails 8.1 authentication generator 원본 `user.rb.tt`에도 검증이 없으나 generator는 회원가입 컨트롤러를 생성하지 않아 이 경로가 원본엔 존재하지 않음 — 회원가입을 추가한 본 프로젝트에서 결함이 노출됨. 이메일 정규화(normalizes)로 대소문자·공백 변형도 동일 충돌(실측: `"  REVIEW-DUP@example.com "` → 충돌). | `app/models/user.rb`에 `validates :email, presence: true, uniqueness: true` 추가(`normalizes`가 검증 전 다운케이스하므로 대소문자 불일치 우회 없음). 빈 이메일·공백도 동일 검증으로 422 처리됨. |
| 2 | **CRITICAL** | AUTH-1 (실패 단일 안내문)·AUTH-8 | `app/controllers/sessions_controller.rb:16`, `app/controllers/passwords_controller.rb:28` | **로그인·재설정 실패 안내문이 화면에 표시되지 않음.** `render :new, status: :unprocessable_entity, alert: "..."` — `:alert` 옵션은 `redirect_to`(`actionpack/metal/redirecting.rb`)에서만 flash로 처리되며 `render`는 미지원(8.1.4 actionpack 소스 확인: rendering 경로에 :alert/:notice/flash 처리 부재). 실측: `POST /session` 실패 → 422 재렌더되나 `flash={}`, 본문에 「이메일 또는 비밀번호가 올바르지 않습니다」 부재. AUTH-1이 요구하는 로그인 실패 단일 안내문이 사용자에게 도달하지 않고, AUTH-8 재설정 실패(`PasswordsController#update` 동일 패턴)도 무피드백. | `flash.now[:alert] = "..."` 할당 후 `render :new, status: :unprocessable_entity`(레이아웃 `flash[:alert]` 블록에 표시됨). 두 컨트롤러 모두 동일 수정. |
| 3 | **CRITICAL** | AUTH-1 (가입 흐름)·규약 §3.3(422 재렌더 계약) | `app/views/registrations/new.html.erb` (전체 — 오류 표시 블록 부재) | **회원가입 폼이 검증 오류를 전혀 표시하지 않음.** `@user.errors` 렌더링이 뷰에 없다. 이슈 #1 수정 후에도 중복 이메일·빈 비밀번호는 422로 폼이 재렌더되지만 오류 문구가 하나도 노출되지 않아 사용자는 실패 원인을 알 수 없다(무응답 실패). 규약 §3.3의 「실패 재렌더 422」 계약은 오류 안내를 동반하는 폼 교체가 전제 — 현재 렌더만 있고 안내가 없어 계약의 목적 미달. | 오류 표시 블록 추가(요약 `full_messages` 또는 필드별 `@user.errors[:email]`). 이때 기본 로캐일이 `:en`(`config/locales`에 en.yml만 존재)이므로 오류 문구가 영어로 출력됨 — 한국어 문구 locale 파일 또는 커스텀 메시지를 함께 적용. |
| 4 | WARNING | AUTH-8 (운영 보안) | 재설정 링크 URL 구조 (`config/routes.rb:6` — `/passwords/:token/edit`) | **재설정 토큰이 접근 로그 경로에 평문 기록됨.** Rails 기본 요청 로그 `Started GET "/passwords/<서명 토큰>/edit" ...` 에 토큰 원문 포함. `filter_parameter_logging`(:passw·:email·:token)은 파라미터만 필터하고 경로에는 미적용. Rails 표준 generator 동작이고 토큰은 15분 만료·1회성이라 실위험은 낮으나, 체크리스트 「로그에 토큰 평문 출력 금지」 관점에서 기록. | 운영 단계에서 로그 접근통제·보존기간 관리 시 본 항목 유의. 위험 상승 시 로그 포맷 제어(lograge 등)로 경로 마스킹 검토. 현 시점 코드 수정 불필요. |
| 5 | WARNING | AUTH-8 | `app/views/passwords_mailer/reset.html.erb:10-11`, `reset.text.erb:5-6` | **메일 만료 안내에 영어가 삽입됨.** `distance_of_time_in_words(0, @user.password_reset_token_expires_in)` — 기본 로캐일 `:en`이고 ko locale·rails-i18n 미설치(실측: `config/locales` = en.yml만)로 「이 링크는 15 minutes 후 만료되며」처럼 한글 문장 중간에 영어 출력. | 「15분 후 만료」 고정 문구로 교체(토큰 만료는 모델 설정에 따른 상수)하거나 ko locale 도입 시 해소. |
| 6 | WARNING (확인 요청) | AUTH-1 (계정 열거) | `app/models/user.rb` (이슈 #1 수정의 파생 효과) | **가입 중복 이메일 오류로 계정 존재 여부가 노출됨(수정 후).** 이슈 #1의 uniqueness 검증 추가 시 「이미 등록된 이메일」 오류가 존재 자체를 알린다. 단 PRD AUTH-1이 이메일 인증 링크 없는 **가입 즉시 활성화** + AUTH-1.4 고유 이메일을 확정한 이상 불가피한 트레이드오프 — 로그인 실패(단일 안내문·`authenticate_by` 타이밍 저항 소스 확인)와 재설정 요청(동일 응답)은 이미 누설 없음. 회원가입 rate_limit(10회/3분)이 대량 열거를 완충. | 구현 결함 아님 — 제품 판단 확인 요청. 오류 문구를 「이미 등록된 이메일입니다」 대신 「이 이메일로 가입된 계정이 있거나 입력이 올바르지 않습니다」 수준으로 일반화할지 여부만 결정하면 됨. |

### BLOCKER 처리 원칙

이슈 #1은 「BLOCKER 발견 시 즉시 보고·수정 후 재리뷰」 대상이다. 재리뷰는 #1 수정 커밋 기준으로 user.rb·registrations 흐름만 재검증하면 충분하다(#2·#3은 독립 수정 가능하며 재검 즉시 승격 가능).

---

## 검증했으나 이슈 아닌 항목 (위양성 방지 기록)

- **OAuth 잔존 코드 전무(AUTH-1 반전)**: `app/`·`config/`·`lib/`·`test/`·Gemfile 전역 검색 — omniauth/kakao/naver/google/oauth/social 관련 코드 0건(storage.yml의 GCS 주석 예시만 존재, 무관). Gemfile에는 bcrypt만 추가.
- **재설정 토큰 보안(AUTH-8)**: `generates_token_for :password_reset` 기반 — `secret_key_base` HMAC 서명 토큰으로 무차별 대입 사실상 불가, 만료 15분 실측(`password_reset_token_expires_in => 15 minutes`), 라운드트립 정상(`find_by_password_reset_token!` 복원 확인), 1회성은 토큰 서명에 `password_salt` 후미 10자가 포함되어 비밀번호 변경 시 자동 무효화. DB 평문 저장 구조 아님(서명 검증 방식).
- **재설정 완료 시 기존 세션 무효화(AUTH-8)**: `passwords_controller.rb:25` `@user.sessions.destroy_all` — 전 세션 강제 로그아웃 확인.
- **로그인 계정 열거 방지**: 실패 응답 「이메일 또는 비밀번호가 올바르지 않습니다」 단일 문구(어느 쪽이 틀렸는지 미노출). `User.authenticate_by`는 레코드 부재 시에도 bcrypt digest를 소모해 타이밍 기반 열거 저항(activerecord 8.1.4 소스 확인). ※ 단 안내문이 화면에 안 뜨는 것은 이슈 #2.
- **재설정 요청 열거 방지**: 가입 여부와 무관 동일 응답·동일 문구(`passwords_controller.rb:13-18`), 메일 발송은 `deliver_later`(비동기)라 타이밍 차 미미.
- **비밀번호 저장**: `password_digest`(bcrypt) 외 평문 처리 0건. `filter_parameter_logging`이 :passw·:email·:token 필터 — 로그로 자격증명·이메일·토큰 파라미터 유출 없음(경로 로깅은 이슈 #4로 별도 기록).
- **세션 처리**: 로그아웃 = 세션 레코드 destroy + 쿠키 삭제(`terminate_session`). 로그인/가입 시 신규 세션 레코드 발급(세션 고정 방어). 쿠키 `httponly: true`·`same_site: :lax`, 운영 `force_ssl` 전제 하 secure 보장. 세션 만료 30일 상수(`SESSION_COOKIE_MAX_AGE`, AUTH-1.6).
- **CSRF**: `ActionController::Base` 기본 보호 유지, 모든 폼 `form_with`(토큰 포함). 별도 비활성화 0건.
- **rate_limit**: 로그인·회원가입·재설정 요청 각 10회/3분 — 남용 방지 확인.
- **마이그레이션·스키마(AUTH-1.4)**: `users.email` null: false + 고유 인덱스, `password_digest` null: false, `sessions.user_id` FK·null: false — schema.rb와 일치 확인.
- **가입 즉시 활성화(AUTH-1)**: 이메일 인증 링크·확인 메일러 전무, 가입 성공 → 즉시 세션 시작 → 303 `/welcome`(통합 리퀘스트 실측).
- **이메일 정규화(AUTH-1.4)**: `normalizes :email`(strip+downcase) — 대소문자·공백 변형이 동일 계정으로 수렴함을 충돌 실측으로 간접 확인, 모델 테스트 존재.
- **params.expect**: 최상위 멀티키(`params.expect(:email, :password)`)·중첩(`user: [...]`) 모두 사용 — 로그인 실패 요청이 422로 정상 파싱·분기됨을 실측(파싱 실패 시 400·ParameterMissing).
- **오픈 리다이렉트 부재**: `return_to_after_authenticating`은 `request.url` 원본만 저장(외부 주입 불가).
- **welcome 화면 인증**: `allow_unauthenticated_access` 미선언 액션 — 비인증 접근 시 로그인 리다이렉트 구조 확인(액션 목록 `only: %i[new create]`).
- **ActionCable connection**: generator 표준 그대로(세션 쿠키 기반 식별) — 본 Phase 미사용, 이슈 없음.

## Rule ID 준수 매핑

| Rule ID | PRD 원문 요구 | 구현 검증 결과 | 판정 |
|:---|:---|:---|:---|
| **AUTH-1** | 이메일/비밀번호만·OAuth 폐기·Rails 표준 인증·이메일 인증 링크 없이 가입 즉시 활성화 | has_secure_password+bcrypt·세션 골격, OAuth 코드 0건, 가입 즉시 세션(실측 303→/welcome). **단 로그인 실패 단일 안내문이 사용자에게 미표시(이슈 #2)** — 안내문 자체는 존재하나 `render :alert` 무시로 미출력 | ⚠️ 부분 준수 (#2 수정 시 준수) |
| **AUTH-1.4** | 이메일 = 로그인 아이디(필수·고유) | 스키마 null:false+고유 인덱스, normalizes(strip·downcase). **모델 검증 부재로 고유성이 500으로 폭발(이슈 #1)** | ⚠️ 부분 준수 (#1 수정 시 준수) |
| **AUTH-1.6** | 세션 유지 기본 30일, 재인증 = 비밀번호 재로그인 | 세션 쿠키 `expires: 30.days` 상수화, 재인증 경로는 비밀번호 재로그인뿐(별도 재인증 매커니즘 없음) | ✅ 준수 |
| **AUTH-8** | 1회성·단기 만료 재설정 링크, 완료 시 기존 세션 무효화, 발송 서비스 미선정 전까지 개발 로그 발송 | signed 토큰 15분 만료(실측)·변경 시 무효화(1회성)·`sessions.destroy_all`, Action Mailer 기본(실발송 연결 없음 — 개발 로그/프리뷰). **만료 문구 영어 혼입(#5), 실패 안내문 미표시(#2)** | ⚠️ 부분 준수 (#2·#5 수정 시 준수) |
| **AUTH-1.1/1.2** | 폐기(결번) — 재사용 금지 | 카카오·네이버·구글 관련 코드 0건, Gemfile 무관련 젬 | ✅ 준수(폐기 확인) |
| **SURF-4** | ①→② 진입은 가입 CTA(이메일/비밀번호 회원가입) 단일 진입점 | 랜딩의 `<a>`는 `new_registration_path` 유일(CTA 「무료로 시작하기」), 로그인·재설정은 랜딩에 노출 없음(인증 화면 상호 링크만) | ✅ 준수 |
| **LP-1** | 주 CTA 「무료로 시작하기 — 무료 · 카드등록 없음 · 3분」 | CTA 문구 + 보조 문구 원문 일치, 이전 「카카오로 시작하기」 버튼·「로그인은 곧 오픈됩니다」 안내문 삭제 확인 | ✅ 준수 |
| **AUTH-7** | 관리자 계정 U1과 완전 분리 | 본 Phase 범위 외 — 관리자 코드 미구현 상태 확인(범위 준수) | — (범위 외·확인됨) |

## 보안·데이터 무결성 점검 요약

- [x] 소유권 격리: 인증 도메인만 존재(타 사용자 자원 라우트 없음). `/welcome` 인증 필요 확인
- [x] 비밀번호: 해시 저장 외 평문 처리 0건·로그 필터 확인(경로 토큰 로깅은 #4 기록)
- [x] 재설정 토큰: 만료 15분·1회성·HMAC 서명(무차별 대입 비실용) — #4 운영 유의
- [x] 계정 열거: 로그인 단일 문구 + authenticate_by 타이밍 저항 + 재설정 동일 응답 / 가입 중복은 #6(불가피·확인 요청)
- [x] 세션: 신규 발급(고정 방어)·로그아웃 파기·재설정 시 전 파기·30일 만료
- [x] CSRF 보호 유지·rate_limit 3개 소프트게이트
- [x] 마이그레이션 제약(null:false·고유 인덱스·FK)
- [x] XSS: `raw`/`html_safe` 미사용, ERB 기본 이스케이프(모든 뷰 확인)

## 아키텍처 준수 (ARCHITECTURE_CONVENTION)

- [x] §3.3 컨트롤러: 액션 본문 전부 10줄 이내, `params.expect` 화이트리스트, 성공 303/실패 422 규약 준수(단 422 재렌더의 오류 안내 부재 = 이슈 #2·#3)
- [x] §3.7 라우트: 명사형 리소스만(`resource :session/:registration`, `resources :passwords param: :token`), `welcome` 임시 액션은 플랜 승인 범위, URL 하드코딩 없음
- [x] §3.6 뷰: DB 쿼리·모델 호출 없음, 표현 로직 3줄 미만, flash는 레이아웃 단일 표시로 정리(generator 뷰별 flash 블록 제거 확인)
- [x] 의존 방향: Controller→Model(Authentication concern은 표준 구성), Model→Service 위반 없음
- [x] Zeitwerk: Phase 4 실측 통과 보고와 일치

## 범위 준수 (후속 제외 항목 — 미구현 상태 확인)

| 항목 | 상태 |
|:---|:---|
| AUTH-1.3 최초 프로필 설정 | 미구현 확인(가입 후 `/welcome` 임시 안내 — 플랜 승인 범위) |
| /app 대시보드 뼈대 | 미구현 확인 |
| 관리자(AUTH-7) | 미구현 확인 |
| 재설정 메일 실발송(EXT 미선정) | 미연결 확인(Action Mailer 기본·프리뷰 제공) — 플랜 D-2와 일치 |

범위 초과 구현(스코프 크리프) 없음.

## 이전 리뷰 이슈 추적 (`_workspace_prev/05_review.md`, 2026-10-08 랜딩 골격)

| 이전 이슈 | 현재 상태 |
|:---|:---|
| WARNING SURF-6 — 공유 레이아웃 importmap JS가 ①에 로드 | 후속 조건부 유지(표면 ② 자원 아직 없음). 본 Phase에서 레이아웃은 flash 단일화만 수정 — 이전 판정 그대로 유효, F-② 구축 시 재검 |
| WARNING DESIGN-3 — 인라인 폰트·Pretendard 미적용 | 후속 조건부 유지(랜딩 CTA 수정과 무관) |

중복 지적 없음.

---

## Tester에게 제안하는 중점 테스트 영역

> 현재 `test/controllers/`의 인증 테스트 2건은 generator 영문 계약(`email_address` 파라미터·실패 redirect 가정) 기준이라 현 구현(한글·`email`·422)과 불일치, 랜딩 테스트는 CTA 링크 전환으로 2건(「카카오로 시작하기」 버튼·`<a>` 0개 어설션) 확정 실패 — Phase 7 갱신 전제 아래 아래 시나리오를 신규/갱신 테스트로 작성할 것.

### 1. 회원가입 (이슈 #1·#3의 회귀 방지 핵심)
- **중복 이메일**: 동일 이메일 2회 가입 → 2번째는 **422 + 오류 문구 표시**(500 아님 — 수정 전 결함의 회귀 테스트로 필수)
- **정규화 동일성**: ` A@B.com ` 가입 후 `a@b.com` 로그인 성공 / 대소문자 변형 가입은 중복으로 422
- **빈 비밀번호·불일치 확인**: 422 + 오류 표시(수정 후)
- **가입 즉시 활성화**: 가입 303 → `/welcome`, 인증 없이 `/welcome` 직접 접근 → 로그인 리다이렉트
- 가입 폼 rate_limit: 11회째 요청 리다이렉트(10회/3분)

### 2. 로그인/로그아웃 (이슈 #2의 회귀 방지)
- **실패 안내문 표시**: 존재하지 않는 이메일·틀린 비밀번호 각각 → 422 + 「이메일 또는 비밀번호가 올바르지 않습니다」가 **화면에 렌더됨**(flash.now — 수정 전에는 표시 안 됨)
- **동일 응답**: 두 실패 케이스의 본문·상태코드 동일(열거 방지)
- **로그아웃 후 세션 무효**: 로그아웃 뒤 이전 `session_id` 쿠키로 `/welcome` 접근 → 로그인 리다이렉트
- rate_limit 10회/3분 초과 → 안내 리다이렉트
- CSRF 토큰 없는 `POST /session` → 거부

### 3. 비밀번호 재설정 (AUTH-8 전수)
- **열거 방지**: 미가입 이메일 요청 → 가입 이메일과 동일 303·동일 안내문
- **토큰 만료**: 15분 경과 토큰(또는 변조) → edit 접근 시 만료 안내 리다이렉트
- **1회성**: 재설정 완료 후 동일 토큰 재사용 → 거부
- **기존 세션 무효화**: 브라우저 A 로그인 상태에서 브라우저 B가 재설정 완료 → A의 세션으로 `/welcome` 접근 시 로그인 리다이렉트
- 재설정 성공 → 새 비밀번호 로그인 성공·구 비밀번호 로그인 실패
- 재설정 요청 rate_limit

### 4. 랜딩 CTA (SURF-4·LP-1 — 기존 랜딩 테스트 갱신)
- 주 CTA `<a href>` → `/registration/new` 이동(링크 활성화 — 기존 「`<a>` 0개」 어설션 교체)
- 문구 원문: 「무료로 시작하기」·「무료 · 카드등록 없음 · 3분」·헤드라인 유지
- 랜딩에 로그인·재설정 직접 링크 없음(단일 진입점)
- 인증 화면 상호 링크: 로그인↔가입↔재설정 이동 동작

### 5. 접근성·동작 확인
- 폼 터치 타깃·레이블 연결(`form.label` 대응) 육안 점검(DESIGN-6)
- 세션 쿠키 30일 만료 속성 확인(선택)

---

## 재리뷰 (Phase 5b)

- **일자**: 2026-10-12
- **Reviewer**: AuthReReviewer
- **대상**: Phase 6 수정분(`_workspace/03_implementation.md` 「수정 이력 (Phase 6)」) — 이슈 #1(BLOCKER)·#3(CRITICAL) 검증 중심, #2·#5는 코드 확인(+ #2는 실측 포함)
- **방법**: 정적 리뷰 + Rails 8.1.4 젬 소스 대조(activemodel `ConfirmationValidator`·`SecurePassword` — 오류가 추가되는 속성·i18n 키 확증) + 개발 DB 러너 실측(트랜잭션 롤백·무흔적: 모델 검증·통합 리퀘스트·오류 문구 5종 포함 18/18 PASS)

### Status: APPROVED

**최종 판정 근거**: BLOCKER #1 해소 실증(중복 가입 500→422 전환·정규화 정합), #2·#3·#5 검증 완료, #4·#6 미수정 확정(원 판정 유지). Phase 7 테스트 갱신 전제로 진행 가능.

### 이슈별 해소 여부

| # | Severity | 해소 | 검증 근거 |
|---|----------|------|-----------|
| 1 | BLOCKER / AUTH-1.4 | ✅ | `app/models/user.rb:7` `validates :email, presence: true, uniqueness: true`. 실측: 동일·변형(대소문자+공백) 이메일 모두 `valid? = false` + 「이미 등록된 이메일입니다」, `POST /registration` 중복 → **422 + 오류 렌더**(500 소멸). 신규 조합 `valid? = true`·오류 0건(정상 가입 회귀 없음). `normalizes`(strip·downcase)가 검증 전 적용 — 대소문자·공백 우회 없음(변형 이메일 접근값 정규화 결과 실측) |
| 2 | CRITICAL / AUTH-1·AUTH-8 | ✅ | `sessions_controller.rb:16`·`passwords_controller.rb:28` — `flash.now[:alert]` 선할당 후 `render`(레이아웃 `flash[:alert]` 블록 표시). 실측: 로그인 실패 POST → 422 + 「이메일 또는 비밀번호가 올바르지 않습니다.」 본문 렌더 |
| 3 | CRITICAL / AUTH-1·규약 §3.3 | ✅ | `registrations/new.html.erb:6-16` 오류 블록(`role="alert"`). 젬 소스 확증: 8.1.4 `ConfirmationValidator`는 `password_confirmation` 속성에 `:confirmation` 키로 오류 추가, `SecurePassword`는 `password`에 `:blank`·`:password_too_long` 추가 — en.yml 5개 키(`email.blank/taken`·`password.blank/password_too_long`·`password_confirmation.confirmation`) 경로 전부 정확. 실측: 5종 전부 한글 출력·영어 폴백 잔존 없음. 현 User 검증 세트에서 이 폼이 도달 가능한 오류는 5종이 전부(커버 완전). raw message(`errors.messages` 값) 렌더라 :en 로캐일의 영어 속성명 접두 노출 없음 — `full_messages` 미사용이 적절 |
| 5 | WARNING / AUTH-8 | ✅ | `reset.html.erb:11`·`reset.text.erb:6` — 「이 링크는 15분 후 만료되며,」 고정 한글 문구. `distance_of_time_in_words` 삭제로 영어 출력 경로 자체 소멸 |
| 4 | WARNING / AUTH-8 | — 미수정 확정 | 원 판정 유지(운영 단계 로그 접근통제·보존기간 관리, 위험 상승 시 lograge 검토) — 이상 없음 |
| 6 | WARNING(확인요청) / AUTH-1 | — 미수정 확정 | 「이미 등록된 이메일입니다」 구체 문구 유지 제품 결정 확정 — 구현 결함 아님 |

### 실측 상세 (2026-10-12, 개발 DB·트랜잭션 롤백)

- **모델**: 중복 이메일 valid? false·taken 한글(A1/A2), 변형 이메일 동일 판정·정규화 적용값(B1~B3), 오류 문구 5종 한글(C1/D1/E1/F1), 신규 조합 valid(G1) — **18/18 PASS**
- **통합 리퀘스트**: 중복(변형) 이메일 `POST /registration` → 422 + `role="alert"` 블록 + 「이미 등록된 이메일입니다」 본문 포함 + "has already been taken" 부재(H1~H4). 로그인 실패 `POST /session` → 422 + 실패 안내문 렌더(I1/I2)
- **무흔적 확인**: 롤백 후 `re5b.*` 잔여 0·users 0·sessions 0 (※ 러너 종료부의 QueryLogs/ExecutionContext 예외 노이즈는 `rails runner` 컨텍스트 산물 — 앱 결함 아님, 롤백 완료는 별도 실증)

### 범위 준수 (Phase 6)

- Phase 6 수정 파일(동일 타임스탬프 08:44:22 일괄 편집) 7개 == 수정 이력 문서와 **1:1 정확 대응**: `app/models/user.rb`·`app/controllers/sessions_controller.rb`·`app/controllers/passwords_controller.rb`·`app/views/registrations/new.html.erb`·`config/locales/en.yml`·`app/views/passwords_mailer/reset.html.erb`·`reset.text.erb` — 범위 외 소스 변경 없음
- 같은 시각 변경된 `app/assets/builds/tailwind.css`는 gitignored 빌드 산출물(자동 재빌드) — 소스 범위 외
- `test/test_helper.rb`(수정)·`test/test_helpers/session_test_helper.rb`(08:26, Phase 6 이전)는 Rails 8.1 인증 제너레이터 표준 산출물(템플릿과 **바이트 동일** 실측) — Phase 3 범위
- 그 외 작업 트리 변경 전부 Phase 3 문서 파일 목록 ∪ 하네스 산출물(`.omp/`·`_workspace*`·`_workspace_prev/`·PRD/AGENTS)에 소속

### 이슈 아닌 관찰 기록 (위양성 방지)

- **uniqueness TOCTOU 레이스**: 모델 uniqueness 검증은 SELECT-후-INSERT 구조상 동시 요청 교차 시 `RecordNotUnique`(500) 이론상 가능. 표준 Rails 구조이며 DB 고유 인덱스가 최종 방어, rate_limit(10회/3분) 완충 — 원 리뷰가 처방한 수정과 동일한 구현이므로 신규 이슈 아님. Phase 7은 순차 요청 시나리오로 커버(동시성 재현 테스트 불요)
- **오류 문구 5종 커버 완전성**: 향후 User 모델에 검증 추가 시 이 폼에 신규 오류 키가 생기면 en.yml 동기 필요 — 후속 단계 공지 사항(현 시점 결함 아님)

### Phase 7 Tester 최종 중점 영역 (갱신 — 원 §1·§2를 수정 완료 기준으로 확정)

> 원 「Tester에게 제안하는 중점 테스트 영역」 중 §3(재설정 전수)·§4(랜딩 CTA)·§5(접근성)은 그대로 유효. 아래 §1·§2만 확정 갱신.

**1. 회원가입 회귀(이슈 #1·#3 — 최우선)**
- 동일 이메일 2회 가입 → 2번째 **422 + 「이미 등록된 이메일입니다」 화면 표시**(500 아님 — 수정 전 결함 회귀 방지)
- 대소문자·공백 변형: ` A@B.com ` 가입 후 `a@b.com` 로그인 성공 / 변형 이메일 재가입은 중복 422
- 빈 이메일·빈 비밀번호·확인 불일치·73자 비밀번호 → 각각 422 + 대응 한글 문구 표시(「이메일을 입력해 주세요.」·「비밀번호를 입력해 주세요.」·「비밀번호 확인이 일치하지 않습니다.」·「비밀번호가 너무 깁니다. 72자 이내로 입력해 주세요.」)
- 정상 가입 → 303 `/welcome`, 인증 없는 `/welcome` 직접 접근 → 로그인 리다이렉트
- 가입 rate_limit: 11회째 요청 리다이렉트(10회/3분)

**2. 로그인/로그아웃(이슈 #2 회귀 방지)**
- 미가입 이메일·틀린 비밀번호 각각 → 422 + 「이메일 또는 비밀번호가 올바르지 않습니다.」 **화면 렌더**(flash.now — 수정 전 미표시 결함 회귀 방지)·두 케이스 본문·상태코드 동일(열거 방지)
- 로그아웃 후 이전 세션 쿠키로 `/welcome` 접근 → 로그인 리다이렉트
- rate_limit 10회/3분 초과 → 안내 리다이렉트, CSRF 토큰 없는 `POST /session` → 거부
