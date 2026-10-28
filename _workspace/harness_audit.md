# 하네스 전환 감사 기록 — omp → ZCode Desktop

**일자**: 2026-10-29
**모드**: 신규 구성(A) + omp 마이그레이션 (`$harness` 메타 스킬)
**규약**: HARNESS_CONVENTION.md v3.2.0(omp) → **v4.0.1(ZCode Desktop)** 교체

## 감사 결과 (전환 전)

| 항목 | 경로 | 상태 | 조치 |
|:---|:---|:---|:---|
| 규약 문서 | `HARNESS_CONVENTION.md` | omp v3.2.0 — ZCode에서 미지원(modelRoles·task tool·Agent Hub 규약) | v4.0.1 사본으로 교체 |
| 진행 상태 | `.omp/progress.json` | omp 전용 경로 | `.zcode/progress.json`으로 이관(값은 null 상태 그대로) |
| 오케스트레이터 | `.omp/skills/badeuldon-orchestrator/` | omp task tool·hub cancel 문법 포함 | Agent tool·모드별 프로필 문법으로 재작성 |
| 서브에이전트 | `.omp/agents/` 3개(일반만 존재) | `model: "@developer"`(@롤)·`autoloadSkills` — ZCode 미지원 | 프로필 6개(일반/절약) 재작성 — 명시 model·thoughtLevel·injectAgentsMd |
| 참조 스킬 5종 | `.omp/skills/` | 런타임 무관 내용 — 이관 대상 | 플러그인 `skills/`로 이관(git-deploy는 progress 경로만 수정) |
| business-rules 스킬 | `.omp/skills/badeuldon-business-rules/` | **내용 낡음** — AUTH-1 소셜 로그인 기술(PRD v0.22는 이메일/비밀번호), SURF-4 개정 미반영, 외부 서비스 표에 소셜 로그인 잔존 | PRD 원문 대조 후 수정 이관(AUTH-1·AUTH-8·SURF-4·외부 서비스 표) |
| 명령어 2개 | (없음 — omp는 `/skill:` 라우팅) | 누락 | `badeuldon_orchestrator`·`badeuldon_orchestrator_lite` 신규 생성 |
| 플러그인/marketplace | (없음) | 누락 | `.zcode/harness-marketplace/` 신규 생성 |
| 루트 AGENTS.md | `AGENTS.md` | omp 서술 존재(task tool 스폰 문법·`.omp/progress.json`) | ZCode 하네스 서술로 갱신, 변경 이력 추가 |
| omp 설정 잔존 | `.omp/`(전체) | 사용자 요청에 따라 전면 제거 대상 | Git 추적 확인 후 삭제 |

## 변경 요약

**신규 생성** (`.zcode/harness-marketplace/plugins/badeuldon-harness/`)
- `marketplace.json`, `.zcode-plugin/plugin.json`
- `commands/badeuldon_orchestrator.md` (glm-5.3) · `commands/badeuldon_orchestrator_lite.md` (glm-5.3-flash) — 양쪽 모두 `badeuldon-orchestrator` 스킬 로드
- `agents/` 프로필 6개: developer(glm-5.3-flash/high) · reviewer(glm-5.3/high, 읽기 전용 도구) · tester(glm-5.3-flash/high) + 각 `-lite`(developer/tester low, reviewer는 glm-5.3-flash/high)
- `skills/` 6종: orchestrator(ZCode 재작성) · business-rules(최신화 이관) · feature-dev · review-checklist · test-patterns(git-deploy는 경로 수정) · git-deploy
- `.zcode/progress.json`

**교체·갱신**
- `HARNESS_CONVENTION.md` — v4.0.1(내장 규약 사본, Git 관리)
- `AGENTS.md` — 헤더 문구, 하네스 섹션(진입점 명령어 2개·구성 요소·에이전트 스폰·승인 게이트), 작업 재개 가이드 경로, 변경 이력

**삭제**
- `.omp/` 전체(AGENTS.md, RULES.md, agents 3, skills 6, progress.json) — Git 이력에서 복구 가능

## 승인 게이트 3곳 반영 확인

루트 `AGENTS.md` 하네스 섹션 / `badeuldon-orchestrator` SKILL.md 하드 룰 1 / 양쪽 명령어 본문 — 모두 "승인 전 서브에이전트 호출 금지, 플랜 보고 후 턴 종료" 명시.

## 잔여 검증 항목 (사용자 액션 필요)

1. ZCode Settings → Plugins에서 로컬 marketplace `.zcode/harness-marketplace` 등록 후 `badeuldon-harness` 설치·활성화
2. `/` 명령 패널에서 명령어 2개 표시 확인
3. 최초 실행 시 `glm-5.3`/`glm-5.3-flash` 모델 인식 확인 — `model not found` 시 실제 내부 ID로 수정 필요(규약 §1.4 제약 3)
4. 저위험 작업으로 E2E 검증: 플랜 보고 → `awaiting_approval` 기록 → 승인 전 프로필 미호출 → 승인 후 일반/절약 프로필 각각 호출 확인(규약 §9.2 7단계)
5. 변경 사항 Git 커밋(요청 시 `badeuldon-git-deploy` 스킬)

## 후속 수정 — marketplace Install 실패 (2026-10-29)

**증상**: Install 클릭 시 `Unsupported or missing plugin source: ./badeuldon-harness`

**원인**: marketplace.json의 `pluginRoot: "plugins"` + `source: "./badeuldon-harness"` 조합을 현재 ZCode 빌드가 해석하지 못함 — `pluginRoot`를 적용하지 않고 marketplace 루트 기준으로만 경로를 해석해 존재하지 않는 `badeuldon-harness`를 찾음(공식 문서의 pluginRoot 동작과 실제 빌드 불일치 — 규약 §1.4 "모델 ID 실측"과 동일한 실측 원칙 적용).

**조치**:
- `marketplace.json`: `pluginRoot` 제거, `source`를 marketplace 루트 기준 상대경로 `plugins/badeuldon-harness`로 수정 — pluginRoot 적용 여부와 무관하게 결정적으로 해석됨
- UI가 읽는 복제본(`~/.zcode/cli/plugins/marketplaces/badeuldon-harness-marketplace/marketplace.json`)에도 동일 반영
- 프로젝트·전역 `$harness` 양쪽 HARNESS_CONVENTION.md의 marketplace.json 예시도 동일하게 수정(타 프로젝트 재발 방지)

## 후속 수정 2 — 설치 성공 후 `/` 명령어 미표시 (2026-10-29)

**증상**: Install 성공 후 `/` 명령어 목록에 `badeuldon_orchestrator`·`badeuldon_orchestrator_lite` 미표시.

**진단**(로그 `~/.zcode/v2/logs/2026-10-29.log` 실측):
- 명령어 스캔(`slashCommandCount: 4`)은 07:36 세션 시작 시 1회 수행, 플러그인 설치는 08:02 — **세션 시작이 설치보다 앞서 발견 목록에 반영되지 않음**. 디스크 상태(캐시 파일·frontmatter·이름 패턴·`enabledPlugins: true`·설정 비활성화 없음)는 모두 정상.
- 추가 발견: 공식 진단 스킬 및 런타임 로그(`subagentRuntimeConfig`가 프로젝트 `.zcode/agents` 감시) 기준, **플러그인 `agents` 필드는 기록만 되고 실행되지 않음** — 서브에이전트 6개가 플러그인에만 있으면 오케스트레이터가 Developer/Reviewer/Tester를 호출할 수 없음.

**조치**:
- 서브에이전트 프로필 6개를 런타임이 읽는 `.zcode/agents/`로 이동(단일 소스) — 플러그인 agents/·plugin.json `agents` 필드는 프로젝트·clone·캐시 3곳에서 제거
- AGENTS.md 하네스 섹션에 규약 v4.0.1 구조에 대한 프로젝트 예외로 기록(사유: ZCode 실측 동작)
- 공식 문서는 서브에이전트를 사용자 범위(`~/.zcode/agents/`) Beta로만 안내하나, 런타임은 프로젝트 `.zcode/agents/`도 감시 — 문서 미갱신 사례(pluginRoot에 이어 2건째)

**새 세션 검증 항목**:
1. `/` 목록에 명령어 2개 표시
2. Settings → Skills에 badeuldon 스킬 6종 표시
3. 오케스트레이터 실행 시 Agent tool의 서브에이전트 유형에 `badeuldon-developer` 등 6개 표시 — **미표시 시** 폴백: `.zcode/agents/*.md`를 `~/.zcode/agents/`(사용자 범위, 공식 문서가 안내하는 위치)로 복사
4. 명령어 frontmatter `model: glm-5.3` / `glm-5.3-flash` 인식 확인

## 후속 수정 3 — 플러그인 경로 폐기, 워크스페이스 전용 리소스 전환 (2026-10-29)

**계기**: 플러그인·마켓플레이스가 프로젝트 전용이 아닌 전역으로 적용됨을 사용자가 지적. 공식 구성 가이드 확인 결과 플러그인에는 워크스페이스 스코프가 없음(설치·활성화가 `~/.zcode/cli/config.json`에 저장되어 모든 워크스페이스에 적용). 반면 커맨드·스킬은 워크스페이스 스코프(`.zcode/commands/`, `.zcode/skills/`)를 공식 지원. 서브에이전트 6개의 `.zcode/agents/` 등록은 이전 단계에서 실측 확인됨(세션의 Agent 도구 유형 목록에 6개 나타남 — Reviewer 읽기 전용 도구 포함).

**조치**:
- 프로젝트: 플러그인 `commands/` → `.zcode/commands/`, `skills/` → `.zcode/skills/` 이동, 에이전트 6개의 참조 스킬 경로 수정, `.zcode/harness-marketplace/` 삭제. 루트 AGENTS.md 하네스 섹션·변경 이력 갱신
- 전역: `config.json` enabledPlugins·`known_marketplaces.json`에서 badeuldon 항목 제거, `~/.zcode/cli/plugins/{marketplaces,cache,data}`의 badeuldon 항목 삭제(편집 전 백업: `/tmp/zcode-config-backup.json`, `/tmp/known-marketplaces-backup.json`)
- 규약 v4.0.3(전역+프로젝트 사본): §1.1~1.2·§1.4 제약 8·§1.7·§4.2·§5.2·§9.2 4~8단계·§10.5·부록 B를 워크스페이스 리소스 구조로 전면 갱신, marketplace.json/plugin.json 예시 삭제
- 메타 스킬 SKILL.md: §2 감사 항목(플러그인 흔적 발견 시 제거 권고 추가)·§3.2 구조 전환·§3.6 검사·§5 C-1 갱신

**효과**: 하네스가 프로젝트 내부에만 존재(다른 프로젝트의 `/` 목록 오염 제거) + 다른 PC에서 git clone만으로 하네스 완결(마켓플레이스 등록 절차 소멸).

**새 세션 검증 항목 (갱신)**:
1. `/` 목록에 `badeuldon_orchestrator`·`badeuldon_orchestrator_lite` 표시(워크스페이스 commands 경유)
2. badeuldon 스킬 6종이 워크스페이스 스코프로 표시
3. 서브에이전트 6개 Agent 도구 유형 유지 확인
4. 다른 프로젝트 워크스페이스에서는 두 명령어가 보이지 않는 것 확인
