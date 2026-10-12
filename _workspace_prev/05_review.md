# 05_review.md — Phase 5 리뷰: /app 대시보드 뼈대 + 레이아웃 3분리 + welcome 소멸

- **일자**: 2026-10-12
- **리뷰 대상**: git 변경분(신규 9 · 수정 9 · 삭제 1 + 산출물 문서) — `_workspace/03_implementation.md` 기준
- **검증 방식**: 전 파일 원문 열독 + git diff 대조 + PRD v0.18.2 원문 인용 + 빌드 산물(css) 실측. Phase 4 실측(53파일 RuboCop 0에러·zeitwerk·라우트) 전제
- **이전 이슈 추적**: `_workspace_prev/05_review.md`(랜딩·프로필 회차) 이슈 잔존 없음 — 이번 변경분과 교집합 없음

## Status: CHANGES_REQUESTED

**BLOCKER 0 · CRITICAL 0 · WARNING 3** — Rule 정합성(DASH·ONB·SURF·AUTH-1.3)·보안 가드·아키텍처는 전부 통과. WARNING 3건은 UI 품질 기준 회귀 2건(사용자 노출 화면) + 기록 정확성 1건으로 **Phase 6 수정 권장**이나, Phase 7 Tester의 16건 갱신 작업을 막는 사항은 아님(병행 가능). 수정 후 전체 재리뷰 불필요 — 변경 파일 국소 재확인으로 족함.

## 이슈 목록

| # | Severity | Rule ID | File:Line | 설명 | 수정 제안 |
|---|----------|---------|-----------|------|-----------|
| 1 | WARNING | UI 품질 기준(AGENTS.md §116) | `app/views/layouts/application.html.erb:7-15` | **인증 화면 브랜드 크롬 소실**. 구현 보고는 전역 헤더 제거를 "크롬은 표면별 레이아웃으로 이관"으로 기술했으나, 인증 화면(로그인·가입·재설정)은 전용 레이아웃 없이 크롬 없는 공통 기반에 남아 페이지 최상단이 곧 h1 폼이 됨(이전: 워드마크 헤더 상시 존재). 브랜드 부재는 로그인 화면 신뢰도·피싱 유사 우려를 키우며 "뼈대만 노출하는 구현 금지" 기준에 배치될 여지. 기존 테스트가 헤더를 어설션하지 않아 회귀로 검출되지 않음. | 인증 화면용 최소 크롬 추가 — ① application 레이아웃에 `content_for` 기반 선택적 워드마크 파셜, 또는 ② sessions/registrations/passwords 공유 미니 헤더(`span` 워드마크, 링크 없음 — SURF-4 앵커 순수성 유지. 기존 랜딩 상단 바와 동일 마크업) |
| 2 | WARNING | UI 품질 기준·AUTH-1.3 | `app/views/layouts/app.html.erb:56` | **프로필 미완료 사용자의 헤더 표시명 슬롯 공백 렌더링**. `App::ProfilesController`는 `require_complete_profile`을 skip하므로(필요한 예외 — 타당) 표시명 공백 사용자가 /app/profile 화면에서 헤더 우측이 빈 `span`으로 렌더됨. 가입 직후 가장 많이 거치는 화면이라 헤더 표시명 UX 검증 항목(과제 검증 기준 ②)에 걸림. | `Current.user.display_name.presence \|\| "게스트"` 등 플레이스홀더 표기, 또는 미설정 시 슬롯 미출력 조건 분기 |
| 3 | WARNING | SURF-6(기록 정확성) | `app/views/layouts/_head.html.erb:23`·`app/javascript/controllers/index.js:3` | **03 보고의 SURF-6 서술 과대**. "랜딩은 정적 마크업+공통 head만, 앱 자원 의존 제거"는 마크업 수준에서만 참. 공통 `_head`가 `javascript_importmap_tags`를 내보내고 `index.js`가 `eagerLoadControllersFrom`으로 컨트롤러 전체를 즉시 로드하므로 `sidebar_controller.js`는 표면 ①에서도 여전히 다운로드되며, CSS도 단일 tailwind 빌드를 공유(신규 유틸리티 포함 — 빌드 파일 실측 확인됨: `lg:pl-64`·`bg-orange-500`·`min-h-11` 등 존재, mtime 10-12 11:08). 현재 규모(컨트롤러 3개·CSS 34KB)로는 SURF-6 예산 영향 없어 **위반 아님** — 다만 "의존 제거" 서술은 예산 분리가 완료되지 않은 상태로 읽힘. | 03 §3 SURF-6 행을 "마크업·의존 참조 수준 분리(JS·CSS 번들은 공유)"로 정정하고, F-INV 본체 구현 시점의 번들 분리(표면별 엔트리 또는 lazy loading)를 AGENTS.md 기술 부채 목록에 등록 |

### 기각 후보(위양성 방지 기록)

- `require_complete_profile`의 `Current.user.display_name` NilClass 가능성 → 없음. `require_authentication`(ApplicationController, 부모 필터 선행)이 리다이렉트 시 필터 체인이 중단되어 도달 불가.
- `noindex?`의 `"/app"` prefix가 `/apple` 유사 경로도 매칭 → 해당 라우트 부재 + 기존 패턴 계승. 실질 영향 없음.
- 비활성 내비 `text-stone-400` 저대비 → WCAG 1.4.3 비활성 컴포넌트 예외 항목. disabled 상태 의도적 강조 해제. 배지는 stone-500(이전 리뷰 #4 기준 준수).
- `redirect_to edit_app_profile_path`(가드)에 status 미명시(302) → GET 내비게이션 리다이렉트로 302는 규약상 문제 없음. 폼 제출 303 규약 대상 아님.

## Rule ID 준수 매핑

| Rule ID | 판정 | 근거(파일:행) |
|:---|:---|:---|
| **DASH-1** | ✅ 준수 | `show.html.erb:14-29`·`base_helper.rb:27-33` — 카드 3종(미수 총액·연체 건수·금액·7일 내 만기) 골격 + 빈 상태 「청구서를 발행하면 여기에 표시됩니다」. 수치 슬롯은 대시(—) `aria-hidden` 처리로 **거짓 0원 부재 확인**(02_prd_update 결정 이행). PRD 원문 3요소 라벨 정합 |
| **DASH-2** | ✅ 준수 | `show.html.erb:31-40` — 「오늘 할 일이 없습니다」 + 발송 예정·약속일 도래 카드 안내. 카드형 골격(DESIGN-5) |
| **DASH-4** | ✅ 준수 | `show.html.erb:59-77` — 목록 영역 + 「연체일이 긴 순서부터 표시됩니다」(=연체일 내림차순). 정렬 구현은 플랜대로 F-INV 인계 |
| **ONB-1** | ✅ 준수 | `show.html.erb:42-57` — 「3분이면 첫 청구서를 발행합니다」 + 원문 3요소(표시명·계좌 자동 채움 / 품목 예시 / 만기일 기본 30일 — INV-3 정합). CTA disabled + 「준비 중」 배지(플랜 결정 #3) |
| **SURF-3** | ✅ 준수 | `application_helper.rb:4`(prefix `/app`·`/b/`·`/admin`) + `_head.html.erb:9`(noindex, nofollow 메타 — app 레이아웃도 `_head` 공유) + `robots.txt:5-7` 3행. `/welcome` 제거는 경로 소멸에 따른 정당 청소 |
| **SURF-4** | ✅ 준수 | 랜딩 레이아웃 상단 바는 `span` 워드마크로 앵커 0(`landing.html.erb:12`) — 기존 「①의 a 요소는 가입 진입이 유일하다」 테스트 통과 유지(67건 통과 목록). 앱(②)→① 링크 부재 확인(워드마크 `span`, 로그아웃 → 세션 파괴 → 로그인 화면) |
| **SURF-6** | ✅(마크업 수준) | 레이아웃 3분리로 ①에 사이드바·내비 헬퍼·Stimulus 마크업 유입 없음. 잔여: JS/CSS 번들 공유 — 이슈 #3 |
| **DESIGN-2** | ✅ 준수 | 범례 3색 = PRD 원문대로 연체 주황(`bg-orange-500`)·대기·약속 중립(`bg-stone-400`)·수금 완료 녹색(`bg-green-600`). 카드 브랜딩 점(연체 카드만 주황). 크림 배경+딥 그린 액센트 계승 |
| **DESIGN-3** | ✅ 준수 | 금액 슬롯 `text-4xl tabular-nums`(빈 상태 대시 포함) |
| **DESIGN-4** | ✅ 준수 | 표면 ② 정보 밀도 중심 — h2 섹션 위계·카드·텍스트 중심, 장식은 ONB-1 밴드 1곳 |
| **DESIGN-5** | ✅ 준수 | 요약 큰 숫자 카드·액션 카드형·사이드바+카드 골격(shadcn dashboard-01 벤치마킹 포인트만 취함 — DESIGN-7 준수) |
| **DESIGN-6** | ✅ 준수 | 터치 타깃 전 구간 `min-h-11`/`h-11 w-11`(44px). `aria-current="page"`(활성 내비)·`aria-controls`+`aria-expanded` 동기화(해시버거)·`sr-only` 라벨·배경 버튼 `aria-hidden`+`tabindex="-1"` |
| **AUTH-1.3** | ✅ 준수 | `base_controller.rb:13-15` 신규 가드(표시명 공백 → 프로필 리다이렉트) — 로그인 직후(기존)·/app 직접 접근(신규) 모두 커버. `profiles_controller.rb:4` skip은 해당 화면이 완료 화면이므로 타당(redirect 루프 없음) |
| **AUTH-1** | ✅ 준수 | 표면 ② 공개 예외 없음 — namespace 내 `allow_unauthenticated_access` 부재, ApplicationController 가드 상속 |
| **LP-10** | ✅ 준수 | 푸터 마크업·문구(문의 채널·© 2026) 불변 이관(`landing.html.erb:24-34`) — 기존 LP-10 테스트 통과 유지 |
| **LP-12** | ✅ 준수 | §3.1 신규 문구 전수 점검 — 확정 보장·압박·법적 조치·추심 오인 표현 없음. 「~카드로 표시됩니다」류 미래형 안내는 사실 범위 내 |
| **SEC(CSRF)** | ✅ 준수 | 로그아웃 `button_to`(authenticity token 동반) + `turbo_confirm`. `raw`/`html_safe` 미사용. 민감정보 로깅 없음 |

## 리다이렉트 흐름 검증표 (코드 실측 대조 — 03 §4.1 전 행 확인)

| 시점 | 구현 위치 | 코드 | 판정 |
|:---|:---|:---|:---|
| 가입 직후 | `registrations_controller.rb:16` | `redirect_to edit_app_profile_path, status: :see_other` | ✅ 플랜 A-3 — 프로필 직행 |
| 프로필 저장 완료 | `profiles_controller.rb:15` | `redirect_to app_root_path, status: :see_other` | ✅ /app 진입 |
| 로그인 — 프로필 미완료 | `authentication.rb:44` | `return edit_app_profile_url if Current.user&.display_name.blank?` | ✅ 불변(프로필 우선) |
| 로그인 — 프로필 완료 | `authentication.rb:46` | `return_to \|\| app_root_url` | ✅ root_url → app_root_url 변경. return_to 우선 불변 |
| /app 직접 접근 — 비인증 | `authentication.rb:23-24`(상속) | `require_authentication` → 302 `new_session_path` | ✅ 가드 상속 확인 |
| /app 직접 접근 — 프로필 미완료 | `base_controller.rb:14` | `redirect_to edit_app_profile_path`(302) | ✅ 신규 가드 정상 |
| 가드 예외 화면 | `profiles_controller.rb:4` | `skip_before_action :require_complete_profile` | ✅ 루프 없음(edit/update 모두 예외 — 의도) |
| `GET /welcome` | `config/routes.rb` | 라우트 부재 | ✅ 404 — 소멸 확인 |
| 사이드바 설정 링크 | `base_helper.rb:11` | `edit_app_profile_path` 실링크 + `/app/profile` prefix 활성 판정 | ✅ |

- 실패 16건 전수 대조: grep 실측 기준 `welcome_path`/`welcome_url` 참조 테스트 13건 + `root_url` 폴백 변경 1건(sessions:25) + robots 행 1건 + noindex welcome 화면 1건 = 16건, 03 §4.2 목록과 **전수 일치**. app/·config/·public/에 잔여 `welcome`·`show_login_link?` 참조 없음(주석의 이력 언급만 존재 — 무해).
- 통과 유지 67건 주장 중 회귀 민감 항목 실측: SURF-4 앵커 순수성 테스트(`landing_controller_test.rb:37-44`)는 신규 레이아웃 헤더가 `span`이라 통과 논리 확인. LP-10 `assert_select "footer"`는 응답 전체 대상 — 이관 후에도 통과.

## 아키텍처·보안 점검 요약

- **액션 규약**: `Dashboards#show` 1줄·프로필/가입 액션 10줄 이내, `params.expect` 화이트리스트 유지 ✅
- **뷰 무쿼리**: 대시보드 뷰는 헬퍼(`dash_summary_cards`·`app_nav_items` — 프레젠테이션 데이터만) 참조. `Current.user.display_name`(레이아웃)은 속성 접근이며 가드로 non-nil 보장 ✅
- **Stimulus**: `sidebar_controller.js` 순수 UI 토글(aria 동기화 포함), 비즈니스 로직 없음. `connect()`의 `close()`가 데스크톱(`lg:flex`)에 영향 없음 — Tailwind 반응형 우선순위로 안전 ✅
- **App::BaseController 추상화**: layout+가드 중복 제거, 향후 F-INV·F-CLIENT 컨트롤러가 직접 수혜 — 과잉 추상화 아님(수용처 2+예정) ✅
- **noindex 중복·누락**: `_head` 단일 지점이라 중복 렌더 불가, `/app` prefix가 `/app/*` 전경로 커버 ✅
- **범위 준수**: 코드 변경은 리뷰 대상 19파일에 한정(그 외는 산출물 문서·progress.json). 마이그레이션 없음. 후속 제외(실데이터·청구서 화면 본체) 미구현 확인 — 셸+빈 상태만 ✅

## Tester에게 제안하는 중점 테스트 영역 (Phase 7)

1. **16건 갱신(03 §4.2 방향 승인)** — 보완 노트:
   - #2·#3·#11·#13·#14처럼 `/welcome`을 「인증 필요 경로」 용도로 쓰던 테스트는 `/app` 치환 시 `assert_redirected_to new_session_path`(비인증 302)로 목적 보존.
   - #10·#12는 어설션 `app_root_url` + 테스트명 「…/app로 진입한다」 갱신 — return_to 우선 분기(#13)는 경로 치환 후에도 프로필 우선 로직이 이기는지 재확인.
   - #15는 삭제 대신 「/app 대시보드 noindex」 신규 테스트로 대체 권장(기존 /app/profile noindex 케이스와 별개 경로).
2. **신규 권장(03 §6.1 승인 + 세부화)**:
   - /app 비인증 302 → new_session_path (AUTH-1)
   - /app 프로필 미완료 직접 접근 → edit_app_profile_path 리다이렉트 (AUTH-1.3 신규 가드 — 라우트·컨트롤러 회귀의 핵심)
   - 프로필 완료 사용자 /app 200: h1 「대시보드」·DASH-1/2/4 빈 상태 문구·ONB-1 CTA `button[disabled][aria-disabled]` 존재, **「0원」 등 수치 문자열 부재** 어설션 (DASH-1 거짓 수치 금지)
   - 사이드바: 활성 링크 `a[aria-current="page"]`(대시보드) 1건, `span[aria-disabled]` 2건(청구서·거래처), 설정 실링크 href (구조 안내)
   - 로그아웃: `form[action=session]` 내 `input[name=_method][value=delete]` 존재(button_to CSRF 구조) + turbo_confirm 속성
   - 랜딩 회귀: a 순수성(기존) + 푸터가 레이아웃 이동 후에도 렌더(LP-10)
3. **시스템 테스트 스코프 노트**: 모바일 드로어는 backdrop 탭 닫기·내비 링크 클릭 닫기·`aria-expanded` 토글까지만 검증 범위로(Esc·포커스 트랩은 미구현 — 03 §6.5 후속 과제).

## 남기는 판단 (Phase 6 Developer 전달용)

- 이슈 #1·#2는 각각 미니 크롬 파셜 추가·표시명 플레이스홀더 조건 분기 수준의 국소 수정 — 라우트·가드·리다이렉트 불변.
- 이슈 #3은 문서 정정 + 기술 부채 등록(AGENTS.md 로드맵 갱신은 Phase 9에서 일괄 가능).
- 수정 반영 후 본 파일 이슈 표의 해결 여부만 갱신해 재리뷰 대기 상태로 관리 권장.
