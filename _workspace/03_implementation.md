# 03_implementation.md — 랜딩 페이지 루트 화면 (표면 ① 최소 골격)

- **일자**: 2026-10-08
- **범위**: LP-1 히어로만 (LP-2~13 후속). 마이그레이션/모델/잡/서비스 없음 — 정적 페이지
- **빌드 환경 비고**: Tailwind v4 (`tailwindcss-rails 4.6.0`, `app/assets/tailwind/application.css` — 템플릿 자동 스캔, arbitrary value 지원 확인)

## 변경 파일 목록

| 파일 | 구분 | 요약 |
|:---|:---|:---|
| `app/controllers/landing_controller.rb` | **신규** | `LandingController < ApplicationController`, `index` 빈 액션 1개(뷰 렌더용). 표면 ①은 비로그인 공개이므로 인증 before_action 없음(§3.3 규칙 7 준수 — 인증이 없는 것이 아니라 불필요). 클래스 주석에 SURF-1·SURF-6 근거 기록 |
| `app/views/landing/index.html.erb` | **신규** | LP-1 히어로 정적 마크업. `content_for :title` 지정. DB 쿼리·모델 호출·Stimulus 없음 |
| `config/routes.rb` | **수정** | 스캐폴드 주석 예시(`# root "posts#index"`)를 `root "landing#index"`로 활성화 + 「── 표면 ① 랜딩 ──」 도메인 주석 블록 추가(§3.7 규칙 4) |
| `app/views/layouts/application.html.erb` | **수정 없음** | title 태그가 이미 `content_for(:title) \|\| "Badeuldon"` 형태로 content_for를 지원 → 수정 불요. 지시서 조건부 수정 허용은 발동하지 않음 |

## 파일별 구현 상세

### 1. `app/controllers/landing_controller.rb`
- 액션 본문 비어 있음(주석만) — §3.3 "before_action의 @객체 사용 — 본문 불필요" 패턴과 동일한 빈 액션 관용구.
- `ApplicationController` 상속 유지(allow_browser 등 공통 동작 재사용).

### 2. `app/views/landing/index.html.erb`
- **title**: `<% content_for :title, "받을돈 — 말하기 어려운 '돈 다오', 받을돈이 대신합니다" %>`
- **LP-1 헤드라인(h1)**: 「말하기 어려운 '돈 다오', 받을돈이 대신합니다」 — Q6 확정 문구 그대로(개행은 `<br>`).
- **서브카피**: 수금 루프 한 문장 — 「청구 링크 → 열람 추적 → 자동 리마인더 → 입금 약속 수집까지, 수금 루프 전체를 받을돈이 대신합니다.」 (LP-1 명시 4단계 어휘 + 헤드라인의 "대신합니다"만 재사용, 신규 카피 문구 없음)
- **주 CTA**: 「카카오로 시작하기」 — `<button type="button" disabled aria-disabled="true">` (F-AUTH 미구현 → href 없음, 연결은 F-AUTH 시점). 버튼 아래 보조 문구 「무료 · 카드등록 없음 · 3분」 + 안내 문구 「로그인은 곧 오픈됩니다」(지시서 지정 문구) 작게 표기.
- **보조 CTA**: 「작동 방식 보기」 — 대상 섹션(LP-3) 미구현 → href 없는 비활성 버튼(딥 그린 아웃라인 스타일).
- **뷰 규칙 준수**: 정적 마크업만, `raw`/`html_safe` 없음, 표현 로직 3줄 미만(헬퍼 불필요), ERB 주석에 Rule ID 근거 인라인 기록.

### 3. `config/routes.rb`
```ruby
# ── 표면 ① 랜딩 ───────────────────────────────
# 비로그인 공개(SURF-1) — 색인 허용(SURF-3), ①→② 진입은 소셜 로그인 CTA 단일(SURF-4)
root "landing#index"
```
- 경로 하드코딩 없음(컨트롤러 문자열 표기는 Rails DSL 표준).

## Rule ID별 구현 매핑

| Rule ID | 요구사항 | 구현 | 위치 |
|:---|:---|:---|:---|
| SURF-1 | 표면 ① = 메인 도메인 `/` | `root "landing#index"` — 단일 도메인 루트 | `config/routes.rb` |
| SURF-3 | 표면 ①은 색인 허용(noindex 금지) | 뷰·레이아웃에 noindex 메타 미삽입(레이아웃도 noindex 무소유) — Tester가 "noindex 없음" 검증 대상 | `app/views/landing/index.html.erb` |
| SURF-4 | ①→② 진입은 소셜 로그인 CTA 단일 | 「카카오로 시작하기」 CTA 1회 렌더(유일한 진입 CTA) — F-AUTH 전이라 href 미연결 비활성 버튼 | 뷰 주 CTA 블록 |
| SURF-6 | 표면 ① 경량 렌더링 | 정적 ERB만 — 앱 JS/Stimulus/DB 쿼리 의존 0 | 컨트롤러·뷰 전체 |
| LP-1 | 히어로: 헤드라인(Q6 확정)·서브카피(수금 루프 1문장)·주 CTA 「카카오로 시작하기 — 무료 · 카드등록 없음 · 3분」·보조 CTA 「작동 방식 보기」 | 4요소 전부 반영. 주 CTA는 버튼 텍스트+보조 문구 2줄로 분해 표기(지시서 분해안 따름) | 뷰 |
| LP-12 | 확정 보장·압박 표현 금지, PRD 확정 문구 외 창작 금지 | 문구는 Q6 헤드라인·LP-1 4단계 루프 어휘·지시서 지정 안내문만 사용 — 보장/압박 표현 0 | 뷰 |
| DESIGN-1 | 온기×격식 | 장식·일러스트 없는 타이포 중심 히어로 | 뷰 |
| DESIGN-2 | 크림·아이보리 배경 + 딥 그린 액센트 | 배경 `bg-[#faf9f5]`, 액센트 `text-emerald-800/900`·`bg-emerald-800`·`border-emerald-800` | 뷰 |
| DESIGN-3 | 국문 우선 타이포 | 시스템 폰트 스택 `'Apple SD Gothic Neo', 'Noto Sans KR', sans-serif`(인라인 style — Pretendard CDN은 별도 작업 시점 도입, 임시 스택임을 주석 명시) | 뷰 루트 section |

## 자체 점검 결과

| 점검 | 명령 | 결과 |
|:---|:---|:---|
| RuboCop | `bin/rubocop` | `25 files inspected, no offenses detected` (exit 0) |
| Zeitwerk | `bin/rails zeitwerk:check` | `All is good!` (exit 0) |

- 마이그레이션 없음 → `db:migrate`·`db/schema.rb` 해당 없음.
- 서버 기동·테스트 작성은 수행하지 않음(Phase 4·7·8 — 오케스트레이터/Tester 담당).

## 후속 작업 참고 (Reviewer/Tester용 관찰 사항)

1. **application 레이아웃 재사용에 따른 렌더링 특성**: 레이아웃의 `<main class="container mx-auto mt-28 px-5 flex">` 안에 히어로가 렌더된다. 히어로 section에 `w-full`을 두어 flex 폭 수축을 방지했으나, 상단 `mt-28` 여백과 컨테이너 폭 제한은 레이아웃 소유다. 랜딩 풀블리드·여백 조정은 LP-2~13 후속 작업에서 레이아웃 정비와 함께 검토 필요.
2. **CTA 비활성 상태는 의도된 범위 한계**: F-AUTH 완료 시 주 CTA를 `new_session_path` 등 소셜 로그인 진입 경로로 연결해야 한다(SURF-4 단일 진입점 유지).
3. **폰트**: DESIGN-3의 Pretendard 도입은 별도 작업 — 현재는 임시 시스템 폰트 스택(지시서 명시).
