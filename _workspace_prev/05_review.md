# 05_review.md — Phase 5 코드 리뷰: 랜딩 루트 화면(표면 ① 최소 골격)

- **일자**: 2026-10-08
- **Reviewer**: LandingReviewer
- **리뷰 대상**: Phase 3 변경분 — `app/controllers/landing_controller.rb`(신규), `app/views/landing/index.html.erb`(신규), `config/routes.rb`(수정), `app/views/layouts/application.html.erb`(수정 없음 주장 — 검증됨)
- **기준**: PRD.md §7 원문(SURF-1/3/4/6, LP-1/12, DESIGN-1/2/3) > ARCHITECTURE_CONVENTION §3.3/§3.6/§3.7 > 승인 플랜 `_workspace/01_plan.md`. 코드 스타일은 Phase 4(RuboCop 0에러)가 처리했으므로 제외.

## Status: APPROVED

**BLOCKER 0건 · CRITICAL 0건 · WARNING 2건(모두 후속 작업 조건부 — 현 시점 수정 불필요)**

---

## 이슈 목록

| # | Severity | Rule ID | File:Line | 설명 | 수정 제안 |
|---|----------|---------|-----------|------|-----------|
| 1 | WARNING | SURF-6 | `app/views/layouts/application.html.erb:23` | 공유 레이아웃의 `javascript_importmap_tags`가 표면 ①에도 앱 JS를 로드한다. SURF-6은 "②의 앱 자원이 ①의 로딩 성능에 영향 주지 않을 것"을 요구 — 현재는 ② 앱 자원이 없고 플랜이 레이아웃 재사용을 승인했으므로 **현 시점 위반 아님(잠재 리스크)**. | F-AUTH/표면 ② 구축 시점에 ① 전용 레이아웃 분리 또는 조건부 스크립트 주입으로 예산 분리 검토. 해당 시점까지 미조치 시 CRITICAL 승격 후보. |
| 2 | WARNING | DESIGN-3 | `app/views/landing/index.html.erb:5` | 국문 우선 폰트를 임시 시스템 스택(`'Apple SD Gothic Neo', 'Noto Sans KR'`) + **인라인 `style` 속성**으로 지정. PRD 규칙 문구("국문 우선 폰트, 예: Pretendard")는 충족하나 플랜 명시의 Pretendard가 아니고, 인라인 스타일은 페이지 국소 임시 방편. | Pretendard 도입 작업 시점에 인라인 `style` 제거 → CSS(애셋) 전역 폰트 설정으로 전환. 임시 상태임이 ERB 주석으로 명시되어 있어 현 시점 수정 불필요. |

### 검증했으나 이슈 아닌 항목 (위양성 방지 기록)

- **주 CTA가 `disabled` 버튼(href 없음)**: 플랜이 명시적으로 승인한 범위 한계("CTA 렌더 단, F-AUTH 전이라 링크 비활성") — SURF-4 위반 아님. `01_plan.md` 리스크 항목 및 구현 보고 후속 #2와 일치. F-AUTH 시점 연결 필수.
- **서브카피 "수금 루프 전체를 받을돈이 대신합니다"**: '전체'는 루프(업무 범위)를 수식하며 회수율 확정 보장이 아님. 어휘는 Q6 헤드라인 + LP-1 명시 4단계 원문에서 재구성 — LP-12 준수.
- **"로그인은 곧 오픈됩니다" 문구**: 확정 보장·압박·추심 오인 표현 아님(LP-12 무관), 지시서 지정 문구 — 이슈 아님.
- **`public/robots.txt`**: 주석 1줄뿐 `Disallow` 없음 — 표면 ① 색인 차단 없음 확인(SURF-3 역방향 검증 통과).
- **SEO 메타(description·OG·구조화 데이터) 부재**: SURF-3은 표면 ①에 SEO 요소 적용을 요구하나, 이는 LP-2~13 랜딩 전체 구축 범위(플랜 승인 제외 항목)에 속함 — 골격 단계 이슈 아님. **후속 랜딩 작업 시 필수 반영 항목으로 이관.**

## Rule ID 준수 매핑

| Rule ID | PRD 원문 요구 | 구현 검증 결과 | 판정 |
|:---|:---|:---|:---|
| SURF-1 | 표면 ① = 메인 도메인 `/` | `config/routes.rb:14` `root "landing#index"` — 단일 도메인 루트, 스캐폴드 예시 주석 대체(diff 확인) | ✅ 준수 |
| SURF-3 (역방향) | 표면 ① 색인 **허용** — noindex 금지 | 뷰 전체 행 검색: noindex/robots 메타 없음. 레이아웃에도 없음. `public/robots.txt` Disallow 없음 | ✅ 준수 |
| SURF-4 | ①→② 진입 = 가입 CTA(소셜 로그인) 단일 진입점, 타 링크 금지 | 「카카오로 시작하기」 CTA 1회만 존재. 뷰에 `<a>` 요소 0개(CTA·보조 CTA 모두 비활성 `<button>`), 레이아웃에 내비 없음 → ② 이외 표면으로의 링크 불가 구조 | ✅ 준수 |
| SURF-6 | ① 경량 렌더링 — ② 자원이 ① 로딩에 영향 금지 | 뷰: DB 쿼리·모델 호출·Stimulus 0(정적 ERB). 컨트롤러: 빈 액션. 단, 레이아웃 importmap JS는 이슈 #1(후속 조건부) | ✅ 준수 (⚠️ #1 후속 조건) |
| LP-1 | 헤드라인 Q6 확정문, 서브카피=수금 루프 1문장, 주 CTA 「카카오로 시작하기 — 무료 · 카드등록 없음 · 3분」, 보조 CTA 「작동 방식 보기」 | h1 = 「말하기 어려운 '돈 다오', 받을돈이 대신합니다」(Q6 원문 일치, `<br>`은 시각 개행만). 서브카피 1문장에 PRD 명시 4단계 어휘 그대로. 주 CTA 텍스트+보조 문구 2줄 분해(플랜 지시안). 보조 CTA 존재. title도 지시서 문구로 content_for 설정 | ✅ 준수 |
| LP-12 | 확정 보장·압박·추심 오인·경쟁사 비방 금지 | 사용 문구 = Q6 원문·LP-1 어휘·지시서 지정 안내문뿐(신규 창작 카피 0). 금지 표현 미발견 | ✅ 준수 |
| DESIGN-1 | 온기×격식, 일러스트는 허용·아껴 쓰기 | 타이포 중심 히어로, 장식 없음(일러스트는 의무 아님) | ✅ 준수 |
| DESIGN-2 | 크림·아이보리 배경 + 딥 그린 단일 액센트 | `bg-[#faf9f5]`(크림·아이보리 계열) + `emerald-800/900` 액센트 일관 | ✅ 준수 |
| DESIGN-3 | 국문 우선 폰트(예: Pretendard) | 국문 우선 시스템 스택으로 규칙 문귀는 충족하나 Pretendard 미반영 + 인라인 style | ⚠️ 부분 준수 (이슈 #2) |

## 보안·데이터 무결성 점검

- [x] **입력·XSS**: 표면 ①은 사용자 입력 전혀 없음(정적 페이지) — `raw`/`html_safe` 미사용 확인. 이스케이프 이슈 성립 불가.
- [x] **인증**: 비로그인 공개 표면(SURF-1/P3 맥락) — 인증 before_action 부재가 정당. 우회 경로 해당 없음. `ApplicationController` 상속으로 `allow_browser` 등 공통 동작 유지.
- [x] **민감 정보**: 페이지에 토큰·개인정보·계좌 정보 없음(P2/REM-1 무관 상태).
- [x] **CSRF/CSP**: 레이아웃 `csrf_meta_tags`·`csp_meta_tag` 유지 확인.

## 아키텍처 준수

- [x] **§3.3 컨트롤러**: 표준 `index` 액션, 본문 주석만(빈 액션 관용구 — §3.3 예시 `show` 패턴과 동일). 액션 내 인증 분기 없음(공개 표면). 클래스 주석에 SURF-1·SURF-6 근거 기록.
- [x] **§3.6 뷰**: 컨트롤러 @변수 불필요(정적), DB 쿼리·모델 호출 없음, 표현 로직 3줄 미만(헬퍼 불필요), ERB 주석에 Rule ID 근거 인라인.
- [x] **§3.7 라우트**: `root` 정의 + 「── 표면 ① 랜딩 ──」 도메인 주석 블록(규칙 4). URL 하드코딩 없음. 커스텀 액션 없음.
- [x] **Zeitwerk**: Phase 4 실측 통과(`bin/rails zeitwerk:check` — All is good).

## 범위 준수 (git status 대조)

| 변경 | 판정 |
|:---|:---|
| `config/routes.rb` 수정(스캐폴드 주석 → root + 주석 블록 5줄) | 플랜 허용 범위 내 · 정확 일치 |
| `app/controllers/landing_controller.rb` 신규 | 플랜 대상 |
| `app/views/landing/index.html.erb` 신규(디렉터리 내 파일 1개만) | 플랜 대상 |
| `app/views/layouts/application.html.erb` | **수정 없음 — Developer 주장 실측 검증됨**(변경 목록에 없음, title이 원래부터 `content_for(:title) \|\| "Badeuldon"` 지원) |
| `PRD.md`(v0.17→v0.17.1 버전 라인만), `.omp/progress.json`, `_workspace/*` | 파이프라인 소유 산출물 — 범위 외 변경 아님 |

**플랜 외 파일 침범 없음. 마이그레이션·모델·잡·서비스 변경 없음 확인.**

---

## Tester에게 제안하는 중점 테스트 영역 (Phase 7)

1. **루트 라우팅**: `GET /` 비로그인(세션 없음) → 200 + `landing/index` 렌더. 로그인 상태에서도 동일(공개 표면).
2. **LP-1 문구 정확 매칭** (개행 포함 주의 — h1이 `<br>` 분할):
   - `assert_select "h1", text: /말하기 어려운 '돈 다오',\s*받을돈이 대신합니다/` (작은따옴표·쉼표 포함 정확 문자열)
   - 서브카피에 「청구 링크 → 열람 추적 → 자동 리마인더 → 입금 약속 수집」 4단계 어휘 포함
   - 「카카오로 시작하기」·「무료 · 카드등록 없음 · 3분」·「작동 방식 보기」 전부 노출
3. **SURF-3 역방향**: 응답 본문에 `noindex` 부문자열 없음 단언. `title` 태그가 「받을돈 — 말하기 어려운 '돈 다오', 받을돈이 대신합니다」로 렌더(content_for → 레이아웃 전달 검증).
4. **SURF-4 단일 진입점**: 응답 HTML에 `<a` 요소 0개 단언(비활성 CTA가 우발적 링크로 렌더되지 않음). 주 CTA 버튼이 `disabled` 속성 보유.
5. **회귀 방지**: 기존 경로(`/up` 헬스체크) 영향 없음.

> 후속(F-AUTH·랜딩 전체 구축) 시점 테스트 후보로 기록: CTA 링크 연결 후 SURF-4 단일 진입 재검증, SEO 메타 적용 여부, ① 전용 레이아웃 분리 시 SURF-6 예산 측정.

## 종합 의견

승인 플랜(표면 ① 최소 골격, LP-1 히어로만)의 범위를 정확히 지켰고, PRD 확정 문구·금지 표현·표면 구조 규칙에 대한 위반 0. WARNING 2건은 모두 Developer가 미리 문서화한 후속 작업 조건부 항목으로 현 시점 수정을 요구하지 않는다. **APPROVED — Phase 7(테스트) 진행 가능.**
