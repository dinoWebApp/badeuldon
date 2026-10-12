# 03_implementation.md — Phase 3 구현 보고: /app 대시보드 뼈대(표면 ② 셸) + 레이아웃 분리 + welcome 소멸

- **일자**: 2026-10-12
- **범위**: `_workspace/01_plan.md` A절 전체 (A-1 레이아웃 분리 / A-2 /app 대시보드 셸 / A-3 플로우 정리)
- **기준**: PRD v0.18.2 §6.9(DASH-1/2/4)·§6.2(ONB-1)·§7(SURF-3/4/6)·§7.3(DESIGN-2/4/5/6), AGENTS.md 「UI 품질 기준」

## 1. 변경 파일 목록

### 신규 생성 (8)

| 파일 | 요약 |
|:---|:---|
| `app/views/layouts/_head.html.erb` | 표면 공통 `<head>` 파셜 — title/description/noindex(SURF-3)·csrf·Pretendard·CSS 파이틀. 3개 레이아웃이 함께 사용(중복 제거) |
| `app/views/layouts/_flash.html.erb` | 플래시 파셜(`p#notice`/`p#alert` 불변) — application·landing·app 레이아웃 공용 |
| `app/views/layouts/landing.html.erb` | 표면 ① 전용 레이아웃 — 상단 바(워드마크, 링크 없음 = SURF-4 단일 진입 유지) + LP-10 푸터. main은 폭 제약 없음(섹션 파셜이 각자 풀블리드 배경·컨테이너 관리) |
| `app/views/layouts/app.html.erb` | 표면 ② 전용 레이아웃 — 데스크톱 고정 사이드바(w-64, `lg:pl-64` 본문 오프셋) + 모바일 해시버거 드로어 + 헤더(표시명·로그아웃 `button_to` DELETE + turbo_confirm) |
| `app/controllers/app/base_controller.rb` | 표면 ② 공통 베이스 — `layout "app"` + `require_complete_profile`(AUTH-1.3 표시명 미설정 → `edit_app_profile_path` 리다이렉트). 인증은 ApplicationController 가드 상속 |
| `app/controllers/app/dashboards_controller.rb` | `App::DashboardsController#show` — `@user = Current.user` 설정만(액션 2줄). 실데이터 조회 없음(F-INV 이후) |
| `app/views/app/dashboards/show.html.erb` | 대시보드 셸 — DASH-1 요약 카드 3종 / DASH-2 오늘의 액션 / ONB-1 훅 / DASH-4 목록 + DESIGN-2 상태색 범례. 전 구역 빈 상태 |
| `app/helpers/app/base_helper.rb` | `app_nav_items`(사이드바 내비·경로 기반 활성 판정)·`app_nav_link_classes`(활성 = 딥 그린)·`dash_summary_cards`(요약 카드 3종 + 상태색 점) |
| `app/javascript/controllers/sidebar_controller.js` | 모바일 드로어 토글 Stimulus 1개 — `toggle`/`open`/`close` + `aria-expanded` 동기화. UI 동작만(비즈니스 로직 없음) |

### 수정 (8)

| 파일 | 변경 |
|:---|:---|
| `app/views/layouts/application.html.erb` | 공통 기반만으로 축소 — head/flash 파셜화, 전역 헤더 바 제거(크롬은 표면별 레이아웃으로 이관). 인증 화면은 계속 이 레이아웃 사용 |
| `app/controllers/landing_controller.rb` | `layout "landing"` 추가 — 표면 ① 전용 레이아웃 적용(SURF-6) |
| `app/views/landing/_closing.html.erb` | LP-10 푸터 요소를 랜딩 레이아웃으로 이동 — 파셜은 최종 CTA 섹션만 유지. 마크업·문구·CTA 링크 불변 |
| `app/controllers/app/profiles_controller.rb` | `App::BaseController` 상속 + `skip_before_action :require_complete_profile`(이 화면 자체가 미완료 사용자의 완료 화면). 프로필 저장 성공 리다이렉트 `welcome_path` → `app_root_path` |
| `app/controllers/registrations_controller.rb` | `welcome` 액션 제거. 가입 리다이렉트 `welcome_path` → `edit_app_profile_path`(AUTH-1.3 최초 프로필 설정 직행 — 가입 계정은 표시명이 항상 공백) |
| `app/controllers/concerns/authentication.rb` | `after_authentication_url` 폴백 `root_url` → `app_root_url`(프로필 완료 사용자 로그인 → /app). 미설정 → 프로필 우선 로직 불변 |
| `config/routes.rb` | `get "welcome"` 제거. `namespace :app`에 `root to: "dashboards#show"` 추가(`app_root_path` = `/app`). profile resource 불변 |
| `app/helpers/application_helper.rb` | `NOINDEX_PATH_PREFIXES`에서 `/welcome` 제거(경로 소멸). `show_login_link?` 제거(전역 헤더 바 소멸로 미사용 코드). `noindex?`·`step_icon_path` 불변 |
| `public/robots.txt` | `Disallow: /welcome` 제거(경로 소멸). `/app`·`/b/`·`/admin` 차단 불변(SURF-3 — 사전 확인 후 유지) |

### 삭제 (1)

| 파일 | 사유 |
|:---|:---|
| `app/views/registrations/welcome.html.erb` | welcome 임시 화면 소멸 — 프로필 완료·로그인 목적지를 /app 셸로 대체(플랜 A-3·결정 #1) |

## 2. 레이아웃 분리 다이어그램 (SURF-6)

```
layouts/_head.html.erb (공통: title·noindex·csrf·Pretendard·CSS·importmap)
layouts/_flash.html.erb (공통: p#notice / p#alert)
        │
        ├── application.html.erb ── 공통 기반만(크롬 없음)
        │       └── 인증 화면: sessions/new · registrations/new · passwords/new·edit
        │
        ├── landing.html.erb ── 표면 ① (LandingController: layout "landing")
        │       ├── 상단 바: 워드마크만(링크 0 — SURF-4 ①→② 가입 CTA 단일)
        │       ├── main(폭 제약 없음 — 섹션 파셜이 풀블리드 배경·컨테이너 관리)
        │       └── LP-10 푸터(_closing 파셜에서 이동)
        │
        └── app.html.erb ── 표면 ② (App::BaseController: layout "app")
                ├── aside#app-sidebar: 대시보드(app_root, 활성) · 청구서(준비 중) · 거래처(준비 중) · 설정(edit_app_profile 실링크)
                │     데스크톱 fixed w-64 · 모바일 hidden → 해시버거 토글 드로어(Stimulus sidebar 1개)
                ├── header: 모바일 해시버거+워드마크 / 표시명(Current.user) · 로그아웃 button_to DELETE /session + turbo_confirm
                └── main(max-w-6xl): flash + yield
```

- 표면 ③ 뷰어(/b/*)·④ 관리자(/admin)는 전용 레이아웃이 필요한 시점(VIEW-8 — 앱 내비 공유 금지)에 별도 분리. 현재 미구현으로 application 폴백.
- 부수 효과(의도): 랜딩 main의 `max-w-6xl` 이중 구속이 해소되어 섹션 파셜의 `section.bg-white/bg-cream` 풀블리드 배경이 전체 폭으로 렌더링된다(파셜이 각자 `mx-auto max-w-6xl` 컨테이너를 이미 보유 — 시각 개선, 콘텐츠 불변).

## 3. Rule ID 매핑

| Rule ID | 구현 |
|:---|:---|
| **DASH-1** | 요약 카드 3종(미수 총액 · 연체 건수·금액 · 7일 내 만기) — DESIGN-5 큰 숫자 카드 골격(text-4xl tabular-nums 슬롯). F-INV 데이터 전까지 빈 상태: 수치 슬롯은 대시(—, aria-hidden) + 「청구서를 발행하면 여기에 표시됩니다」. **거짓 0원 표기 없음**(02_prd_update 결정) |
| **DASH-2** | 「오늘의 액션」 섹션 — 카드형 골격(DESIGN-5). 빈 상태: 「오늘 할 일이 없습니다」 + 발행 시 발송 예정·약속일 도래 등이 카드로 표시된다는 안내 |
| **DASH-4** | 청구서 목록 영역 + 기본 정렬 안내 — 빈 상태 문구 「발행된 청구서는 연체일이 긴 순서부터 표시됩니다」(정렬 구현 자체는 F-INV 인계) |
| **ONB-1** | 중앙 훅 — 딥 그린 밴드 안 「첫 청구서 발행하기」 CTA(disabled + 「준비 중 — 청구서 기능과 함께 열립니다」 배지) + 3분 플로우 안내 문구(프로필 표시명·계좌 자동 채움, 품목 예시, 만기일 기본 30일 — ONB-1 원문 3요소 반영). F-INV 시점에 disabled 해제만으로 활성화 |
| **SURF-3** | `/app` noindex(기존 `NOINDEX_PATH_PREFIXES` 유지) + robots.txt `Disallow: /app`(사전 차단 확인 후 유지). `/welcome` 항목은 경로 소멸로 제거(청소) |
| **SURF-4** | 표면 간 이동 규칙 유지 — 랜딩 레이아웃 상단 바는 링크 없는 워드마크(①→② 가입 CTA 단일 불변, 기존 `a[href=new_registration_path]` 전체 순수성 테스트 통과). 앱(②)→① 링크 없음 |
| **SURF-6** | 레이아웃 3분리로 앱 자원(사이드바 UI·Stimulus 마크업·내비 헬퍼)과 랜딩 렌더를 **마크업·의존 참조 수준**에서 분리. 단, JS·CSS 번들은 공유 — 공통 `_head`가 `javascript_importmap_tags`를 내보내고 `index.js`가 `eagerLoadControllersFrom`으로 컨트롤러 전체를 즉시 로드하므로 `sidebar_controller`는 표면 ①에서도 다운로드되며, CSS도 단일 tailwind 빌드를 공유한다. 현재 규모(컨트롤러 3개·CSS 34KB)에서 SURF-6 예산 영향은 없음 — 번들 분리(표면별 컨트롤러 로드·CSS 분할)는 기술 부채로 등록(「수정 이력 (Phase 6)」 #3) |
| **DESIGN-2** | 상태색 3종 반영 — DASH-4 범례(연체 주황 `bg-orange-500` / 대기·약속 중립 `bg-stone-400` / 수금 완료 녹색 `bg-green-600`) + DASH-1 카드 브랜딩 점(연체 카드 주황·나머지 중립). 크림 배경+딥 그린 액센트는 기존 토큰 계승 |
| **DESIGN-4** | 표면 ② 강도 — 정보 밀도 중심·장식 최소(섹션 h2 위계·카드·빈 상태 텍스트 중심, 장식은 ONB-1 밴드 한 곳) |
| **DESIGN-5** | 상태 시각화 골격 — 요약 수치는 큰 숫자 카드, 오늘의 액션은 카드형. shadcn dashboard-01의 사이드바+카드 표준 골격만 취함(복제 금지 원칙 준수) |
| **DESIGN-6** | 접근성 — 터치 타깃: 내비 링크 `min-h-11`·해시버거 `h-11 w-11`·로그아웃 `min-h-11`·드로어 배경 button. 사이드바 내비 `aria-current="page"`, 드로어 `aria-controls`+`aria-expanded` 동기화, 배지 텍스트 stone-500(이전 리뷰 #4 저대비 기준 준수) |
| **AUTH-1.3** | 프로필 미완료(표시명 공백) 사용자는 /app 어떤 경로로 접근해도 최초 프로필 설정 화면으로 안내(`App::BaseController#require_complete_profile`) — 로그인 직후 리다이렉트(기존)와 직접 접근(신규) 모두 커버. 프로필 화면은 가드 skip |
| **LP-10** | 푸터를 랜딩 레이아웃 하단 고정 크롬으로 이관 — 마크업·문구(문의 채널·© 2026 받을돈) 불변, 기존 LP-10 테스트 통과 유지 |
| **LP-12** | 신규 문구 전체 — 확정 보장·압박·추심 오인 표현 없음(§3.1 문구 목록) |

## 3.1 신규 작성 문구 목록 (Reviewer 집중 검증 대상)

- 대시보드 헤더: 「{표시명}님의 수금 현황입니다.」
- DASH-1 빈 상태(3카드 공통): 「청구서를 발행하면 여기에 표시됩니다.」
- DASH-2 빈 상태: 「오늘 할 일이 없습니다」 / 「첫 청구서를 발행하면 오늘 발송 예정·약속일 도래 같은 처리할 일이 카드로 표시됩니다.」
- ONB-1: 「3분이면 첫 청구서를 발행합니다」 / 「프로필의 표시명·계좌가 자동으로 채워지고, 품목 예시와 만기일(기본 30일)은 몇 번의 클릭으로 완성됩니다.」 / CTA 「첫 청구서 발행하기」(disabled) / 배지 「준비 중 — 청구서 기능과 함께 열립니다」
- DASH-4 빈 상태: 「아직 발행된 청구서가 없습니다」 / 「발행된 청구서는 연체일이 긴 순서부터 표시됩니다.」 / 범례: 「연체 · 대기·약속 · 수금 완료」
- 사이드바: 「대시보드 · 청구서(준비 중) · 거래처(준비 중) · 설정」 / 로그아웃 확인 문구 「로그아웃하시겠습니까?」

## 4. 리다이렉트 변경 전후 + 실패 예상 테스트

### 4.1 리다이렉트 변경 전후

| 시점 | 이전 | 이후 | 근거 |
|:---|:---|:---|:---|
| 가입 직후 (`RegistrationsController#create`) | `welcome_path`(임시 안내 화면) | `edit_app_profile_path`(AUTH-1.3 최초 프로필 설정) | 플랜 A-3 — welcome 소멸, 가입 직후는 기존대로 프로필 리다이렉트 |
| 프로필 저장 완료 (`App::ProfilesController#update`) | `welcome_path`(임시 완료 화면) | `app_root_path` = **/app** | 플랜 A-3 — /app가 welcome 역할 대체 |
| 로그인 — 프로필 미완료 (`after_authentication_url`) | `edit_app_profile_url` | **불변** | AUTH-1.3 프로필 우선 로직 유지 |
| 로그인 — 프로필 완료 (`after_authentication_url` 폴백) | `root_url`(= 랜딩 ①) | `app_root_url` = **/app** | 플랜 A-3 — 완료 사용자는 랜딩이 아닌 대시보드 진입 |
| return_to 있음 + 프로필 완료 | return_to | **불변**(return_to 우선) | 기존 동작 유지 |
| `/app` 직접 접근 — 프로필 미완료 | (프로필 화면만 존재, 해당 없음) | `edit_app_profile_path`(신규 가드) | AUTH-1.3 — 표면 ② 진입 일괄 안내 |
| `GET /welcome` | 임시 안내 화면(인증 필요) | **라우트 소멸**(404) | 플랜 A-3 |

### 4.2 §4 실패 예상 테스트 목록 — 실측 확인 (Phase 7 Tester 갱신 대상)

**`bin/rails test` 실측: 83 runs, 476 assertions, 2 failures, 14 errors, 0 skips — 실패 16건 전부 하기 목록과 일치. 기존 테스트 파일은 수정하지 않음(Phase 7 인계).**

실패 유형 3종: (a) `welcome_path`/`welcome_url` 헬퍼 소멸 NameError (b) 리다이렉트 대상 변경 (c) robots.txt `/welcome` 행 제거.

| # | 테스트 | 파일:행 | 실패 원인 | 갱신 방향(제안) |
|:---|:---|:---|:---|:---|
| 1 | 정상 가입은 303으로 세션을 시작하고 welcome으로 안내한다 (AUTH-1) | registrations_controller_test.rb:13 | 가입 리다이렉트 → 프로필 설정 | `assert_redirected_to edit_app_profile_path` + notice 확인 |
| 2 | 가입으로 시작한 세션으로 /welcome에 접근할 수 있다 (AUTH-1) | registrations_controller_test.rb:28 | /welcome 소멸 | 테스트 목적(가입 세션 유효)에 맞게 /app 접근으로 치환 또는 삭제 |
| 3 | 인증 없이 /welcome 접근은 로그인 화면으로 리다이렉트된다 | registrations_controller_test.rb:37 | /welcome 소멸 | 대상 경로를 /app 등 인증 표면으로 치환 또는 삭제 |
| 4 | 변형 이메일로 가입하면 정규화된 이메일로 로그인된다 (AUTH-1.4) | registrations_controller_test.rb:58 | `welcome_path` NameError | 첫 어설션을 `edit_app_profile_path`로 |
| 5 | 6필드 저장은 303으로 완료 화면에 안내하고 6컬럼 전부 DB에 반영된다 (AUTH-1.3) | app/profiles_controller_test.rb:77 | 저장 리다이렉트 → /app | `assert_redirected_to app_root_path` + notice/h1 확인 |
| 6 | 필수 2필드만으로 저장하며 선택 4필드는 공백으로 남는다 (AUTH-1.3) | app/profiles_controller_test.rb:62 | `welcome_url` NameError | `app_root_url`로 |
| 7 | 프로필 업데이트는 로그인 사용자에게만 적용되고… (소유자 스코프) | app/profiles_controller_test.rb:123 | `welcome_url` NameError | `app_root_url`로 |
| 8 | welcome 미설정 분기에 프로필 설정 안내 CTA가 노출된다 (AUTH-1.3) | app/profiles_controller_test.rb:109 | /welcome 소멸 | 삭제(해당 화면 소멸) — 필요 시 /app 프로필 미완료 가드 테스트로 대체 |
| 9 | welcome 완료 분기에 프로필 수정 링크가 노출된다 (AUTH-1.3) | app/profiles_controller_test.rb:116 | /welcome 소멸 | 삭제(해당 화면 소멸) |
| 10 | 프로필 완료 후 재로그인하면 root로 진입한다 (AUTH-1.3 분기) | app/profiles_controller_test.rb:98 | 저장 리다이렉트(`welcome_url`) + 재로그인 리다이렉트(`root_url`) 모두 변경 | 두 어설션을 `app_root_url`로 |
| 11 | 재설정 완료 시 기존 세션은 전부 무효화된다 (AUTH-8) | passwords_controller_test.rb:112 | `welcome_path` NameError(인증 표면 접근 수단으로만 사용) | 임의 인증 필요 경로(예: `/app`)로 치환 |
| 12 | 프로필이 완료된 사용자 로그인은 root로 진입한다 (AUTH-1.3 분기) | sessions_controller_test.rb:25 | 로그인 폴백 → /app | `assert_redirected_to app_root_url` + 테스트명 갱신 |
| 13 | 로그인 전 방문 예정 페이지가 있어도 프로필 미설정이면 설정 화면이 우선한다 (AUTH-1.3) | sessions_controller_test.rb:31 | `welcome_path` NameError(return_to 세팅용 경로) | return_to용 경로를 /app 등으로 치환 |
| 14 | 로그아웃은 세션을 파기해 이전 쿠키로 재진입할 수 없다 (AUTH-1) | sessions_controller_test.rb:80 | `welcome_path` NameError(재진입 검증용 경로) | 재진입 검증 경로를 /app 등으로 치환 |
| 15 | welcome 화면도 noindex 메타를 출력한다 (SURF-3) | integration/surf3_indexing_test.rb:16 | /welcome 소멸 | 삭제 — 표면 ② noindex는 /app/profile 케이스(#3행 전 테스트)가 계속 커버. /app 대시보드 noindex 신규 테스트 권장 |
| 16 | robots.txt는 대시보드·뷰어·관리자·welcome 경로를 차단한다 (SURF-3) | integration/surf3_indexing_test.rb:31 | `Disallow: /welcome` 행 제거 | welcome 행 어설션 제거(나머지 3행 유지) |

- **통과 유지(67건)**: 랜딩 전체(LP-1~8·10 — 푸터는 레이아웃으로 이동했지만 `assert_select "footer"`는 응답 본문 전체 대상이라 통과), 프로필 edit/소유권/오류, 세션 발급·만료, AUTH-8 본체, SURF-3 나머지(noindex 메타·robots 3행), 소유자 스코프 등 — **레이아웃 분리·사이드바 신설로 인한 회귀 0건**.

## 5. 자체 점검 결과 (2026-10-12 실측)

| 점검 | 결과 |
|:---|:---|
| `bin/rubocop` | **0 offenses** (53 files inspected) |
| `bin/rails zeitwerk:check` | **통과** — "Otherwise, all is good!" (test/mailers/previews 경고는 Rails 스캐폴드 기본 안내로 기존 존재) |
| `bin/rails test` | **83 runs, 476 assertions, 2 failures, 14 errors, 0 skips** — 실패 16건 전부 §4.2 목록(welcome 소멸·리다이렉트 변경·robots 행 제거)과 일치. 신규 기능으로 인한 실패 0건 |
| `bin/rails routes` | `app_root GET /app → app/dashboards#show`, `edit_app_profile GET /app/profile/edit`, `root GET / → landing#index` — welcome 라우트 소멸 확인 |
| 마이그레이션 | 없음(플랜대로) — `db/schema.rb` 변경 없음 |
| 서버 기동·테스트 작성 | 하지 않음(지시 준수 — Phase 4·7 인계) |

## 6. 후속 인계 노트 (Reviewer/Tester)

1. **Phase 7**: §4.2의 16건 갱신 + (권장) 신규 테스트 — /app 비인증 302·미완료 가드 리다이렉트·DASH 빈 상태 문구·사이드바 내비·noindex·robots 3행.
2. **DASH-1/2 실데이터 전환점**: `App::DashboardsController#show`에서 F-INV 집계 주입 시 빈 상태 블록을 조건 분기로 교체하면 된다(뷰는 `dash_summary_cards` 헬퍼만 참조).
3. **첫 발행 CTA 활성화(F-INV 시점)**: `show.html.erb` ONB-1 섹션의 disabled `button`을 실링크로 교체하는 단일 지점.
4. **사이드바 준비 중 메뉴(청구서·거래처)**: F-INV·F-CLIENT 구현 시 `app_nav_items`(App::BaseHelper)에서 `disabled: true`를 제거하고 path를 연결하면 된다.
5. **모바일 드로어**: `sidebar_controller.js`는 UI 토글만 담당(규약 준수). Esc 닫기·포커스 트랩은 후속 접근성 고도화 과제로 남김(현재 배경 탭 닫기 + 링크 클릭 닫기).
6. **Pretendard CDN**은 기존 결정 유지(셀프호스팅은 기술 부채 목록 기존 항목).
7. 레이아웃 분리로 `app/assets/builds/tailwind.css`에 신규 유틸리티(lg:flex·w-64·bg-orange-500 등)가 필요 — Phase 4 빌드(`bin/dev` watch)에서 재생성됨. 이번 실측은 소스 클래스 기준.

## 수정 이력 (Phase 6) — Phase 5 리뷰 WARNING 3건 최소 수정

- **일자**: 2026-10-12
- **범위**: `_workspace/05_review.md` 이슈 #1~#3과 1:1 대응. 기존 테스트 파일 수정 없음(Phase 7 인계 대기)

### #1 인증 화면 브랜드 크롬 복원 (리뷰 #1 — UI 품질 기준)

- **변경**: `app/views/layouts/application.html.erb` — 폼 h1 위에 링크 없는 중앙 워드마크 「받을돈」 미니 크롬 추가(`flex justify-center pt-10 pb-6` + 랜딩 상단 바와 동일 계열 `text-lg font-extrabold tracking-tight text-emerald-900`, `span` — a 요소 없음으로 SURF-4 앵커 순수성 유지)
- **영향 범위**: 이 레이아웃은 인증 화면(sessions·registrations·passwords)만 사용 — 표면 ①(landing 레이아웃)·②(app 레이아웃) 렌더에 영향 없음(컨트롤러 layout 지정 원문 확인)

### #2 프로필 미완료 표시명 플레이스홀더 (리뷰 #2 — UI 품질 기준·AUTH-1.3)

- **변경**: `app/views/layouts/app.html.erb` 헤더 표시명 슬롯 → `Current.user.display_name.presence || "프로필 완성 중"`(공백 사용자의 빈 span 렌더링 제거)
- **근거**: `App::ProfilesController`는 `require_complete_profile` skip(타당한 예외)이라 표시명 공백 사용자가 이 레이아웃을 통과한다 — 그 외 ② 화면은 가드가 공백을 차단하므로 플레이스홀더가 노출될 일 없음

### #3 SURF-6 기록 정정 + 기술 부채 등록 (리뷰 #3 — SURF-6 기록 정확성)

- **정정**: 본 보고서 §3 SURF-6 행을 「마크업·의존 참조 수준 분리」로 수정 — `_head`의 `javascript_importmap_tags` + `index.js`의 `eagerLoadControllersFrom`으로 `sidebar_controller`가 표면 ①에서도 로드되고, CSS는 단일 tailwind 빌드 공유. 현재 규모(컨트롤러 3개·CSS 34KB)에서 SURF-6 예산 영향 없음 — 위반 아님, 서술 과대만 정정
- **기술 부채 등록(본 보고서 한정 — AGENTS.md 로드맵 갱신은 Phase 9 오케스트레이터 담당)**:
  1. 표면별 Stimulus 컨트롤러 로드 분리 — `eagerLoadControllersFrom` 전면 로드를 표면별 엔트리 또는 lazy loading으로 분리(F-INV 본체 구현 시점 권장)
  2. CSS 표면별 분할 — 단일 tailwind 빌드를 표면(①·②)별 엔트리포인트로 분할(번들 확대로 예산 분리가 필요해지는 시점 권장)

### 자체 점검 (2026-10-12 실측)

| 점검 | 결과 |
|:---|:---|
| `bin/rubocop` | **0 offenses** (53 files inspected) |
| `bin/rails zeitwerk:check` | **통과** — "Otherwise, all is good!" |
| 마이그레이션 | 없음 — `db/schema.rb` 변경 없음 |
| 서버 기동·테스트 작성 | 하지 않음(지시 준수) — 변경 마크업은 원문 대조로 확인 |
