# Harness Convention — ZCode Desktop 범용 개발 자동화 하네스 구성 규약

**버전**: 4.0.3
**최종 수정일**: 2026-10-29

---

## 이 문서의 목적

이 문서는 **ZCode Desktop의 Agent, 사용자 정의 명령어, 워크스페이스 스킬, 서브에이전트, AGENTS.md**를 조합해 프로젝트별 AI 개발 자동화 체계(이하 "하네스")를 구성하는 표준과 운영 원칙을 정의한다. 반복적인 개발 사이클(분석 → 문서화 → 구현 → 코드 정리 → 리뷰 → 수정 → 테스트 → 실행 검증 → 완료 보고)을 자동화하고 코드 품질과 비즈니스 규칙 정합성을 보장한다.

핵심 원칙(Phase 파이프라인, 사용자 승인 게이트, 문서 선행, Rule ID, Developer/Reviewer/Tester 역할 분리)은 유지한다. OMP 전용 `modelRoles`, `autoloadSkills`, task tool, Agent Hub, `@../AGENTS.md` import 등의 런타임 규약은 ZCode 규약으로 대체한다.

**모드 설계 핵심**: 프로젝트마다 일반용과 절약용 오케스트레이터 **명령어 2개**를 제공한다. 두 명령어는 같은 오케스트레이터 스킬과 동일한 Phase 절차를 사용하지만, 서로 다른 메인 모델 및 서브에이전트 프로필을 호출한다. 워크플로우 자체를 두 벌 복제하지 않는다.

---

## 목차

1. [하네스 아키텍처 개요](#1-하네스-아키텍처-개요)
2. [AGENTS.md — 프로젝트 지식 베이스](#2-agentsmd--프로젝트-지식-베이스)
3. [PRD.md — 기능 명세 표준 구조](#3-prdmd--기능-명세-표준-구조)
4. [전문 에이전트 (Agents)](#4-전문-에이전트-agents)
5. [스킬 (Skills)](#5-스킬-skills)
6. [오케스트레이터 — 개발 프로세스 자동화](#6-오케스트레이터--개발-프로세스-자동화)
7. [설정 및 권한 (Settings)](#7-설정-및-권한-settings)
8. [작업 디렉토리 및 컨텍스트 관리](#8-작업-디렉토리-및-컨텍스트-관리)
9. [새 프로젝트 설정 가이드](#9-새-프로젝트-설정-가이드)
10. [운영 및 유지보수](#10-운영-및-유지보수)
11. [Anti-Patterns — 하지 말아야 할 것](#11-anti-patterns--하지-말아야-할-것)
12. [부록](#12-부록)

---

## 1. 하네스 아키텍처 개요

### 1.1 구성 요소 관계도

```text
프로젝트 AGENTS.md + PRD.md + HARNESS_CONVENTION.md
                  │
                  ▼
   워크스페이스 전용 하네스 리소스 (.zcode/{commands,skills,agents})
                  │
       ┌──────────┴──────────┐
       ▼                     ▼
/{project_command_prefix}_orchestrator   /{project_command_prefix}_orchestrator_lite
   일반 모드 명령어           절약 모드 명령어
       │                     │
       └──────────┬──────────┘
                  ▼
   공통 {project}-orchestrator 스킬
   (동일한 Phase 0~9, 승인 게이트, 산출물 규칙)
                  │
       ┌──────────┼──────────┐
       ▼          ▼          ▼
   Developer   Reviewer    Tester
   일반 프로필   일반 프로필  일반 프로필
       또는       또는        또는
   Developer   Reviewer    Tester
      -lite       -lite       -lite
                  │
                  ▼
     .zcode/progress.json + _workspace/
```

### 1.2 구성 파일 트리

프로젝트 내 모든 하네스 설정은 워크스페이스 스코프 리소스로 구성하고 Git으로 관리한다. 플러그인·마켓플레이스는 사용하지 않는다(§1.4 제약 8).

```text
프로젝트 루트/
├── AGENTS.md                         # ZCode가 읽는 프로젝트 지식 베이스
├── PRD.md                            # 기능 명세·Rule ID·에러 코드
├── HARNESS_CONVENTION.md             # 프로젝트가 따르는 하네스 규약 사본
├── ARCHITECTURE_CONVENTION.md        # 선택: 아키텍처 표준
├── .zcode/
│   ├── progress.json                 # Git 추적 진행 상태
│   ├── commands/                     # 오케스트레이터 명령어 2개 (워크스페이스 스코프)
│   │   ├── {project}_orchestrator.md
│   │   └── {project}_orchestrator_lite.md
│   ├── skills/                       # 공통 오케스트레이터 + 참조 스킬
│   │   ├── {project}-orchestrator/SKILL.md
│   │   ├── {project}-business-rules/SKILL.md
│   │   ├── {project}-feature-dev/SKILL.md
│   │   ├── {project}-review-checklist/SKILL.md
│   │   ├── {project}-test-patterns/SKILL.md
│   │   └── {project}-git-deploy/SKILL.md  # 선택
│   └── agents/                       # 서브에이전트 프로필 6개 — 런타임 감시 위치(실측)
│       ├── {project}-developer.md
│       ├── {project}-reviewer.md
│       ├── {project}-tester.md
│       ├── {project}-developer-lite.md
│       ├── {project}-reviewer-lite.md
│       └── {project}-tester-lite.md
└── _workspace/                       # Phase별 산출물, Git 추적
    ├── 01_plan.md
    ├── 02_prd_update.md
    ├── 03_implementation.md
    ├── 05_review.md
    ├── 07_test_report.md
    └── 08_run_report.md
```

전역 하네스 메타 스킬은 프로젝트 밖에 한 번만 설치한다:

```text
~/.zcode/skills/harness/
├── SKILL.md
└── HARNESS_CONVENTION.md
```

ZCode는 프로젝트 루트 `AGENTS.md`와 사용자 전역 `~/.zcode/AGENTS.md`를 읽지만, 하위 디렉터리의 `AGENTS.md`를 자동 병합하거나 `@../AGENTS.md`를 확장하지 않는다. 따라서 중요한 프로젝트 규칙은 루트 `AGENTS.md`에 둔다. 이 동작은 ZCode 버전에 따라 달라질 수 있으므로 공식 문서에서 현재 동작을 확인한다.

### 1.3 핵심 설계 원칙

| 원칙 | 설명 |
|:---|:---|
| **관심사 분리** | 구현·리뷰·테스트를 독립된 전문 서브에이전트로 분리 |
| **모델 차등화** | 일반/절약 명령어별로 역할마다 다른 모델과 추론 수준을 지정 |
| **단일 워크플로우** | 일반/절약 명령어는 같은 오케스트레이터 스킬을 사용하며 Phase 규칙을 복제하지 않음 |
| **정적 지식 베이스** | AGENTS.md + PRD.md에 프로젝트 컨텍스트를 기록 |
| **Phase 기반 파이프라인** | 분석 → 승인 → 문서화 → 구현 → 정리 → 리뷰 → 수정 → 테스트 → 실행 검증 → 완료 보고 |
| **사용자 승인 게이트** | 계획을 보고하고 사용자가 승인하기 전에는 Developer/Reviewer/Tester를 호출하지 않음 |
| **파일 기반 데이터 전달** | Phase 간 결과를 `_workspace/` 파일로 전달해 컨텍스트 단절을 줄임 |
| **Git 추적 진행 상태** | `.zcode/progress.json`과 `_workspace/`를 Git으로 추적 |
| **문서 선행** | 코드 구현 전에 PRD.md/AGENTS.md를 필요한 범위에서 갱신 |

### 1.4 모델 프로필 정책 — 일반 모드와 절약 모드

OMP의 `modelRoles`와 달리 ZCode는 명령어 frontmatter에 메인 모델을, 서브에이전트 정의에 각 에이전트의 모델·추론 수준을 직접 지정한다. 따라서 ZCode에서는 **모델 프로필을 명시한 6개의 서브에이전트 정의 파일**을 만든다.

| 역할 | 일반 모드 프로필 | 절약 모드 프로필 |
|:---|:---|:---|
| 메인 Agent / Planner | GLM-5.3 | GLM-5.3-Flash |
| Developer | GLM-5.3-Flash · High | GLM-5.3-Flash · Low |
| Reviewer | GLM-5.3 · High | GLM-5.3-Flash · High |
| Tester | GLM-5.3-Flash · High | GLM-5.3-Flash · Low |

**중요한 설정 제약**:

1. ZCode 명령어 frontmatter의 공식 문서상 `model`은 지원되지만 명령어별 `thoughtLevel` 지정은 문서화되어 있지 않다. 따라서 명령어는 메인 모델을 선택하고, 메인 Agent의 추론 수준은 ZCode UI의 모델/추론 수준 선택에서 확인한다. 사용자 스크린샷에서는 GLM-5.3이 선택되어 있고 Effort가 `Max`로 표시된다. 이 화면은 현재 선택 상태를 증명하지만 명령어로 Effort를 자동 변경할 수 있음을 증명하지는 않는다.
2. 서브에이전트는 `model`과 `thoughtLevel`을 각 정의에 지정할 수 있다. `thoughtLevel`은 특정 모델을 명시했을 때만 적용된다. ZCode 공식 문서는 GLM-5.3에 `low`, `high`, `max` 수준을 명시한다. Flash에서 사용할 수 있는 수준은 Flash를 선택한 뒤 UI/실행에서 확인한다.
3. 사용자가 제공한 ZCode 화면에서 Z.ai Individual의 모델 표시명 `GLM-5.3`과 `GLM-5.3-Flash`가 확인되었다. 이 규약은 해당 내장 모델의 `model` 값으로 각각 `glm-5.3`, `glm-5.3-flash`를 우선 사용한다. 단, 스크린샷은 UI 표시명만 보여주고 런타임 내부 ID를 직접 노출하지 않으므로 실제 실행 검증이 필수다. `model not found` 등 오류가 나면 ZCode Settings → Model Settings 또는 ZCode가 생성한 서브에이전트 정의에서 실제 ID를 확인해 수정하며, OMP 전용 `zai/glm-5.3` 표기를 추정해 붙이지 않는다.
4. ZCode 명령어의 모델 변경만으로 명시적 모델을 가진 서브에이전트가 자동 전환되지는 않는다. 일반/절약 모드마다 다른 서브에이전트 프로필을 호출한다.
5. 일반 모드 명령어는 `*-developer`, `*-reviewer`, `*-tester`만 호출한다. 절약 모드 명령어는 `*-developer-lite`, `*-reviewer-lite`, `*-tester-lite`만 호출한다.
6. 플러그인 manifest의 `agents` 필드는 기록만 되고 세션 서브에이전트로 실행되지 않는다(2026-10-29 실측). 서브에이전트 정의 파일은 프로젝트 `.zcode/agents/`에 둔다 — 런타임이 이 경로를 감시해 세션 시작 시 Agent 도구 유형으로 등록한다.
7. `/` 명령 목록과 서브에이전트 등록은 세션 시작 시 스캔되므로, 리소스 설치·변경 후에는 새 세션에서 발견을 확인한다.
8. **플러그인은 하네스에 사용하지 않는다(4.0.3부터 표준).** 플러그인에는 워크스페이스 스코프가 없어 설치·활성화가 사용자 전역으로 적용되고(실측), 명령어·스킬이 모든 프로젝트에 노출된다. 플러그인 route에는 추가 실측 장애가 있었다 — marketplace.json의 `pluginRoot`는 현재 빌드의 소스 경로 해석에 적용되지 않는다. 프로젝트 전용 하네스는 워크스페이스 스코프를 공식 지원하는 `.zcode/{commands,skills,agents}` 리소스로 구성한다.

### 1.5 트리거 메커니즘 — 명령어 우선

ZCode에서 일반 개발 요청을 자동 매칭에만 의존하면 오케스트레이터를 건너뛸 수 있다. 프로젝트 `AGENTS.md`에는 모든 기능 구현·버그 수정·리팩터링·테스트·리뷰 요청에 해당 프로젝트의 오케스트레이터 명령어를 사용하라고 명시한다. 그러나 가장 신뢰할 수 있는 일상 운영 방식은 사용자가 직접 명령어를 선택하는 것이다.

- 일반 모드: `/{project_command_prefix}_orchestrator <작업 요청>`
- 절약 모드: `/{project_command_prefix}_orchestrator_lite <작업 요청>`
- 하네스 신규 구성/감사/동기화: `$harness <요청>`

명령어는 `commands/*.md`에 두며 `description`, `model`, `skills` 등의 ZCode 지원 frontmatter 필드를 사용한다. 일반용과 절약용 명령어는 같은 `{project}-orchestrator` 스킬을 자동 로드하도록 설정한다. ZCode 문서의 명령어 이름 허용 패턴에는 하이픈이 포함되지 않으므로, 명령어 파일명/호출명에는 `{project_command_prefix}`(소문자 프로젝트명을 `_`로 정규화)를 사용한다. 스킬 디렉터리명은 kebab-case를 유지해도 된다.

### 1.6 하네스가 실제로 실행됐는지 확인하는 방법

1. `/` 명령 패널에서 명령어가 일반용과 절약용 두 개 모두 표시되는지 확인한다. 명령어 목록은 세션 시작 시 스캔되므로, 리소스 설치·변경 직후라면 새 세션에서 확인한다.
2. 선택한 명령어가 해당 모드의 메인 모델을 선택하는지 확인한다.
3. 계획을 먼저 출력하고 `awaiting_approval` 상태를 기록하는지 확인한다.
4. 사용자 승인 전에는 어떤 Developer/Reviewer/Tester 서브에이전트도 호출되지 않는지 관찰한다.
5. 승인 후 올바른 모드의 에이전트가 호출되고, 산출물이 `_workspace/`에 기록되는지 확인한다.
6. 최종 보고에서 실행 모드, 호출된 에이전트 이름, 모델, 테스트 결과를 명시한다.

ZCode Plan mode는 계획을 먼저 제시하고 확인 후 편집을 시작하는 데 도움이 되지만, **Plan mode만으로 서브에이전트 호출까지 무조건 차단된다고 가정하지 않는다.** 승인 전 에이전트 미호출 여부는 규칙과 실제 검증으로 확인해야 한다.

### 1.7 ZCode 구성 표준

| 개념 | ZCode 표준 |
|:---|:---|
| 지식 베이스 | 루트 `AGENTS.md` + 전역 `~/.zcode/AGENTS.md` |
| 프로젝트 하네스 등록 | 불필요 — 워크스페이스 `.zcode/{commands,skills,agents}` 리소스(플러그인·마켓플레이스 미사용) |
| 일반/절약 진입점 | `.zcode/commands/{project}_orchestrator.md`, `.zcode/commands/{project}_orchestrator_lite.md` |
| 공통 워크플로우 | `.zcode/skills/{project}-orchestrator/SKILL.md` |
| 서브에이전트 정의 | `.zcode/agents/{project}-{role}.md` 및 `-lite` |
| 에이전트 모델 지정 | 서브에이전트 frontmatter `model`, `thoughtLevel` |
| 명령어 모델 지정 | 명령어 frontmatter `model` |
| 강제 스킬 호출 | `$harness` 또는 `/` 패널의 `$` 스킬 선택 |
| 파이프라인 산출물 | `_workspace/` |
| 진행 상태 | `.zcode/progress.json` |
| 승인을 위한 UI | ZCode Plan mode + 오케스트레이터의 승인 대기 프로토콜 |
| 컨텍스트 압축 | ZCode의 `/compact` 및 프로젝트 파일 산출물 |

**ZCode 범위 제약**: 사용자 정의 서브에이전트는 공식 문서상 Beta이며, 공식 문서는 사용자 범위(`~/.zcode/agents/`)만 안내한다. 실측으로는 런타임이 프로젝트 `.zcode/agents/`도 감시하므로, 이 규약은 프로젝트 프로필을 `.zcode/agents/`에 두어 Git으로 관리한다. 명령어(`.zcode/commands/`)와 스킬(`.zcode/skills/`)은 공식 문서가 워크스페이스 스코프를 보장한다. 플러그인은 사용하지 않는다 — 워크스페이스 스코프가 없어 전역 적용되고 `agents` 필드는 미실행(§1.4 제약 6·8). 명령어·에이전트 발견은 세션 시작 시 스캔되므로 리소스 변경 후에는 신규 세션에서 검증한다.

**공식 문서**: [ZCode Agent](https://zcode.z.ai/en/docs/agents) · [Commands](https://zcode.z.ai/en/docs/commands) · [Skills](https://zcode.z.ai/en/docs/skill) · [Subagents](https://zcode.z.ai/en/docs/subagents) · [Plugins](https://zcode.z.ai/en/docs/plugin)

## 2. AGENTS.md — 프로젝트 지식 베이스

### 2.1 목적

`AGENTS.md`는 ZCode가 Workspace 시작 시 프로젝트 지침으로 읽는 지식 베이스다. 사용자 전역 `~/.zcode/AGENTS.md`와 현재 Workspace의 루트 `AGENTS.md`가 함께 사용되며, 프로젝트 지침을 우선 기준으로 삼는다.

**핵심 원칙**: 프로젝트에 대한 모든 컨텍스트(아키텍처, 규칙, 컨벤션, 진행 상황)가 이 파일에 집약되어야 한다. 새 PC에서 클론 받아도 이 파일만 읽으면 프로젝트를 이해하고 작업을 재개할 수 있어야 한다.

### 2.2 필수 섹션

AGENTS.md는 다음 섹션을 반드시 포함해야 한다:

```markdown
# AGENTS.md

이 파일은 ZCode Agent와 프로젝트 하네스 서브에이전트가 이 저장소에서 작업할 때 참고할 가이드입니다.

---

## 프로젝트 개요
- 프로젝트의 정체성, 목적, 도메인을 3~5문장으로 설명
- 핵심 비즈니스 가치와 차별점 명시
- 시스템 구성도 (텍스트 다이어그램)

## 기술 스택
- 언어, 프레임워크, 주요 라이브러리 (버전 명시)
- 데이터베이스, 메시징, 캐싱 등 인프라
- 관측 가능성 도구 (로깅, 모니터링, 추적)

## 빌드 및 실행 명령어
- 빌드, 테스트, 실행, 중지 방법
- 자주 사용하는 커스텀 명령어

## 데이터베이스 (해당 시)
- 환경별 전략 표
- 마이그레이션 컨벤션
- 접속 정보 (개발 환경)

## 아키텍처
- **ARCHITECTURE_CONVENTION.md가 존재하면 해당 문서를 우선 참조한다**
- 시스템 구성도 (텍스트 다이어그램)
- 패키지 구조
- 계층형 아키텍처 설명 (e.g., Handler → Service → Repository → Model)

## 핵심 비즈니스 규칙 (도메인별)
- 각 도메인의 핵심 규칙을 Rule ID와 함께 명시
- 데이터 격리 원칙 (해당 시)
- 상태 전이, 번호 할당 등 도메인 특수 규칙

## API 컨벤션
- 통일 응답 포맷
- HTTP 상태 코드 규칙
- 문서화 규칙 (Swagger/OpenAPI 등)
- URL 네이밍 컨벤션

## 코딩 컨벤션
- **들여쓰기: 스페이스만 사용(탭 문자 \t 금지). Ruby·JavaScript·HTML·ERB는 2칸, 그 외 언어는 4칸**
- 코드 포매팅 규칙
- Import 규칙
- 네이밍 컨벤션 (파일, 클래스, 변수, DB)
- 금지/권장 패턴

## 테스트 전략
- 테스트 프레임워크 및 계층
- 테스트 환경 설정
- 커버리지 기대치

## 하네스: {프로젝트명} 개발 자동화
- 목표, 트리거 규칙, 변경 이력
- 오케스트레이터를 사용해야 하는 상황 명시

## 구현 진행 상황 (로드맵)
- 완료된 작업 표
- 진행 중인 작업
- 예정된 작업
- 작업 재개 가이드
```

### 2.3 참조 문서

AGENTS.md와 함께 다음 문서들을 프로젝트에 포함한다:

| 문서 | 용도 | 경로 예시 |
|:---|:---|:---|
| **PRD.md** | 기능 명세, 비즈니스 규칙 백과사전, DB 스키마 상세 | `/PRD.md` |
| **ARCHITECTURE_CONVENTION.md** | 사내 백엔드 아키텍처 표준 규약 (존재 시) | `/ARCHITECTURE_CONVENTION.md` |
| **HARNESS_CONVENTION.md** | 사내 하네스 구성 표준 규약 (이 문서) | `/HARNESS_CONVENTION.md` |
| CHANGELOG.md | 변경 이력 | `/CHANGELOG.md` |

**분리 기준**: AGENTS.md가 500줄을 초과하면 도메인별 비즈니스 규칙이나 상세 API 명세는 PRD.md로 분리하고 AGENTS.md에서 경로만 참조한다. AGENTS.md는 "색인"과 "빠른 참조" 역할, PRD.md는 "백과사전" 역할이다.

**아키텍처 컨벤션 참조**: 프로젝트 루트에 `ARCHITECTURE_CONVENTION.md`가 존재하면, 모든 에이전트(Developer·Reviewer·Tester)는 이 문서를 추가로 참조하여 패키지 구조, 계층 분리, 네이밍, 의존성 방향을 준수한다. 파일이 없으면 AGENTS.md의 아키텍처 섹션을 기준으로 자체 판단한다.

### 2.4 문서 현행화

AGENTS.md와 PRD.md는 **구현보다 먼저** 업데이트한다. 이는 하네스 Phase 2에서 강제한다.

---

## 3. PRD.md — 기능 명세 표준 구조

### 3.1 목적

PRD(Product Requirements Document)는 프로젝트의 **실행 가능한 명세(spec)** 다. Developer는 이 문서를 보고 무엇을 구현할지 결정하고, Reviewer는 이 문서를 기준으로 구현이 올바른지 검증하며, Tester는 이 문서의 Rule ID 기준으로 테스트 시나리오를 도출한다.

### 3.2 필수 섹션

```markdown
# {프로젝트명} — 제품 요구사항 명세

**버전**: X.X.X
**최종 수정일**: YYYY-MM-DD

## 1. 개요
- 프로젝트의 목적, 해결하려는 문제, 핵심 사용자

## 2. 시스템 아키텍처
- 상위 레벨 구성도
- 외부 시스템 연동 관계

## 3. 데이터 모델
### 3.1 ERD / 테이블 목록
### 3.2 계정/권한 모델 (해당 시)
### 3.3 데이터 격리 원칙 (Multi-Tenant 등)

## 4. 기능 명세 (API 엔드포인트별)
### 4.1 {도메인 1}
#### 4.1.1 {기능 A} — POST /api/...
- 설명, 요청 파라미터, 응답, 에러 코드
### 4.2 {도메인 2}
...

## 5. UI / 화면 명세 (해당 시)

## 6. 외부 연동 명세 (해당 시)

## 7. 비즈니스 규칙 백과사전
### 7.1 {도메인 1} 규칙
- **{접두어}-001**: {규칙 설명}
- **{접두어}-002**: {규칙 설명}
### 7.2 {도메인 2} 규칙
...

## 8. 에러 코드 전체 목록
### 8.1 성공 코드
### 8.2 실패 코드 (도메인별)

## 9. Enum / 상수 정의 (해당 시)
```

### 3.3 Rule ID 네이밍 컨벤션

모든 비즈니스 규칙은 **고유 Rule ID**를 가져야 한다. 이 ID는 Reviewer가 규칙 준수 여부를 확인할 때, Tester가 테스트 시나리오를 도출할 때 참조 키로 사용된다.

**형식**: `{도메인 접두어}-{3자리 숫자}`

| 도메인 예시 | 접두어 | 설명 |
|:---|:---|:---|
| 계정 (Account) | `AC` | 인증, 계정 계층, 권한 |
| 사용자 (User) | `US` | 프로필, 상태 관리 |
| 결제 (Payment) | `PAY` | 결제 흐름, 환불 |
| 알림 (Notification) | `NOTI` | 발송, 수신, 설정 |

**규칙**:
- Rule ID는 절대 재사용하지 않는다 (폐기된 규칙의 ID는 결번 처리)
- PRD에 새 규칙을 추가할 때는 기존 마지막 번호 + 1
- 하나의 Rule ID는 하나의 검증 가능한 규칙만 기술한다

### 3.4 PRD 현행화 규칙

| 변경 유형 | PRD 갱신 대상 |
|:---|:---|
| 새 API 추가 | 4절 기능 명세 + 7절 비즈니스 규칙 + 8절 에러 코드 |
| 기존 API 파라미터 추가 | 4절 해당 엔드포인트 + 7절 (규칙 추가 시) |
| 비즈니스 로직 변경 | 7절 Rule ID 설명 업데이트 |
| 새 ErrorCode 추가 | 8절 실패 코드 목록 |
| DB 스키마 변경 | 3절 데이터 모델 |
| 새 Enum/상수 추가 | 9절 |

---

## 4. 전문 에이전트 (Agents)

### 4.1 3-에이전트 패턴

모든 프로젝트는 **3개의 전문 에이전트**로 구성한다. 개발의 핵심 역할(구현, 검증, 테스트)을 분리하여 각각 최적화된 지시사항과 모델을 적용한다.

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Developer  │ ──→ │  Reviewer   │ ──→ │   Tester    │
│  (구현 롤)   │     │  (리뷰 롤)   │     │  (구현 롤)   │
│  기능 구현   │     │  비즈니스 검증│     │  테스트 실행  │
└─────────────┘     └─────────────┘     └─────────────┘
       ↑                   ↑                   ↑
       └───────────────────┼───────────────────┘
                           │ 오케스트레이터(세션 모델)가 통제
                           │ (수정 피드백 루프)
```

### 4.2 ZCode 서브에이전트 정의 파일 포맷

서브에이전트 정의는 다음 위치에 둔다(워크스페이스 스코프 — Git 추적):

`.zcode/agents/`

일반/절약 모드가 서로 다른 모델을 사용하므로 역할마다 두 정의를 둔다. ZCode 서브에이전트 frontmatter의 주요 키는 `name`, `description`, `model`, `thoughtLevel`, `tools`, `injectAgentsMd`다. OMP의 `autoloadSkills`나 `model: "@developer"` 모드별 서브에이전트 프로필 지정에는 사용하지 않는다.

```markdown
---
name: "{project}-developer"
description: "{프로젝트명} 구현 전문가. 승인된 작업을 PRD와 AGENTS.md에 맞게 구현한다."
model: glm-5.3-flash
thoughtLevel: high
color: green
injectAgentsMd: true
---

# {Project} Developer

## 핵심 역할
- 승인된 구현 계획과 관련 Rule ID를 기준으로 코드만 구현한다.
- AGENTS.md, PRD.md 및 기존 코드 패턴을 확인한다.
- 완료 시 변경 파일, 검증 명령, 미해결 사항을 보고한다.
```

**프로필 운영 규칙**:
- 일반 프로필 `model`과 `thoughtLevel`은 일반 모드 표를 따르고, `-lite` 프로필은 절약 모드 표를 따른다.
- Reviewer 프로필은 가능한 한 읽기 전용 도구만 부여한다. ZCode에서 도구 제한을 설정한 경우 허용 목록에 없는 도구는 호출할 수 없다.
- ZCode 서브에이전트 frontmatter에는 OMP의 `autoloadSkills`와 동등한 범용 스킬 자동 할당 필드가 없다. 필수 규칙은 루트 `AGENTS.md`/PRD와 각 에이전트의 시스템 프롬프트에 포함하고, 오케스트레이터 명령어가 공통 오케스트레이터 스킬을 로드하도록 한다.
- 파일에서 모델 ID를 변경한 뒤에는 새 ZCode 세션에서 적용 여부를 검증한다.

### 4.3 Developer 에이전트 (구현)

| 속성 | 값 |
|:---|:---|
| **파일명** | `{project}-developer.md` |
| **모델 프로필** | 일반: `{project}-developer` / 절약: `{project}-developer-lite` |
| **관련 지식** | PRD.md, AGENTS.md, `{project}-business-rules`, `{project}-feature-dev` (필수 규칙은 문서/프롬프트에 포함) |
| **역할** | 기능 구현, 코드 수정, 리뷰 피드백 반영 |

**핵심 책임**:
1. AGENTS.md와 PRD를 참조하여 코드 생성 및 수정
2. 정해진 레이어 순서대로 구현
3. 기존 코드의 패턴과 일관성 유지
4. API 문서화 및 예외 처리 완결성 보장
5. 구현 코드의 자체 점검 (체크리스트 기반)

### 4.4 Reviewer 에이전트 (검증)

| 속성 | 값 |
|:---|:---|
| **파일명** | `{project}-reviewer.md` |
| **모델 프로필** | 일반: `{project}-reviewer` / 절약: `{project}-reviewer-lite` |
| **관련 지식** | PRD.md, AGENTS.md, `{project}-business-rules`, `{project}-review-checklist` (필수 규칙은 문서/프롬프트에 포함) |
| **역할** | 비즈니스 규칙 정합성, 데이터 무결성, 아키텍처 준수 검증 |

**핵심 책임**:
1. **비즈니스 로직 정합성**을 최우선으로 검증 (코드 스타일은 부차적)
2. 데이터 격리, 권한 제어 등 보안/무결성 사항 확인
3. 이슈 심각도 분류: `BLOCKER` > `CRITICAL` > `WARNING`
4. "잘못됐다"가 아닌 "규칙 X에 따르면 Y가 잘못되었다. Z로 수정해야 한다" 형식의 건설적 피드백

**이슈 심각도 정의**:
| 심각도 | 기준 | 예시 |
|:---|:---|:---|
| **BLOCKER** | 데이터 정합성 훼손, 보안 취약점, 런타임 에러 유발 | 데이터 격리 누락, DB 마이그레이션 파일 누락 |
| **CRITICAL** | 비즈니스 로직 오류, 규칙 명백한 위반 | 중복 검사 누락, 상태 전이 오류 |
| **WARNING** | 컨벤션 위반, 문서화 누락, 미사용 코드, 성능 개선 여지 | API 문서 누락, import 정리 안 됨, N+1 쿼리 |

### 4.5 Tester 에이전트 (테스트)

| 속성 | 값 |
|:---|:---|
| **파일명** | `{project}-tester.md` |
| **모델 프로필** | 일반: `{project}-tester` / 절약: `{project}-tester-lite` |
| **관련 지식** | PRD.md, AGENTS.md, `{project}-business-rules`, `{project}-test-patterns` (필수 규칙은 문서/프롬프트에 포함) |
| **역할** | 테스트 코드 작성, 실행, 실패 원인 분석 |

**핵심 책임**:
1. 비즈니스 규칙의 정상/경계/예외 케이스를 빠짐없이 테스트
2. 계층별 적절한 테스트 작성
3. 테스트 실패 시 **코드 버그인지 테스트 오류인지 반드시 구분**하여 보고
4. 기존 테스트와의 충돌 여부 확인

### 4.6 서브에이전트 수명 주기 — 작업 단위 위임 원칙

각 Phase의 위임은 독립 작업으로 취급한다. ZCode 서브에이전트는 기본 Agent와 격리된 컨텍스트에서 실행되고 결과를 요약해 반환한다. OMP의 Agent Hub, `hub cancel`, parked 로스터 정리 절차는 ZCode 하네스에 적용하지 않는다.

| 원칙 | 내용 |
|:---|:---|
| 작업 범위 명확화 | 한 번의 위임은 하나의 결과물과 완료 기준을 갖는다. |
| 산출물 전달 | 재검토·수정·재테스트는 `_workspace/`의 이전 보고서와 변경 파일을 명시해 별도 호출한다. |
| 재사용 통제 | 역할이 같더라도 새 Phase에서는 기존 결과를 읽고 새로운 호출을 사용한다. 이전 대화가 자동으로 완전하게 전달된다고 가정하지 않는다. |
| 병렬 실행 제한 | 읽기 전용 조사처럼 독립적인 작업만 병렬화한다. 동일 파일을 수정하는 Developer 작업은 병렬화하지 않는다. |
| 완료 확인 | 서브에이전트 결과를 받은 후 오케스트레이터가 실제 diff, 테스트 출력 및 보고서 파일을 직접 확인한다. |

ZCode가 자체적으로 subagent 호출과 수명 주기를 관리하므로, 하네스는 플랫폼 내부 세션을 임의로 종료하거나 로스터를 정리하는 도구 명령을 요구하지 않는다.

## 5. 스킬 (Skills)

### 5.1 스킬 역할 분류

| 유형 | 설명 | 예시 | 호출 방식 |
|:---|:---|:---|:---|
| **오케스트레이터 워크플로우** | Phase, 승인 게이트, 데이터 흐름을 정의하는 공통 스킬 1개 | `{project}-orchestrator` | 일반/절약 명령어가 자동 로드 |
| **참조 스킬** | 비즈니스 규칙, 구현 패턴, 테스트 패턴 | `{project}-business-rules`, `{project}-feature-dev`, `{project}-test-patterns` | 메인 Agent가 필요 시 호출; 필수 지식은 AGENTS.md/PRD에도 유지 |
| **도구 스킬** | 리뷰 체크리스트, 배포 등 특정 작업 | `{project}-review-checklist`, `{project}-git-deploy` | 명령 또는 스킬로 호출 |
| **메타 스킬** | 하네스 자체의 신규 구성·점검·개선 | `harness` | 사용자 전역 `$harness` |

일반용·절약용 오케스트레이터는 **실행 명령어 두 개**다. 각각이 같은 `{project}-orchestrator` 스킬을 로드한다. Phase 규칙을 두 개의 SKILL.md에 복제하지 않는다.

### 5.2 ZCode 스킬 정의 파일 포맷

위치: `.zcode/skills/{skill-name}/SKILL.md` (워크스페이스 스코프)

```markdown
---
name: "{skill-name}"
description: "{무엇을 언제 사용할지 한국어 트리거 포함}"
---

# {Skill Title}

## 목적
{스킬의 용도, 입력, 출력 및 사용 시점}
```

`name`과 `description`은 필수다. 설명은 1024자 이내로 유지한다. ZCode 스킬은 채팅에서 `$skill-name`으로 직접 호출하거나 명령어의 `skills` 필드로 자동 로드할 수 있다. 스킬 수가 지나치게 많으면 설명 메타데이터가 컨텍스트에 부담을 줄 수 있으므로 실제 사용하는 스킬만 활성화한다.

### 5.3 오케스트레이터 워크플로우 스킬

**파일명**: `{project}-orchestrator/SKILL.md`

이 스킬은 대규모/중규모/소규모 작업의 Phase 진행, 승인 게이트, 문서 선행, 검증 결과, 진행 상태 기록을 정의한다. **스스로 코드를 직접 수정하지 않고** 변경은 해당 모드의 Developer 프로필에 위임한다. 일반/절약 명령어 모두 이 하나의 스킬을 로드하며, 명령어의 지시문으로 호출할 서브에이전트 프로필을 구분한다.

### 5.4 비즈니스 규칙 스킬

PRD의 Rule ID를 간단히 찾을 수 있도록 정리한다. 정합성에 중요한 규칙은 하위 에이전트도 읽을 수 있도록 PRD.md와 루트 AGENTS.md에 유지한다.

### 5.5 기능 개발 가이드 스킬

프로젝트 기술 스택에 맞는 단계별 구현 가이드, 레이어 순서, 기존 코드 참조 방법 및 검증 명령을 제공한다.

### 5.6 코드 리뷰 체크리스트 스킬

Reviewer가 비즈니스 규칙, 데이터 격리, 권한, 데이터 무결성, API 규약을 점검하도록 한다. 리뷰어에게 수정 권한을 주지 않는 것을 권장한다.

### 5.7 테스트 패턴 스킬

정상·경계·예외 조건, 계층별 테스트 패턴 및 테스트 실패 원인 분류 규칙을 제공한다.

### 5.8 배포 스킬

커밋·푸시·PR 생성 등 명시적 배포 요청에만 사용한다. 기본 개발 파이프라인이 사용자 승인 없이 배포·푸시하도록 만들지 않는다.

### 5.9 메타 스킬 (`$harness`)

`~/.zcode/skills/harness/SKILL.md`에 설치한다. `HARNESS_CONVENTION.md`가 같은 디렉터리에 있으면 해당 사본을 읽으며, 현재 프로젝트 루트에 규약 파일이 있으면 프로젝트 사본을 우선한다. 이 스킬은 프로젝트의 워크스페이스 하네스 리소스(명령어 두 개, 공통 오케스트레이터 스킬, 6개 프로필)를 생성하거나 점검한다. 프로젝트 기능 구현은 항상 프로젝트 오케스트레이터 명령어로 진행한다.

## 6. 오케스트레이터 — 개발 프로세스 자동화

### 6.1 작업 규모 판별 (Phase 선택)

모든 개발 요청은 **작업 규모에 따라 Phase 진행 방식이 달라진다**. 불필요한 Phase를 생략하여 효율을 높인다. 단, **사용자 승인 게이트(§6.13)는 모든 규모에서 공통 적용되며 생략할 수 없다.**

#### 대규모 작업 (Full Pipeline) — Phase 0 → 1 → ✋승인 → 2 → 3 → 4 → 5 → 6? → 7 → 8 → 9

**판별 기준** (하나라도 해당되면 Full Pipeline):
- 새 도메인/엔티티 생성
- 새 API 엔드포인트 추가
- 비즈니스 로직이 포함된 기능 구현
- DB 스키마 변경 (마이그레이션 필요)
- 여러 파일(3개 이상)에 걸친 변경

#### 중규모 작업 (Standard Pipeline) — Phase 1 → ✋승인 → 3 → 5 → 7

**판별 기준** (하나라도 해당되면 Standard):
- 기존 로직 수정 (파라미터 추가, 검증 로직 변경)
- 1~2개 파일의 기능적 변경
- 버그 수정 (로직 오류)

**생략되는 Phase**: Phase 2(문서 소폭 수정만 — 전체 PRD 현행화 불필요), Phase 4(변경 범위 작아 기계적 정리 생략), Phase 8(테스트로 충분히 검증), Phase 9(간략 보고로 대체). 단, Phase 5 리뷰에서 이슈 발견 시 Phase 6(수정)은 여전히 실행됨

#### 소규모 작업 (Fast Path) — Phase 1(간이) → ✋승인 → 3 → 7

**판별 기준** (하나라도 해당되면 Fast Path):
- 오타 수정, 메시지 변경
- Import 정리, 코드 포매팅
- 단순 설정값 변경
- 주석 추가/수정
- 테스트만 추가 (기능 변경 없음)

**생략되는 Phase**: Phase 2, 4, 5, 8, 9 (결과만 보고). Phase 1은 간이 플랜(§6.13)으로 대체하며 승인 게이트는 유지된다

### 6.2 Full Pipeline Phase 구조

```
사용자 요청
    │
    ▼
Phase 0: 컨텍스트 확인 (오케스트레이터)
    │   .zcode/progress.json, _workspace/ 확인, resume/신규 결정
    │   작업 규모 판별 → Phase 선택
    ▼
Phase 1: 요구사항 분석 (오케스트레이터)
    │   PRD에서 관련 기능/규칙 식별, 작업 범위 결정
    │   산출물: _workspace/01_plan.md
    ▼
✋ 사용자 승인 게이트 (§6.13)
    │   플랜 요약 보고 후 턴 종료 → 승인 대기
    │   승인 전 어떤 에이전트도 스폰하지 않는다
    ▼
Phase 2: 문서 현행화 ⚠️ 필수 (오케스트레이터)
    │   PRD.md, AGENTS.md를 구현 전에 업데이트
    │   "수정 사항 없음"은 허용되지 않는다
    │   산출물: _workspace/02_prd_update.md
    ▼
Phase 3: 구현 (Developer)
    │   레이어 순서대로 구현
    │   산출물: 소스 파일 + _workspace/03_implementation.md
    ▼
Phase 4: 코드 정리 — 구현 코드 (오케스트레이터)
    │   Phase 3에서 생성된 구현 코드의 미사용 코드 제거, 린터 검증, 컴파일 확인
    │   ※ 테스트 코드는 Phase 7에서 Tester가 자체 정리
    ▼
Phase 5: 코드 리뷰 (Reviewer)
    │   비즈니스 규칙, 데이터 무결성, API 컨벤션 검증
    │   산출물: _workspace/05_review.md
    │
    ├── APPROVED → Phase 7 (바로 테스트)
    ├── CRITICAL/WARNING → Phase 6(수정) → Phase 7 (테스트)
    └── BLOCKER → Phase 6(수정) → Phase 5(재리뷰)
    ▼
Phase 6: 수정 (Developer) [필요 시]
    │   리뷰 피드백 반영
    ▼
Phase 7: 테스트 (Tester)
    │   테스트 코드 작성, 자체 코드 정리, 테스트 실행
    │   ⚠️ 테스트 코드 작성 후 미사용 import·변수 제거는 Tester 책임
    │   산출물: 테스트 파일 + _workspace/07_test_report.md
    │
    ├── 모두 통과 → Phase 8 (실행 검증)
    ├── 실패(코드 버그) → Phase 6 (수정)
    └── 실패(테스트 오류) → Phase 7 재실행
    ▼
Phase 8: 실행 검증 (오케스트레이터)
    │   애플리케이션 실행, WARN 로그 분류
    │   산출물: _workspace/08_run_report.md
    │
    ├── 실행 성공 → Phase 9 (완료 보고)
    └── 실행 실패 → Phase 6 (수정)
    ▼
Phase 9: 완료 보고 (오케스트레이터)
    ├── 최종 결과 요약 보고
    ├── AGENTS.md 구현 진행 상황 갱신
    ├── .zcode/progress.json 리셋
    └── Git 커밋
```

### 6.3 Phase 간 데이터 흐름

각 Phase 간 데이터는 **`_workspace/` 디렉토리의 마크다운 파일**로 전달한다:

- Phase별 입력과 출력을 명시해 세션/모델 변경에도 작업 연속성을 유지한다.
- Git으로 추적해 다른 PC에서도 작업을 재개할 수 있게 한다.
- 리뷰·테스트 감사 추적(audit trail)을 제공한다.

ZCode 서브에이전트는 별도 컨텍스트를 사용하므로, 이전 대화가 자동 전달된다고 가정하지 않는다. 위임 프롬프트에 관련 파일 경로, Rule ID, 변경 요약, 완료 기준을 적고 `_workspace/03_implementation.md`, `_workspace/05_review.md`, `_workspace/07_test_report.md` 등을 함께 읽도록 지시한다.

### 6.4 진행 상태 관리

`progress.json`으로 현재 Phase를 추적한다 (Git 관리):

**세션 todo 동기화**: 오케스트레이터는 작업 시작 시 Phase 구조로 Phase 진행 상황을 UI와 `.zcode/progress.json`에 기록한다. 갱신 트리거 2가지: ① **에이전트 결과 수신 직후의 첫 도구 호출 = Phase 완료 상태** — 다음 스폰·검증·문서 작업보다 반드시 먼저 수행한다(이 순서를 놓치는 것이 누적 누락의 주된 원인이다), ② `progress.json` 갱신 시 반드시 세트 갱신. UI의 작업 목록은 Git으로 추적되는 `.zcode/progress.json`을 대체하지 않는다.

```json
{
  "domain": "{현재 작업 도메인명}",
  "currentPhase": "phase5_review",
  "pipelineType": "full",
  "phaseHistory": [
    {"phase": "phase1_plan", "status": "DONE"},
    {"phase": "phase3_implement", "status": "DONE"},
    {"phase": "phase5_review", "status": "IN_PROGRESS"}
  ],
  "lastUpdated": "2026-01-01T12:00:00"
}
```
승인 게이트 대기 중에는 `currentPhase: "awaiting_approval"`를 사용한다(§6.13).

### 6.5 Phase 4: 코드 정리 — 미사용 코드 제거 및 포매팅 검증

이 Phase는 오케스트레이터가 직접 실행하며, 자동화 가능한 코드 품질 검사를 **테스트 코드를 포함한 전체 소스**에 대해 수행한다. 모델 추론이 필요 없는 기계적 검증이므로 추론 특화 모델을 사용하지 않는다.

**⚠️ 중요: 메인 소스와 테스트 소스를 모두 검사한다.** 테스트 코드에서도 미사용 import, 미사용 변수, 미사용 심볼 참조 문제가 자주 발생한다.

**공통 검사 항목**:

| 항목 | 범위 | 방법 |
|:---|:---|:---|
| **미사용 import 제거** | 메인 + 테스트 전체 | 언어별 정적 분석 도구 또는 린터 (`autoflake`, `eslint`, `ruff check`, `gofmt` 등) |
| **미사용 지역 변수 제거** | 메인 + 테스트 전체 | 언어별 린터. 선언만 되고 사용되지 않는 함수/메서드 내 지역 변수 검출 |
| **미사용 private 필드/메서드 제거** | 메인 + 테스트 전체 | 언어별 린터. 선언만 되고 참조되지 않는 멤버 검출 (단, 컴파일 시점에 자동 생성되는 getter/setter/builder 등이 처리하는 필드는 예외) |
| **들여쓰기 및 공백 검증** | 메인 + 테스트 전체 | **Ruby·JavaScript·HTML·ERB: 2칸(space), 그 외 언어: 4칸(space). 탭 문자(\t) 금지.** 언어별 포매터로 검증: `prettier --check`, `rubocop`, `black --check`, `gofmt -d` |
| **컴파일/트랜스파일/빌드** | 전체 프로젝트 | 언어별 빌드 도구 (`gradle`, `maven`, `tsc`, `go build`, `cargo build` 등) |

**들여쓰기 표준**: 언어 생태계 표준 도구와의 일치를 위해 **Ruby·JavaScript·HTML·ERB는 2칸(space)**, **그 외 언어는 4칸(space)** 을 사용한다. 공통 규칙: 탭 문자(`\t`) 금지 — 스페이스만 사용. 프로젝트는 각 언어 표준 린터/포매터(RuboCop, Prettier 등)의 Layout 결과를 단일 기준으로 검증한다.

**프로젝트별 커스터마이징 예시** — 아래는 언어별 대표 도구 조합이다. 프로젝트에 실제로 사용하는 도구로 대체한다:

```bash
# ─── TypeScript / JavaScript ───
npx eslint src/ tests/ --rule 'no-unused-vars: error'
npx prettier --check src/ tests/ --tab-width 2
npx tsc --noEmit

# ─── Python ───
ruff check src/ tests/
black --check --diff src/ tests/
mypy src/

# ─── Go ───
gofmt -d ./...
go vet ./...
golangci-lint run ./...

# ─── Rust ───
cargo fmt --check
cargo clippy -- -D warnings
cargo check

# ─── Java (Gradle) ───
./gradlew compileJava compileTestJava

# ─── Kotlin (Gradle) ───
./gradlew compileKotlin compileTestKotlin

# ─── Swift ───
swiftlint lint --strict
xcodebuild -scheme {Scheme} -destination 'platform=iOS Simulator,name=iPhone 16' build
```

### 6.6 Phase 8: 실행 검증

테스트가 통과해도 실제 애플리케이션 구동 시 발생하는 문제(순환 참조, 의존성 주입 실패, 설정 누락 등)를 조기에 발견하기 위한 단계.

**검증 방법**:
1. 프로젝트 빌드 (`./gradlew build -x test`, `npm run build`, `go build ./...` 등)
2. 애플리케이션 백그라운드 실행 (로그 파일로 리다이렉트)
3. 일정 시간 동안 시작 로그 모니터링 → 시작 완료 신호 확인
4. 오류 키워드 검사 (언어/프레임워크별 주요 에러 패턴)
5. WARN 로그 분류: [허용] / [수정 필요] / [주의]

**WARN 분류 기준**:
| 분류 | 예시 | 조치 |
|:---|:---|:---|
| **허용 (Expected)** | 프레임워크 자체 안내, 미구현 기능 관련 경고 | 기록만 하고 진행 |
| **수정 필요 (Fixable)** | 설정 누락, 프로퍼티 매핑 오류 | Phase 4로 회귀하여 수정 |
| **주의 (Watch)** | Deprecated API, 실험적 기능 사용 | 기록, 차기 작업에서 검토 |

### 6.7 되먹임 루프 최소화 전략

리뷰→수정→재리뷰 반복은 전체 처리량을 크게 떨어뜨린다. 다음과 같은 전략으로 루프 횟수를 최소화한다:

| 전략 | 적용 Phase | 설명 |
|:---|:---|:---|
| **문서 선행** | Phase 2 | PRD가 정확해야 Developer가 잘못 구현할 확률이 낮아짐 |
| **자체 체크리스트** | Phase 2 | Developer가 구현 직후 자체 점검하여 상당수 WARNING을 사전 제거 |
| **Phase 4 선제 정리** | Phase 4 | Reviewer가 지적할 기계적 이슈(미사용 import, 포매팅)를 미리 제거 → Reviewer가 비즈니스 로직에만 집중 |
| **BLOCKER 우선 리뷰** | Phase 3 | Reviewer는 BLOCKER 발견 즉시 리뷰 중단하고 보고 → Developer가 빠르게 수정 → CRITICAL/WARNING만 남은 상태로 재리뷰 |
| **수정 범위 제한** | Phase 4 | 리뷰 지적 사항만 최소 수정, 관련 없는 코드는 절대 건드리지 않음 |

**목표**: 하나의 기능 구현에 대해 Phase 5→6→5 루프는 **최대 2회**로 제한한다. 2회 초과 시 원인(PRD 모호함, Developer 이해 부족, Reviewer 과잉 지적)을 분석하고 개선한다.

### 6.8 병렬 실행 기회

독립적인 작업은 병렬로 처리하여 전체 시간을 단축할 수 있다:

| 병렬 가능 패턴 | 예시 |
|:---|:---|
| 여러 도메인 동시 구현 | "Organization CRUD + Department CRUD 동시에 구현해줘" → Developer가 두 작업을 순차 처리하되, Reviewer와 Tester는 각 도메인 완료 시 즉시 투입 |
| 테스트 + 리뷰 동시 진행 | Reviewer가 Service를 검증하는 동안 Tester가 Repository/Controller 테스트 준비 |
| 여러 테스트 클래스 동시 실행 | 독립적인 테스트 클래스는 병렬 실행 가능 |

**주의**: 공유 자원(DB, 파일)을 수정하는 작업은 병렬 실행 시 충돌할 수 있으므로, 병렬 실행 전에 의존성을 확인해야 한다.

### 6.9 에러 핸들링

| 상황 | 대응 |
|:---|:---|
| **에이전트 실패** | 1회 재시도 → 재실패 시 해당 Phase 건너뛰고 완료 보고에 누락 명시 |
| **비즈니스 규칙 충돌/모호함** | PRD 원문 인용, 해석이 모호하면 사용자에게 질의 |
| **컴파일/빌드 실패** | 빌드 명령어 실행하여 오류 로그 수집 → 오류 기반 수정 |
| **테스트 실패** | 실패 원인 분류 (코드 버그 vs 테스트 오류) → 각각 다른 분기 |
| **되먹임 루프 2회 초과** | 사용자에게 상황 보고, 루트 원인 분석 후 진행 방식 재결정 |

### 6.10 Phase별 완료 기준 (Definition of Done)

각 Phase가 "완료되었다"고 판단하는 명확한 기준이다. 기준을 충족하지 못하면 다음 Phase로 넘어가지 않는다.

| Phase | 완료 기준 | 검증 방법 |
|:---|:---|:---|
| **Phase 0** | progress.json과 _workspace/ 상태 파악 완료. 작업 규모(Full/Standard/Fast) 결정됨 | progress.json의 `pipelineType` 필드가 설정됨 |
| **Phase 1** | 작업 범위, 대상 파일, 관련 Rule ID 목록이 `01_plan.md`에 기록됨. PRD/AGENTS.md 수정 필요 항목이 식별됨 | `01_plan.md` 파일이 존재하고 필수 항목이 모두 채워짐 |
| **승인 게이트 (§6.13)** | 플랜 요약이 사용자에게 보고되고 턴이 종료됨. 승인 응답 전 에이전트 스폰·다음 Phase 미진행 | progress.json `currentPhase`가 `awaiting_approval` → 승인 후 다음 Phase 값으로 전환 |
| **Phase 2** | PRD.md, AGENTS.md의 변경 사항이 실제 파일에 반영됨. 문서 버전/날짜 갱신됨. `02_prd_update.md`에 변경 섹션 목록 기록됨 | 변경된 PRD.md의 diff 확인. "수정 사항 없음"은 불허 |
| **Phase 3** | 모든 레이어의 구현 코드가 생성/수정됨. DB 마이그레이션 파일 있음(해당 시). `03_implementation.md`에 변경 파일 목록과 요약이 기록됨 | 소스 파일 존재 + 구현 요약 파일 있음 |
| **Phase 4** | 구현 코드(메인 소스)에서 미사용 import 0건, 미사용 변수 0건, 컴파일/트랜스파일 오류 0건 | `{컴파일 명령어}`(또는 동등 명령) 종료 코드 0 |
| **Phase 5** | 리뷰 결과가 `05_review.md`에 기록됨. BLOCKER 0건 (있으면 Phase 6→5 반복) | `05_review.md`의 status가 APPROVED 또는 CHANGES_REQUESTED(CRITICAL/WARNING only) |
| **Phase 6** | Reviewer가 지적한 모든 이슈가 수정됨. 수정 외 코드 변경 없음 | 수정된 파일 diff가 리뷰 이슈와 1:1 대응 |
| **Phase 7** | 모든 테스트 통과 (실패 0건, 에러 0건). **테스트 코드에서 미사용 import·변수 0건** (Tester가 자체 정리). `07_test_report.md`에 결과 기록됨 | `{테스트 실행 명령어}` 종료 코드 0 + 테스트 소스 린터 통과 |
| **Phase 8** | 애플리케이션 시작 완료 ("Started" 또는 동등 신호 확인). [수정 필요] WARN 0건 | 로그에 시작 완료 메시지 + [수정 필요] WARN grep 결과 0건 |
| **Phase 9** | 사용자에게 최종 보고 전달됨. AGENTS.md 진행 상황 갱신됨. progress.json 리셋됨 | progress.json의 `currentPhase`가 null |

### 6.11 Git 사전 상태 점검 (Phase 0에서 실행)

Phase 0에서 반드시 다음을 확인하고, 문제가 있으면 작업 시작 전에 해결한다.

```bash
# 1. 작업 디렉토리 상태 확인
git status --short

# 2. 추적되지 않은 파일 확인
git ls-files --others --exclude-standard

# 3. 현재 브랜치 확인
git branch --show-current
```

| 상태 | 판단 | 조치 |
|:---|:---|:---|
| **작업 디렉토리 깨끗함** | ✅ 시작 가능 | Phase 진행 |
| **이전 _workspace/ 변경만 있음** | ✅ 시작 가능 | Phase 0에서 이전 컨텍스트로 인식 |
| **소스 코드에 uncommitted 변경 있음** | ⚠️ 주의 | 사용자에게 확인: (1) 먼저 커밋 후 진행, (2) 변경 포함하여 진행, (3) stash 후 진행 |
| **main/master 브랜치에서 직접 작업** | ⚠️ 주의 | 확인 메시지 표시. 새 기능은 브랜치 생성 권장 |
| **미추적 파일 다수** | ⚠️ 주의 | 의도된 파일인지 확인. .DS_Store 등 불필요 파일은 .gitignore에 추가 |

### 6.12 구체적인 실행 예시 (Narrative Walkthrough)

아래는 "사용자(Person) 생성 API 구현" 요청이 Full Pipeline으로 진행되는 실제 예시다.

```
사용자: "사용자(Person) 생성 API 구현해줘"
```

#### Phase 0: 컨텍스트 확인

```
오케스트레이터(세션 모델):
  1. .zcode/progress.json 확인 → currentPhase: null → 새 작업 모드
  2. _workspace/ 존재 → _workspace_prev/로 이동
  3. git status --short → 깨끗함 ✅
  4. PRD.md 확인 → Person 관련 규칙 US-001~US-008 식별
  5. 판단: 새 엔티티 + API 생성 → Full Pipeline
  6. progress.json 생성: {"domain": "3. 사용자 관리", "currentPhase": "phase1_plan", 
     "pipelineType": "full"}
```

#### Phase 1: 요구사항 분석

```
오케스트레이터(세션 모델):
  1. PRD 4.3.4절 "사용자(Person) 생성" 읽음
     - POST /api/persons
     - 요청: organization_id, employee_no, name, valid_begin_time, valid_end_time, 
       is_perpetual, status
     - 응답: PersonResponse
  2. PRD 7절 관련 Rule ID 목록:
     - US-001: employee_no 마스터 계정 내 고유
     - US-003: is_perpetual = true → valid_end_time 무시
     - US-004: valid_end_time > valid_begin_time
     - US-005: status 기본값 ACTIVE
  3. 대상 파일 결정:
     - 신규: PersonCreateRequest DTO, Person entity(확인 필요), PersonService.create(), 
       PersonController.create()
     - 수정: PersonRepository (existsByEmployeeNo 추가)
  4. PRD 수정 필요 항목 식별: ErrorCode 추가 필요 (DUPLICATE_EMPLOYEE_NO, 
     INVALID_VALID_PERIOD)
  5. _workspace/01_plan.md 작성 완료
```

#### ✋ 승인 게이트 (§6.13)

```
오케스트레이터(세션 모델):
  1. progress.json 갱신: currentPhase → "awaiting_approval"
  2. 플랜 요약 보고 — Full Pipeline 확정, Phase 2~9 예정,
     Phase 3(Developer)·Phase 5(Reviewer)·Phase 7(Tester) 스폰 계획,
     변경 예상 파일 6건, 관련 Rule ID US-001/003/004/005
  3. "플랜을 승인하시겠습니까?" 출력 후 턴 종료
  4. 사용자 "승인" 응답 → Phase 2부터 자동 진행 (게이트는 1회, 재승인 없음)
```

#### Phase 2: 문서 현행화

```
오케스트레이터(세션 모델):
  1. PRD.md 4.3.4절: API 명세 검토 → 이미 작성되어 있음 ✅
  2. PRD.md 7절: US-001, US-003, US-004, US-005 설명이 구현 가능하도록 구체적인지 확인
     → US-004의 valid_end_time 검증 조건이 "is_perpetual = false인 경우에만"임을 명확히
  3. PRD.md 8절: DUPLICATE_EMPLOYEE_NO, INVALID_VALID_PERIOD ErrorCode 추가
  4. PRD.md 버전, 최종 수정일 갱신
  5. AGENTS.md: 변경 없음 (Person은 기존 도메인)
  6. _workspace/02_prd_update.md 작성
```

#### Phase 3: 구현

```
Developer(선택한 모드의 Developer 프로필):
  1. PRD 4.3.4절 + US-001~US-005 읽음
  2. 레이어 순서대로 구현:

  [PersonCreateRequest]
  - API 문서화: 사원번호, 예시: EMP001
  - 검증: NotBlank, 최대 32자
  - String employeeNo
  - valid_begin_time, valid_end_time, is_perpetual 필드 추가

  [PersonRepository]
  - existsByMasterAccountIdAndEmployeeNo(Long, String) 추가

  [PersonService]
  - create(Long masterAccountId, PersonCreateRequest request):
    1. US-001 검증: existsByMasterAccountIdAndEmployeeNo → 중복 시 
       DuplicateEmployeeNoException
    2. US-004 검증: is_perpetual = false일 때만 valid_end_time > valid_begin_time 확인
    3. US-003 처리: is_perpetual = true → valid_end_time을 null로 설정
    4. US-005: status 기본값 ACTIVE
    5. Person 엔티티 생성 및 저장
    6. PersonResponse로 변환 반환

  [PersonController]
  - POST /api/persons
  - API 문서화: "3.14 사용자 생성"
  - 에러 응답 문서화: DUPLICATE_EMPLOYEE_NO, INVALID_VALID_PERIOD 문서화
  - 201 Created 응답

  3. _workspace/03_implementation.md 작성
```

#### Phase 4: 코드 정리

```
오케스트레이터(세션 모델):
  1. 미사용 import 검출 (린터) → 0건
  2. 컴파일 검증 (메인 + 테스트) → 성공 ✅
```

#### Phase 5: 코드 리뷰

```
Reviewer(선택한 모드의 Reviewer 프로필):
  1. PersonCreateRequest 검증:
     - API 문서화(description, example) 확인 ✅
     - 검증 어노테이션(NotBlank, Size) 적절함 ✅
  2. PersonService.create() 검증:
     - US-001 중복 검사가 save() 전에 실행됨 ✅
     - US-004: is_perpetual이 true면 valid_end_time 검증 건너뜀 ✅
     - US-003: is_perpetual이 true면 valid_end_time = null 처리 ✅
     - ⚠️ WARNING: valid_begin_time이 null인 경우에 대한 방어 로직 없음
     - ⚠️ WARNING: 조직 존재 여부(organization_id) 확인 누락
  3. PersonController 검증:
     - API 넘버링: 3.14 (GET /api/persons가 3.13이므로 POST는 3.14) ✅
     - 에러 응답 문서화(마크다운 테이블) 있음 ✅

  결과: CHANGES_REQUESTED (WARNING 2건, BLOCKER 0건, CRITICAL 0건)
  → Phase 7로 직행 (WARNING만 있으므로 Phase 6 수정 후 Phase 7 테스트로, Phase 5 재리뷰 불필요)
  
  _workspace/05_review.md 작성
```

#### Phase 6: 수정

```
Developer(선택한 모드의 Developer 프로필):
  Reviewer 지적 사항 수정:
  1. valid_begin_time null 체크 추가 → INVALID_VALID_PERIOD 에러 반환
  2. organizationRepository.existsByMasterAccountIdAndId() 호출 추가 → 
     ORGANIZATION_NOT_FOUND 에러 반환
  
  ※ 리뷰 지적 외 코드는 건드리지 않음
```

#### Phase 7: 테스트

```
Tester(선택한 모드의 Tester 프로필):
  1. PersonServiceTest 작성 및 실행:

  [성공 케이스]
  - create_ShouldSucceed_WithValidRequest → 통과 ✅
  - create_ShouldSetValidEndTimeNull_WhenIsPerpetual → 통과 ✅

  [실패 케이스]
  - create_ShouldThrow_WhenEmployeeNoDuplicate (US-001) → 통과 ✅
  - create_ShouldThrow_WhenValidEndTimeBeforeBeginTime (US-004) → 통과 ✅
  - create_ShouldThrow_WhenValidBeginTimeIsNull → 통과 ✅
  - create_ShouldThrow_WhenOrganizationNotFound → 통과 ✅

  2. PersonControllerTest 작성 및 실행:
  - POST /api/persons → 201 Created → 통과 ✅
  - POST /api/persons (중복 사번) → 409 Conflict → 통과 ✅
  - POST /api/persons (잘못된 기간) → 400 Bad Request → 통과 ✅

  3. 테스트 코드 자체 정리 (Tester 책임):
  - 미사용 import 검사 → 0건 ✅
  - 컴파일 검증 (테스트 소스) → 성공 ✅

  {테스트 실행 명령어} → 6 tests passed, 0 failed ✅
  _workspace/07_test_report.md 작성
```

#### Phase 8: 실행 검증

```
오케스트레이터(세션 모델):
  1. {빌드 명령어} (테스트 제외) → BUILD SUCCESSFUL ✅
  2. {실행 명령어} (백그라운드, 로그: /tmp/app.log)
  3. 30초 모니터링 → "Started Application in 4.2 seconds" ✅
  4. WARN 분석:
     - [허용] Using generated security password (정상)
     총 1건, [수정 필요] 0건 ✅
  5. 프로세스 종료
  6. _workspace/08_run_report.md 작성
```

#### Phase 9: 완료 보고

```
오케스트레이터(세션 모델):

📊 사용자(Person) 생성 API 구현 완료

변경 파일: 4개 생성, 2개 수정
├── 신규: PersonCreateRequest, PersonService(create), 
│         PersonController(create)
├── 수정: PersonRepository, PRD.md, ErrorCode
└── 테스트: PersonServiceTest, PersonControllerTest (신규 6건)

리뷰: CHANGES_REQUESTED → 수정 완료 (WARNING 2건 해결)
테스트: 6/6 통과 ✅
실행 검증: 애플리케이션 구동 정상 ✅

AGENTS.md 구현 진행 상황: Person CRUD → ✅ 완료 처리
progress.json: 리셋 완료
```

---

**이 예시의 교훈**:
- **Phase 2의 가치**: PRD에 ErrorCode를 미리 추가했기 때문에 Developer가 정확한 에러 코드로 구현했다.
- **Phase 4의 가치**: 기계적 이슈를 미리 제거했기 때문에 Reviewer가 비즈니스 로직(WARNING 2건은 의미 있는 지적)에만 집중했다.
- **WARNING만 있었기에 Phase 3 재실행 없이 Phase 5로 직행** — 전체 시간 단축.
- **되먹임 루프 0회**: Developer 자체 체크 + Phase 4 정리 + Reviewer의 정확한 지적으로 단 한 번의 리뷰 사이클로 완료.

### 6.13 사용자 승인 게이트 (Plan Approval Gate)

오케스트레이터는 **플랜에 대한 사용자 승인을 받기 전까지 Developer/Reviewer/Tester 서브에이전트를 호출하지 않는다.** 모든 작업 규모(Full/Standard/Fast Path)에 공통 적용하며, Phase 생략으로도 면제되지 않는다.

#### 시점

| 파이프라인 | 게이트 시점 | 플랜 산출물 |
|:---|:---|:---|
| Full | Phase 1 완료 직후, Phase 2 진입 전 | `_workspace/01_plan.md` |
| Standard | Phase 1 완료 직후, Phase 3 진입 전 | `_workspace/01_plan.md` |
| Fast Path | 간이 Phase 1 후, 구현 전 | 채팅 요약 플랜(변경 파일·변경점 요약) — 파일 생략 가능 |

#### 절차

1. Full/Standard는 `_workspace/01_plan.md`를 작성하고, Fast Path는 간이 계획을 작성한다.
2. `.zcode/progress.json`을 `"currentPhase": "awaiting_approval"`로 갱신한다.
3. 계획 보고에 작업 규모, Phase 순서, 호출 예정 에이전트 및 모드 프로필, 변경 예상 파일, 관련 Rule ID, 리스크와 검증 방법을 포함한다.
4. 응답 끝에 명시적으로 승인 여부를 묻고 **턴을 종료한다**. 같은 응답에서 Developer/Reviewer/Tester를 호출하거나 구현을 시작하지 않는다.

**ZCode 실행 모드와의 관계**: ZCode Plan mode(입력 상자에서 `Shift+Tab`으로 선택 가능)는 계획 검토와 UI 확인 절차를 보조한다. 그러나 Plan mode의 UI 확인만으로 "승인 전 서브에이전트 호출 금지"가 완벽히 보장된다고 가정하지 않는다. 공통 오케스트레이터 스킬과 양쪽 명령어 본문에 하드 룰을 넣고, 최초 검증 시 실제로 승인 전 호출이 일어나지 않는지 확인한다.

#### 승인 응답 분기

| 사용자 응답 | 처리 |
|:---|:---|
| 승인("진행", "OK", "승인" 등) | `.zcode/progress.json`을 다음 Phase로 갱신하고 후속 Phase 진행. 이후 리뷰·테스트·수정 루프의 재승인은 원칙적으로 요구하지 않음 |
| 수정 요청 | 계획 수정 후 다시 보고하고 승인 대기 |
| 중단 | 진행 상태를 정리하고 종료. 미완료 작업 흔적은 삭제하지 말고 보고 |

#### 세션 재개

`.zcode/progress.json`의 `currentPhase`가 `awaiting_approval`이면 먼저 기존 계획을 요약하고 다시 승인을 기다린다. 승인 상태가 확인되지 않거나 Git에 상태가 없으면 승인받았다고 추정하지 않는다.

#### 강제 규칙 배치

동일한 승인 규칙을 아래 세 곳에 둔다:

1. 루트 `AGENTS.md`의 하네스 섹션
2. `{project}-orchestrator/SKILL.md`
3. 일반/절약 양쪽 `commands/*.md` 본문

`.zcode/RULES.md`는 ZCode가 자동으로 읽는 표준 강제 규칙 파일이라고 가정하지 않는다. 핵심 규칙은 공식적으로 자동 주입되는 파일과 실제 호출 명령어에 둔다.

## 7. 설정 및 권한 (Settings)

### 7.1 승인 및 권한

ZCode의 실행 모드는 파일 편집과 명령 실행 권한을 제어한다. `Ask before changes`, `Edit automatically`, `Plan`, `Full access` 중 작업 위험도에 맞게 선택한다. 복잡하거나 영향 범위가 큰 작업은 Plan mode를 권장한다. 단, 도구 권한 승인과 하네스의 업무 계획 승인 게이트는 서로 다른 절차다.

- **개발/테스트 명령어**: 프로젝트에서 실행할 빌드·테스트 명령을 확인하고 필요할 때만 허용한다.
- **Git 명령어**: 커밋·푸시는 사용자의 명시적 요청 및 배포 스킬의 안전 점검 이후 실행한다.
- **민감 파일**: `.env`, 인증서, 프로덕션 설정, 키 파일을 읽거나 커밋할 때 각별히 주의한다.
- **Reviewer**: 도구 권한을 제한할 수 있다면 기본적으로 읽기 전용 도구만 부여한다.
- **외부 경로**: 프로젝트 밖 파일 변경, 파괴적 명령, 배포 등은 사용자 확인 없이 실행하지 않는다.

### 7.2 권한 부여 원칙

| 원칙 | 설명 |
|:---|:---|
| **필요 최소 권한** | 역할별로 실제 필요한 도구만 활성화 |
| **명시적 위험 관리** | 삭제, 배포, 커밋·푸시, DB 변경은 영향 범위를 설명하고 승인 획득 |
| **Git 관리 신중히** | `git commit`, `git push`는 명시적인 사용자 요청 후 수행 |
| **민감 파일 보호** | `.env`, `*.p12`, `*.jks` 등의 비밀 정보 노출·커밋 방지 |

### 7.3 모드별 권한 및 설정 확인

일반/절약 모드 변경은 모델 및 에이전트 프로필 변경이지 권한 정책 완화가 아니다. 절약 모드에서도 동일한 사용자 승인 게이트와 보안 검사를 유지한다. 명령어·스킬·에이전트 정의를 바꾼 뒤에는 새 세션에서 적용 상태를 확인한다(발견은 세션 시작 시 스캔).

## 8. 작업 디렉토리 및 컨텍스트 관리

### 8.1 _workspace/ 디렉토리

`_workspace/`는 모든 Phase의 중간 산출물을 저장한다. **Git으로 관리**한다.

**파일 네이밍**: `{phase#}_{description}.md`

| 파일 | Phase | 내용 |
|:---|:---|:---|
| `01_plan.md` | Phase 1 | 작업 범위, 대상 파일, 관련 Rule ID |
| `02_prd_update.md` | Phase 2 | 갱신된 PRD/AGENTS.md 섹션 목록 |
| `03_implementation.md` | Phase 3 | 변경 파일 목록 및 요약 |
| `05_review.md` | Phase 5 | 리뷰 상태(APPROVED/CHANGES_REQUESTED), 이슈 목록 |
| `07_test_report.md` | Phase 7 | 테스트 통과/실패 건수, 실패 상세 |
| `08_run_report.md` | Phase 8 | 실행 성공/실패, WARN 분류 |

### 8.2 작업 재개 전략

1. **Git Clone 후**: `.zcode/progress.json` → `currentPhase`의 다음 Phase부터. 단 `awaiting_approval`이면 플랜 요약 재보고 후 승인 대기부터 재개한다(§6.13)
2. **기존 PC에서 새 작업**: `_workspace/` → `_workspace_prev/`로 이동 후 Phase 1부터
3. **부분 재실행**: 해당 Phase만 재실행, 연관 산출물만 교체

---

## 9. 새 프로젝트 설정 가이드

### 9.1 사전 조건

- ZCode Desktop이 설치되어 있고 Z.ai/BigModel Coding Plan 또는 사용할 모델 서비스가 연결되어 있을 것
- Git 저장소가 초기화되어 있을 것
- 프로젝트 루트와 핵심 소스가 준비되어 있을 것(신규 프로젝트면 기본 골격부터 생성)
- `~/.zcode/skills/harness/SKILL.md`와 같은 디렉터리의 `HARNESS_CONVENTION.md`가 설치되어 있을 것
- ZCode 모델 선택기에서 GLM-5.3과 GLM-5.3-Flash를 실제 선택할 수 있는지 확인할 것

### 9.2 단계별 설정 — ZCode Desktop

#### 0단계: 모델 연결

ZCode의 모델 선택기 또는 Settings → Models에서 사용할 Z.ai/BigModel 계정을 연결한다. 터미널 OMP의 API 환경 변수와 ZCode 데스크톱 설정은 자동 동기화되지 않으므로 별도로 설정한다. 일반 모드와 절약 모드에서 사용할 모델이 모델 선택기에 표시되는지 확인한다.

#### 1단계: 전역 메타 스킬 설치 (한 PC에서 1회)

아래 경로를 만든다:

```bash
mkdir -p ~/.zcode/skills/harness
```

제공된 `SKILL.md`를 `~/.zcode/skills/harness/SKILL.md`로, 제공된 `HARNESS_CONVENTION.md`를 같은 디렉터리의 `~/.zcode/skills/harness/HARNESS_CONVENTION.md`로 복사한다. ZCode Settings → Skills에서 Refresh를 누르고 `harness`를 활성화한다.

#### 2단계: 프로젝트 Workspace 열기

ZCode에서 새 프로젝트 루트를 Workspace로 연다. 기존 프로젝트라면 루트 `AGENTS.md`, `PRD.md`, `HARNESS_CONVENTION.md` 및 선택적 `ARCHITECTURE_CONVENTION.md`를 확인한다. 아직 없는 파일은 `$harness`가 기존 소스와 사용자 제공 정보를 바탕으로 초안을 만들게 한다. 민감 정보가 포함된 `.env`는 하네스 생성 컨텍스트에 첨부하지 않는다.

#### 3단계: 최초 하네스 구성 요청

ZCode 입력창에서 `$harness`를 선택한 다음 다음과 같이 요청한다:

```text
$harness
이 프로젝트에 ZCode Desktop용 하네스를 최초 구성해줘.
먼저 HARNESS_CONVENTION.md 전체를 읽고 규약을 준수해.
프로젝트 루트 AGENTS.md를 지식 베이스로 사용하고,
일반용과 절약용 오케스트레이터 명령어 2개가 같은 오케스트레이터
워크플로우 스킬을 사용하도록 구성해줘.
일반/절약 모드별 Developer·Reviewer·Tester 프로필 6개를 만들고,
사용자 스크린샷의 모델 표시명은 GLM-5.3 / GLM-5.3-Flash다. 모델 값은 우선 glm-5.3 / glm-5.3-flash로 설정하고, 최초 실행 시 실제 인식 여부를 검증해. 인식되지 않으면 ZCode의 모델 설정/실행 로그에서 실제 ID를 찾아 수정해.
Phase 승인 게이트, .zcode/progress.json, _workspace 산출물 규칙을 검증해.
파일 작성 전에 생성 계획을 먼저 보고하고 내 승인을 기다려.
```

실행 모드는 Plan mode를 권장한다. 생성 계획을 검토해 승인한 다음에만 파일을 작성하도록 한다.

#### 4단계: 생성된 파일 구조 확인

생성 결과는 다음 구조를 따른다:

```text
프로젝트 루트/
├── AGENTS.md
├── PRD.md
├── HARNESS_CONVENTION.md
├── .zcode/
│   ├── progress.json
│   ├── commands/
│   │   ├── {project}_orchestrator.md
│   │   └── {project}_orchestrator_lite.md
│   ├── skills/                       # 공통 orchestrator + 참조 스킬
│   └── agents/                       # 서브에이전트 프로필 — 일반/절약 6개
└── _workspace/
```

프로젝트 스킬명은 소문자 kebab-case로 유지할 수 있다. 단, ZCode 명령어는 공식 허용 패턴에 하이픈이 없으므로 명령어 파일명과 호출명에는 프로젝트명을 밑줄로 정규화한 `{project_command_prefix}`를 사용한다. `{project_command_prefix}_orchestrator`와 `{project_command_prefix}_orchestrator_lite`는 각각 다른 메인 모델을 지정하지만, 둘 다 같은 `{project}-orchestrator` 스킬을 불러야 한다.

#### 5단계: 발견 확인 (등록 절차 없음)

워크스페이스 스코프 리소스는 별도 등록이 필요 없다 — ZCode가 세션 시작 시 `.zcode/{commands,skills,agents}`를 자동 스캔한다.

1. 플러그인·마켓플레이스 등록 절차는 수행하지 않는다. 관련 파일(`marketplace.json`, `plugin.json`, `.zcode-plugin/`)을 만들지 않는다.
2. 새 세션을 시작하고 `/` 명령 패널에서 명령어 2개가 Commands 그룹에 표시되는지 확인한다.
3. Settings → Skills에서 `{project}` 스킬들이 표시되는지 확인한다.
4. Agent 도구 유형 목록(또는 오케스트레이터 실행 시)에 서브에이전트 6개가 등록됐는지 확인한다.
5. 발견되지 않으면 파일 위치(`.zcode/commands/`, `.zcode/skills/`, `.zcode/agents/`)와 frontmatter를 점검하고 새 세션에서 재확인한다.

#### 6단계: 모델 프로필 설정

`.zcode/commands/*.md`와 `.zcode/agents/*.md`에는 `glm-5.3` / `glm-5.3-flash`를 설정한다. 최초 실행에서 모델이 인식되지 않으면 ZCode의 실제 모델 ID로 수정한다.

| 파일 | 모델 설정 |
|:---|:---|
| `{project_command_prefix}_orchestrator.md` | 메인 Agent: GLM-5.3 (`glm-5.3`) |
| `{project_command_prefix}_orchestrator_lite.md` | 메인 Agent: GLM-5.3-Flash (`glm-5.3-flash`) |
| `{project}-developer.md` | GLM-5.3-Flash / `thoughtLevel: high` |
| `{project}-reviewer.md` | GLM-5.3 / `thoughtLevel: high` |
| `{project}-tester.md` | GLM-5.3-Flash / `thoughtLevel: high` |
| `{project}-developer-lite.md` | GLM-5.3-Flash / `thoughtLevel: low` |
| `{project}-reviewer-lite.md` | GLM-5.3-Flash / `thoughtLevel: high` |
| `{project}-tester-lite.md` | GLM-5.3-Flash / `thoughtLevel: low` |

명령어 frontmatter에서 명시적으로 보장되는 것은 메인 `model` 오버라이드다. 메인 Agent의 추론 수준은 UI에서 확인한다. 서브에이전트 정의에서 지정한 `thoughtLevel`은 해당 모델이 지원하는 값이어야 한다.

#### 7단계: 최초 엔드-투-엔드 검증

먼저 파괴 위험이 낮은 예시 작업(예: README 문구 수정 또는 간단한 Health check API 설계)을 선택한다.

1. `/{project_command_prefix}_orchestrator`를 실행하고 메인 모델이 GLM-5.3인지 확인한다.
2. 계획 보고 후 `awaiting_approval` 상태가 기록되고 응답이 종료되는지 확인한다.
3. 승인 전 Developer/Reviewer/Tester가 호출되지 않는지 확인한다.
4. 승인한 뒤 일반 모드의 프로필만 호출되는지 확인한다.
5. 같은 요청의 새 작업을 `/{project_command_prefix}_orchestrator_lite`로 실행하고 Flash 메인 모델 및 Lite 프로필이 선택되는지 확인한다.
6. 리뷰·테스트, `_workspace/` 산출물, `.zcode/progress.json` 갱신을 확인한다.
7. 실패한 부분은 `HARNESS_CONVENTION.md`와 `SKILL.md`를 기준으로 수정하고 재검증한다.

#### 8단계: Git 관리

`AGENTS.md`, `PRD.md`, `HARNESS_CONVENTION.md`, `.zcode/`(progress.json, commands, skills, agents 전체), `_workspace/`를 프로젝트 정책에 맞게 Git으로 추적한다. API 키, 토큰, 개인정보, `.env`는 포함하지 않는다. 하네스가 워크스페이스 리소스만으로 구성되므로, 다른 PC에서는 clone 후 ZCode에 동일한 모델 접근 권한만 연결하면 된다 — 별도 등록 절차는 없다.

### 9.3 프로젝트 유형별 커스터마이징

| 프로젝트 유형 | 구현 순서 | Phase 4 도구 | Phase 6 검증 |
|:---|:---|:---|:---|
| **백엔드** (Spring Boot, Express, Django, Go) | Model → Migration → DTO/Schema → Data Access → Service → Handler | 언어별 린터 + 컴파일 | 서버 기동 + 로그 검사 |
| **프론트엔드** (React, Vue, Next.js) | Component → Hook/Store → API Client → Page | ESLint + Prettier + tsc | `npm run build && npm run dev` |
| **라이브러리/SDK** | API 설계 → 구현 → 문서화 | 린터 + 빌드 | 빌드 성공 확인 (실행 불필요) |
| **데이터 파이프라인** | Schema → Transform → Load → Validate | SQL 린터, Python 린터 | Dry-run 또는 샘플 데이터로 검증 |

---

## 10. 운영 및 유지보수

### 10.1 점검 주기

| 주기 | 점검 항목 |
|:---|:---|
| **매 작업 완료 시** | Phase 통과율, 되먹임 루프 횟수 확인 |
| **매주** | AGENTS.md / PRD.md 최신성, 누적 WARNING 정리 |
| **매월** | 에이전트/스킬 효과성 평가, 불필요한 체크리스트 제거, Reviewer 오탐률 분석 |
| **기술 스택 변경 시** | 관련 스킬의 코드 템플릿, 명령어, 패키지명 일괄 업데이트 |

### 10.2 하네스 효과성 메트릭

하네스가 잘 작동하는지 정량적으로 추적할 수 있는 지표:

| 메트릭 | 측정 방법 | 목표치 | 개선 액션 |
|:---|:---|:---|:---|
| **Phase 5 첫 리뷰 통과율** | APPROVED / 전체 리뷰 횟수 | 60% 이상 | Developer 체크리스트 강화, PRD 명확화 |
| **되먹임 루프 횟수** | Phase 5→6→5 반복 횟수 | 평균 0.5회 이하 | BLOCKER 우선 리뷰 전략 적용 |
| **Reviewer 오탐률** | 리뷰 지적 중 실제 버그가 아니었던 비율 | 10% 미만 | review-checklist에 경계 조건 명확화 |
| **테스트 커버리지** | 프로젝트 커버리지 도구 | 80% 이상 (신규 코드) | test-patterns에 누락 시나리오 추가 |
| **Phase 8 실패율** | 실행 검증 실패 / 전체 실행 횟수 | 5% 미만 | Phase 4 검증 강화 |
| **Phase 소요 시간** | 각 Phase 평균 완료 시간 | 추세 모니터링 | 병목 Phase 최적화 |

### 10.3 개선 절차

1. **문제 발견**: 에이전트 반복 실패, Reviewer 잦은 오탐, Phase 간 컨텍스트 누락
2. **원인 분석**: 해당 스킬/에이전트 파일의 어떤 지시사항이 문제인지 파악
3. **수정**: AGENTS.md, 에이전트 파일, 스킬 파일 업데이트
4. **검증**: 동일 작업 재실행으로 개선 효과 확인
5. **기록**: AGENTS.md의 "하네스 변경 이력"에 기록

### 10.4 확장: 에이전트 / 스킬 추가

기존 3-에이전트 패턴으로 해결되지 않는 요구가 있을 때만 확장을 검토한다:

- **보안 감사** → `{project}-security-auditor` 에이전트 (Phase 3 다음에 추가)
- **성능 테스트** → `{project}-perf-tester` 스킬 (Phase 5에 통합)
- **API 문서 생성** → `{project}-api-docs` 스킬 (Phase 7에 통합)

### 10.5 다른 PC에서 복제

1. Git clone 후 프로젝트 루트를 ZCode Workspace로 연다.
2. 해당 PC의 ZCode에 GLM 모델 서비스에 로그인/연결한다.
3. Settings → Skills에서 전역 `$harness` 메타 스킬을 설치해 둔다(해당 PC 최초 1회).
4. `.zcode/progress.json`의 `currentPhase`를 확인한다. `awaiting_approval`이면 계획을 재보고하고 재승인을 기다린다.
5. 일반/절약 중 적절한 명령어로 파이프라인을 재개한다. 하네스 리소스가 모두 워크스페이스 스코프이므로 플러그인·마켓플레이스 등록은 불필요하다.

## 11. Anti-Patterns — 하지 말아야 할 것

### 11.1 에이전트 관련

| Anti-Pattern | 문제점 | 올바른 접근 |
|:---|:---|:---|
| **오케스트레이터가 직접 코드 수정** | 오케스트레이터는 높은 수준의 통제만 해야 함. 코드 수정 시 컨벤션 일관성 깨짐 | 반드시 Developer 에이전트에게 위임 |
| **Reviewer가 코드 스타일만 지적** | 고추론 모델의 추론 능력을 낭비. 정작 중요한 비즈니스 로직 검증 누락 | 코드 스타일은 Phase 4에서 기계적으로 처리 |
| **Developer·Tester에 고추론 모델 사용** | 비용 낭비. 코드 생성에는 코드 생성 특화 모델로 충분 | Developer·Tester는 모드에 맞는 `*-developer` / `*-tester` 프로필을 사용 |
| **Reviewer에 저비용 코드 생성 모델 사용** | 비즈니스 로직 검증 품질 저하, 오탐 증가로 신뢰도 하락 | Reviewer는 모드에 맞는 `*-reviewer` 프로필을 사용 |
| **에이전트 프롬프트에 지침 중복** | 컨텍스트 분산, 핵심 지시사항 희석 | 짧은 역할 프롬프트를 유지하고 필수 규칙은 AGENTS.md/PRD.md를 단일 기준으로 사용 |
| **Tester가 테스트 코드 정리를 하지 않음** | Phase 4는 구현 코드만 정리하므로, 테스트 코드에 미사용 import·변수가 누적됨 | Tester는 Phase 7 완료 전에 테스트 소스 자체 정리 필수 |

### 11.2 프로세스 관련

| Anti-Pattern | 문제점 | 올바른 접근 |
|:---|:---|:---|
| **모든 작업에 Full Pipeline** | 단순 오타 수정에 Phase 1~9 전부 거치면 생산성 저하 | [6.1 작업 규모 판별](#61-작업-규모-판별-phase-선택) 기준 적용 |
| **구현 후에 PRD 업데이트** | Developer가 잘못된(오래된) 명세를 보고 구현 | Phase 2(문서 현행화)를 Phase 3(구현)보다 먼저 실행 |
| **PRD 없이 AGENTS.md만으로 진행** | Developer·Reviewer·Tester가 같은 기준을 공유하지 못함 | PRD.md는 필수. 최소한 Rule ID + 기능 목록이라도 작성 |
| **리뷰 피드백 무한 루프** | Phase 5→6→5 반복이 3회 이상 지속 | 2회 초과 시 루트 원인 분석, 필요 시 사용자에게 중재 요청 |
| **_workspace/ 없이 진행** | Phase 간 컨텍스트 단절, 다른 PC에서 작업 재개 불가 | _workspace/와 progress.json은 반드시 유지 |
| **승인 없이 에이전트 스폰** | 사용자가 검증하지 못한 계획으로 코드 변경·토큰 비용 발생 | §6.13 승인 게이트 — 플랜 보고 후 턴 종료, 승인 응답 후 진행 |

### 11.3 문서 관련

| Anti-Pattern | 문제점 | 올바른 접근 |
|:---|:---|:---|
| **AGENTS.md에 모든 것 기록** | 1000줄이 넘으면 오히려 가독성 저하, 핵심 정보 탐색 어려움 | 500줄 초과 시 PRD.md로 분리 |
| **PRD.md가 코드와 불일치** | Developer가 무엇이 "정답"인지 알 수 없음 | Phase 2에서 강제 현행화, Phase 3에서 정합성 검증 |
| **Rule ID 없는 규칙 서술** | Reviewer·Tester가 규칙을 참조할 수 없음 | 모든 비즈니스 규칙은 고유 Rule ID 필수 |

---

## 12. 부록

### 부록 A: 용어 정의

| 용어 | 정의 |
|:---|:---|
| **하네스** | ZCode의 명령어·스킬·서브에이전트·AGENTS.md를 조합한 개발 자동화 체계 |
| **오케스트레이터 명령어** | 일반/절약 모드로 실행을 시작하는 명령어 두 개 |
| **오케스트레이터 스킬** | 두 명령어가 공유하는 Phase 0~9 워크플로우 정의 하나 |
| **서브에이전트** | 구현, 리뷰, 테스트처럼 독립 역할을 맡는 ZCode Agent |
| **Phase** | 오케스트레이터가 관리하는 개발 프로세스 단계 |
| **PRD.md** | 기능, Rule ID, 데이터 모델, 에러 코드 명세 |
| **Rule ID** | PRD 비즈니스 규칙의 고유 식별자(예: `US-001`) |
| **Full Pipeline** | Phase 0~9 전체를 거치는 대규모 작업 모드 |
| **Fast Path** | 계획 승인 후 최소 Phase로 수행하는 소규모 작업 모드 |

### 부록 B: 전체 파일 트리

```text
{project}/
├── AGENTS.md
├── PRD.md
├── HARNESS_CONVENTION.md
├── ARCHITECTURE_CONVENTION.md       # 선택
├── .zcode/
│   ├── progress.json
│   ├── commands/
│   │   ├── {project}_orchestrator.md
│   │   └── {project}_orchestrator_lite.md
│   ├── skills/
│   │   ├── {project}-orchestrator/SKILL.md
│   │   ├── {project}-business-rules/SKILL.md
│   │   ├── {project}-feature-dev/SKILL.md
│   │   ├── {project}-review-checklist/SKILL.md
│   │   ├── {project}-test-patterns/SKILL.md
│   │   └── {project}-git-deploy/SKILL.md
│   └── agents/
│       ├── {project}-developer.md
│       ├── {project}-reviewer.md
│       ├── {project}-tester.md
│       ├── {project}-developer-lite.md
│       ├── {project}-reviewer-lite.md
│       └── {project}-tester-lite.md
└── _workspace/
    ├── 01_plan.md
    ├── 02_prd_update.md
    ├── 03_implementation.md
    ├── 05_review.md
    ├── 07_test_report.md
    └── 08_run_report.md
```

전역 PC 설정:

```text
~/.zcode/
├── AGENTS.md                       # 개인 공통 지침(선택)
└── skills/
    └── harness/
        ├── SKILL.md                # 제공하는 메타 스킬
        └── HARNESS_CONVENTION.md   # 같은 버전의 규약 문서
```

### 부록 C: 에이전트/명령어 스켈레톤

#### C.1 일반용 오케스트레이터 명령어

```markdown
---
description: "{프로젝트} 개발 하네스 실행 — 일반 모드"
model: glm-5.3
skills: "{project}-orchestrator"
---

일반 모드로 작업한다. 동일한 {project}-orchestrator 스킬의 전체 규칙을 따른다.
사용자 승인 전 Developer/Reviewer/Tester를 호출하지 않는다.
호출 프로필: {project}-developer, {project}-reviewer, {project}-tester.
작업 요청: $ARGUMENTS
```

#### C.2 절약용 오케스트레이터 명령어

```markdown
---
description: "{프로젝트} 개발 하네스 실행 — 절약 모드"
model: glm-5.3-flash
skills: "{project}-orchestrator"
---

절약 모드로 작업한다. 동일한 {project}-orchestrator 스킬의 전체 규칙을 따른다.
사용자 승인 전 Developer/Reviewer/Tester를 호출하지 않는다.
호출 프로필: {project}-developer-lite, {project}-reviewer-lite, {project}-tester-lite.
작업 요청: $ARGUMENTS
```

#### C.3 서브에이전트 정의 예시

```markdown
---
name: "{project}-reviewer"
description: "{프로젝트} 코드 리뷰 전문가. 비즈니스 규칙, 보안, 권한, 데이터 무결성을 검증한다."
model: glm-5.3
thoughtLevel: high
color: blue
injectAgentsMd: true
---

# Reviewer

PRD.md와 AGENTS.md를 기준으로 구현을 독립 검토한다. 코드를 직접 수정하지 않는다.
각 이슈에는 severity(BLOCKER/CRITICAL/WARNING), Rule ID, 파일/라인, 근거,
수정 제안을 포함한다. 완료 시 결과를 `_workspace/05_review.md`에 저장한다.
```

> `model` 값은 사용자 스크린샷에 표시된 내장 모델명에 대응하여 `glm-5.3` / `glm-5.3-flash`로 기입했다. 스크린샷에는 내부 ID가 표시되지 않으므로 최초 실행 시 각 명령어·서브에이전트가 실제로 로드되는지 검증한다. `thoughtLevel`은 선택한 모델이 지원하는 수준만 사용한다.

---

> **이 문서는 ZCode Desktop 기반 사내 하네스 구성 기준입니다.** 프로젝트별 예외는 루트 `AGENTS.md`에 사유와 범위를 명시하고, 일반/절약 모드에 공통인 규칙과 모드별 차이를 구분해 기록한다.
>
> **변경 이력**
>
> | 날짜 | 버전 | 변경 내용 |
> |------|------|----------|
> | 2026-10-27 | 4.0.0 | ZCode Desktop 런타임으로 전환. 일반/절약 오케스트레이터 명령어 2개와 공통 워크플로우 스킬 1개, 6개 서브에이전트 프로필, 로컬 plugin marketplace 구조, 승인 게이트 및 모델 설정 제약 반영. OMP 전용 실행 규약 제거 |
> | 2026-10-28 | 4.0.1 | 사용자 스크린샷의 Z.ai 모델 표시명(GLM-5.3 / GLM-5.3-Flash)을 반영해 모델 값과 실행 검증 절차 구체화. ZCode 명령어 파일명 규칙에 맞게 예시를 밑줄 기반으로 수정 |
> | 2026-10-29 | 4.0.2 | 실측 기반 수정: 서브에이전트 정의 위치를 플러그인 `agents/` → 프로젝트 `.zcode/agents/`로 변경(플러그인 `agents` 필드 미실행 확인), marketplace.json `pluginRoot` 미적용 확인으로 `source`를 마켓플레이스 루트 기준 상대경로로 수정, 명령어·에이전트 발견 시점(세션 시작 스캔)을 검증 절차에 명시 |
> | 2026-10-29 | 4.0.3 | 플러그인·마켓플레이스 경로 폐기 — 플러그인에는 워크스페이스 스코프가 없어 전역 적용됨이 실측됨(§1.4 제약 8). 하네스 구성을 워크스페이스 스코프 리소스(`.zcode/{commands,skills,agents}`)로 전면 전환: marketplace.json·plugin.json 예시 삭제, 등록 절차(구 5단계)를 발견 확인으로 교체, 다른 PC 복제 절차에서 마켓플레이스 등록 단계 제거. git clone만으로 하네스 완결 |
