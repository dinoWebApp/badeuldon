# Harness Convention — 범용 개발 자동화 하네스 구성 규약

**버전**: 3.2.0
**최종 수정일**: 2026-10-08

---

## 이 문서의 목적

이 문서는 **omp(oh-my-pi) CLI를 활용한 프로젝트 전용 AI 개발 자동화 체계(이하 "하네스")** 의 구성 방법과 운영 원칙을 정의한다. 에이전트 CLI의 확장 기능(에이전트·스킬·컨텍스트 파일)을 체계적으로 조합하여, 반복적인 개발 사이클(구현 → 리뷰 → 테스트 → 실행 검증)을 자동화하고 코드 품질과 비즈니스 규칙 정합성을 보장한다.

omp 런타임의 구성 표준(파일 위치, frontmatter 포맷, modelRoles)은 [1.7 omp 구성 표준](#17-omp-구성-표준)에 집약되어 있으며, 본문의 원칙(Phase 파이프라인, 문서 선행, Rule ID, 3-에이전트 패턴)은 모든 프로젝트에서 동일하게 적용된다.

사내 모든 프로젝트는 이 규약에 따라 하네스를 구성하며, 프로젝트별 기술 스택과 도메인에 맞게 커스터마이징한다.

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

```
┌─────────────────────────────────────────────────────────────┐
│                     AGENTS.md (정적 지식)                     │
│   프로젝트 개요 · 기술 스택 · 아키텍처 · 비즈니스 규칙 · 컨벤션    │
└──────────────────────┬──────────────────────────────────────┘
                       │ 참조 (모든 구성요소가 읽음)
    ┌──────────────────┼──────────────────┐
    ▼                  ▼                  ▼
┌──────────┐   ┌──────────┐   ┌──────────┐
│ Developer│   │ Reviewer │   │  Tester  │  ← 전문 에이전트 (Agents)
│  (구현)  │   │  (리뷰)   │   │  (구현)  │     롤: 구현/테스트=@developer
│  기능 구현 │   │비즈니스 검증│   │ 테스트 실행│          리뷰/통제=@reviewer
└────┬─────┘   └────┬─────┘   └────┬─────┘
     │              │              │
     └──────────────┼──────────────┘
                    │ 통제 (planner 롤)
           ┌───────▼────────┐
           │  Orchestrator  │  ← 오케스트레이터 스킬 (Skill)
           │  (Phase 0~9)   │     Phase 0/1/2/4/8/9: 세션 모델(planner 롤)
           └───────┬────────┘
                   │ 부가 스킬 (모든 에이전트가 참조)
     ┌─────────────┼─────────────┐
     ▼             ▼             ▼
┌──────────┐ ┌──────────┐ ┌──────────┐
│ BizRules │ │FeatureDev│ │ TestPat. │  ← 참조 스킬 (Skills)
│(비즈니스) │ │(개발가이드)│ │(테스트패턴)│
└──────────┘ └──────────┘ └──────────┘
┌──────────┐ ┌──────────┐
│ Review   │ │ GitDeploy│
│Checklist │ │ (배포)    │
└──────────┘ └──────────┘
```

### 1.2 구성 파일 트리

```
프로젝트 루트/
├── AGENTS.md                       # 프로젝트 지식 베이스 — 단일 소스 (Git 관리)
├── PRD.md                          # 기능 명세 (Git 관리)
│
├── .omp/
│   ├── AGENTS.md                   # omp 진입점 — 본문 첫머리에 @../AGENTS.md import (Git 관리)
│   ├── RULES.md                    # 스티키 강제 규칙 (선택, Git 관리)
│   ├── config.yml                  # modelRoles 등 omp 설정 (Git 관리, 선택)
│   ├── progress.json               # Phase 진행 상태 (Git 관리)
│   │
│   ├── agents/                     # 전문 에이전트 정의
│   │   ├── {project}-developer.md
│   │   ├── {project}-reviewer.md
│   │   └── {project}-tester.md
│   │
│   └── skills/                     # 스킬 정의
│       ├── {project}-orchestrator/
│       │   └── SKILL.md
│       ├── {project}-business-rules/
│       │   └── SKILL.md
│       ├── {project}-feature-dev/
│       │   └── SKILL.md
│       ├── {project}-review-checklist/
│       │   └── SKILL.md
│       ├── {project}-test-patterns/
│       │   └── SKILL.md
│       └── {project}-git-deploy/
│           └── SKILL.md
│
└── _workspace/                     # 작업 산출물 (Git 관리)
    ├── 01_plan.md
    ├── 02_prd_update.md
    ├── 03_implementation.md
    ├── 05_review.md
    ├── 07_test_report.md
    └── 08_run_report.md
```

**스킬 위치 전략**: 스킬은 반드시 `.omp/skills/` 에 둔다 — omp가 프로젝트 네이티브 스킬 루트로 자동 발견한다. 에이전트는 `.omp/agents/` 에 두며, frontmatter의 `model`은 롤 앨리어스(`"@롤명"`)로 지정한다(`4.2 참조`).

### 1.3 핵심 설계 원칙

| 원칙 | 설명 |
|:---|:---|
| **관심사 분리** | 구현 / 리뷰 / 테스트를 각각 독립된 전문 에이전트로 분리 |
| **모델 차등화** | Developer·Tester는 코드 생성 특화 모델(`@developer` 롤), Reviewer·Orchestrator는 추론·판단 특화 모델(`@reviewer` 롤). 비용 효율과 품질을 동시에 확보 |
| **정적 지식 베이스** | AGENTS.md + PRD.md에 프로젝트의 모든 컨텍스트 기록. 에이전트가 매번 참조하여 일관된 출력 보장 |
| **Phase 기반 파이프라인** | 분석 → 문서화 → 구현 → 정리 → 리뷰 → 수정 → 테스트 → 실행검증 → 완료보고. 단, 작업 규모에 따라 Phase 생략 가능. **에이전트 스폰 전 사용자 승인 게이트(§6.13)는 규모와 무관하게 항상 적용** |
| **파일 기반 데이터 전달** | Phase 간 데이터는 `_workspace/` 디렉토리의 파일로 전달하여 컨텍스트 단절 방지 |
| **Git 추적 진행 상태** | `.omp/progress.json`과 `_workspace/`를 Git으로 추적. 다른 PC에서 `git pull`만으로 작업 재개 가능 |
| **문서 선행 원칙** | PRD.md/AGENTS.md 갱신은 구현보다 먼저. 개발자가 최신 명세를 보고 작업하도록 강제 |

### 1.4 모델 차등화 전략 (핵심)

```
비용 효율 <────────────────────────────> 추론 품질
  코드 생성 특화                          추론 특화
      │                                     │
      ├── Developer (구현)                  ├── Reviewer (코드 리뷰)
      ├── Tester (테스트 작성·실행)          ├── Orchestrator Phase 1 (분석)
      │                                     ├── Orchestrator Phase 2 (문서화)
      │                                     ├── Orchestrator Phase 4 (정리)
      │                                     ├── Orchestrator Phase 8 (실행 검증)
      │                                     └── Orchestrator Phase 9 (완료 보고)
```

| 역할 | 롤 앨리어스 | 사유 |
|:---|:---|:---|
| **Developer** | `@developer` | 코드 생성은 패턴 매칭에 가깝고, 속도·비용이 중요 |
| **Tester** | `@developer` | 테스트 코드 생성·실행은 구현과 유사한 성격 (별도 `tester` 롤 정의 가능) |
| **Reviewer** | `@reviewer` | 비즈니스 로직 정합성 검증은 고도의 추론 능력 필요 — 위양성(false positive)은 신뢰도를 떨어뜨림 |
| **Orchestrator** (Phase 0, 1, 2, 4, 8, 9) | 세션 모델 (`planner`/`default` 롤) | 요구사항 분석, 문서 현행화 판단, 실행 로그 해석, 최종 보고는 판단력이 중요한 작업 |

**준수 규칙**: 에이전트 파일에는 모델명을 직접 쓰지 않고 **modelRoles 롤 앨리어스**(`model: "@developer"`, `model: "@reviewer"`)로 지정한다. 롤→실제 모델 매핑은 **전역 `~/.omp/agent/config.yml`의 `modelRoles`에서 단일 관리**한다 ([1.7 omp 구성 표준](#17-omp-구성-표준) 참조). **프로젝트별 `.omp/config.yml`은 생성하지 않는다** — 모델 교체는 전역 config의 매핑만 바꾸면 된다.

### 1.5 트리거 메커니즘 — 하네스가 작동하는 실질적 원리

하네스의 모든 구성요소는 omp의 **설명(description) 기반 자동 매칭**에 의해 호출된다. 이 메커니즘을 이해하지 못하면 하네스를 아무리 정교하게 구성해도 작동하지 않는다.

#### 스킬 트리거: `description` 필드

스킬의 프론트매터 `description`은 omp UI에 표시되는 설명이자, **omp가 어떤 사용자 요청에 이 스킬을 호출할지 판단하는 근거**다.

```
사용자 입력: "사용자 관리 API 구현해줘"
     │
     ▼ omp가 모든 스킬의 description을 스캔
     │
     ├── sentrapass-orchestrator: "SentraPass 개발 오케스트레이터. 신규 기능 구현, 코드 수정, ..."
     │   → 매칭! "구현" 키워드 → 이 스킬을 로드
     │
     ├── sentrapass-business-rules: "SentraPass 비즈니스 규칙 참조 ..."
     │   → 매칭되지 않음 (직접 호출 대상 아님)
     │
     └── sentrapass-git-deploy: "SentraPass Git 배포 ..."
         → 매칭되지 않음 ("배포" 키워드가 없음)
```

**description 작성 규칙**:
1. **오케스트레이터 description**: 프로젝트의 모든 개발 요청 키워드를 포괄한다.
   ```
   description: {프로젝트명} 개발 오케스트레이터. 신규 기능 구현, 코드 수정, 리팩터링, 
   테스트 작성, 코드 리뷰 등 {프로젝트명} 프로젝트의 모든 개발 작업을 조율한다. 
   {프로젝트명} 관련 개발 요청, 기능 구현, 코드 리뷰, 테스트 작성, 디버깅, API 설계, 
   데이터베이스 마이그레이션, 비즈니스 로직 검증 요청 시 사용한다. 
   후속 작업(수정, 보완, 개선, 리팩터링, 재실행, 업데이트)도 처리한다.
   ```
   → "구현", "수정", "리팩터링", "테스트", "리뷰", "API", "디버깅" 등 모든 개발 관련 키워드를 포함.

2. **배포 스킬 description**: 배포 관련 키워드만 포함.
   ```
   description: {프로젝트명} Git 배포 스킬. 변경 사항을 커밋, ... Push 한다. 
   "git 배포", "커밋", "푸시", "배포", "push" 요청 시 사용한다.
   ```

3. **참조 스킬 description**: 직접 호출되지 않고 에이전트가 참조하므로, description은 설명 목적으로만.
   ```
   description: {프로젝트명} 비즈니스 규칙 참조 스킬. PRD에서 추출한 핵심 비즈니스 규칙, 
   데이터 격리 원칙 등을 제공한다. {프로젝트명} 코드를 작성하거나 리뷰할 때 반드시 참조한다.
   ```

#### AGENTS.md 트리거 섹션: 명시적 호출 지시

`description` 매칭만으로는 오케스트레이터가 항상 의도대로 호출되지 않을 수 있다. **AGENTS.md에 명시적인 트리거 지시문**을 추가하여 이를 보완한다. 이 섹션은 omp가 매 턴마다 읽는 AGENTS.md에 있으므로 가장 강력한 트리거다.

**표준 패턴** (AGENTS.md의 "하네스" 섹션에 포함):

```markdown
## 하네스: {프로젝트명} 개발 자동화

**목표:** PRD 비즈니스 규칙과 AGENTS.md 아키텍처를 준수하는 코드의 구현·리뷰·테스트를 자동화한다.

**트리거:** 아래에 해당하는 모든 요청은 반드시 `{project}-orchestrator` 스킬을 사용하라:
- 기능 구현, 코드 수정, 리팩터링, 버그 수정
- 코드 리뷰, 테스트 작성, 디버깅
- API 설계, 데이터베이스 마이그레이션, 비즈니스 로직 검증
- 위 작업의 후속 요청 (수정, 보완, 개선, 리팩터링, 재실행, 업데이트)
단순 질문(문서 내용 확인, 의미 해석)은 직접 응답 가능.

**배포:** "git 배포", "커밋", "푸시", "배포", "push" 요청 시 `{project}-git-deploy` 스킬을 사용하라.

**변경 이력:**
| 날짜 | 변경 내용 | 대상 | 사유 |
|------|----------|------|------|
| YYYY-MM-DD | 초기 하네스 구성 | 전체 | 신규 구축 |
```

**이 섹션이 중요한 이유**: omp가 매 턴마다 AGENTS.md를 시스템 프롬프트로 읽는다. "X 요청 시 Y 스킬을 사용하라"는 명시적 지시문은 description 매칭보다 우선적으로 적용된다.

**omp 런타임**: omp는 루트 `AGENTS.md`를 자동으로 읽지 않는다. 대신 `.omp/AGENTS.md`(프로젝트 컨텍스트, 매 세션 자동 로드)를 두고 본문 첫머리에 `@../AGENTS.md` import 한 줄을 넣어 AGENTS.md를 단일 소스로 유지한다. 트리거 섹션은 AGENTS.md에 이미 있으므로 import만으로 omp에서도 동일하게 작동한다. 추가 강제 규칙이 필요하면 `.omp/RULES.md`(스티키 규칙, 긴 대화 후에도 재부착)를 사용한다.

#### 에이전트 호출: description + 오케스트레이터의 명시적 지정

에이전트는 사용자가 직접 호출하지 않고 오케스트레이터가 호출한다. 따라서 에이전트의 `description`은 오케스트레이터가 이 에이전트를 언제 선택할지 판단하는 기준이 된다.

```yaml
# Developer 에이전트 description 예시
description: {Project} 기능 구현 전문가. {기술 스택} 기반의 모델, 
데이터 접근 계층, 비즈니스 로직, API 핸들러를 PRD 및 AGENTS.md 규칙에 맞게 생성/수정한다.
```

오케스트레이터는 Phase 2, 4에서 이 description을 보고 Developer 에이전트를 선택한다.

#### 트리거 계층 요약

```
사용자 요청
    │
    ├──→ AGENTS.md 트리거 섹션 (최우선) 
    │      "{keyword} 요청 시 {skill} 스킬을 사용하라"
    │
    ├──→ 스킬 description 매칭 (보조)
    │      omp가 description 텍스트와 사용자 입력의 의미적 유사성으로 판단
    │
    └──→ 오케스트레이터가 직접 에이전트 지정 (Phase 내)
           task tool — { "tasks": [{ "agent": "{project}-developer", "task": "..." }] }
```

### 1.6 하네스를 100% 확실하게 타는 방법 — 사용자 입력 패턴

omp가 요청을 오케스트레이터로 라우팅할지 직접 처리할지는 **AGENTS.md 트리거 지시문 + 스킬 description 매칭 + 사용자 입력**의 조합으로 결정된다. 대부분의 경우 잘 동작하지만, 애매한 요청은 omp가 "이건 그냥 내가 답변해도 되겠다"라고 판단하여 오케스트레이터를 건너뛸 수 있다.

이를 방지하고 **100% 하네스 로직을 타도록 보장하는 세 가지 방법**이 있다:

#### 방법 1: 슬래시 커맨드 (★ 가장 확실)

omp는 `/skill:{skill-name}` 문법으로 스킬을 강제 호출할 수 있다.

```
/{project}-orchestrator 사용자 생성 API 구현해줘
```

```
/{project}-orchestrator 위 변경사항 코드 리뷰해줘
```

```
/{project}-orchestrator 테스트가 실패했는데 수정해줘
```

**장점**: 라우팅 추론을 완전히 우회한다. 무조건 오케스트레이터가 로드된다.
**단점**: 매번 `/{project}-orchestrator`를 타이핑해야 한다.

#### 방법 2: 트리거 키워드를 요청 첫머리에 배치

omp는 요청의 첫 부분을 가장 중요하게 본다. AGENTS.md 트리거 섹션에 나열된 키워드로 시작하면 라우팅 정확도가 크게 올라간다.

```
✅ "사용자 관리 API 구현해줘"           → "구현" 키워드 → 오케스트레이터
✅ "코드 리뷰해줘. 방금 구현한 PersonService" → "리뷰" 키워드 → 오케스트레이터
✅ "버그 수정해줘. 로그인 API에서..."       → "수정" 키워드 → 오케스트레이터
❌ "PersonService에 create 메서드가 필요한데..." → 애매함 → 직접 처리될 가능성
❌ "이 코드 좀 봐줘"                         → 너무 모호 → 직접 처리될 가능성
```

#### 방법 3: AGENTS.md 트리거 지시문을 더 강하게 작성

AGENTS.md의 트리거 섹션에 "반드시", "항상" 같은 절대적 표현을 추가한다. SentraPass의 실제 트리거 섹션을 예로 들면:

```markdown
**트리거:** 아래에 해당하는 모든 요청은 반드시 `{project}-orchestrator` 스킬을 사용하라:
- 기능 구현, 코드 수정, 리팩터링, 버그 수정
- 코드 리뷰, 테스트 작성, 디버깅
- API 설계, 데이터베이스 마이그레이션
- 위 작업의 후속 요청 (수정, 보완, 재실행, 업데이트)
단, 순수한 문서 내용 확인 질문("~가 무슨 뜻이야?", "~는 어디에 있어?")은 직접 응답 가능.
```

**핵심**: "아래에 해당하는 모든 요청은 반드시"라는 표현 + 구체적인 요청 유형 목록.

#### 종합 권장

**AGENTS.md 트리거 섹션을 방법 3처럼 강하게 작성**해두고, 평소에는 방법 2(키워드 첫머리 배치)로 자연스럽게 사용하다가, **오케스트레이터가 안 탔을 때만 방법 1(슬래시 커맨드)로 재시도**하는 전략이 가장 실용적이다.

#### 오케스트레이터 탔는지 확인하는 법

오케스트레이터가 정상적으로 로드되면 omp의 첫 응답에 스킬의 내용(SKILL.md의 첫 부분)이 컨텍스트로 주입된다. 즉, 응답 초반에 "Phase 0: 컨텍스트 확인" 이나 오케스트레이터 특유의 Phase 기반 사고가 보이면 하네스를 탄 것이다. 그렇지 않고 바로 코드나 설명을 출력하면 직접 처리 중인 것이다.

### 1.7 omp 구성 표준

하네스의 원칙과 파이프라인은 모든 프로젝트에서 동일하다. 프로젝트별로 달라지는 것은 도메인 내용(지식 베이스, PRD, Rule ID)뿐이며, 구성 파일의 위치와 포맷은 아래 표준을 따른다.

#### omp 구성 개념 표

| 개념 | omp 표준 |
|:---|:---|
| 지식 베이스 | 루트 `AGENTS.md` (단일 소스) — `.omp/AGENTS.md` 진입점이 본문 첫머리 `@../AGENTS.md` import로 로드 |
| 스티키 강제 규칙 | AGENTS.md 트리거 섹션 + `.omp/RULES.md` (선택 — 긴 대화 후에도 재부착) |
| 전문 에이전트 위치 | `.omp/agents/{project}-{role}.md` |
| 에이전트 모델 지정 | `model: "@developer"` / `model: "@reviewer"` (modelRoles 롤 앨리어스) |
| 에이전트 스킬 할당 | `autoloadSkills:` 목록 |
| 에이전트 호출 (스폰) | task tool — `{"tasks":[{"agent":"{project}-developer","task":"..."}]}` |
| 에이전트 간 직접 통신 | Agent Hub (`Alt+A`) / hub tool — 진행 중 협업만 허용. 완료된 에이전트 재소환 금지, 완료 후 등록 해제 — `hub cancel`, 미제공 세션은 UI `x: kill` 수동 정리 (§4.6) |
| 스킬 위치 | `.omp/skills/{skill}/SKILL.md` |
| 메타 스킬 | 전역 `~/.omp/agent/skills/harness/` (`skill://harness`) |
| 강제 스킬 호출 | `/skill:{project}-orchestrator` |
| 모델 차등화 설정 | `modelRoles` — **전역 `~/.omp/agent/config.yml` 단일 관리** (프로젝트 `.omp/config.yml` 생성 금지 — 설정 단일화로 프로젝트 간 모델 롤 일관성 유지) |
| 진행 상태 | `.omp/progress.json` |
| 작업 산출물 | `_workspace/` |
| 권한/승인 | omp 자체 승인 모델 (프로젝트 권한 파일 없음) |
| 세션 재개 | `omp -c` / `omp -r` (피커) |
| 컨텍스트 압축 | 자동 압축 (임계값/overflow 압축, `/compact`) |

#### omp modelRoles — 모델 차등화

```yaml
# ~/.omp/agent/config.yml (전역 단일 관리 — 프로젝트별 .omp/config.yml은 생성하지 않는다)
modelRoles:
  planner: openrouter/z-ai/glm-5.3-flash                  # 오케스트레이터 (세션 모델, 추론 특화)
  reviewer: openrouter/z-ai/glm-5.3-flash                 # Reviewer 에이전트 (추론 특화)
  developer: openrouter/deepseek/deepseek-v4-flash-0731   # Developer·Tester 에이전트 (코드 생성 특화)
```

에이전트 frontmatter의 `model: "@developer"`는 스폰 시점에 `modelRoles.developer`로 해석되므로, 모델 교체 시 에이전트 파일 수정 없이 config의 롤 매핑만 바꾸면 된다.

---

## 2. AGENTS.md — 프로젝트 지식 베이스

### 2.1 목적

`AGENTS.md`는 omp가 매 세션 자동으로 로드하는 지식 베이스다(`.omp/AGENTS.md` 진입점이 `@../AGENTS.md` import로 로드). 하네스의 모든 구성요소가 이 파일을 기준으로 동작한다.

**핵심 원칙**: 프로젝트에 대한 모든 컨텍스트(아키텍처, 규칙, 컨벤션, 진행 상황)가 이 파일에 집약되어야 한다. 새 PC에서 클론 받아도 이 파일만 읽으면 프로젝트를 이해하고 작업을 재개할 수 있어야 한다.

### 2.2 필수 섹션

AGENTS.md는 다음 섹션을 반드시 포함해야 한다:

```markdown
# AGENTS.md

이 파일은 omp 에이전트가 이 저장소에서 작업할 때 참고할 가이드입니다.

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

### 4.2 에이전트 정의 파일 포맷

위치: `.omp/agents/{project}-{role}.md`

```markdown
---
name: {project}-{role}
description: {프로젝트명} {역할 한글명}. {주요 업무 설명}.
model: "@developer"        # ← Developer/Tester="@developer", Reviewer="@reviewer"
autoloadSkills:
  - {project}-business-rules
  - {project}-{guide-skill}
---

# {Project} {Role}

## 핵심 역할

{3~5문장으로 역할 정의. 이 에이전트가 무엇을 하는지, 왜 중요한지를 명확히.}

## 작업 원칙

1. **{원칙 1}** — {상세 설명}
2. **{원칙 2}** — {상세 설명}
...

## {구현/리뷰/테스트} 체크리스트

### {레이어/영역} (해당 시)
- [ ] {체크 항목}
- [ ] {체크 항목}

## 입력/출력 프로토콜

- **입력**: {무엇을 받는지}
- **출력**: {무엇을 반환하는지}
- **중간 산출물**: `_workspace/` 디렉토리에 저장할 파일들

## 에러 핸들링

- {상황} → {대응 방법}

## 협업

- 다른 에이전트와의 상호작용 방법
- 오케스트레이터와의 보고 체계

## 이전 산출물이 있을 때의 행동

- `_workspace/` 디렉토리가 존재하면 이전 결과를 읽고 중복 작업을 피한다.
```

**frontmatter 규칙**: `model`은 롤 앨리어스(`"@롤명"`)로 지정하며 modelRoles 매핑으로 해석된다(§1.7 참조). omp 태스크 에이전트는 `type` 필드가 없으며 기본 전체 도구를 보유한다. 본문(systemPrompt)은 역할 원칙·체크리스트·입출력 프로토콜을 담는다.

### 4.3 Developer 에이전트 (구현)

| 속성 | 값 |
|:---|:---|
| **파일명** | `{project}-developer.md` |
| **모델 롤** | **`@developer`** (코드 생성에 적합, 비용 효율) |
| **할당 스킬** | `{project}-business-rules`, `{project}-feature-dev` |
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
| **모델 롤** | **`@reviewer`** (고도의 추론 능력이 필요한 비즈니스 로직 검증) |
| **할당 스킬** | `{project}-business-rules`, `{project}-review-checklist` |
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
| **모델 롤** | **`@developer`** (테스트 코드 생성은 구현과 유사, 비용 효율) |
| **할당 스킬** | `{project}-business-rules`, `{project}-test-patterns` |
| **역할** | 테스트 코드 작성, 실행, 실패 원인 분석 |

**핵심 책임**:
1. 비즈니스 규칙의 정상/경계/예외 케이스를 빠짐없이 테스트
2. 계층별 적절한 테스트 작성
3. 테스트 실패 시 **코드 버그인지 테스트 오류인지 반드시 구분**하여 보고
4. 기존 테스트와의 충돌 여부 확인

### 4.6 서브에이전트 수명 주기 — 일회성 스폰 원칙

서브에이전트는 **일회성(one-shot)**으로 운영한다. omp 런타임은 완료된 서브에이전트를 parked 상태로 보존하므로, 규약 차원에서 재사용을 차단한다.

**원칙**:

| # | 원칙 | 내용 |
|---|---|---|
| 1 | **작업마다 신규 스폰** | 모든 작업 위임은 task tool로 **새 에이전트**를 스폰한다. 동일 역할 재위임(리뷰 반영 수정·재테스트 등)도 예외 없이 신규 스폰하며, 선행 작업 맥락은 `_workspace/` 산출물(`03_implementation.md`, `05_review.md` 등)로 전달한다. |
| 2 | **완료 에이전트 재소환 금지** | 완료 보고를 낸 에이전트를 `hub send`로 다시 깨워 후속 작업을 맡기지 않는다. 재소환은 이전 작업의 오염된 컨텍스트와 과거 규약 기준을 이어받게 한다. |
| 3 | **완료 후 등록 해제** | 오케스트레이터는 서브에이전트의 최종 결과를 수신한 뒤 **즉시** 등록 해제를 시도한다 — Agent Hub 로스터에 잔류하지 않아야 한다. 해제 수단: `hub cancel`. 단, `proc://<에이전트ID>/kill`은 **실행 중인 세션만** 취소하며 완료(parked) 에이전트의 로스터 등록은 해제하지 못한다(실측: not found). `hub` 도구가 없는 세션에서는 자동 해제가 불가하므로 Agent Hub UI(`x: kill`)로 수동 정리하고, 오케스트레이터는 최종 보고에 잔존 에이전트를 안내한다. |

**예외 — 진행 중 협업**: 작업 진행 중 양쪽 에이전트가 모두 살아 있을 때의 조정(리뷰어→개발자 중간 질의 등)은 Agent Hub 사용을 허용한다. 금지 대상은 **완료된 에이전트의 재소환**뿐이다.

**근거**: ① 컨텍스트 신선도 — 이전 작업 맥락이 새 작업 판단을 오염시키지 않는다. ② 로스터 위생 — 허브 목록에 사용 완료 에이전트가 누적되지 않는다. ③ 결정론적 재현 — 같은 산출물 기반이라면 누가 수행해도 동일하게 진행된다.

---

## 5. 스킬 (Skills)

### 5.1 스킬 역할 분류

| 유형 | 설명 | 예시 | 할당 대상 |
|:---|:---|:---|:---|
| **오케스트레이터** | 전체 프로세스 통제, Phase 관리 | `{project}-orchestrator` | 사용자 직접 호출 |
| **참조 스킬** | 비즈니스 규칙, 개발 패턴, 테스트 패턴 등 프로젝트 특화 지식 | `{project}-business-rules`, `{project}-feature-dev`, `{project}-test-patterns` | Developer, Reviewer, Tester |
| **도구 스킬** | 체크리스트, 배포 등 특정 작업 자동화 | `{project}-review-checklist`, `{project}-git-deploy` | Reviewer, 사용자 |
| **메타 스킬** | 하네스 자체의 구성·점검·개선 | `harness:harness` | 관리자 |

### 5.2 스킬 정의 파일 포맷

위치: `.omp/skills/{skill-name}/SKILL.md`

```markdown
---
name: {skill-name}
description: {한 줄 설명. omp UI에 표시되며, 어떤 상황에서 호출할지 포함한다.}
---

# {Skill Title}

## 이 스킬의 목적

{2~3문장으로 이 스킬이 해결하는 문제와 사용 시기를 설명}

## {Section 1}

{본문 — 필요한 만큼 섹션을 구성}
```

**스킬 위치 표준**: 스킬은 반드시 `.omp/skills/{skill-name}/SKILL.md`에 둔다 — omp가 프로젝트 네이티브 스킬로 자동 발견하며, 이때 `description` 필드가 필수다. 오케스트레이터 스킬 본문의 에이전트 호출 문법은 omp task tool로 통일한다(§1.7 참조).

### 5.3 오케스트레이터 스킬

**파일명**: `{project}-orchestrator`

**목적**: 개발 작업의 전체 프로세스를 조율한다. 사용자의 개발 요청을 받아 Phase 0~9을 진행하며, 각 Phase마다 적절한 전문 에이전트를 호출하고 결과를 검증한다.

**절대 직접 코드를 수정하지 않는다.** 코드 수정이 필요한 모든 작업은 Developer 에이전트에게 위임한다.

**오케스트레이터의 역할**:
- Phase 간 전환과 진행 상태 관리
- 사용자 승인 게이트 운영 — 플랜 승인 전 에이전트 스폰 금지 (§6.13)
- 문서(AGENTS.md/PRD.md) 현행화
- 기계적 검증 (Phase 4)
- 실행 검증 (Phase 6)
- 최종 완료 보고 (Phase 7)
- 작업 복잡도에 따른 Phase 생략 판단

**상세 Phase 구조**: [6. 오케스트레이터 — 개발 프로세스 자동화](#6-오케스트레이터--개발-프로세스-자동화) 참조.

### 5.4 비즈니스 규칙 스킬

**파일명**: `{project}-business-rules`

PRD 7장의 핵심 규칙을 Rule ID와 함께 빠르게 참조할 수 있도록 정리한다. Developer, Reviewer, Tester 모두가 작업 시 참조한다.

### 5.5 기능 개발 가이드 스킬

**파일명**: `{project}-feature-dev`

프로젝트의 기술 스택에 맞는 단계별 구현 가이드와 각 레이어별 코드 템플릿을 제공한다.

### 5.6 코드 리뷰 체크리스트 스킬

**파일명**: `{project}-review-checklist`

Reviewer가 코드 리뷰를 체계적으로 수행하기 위한 레이어별 점검 항목과 Rule ID 매핑을 제공한다.

### 5.7 테스트 패턴 스킬

**파일명**: `{project}-test-patterns`

프로젝트의 테스트 계층별 템플릿과 Rule ID별 필수 테스트 시나리오를 제공한다.

### 5.8 배포 스킬

**파일명**: `{project}-git-deploy`

변경 사항을 Git에 커밋하고 원격 저장소에 푸시한다. 브랜치 전략에 따라 PR 생성도 지원한다.

### 5.9 메타 스킬 (harness:harness)

하네스 자체를 구성·점검·개선하는 메타 스킬. 다음과 같은 요청을 처리한다:

- **구성**: "하네스 구성해줘", "하네스 구축해줘", "하네스 설계"
- **점검**: "하네스 점검해줘", "하네스 감사", "하네스 현황"
- **동기화**: "에이전트/스킬 동기화", "하네스 확장"

이 스킬은 HARNESS_CONVENTION.md를 참조하여 프로젝트에 하네스를 신규 구성하거나, 기존 하네스의 상태를 점검하고 개선하는 작업을 수행한다.

**omp 런타임**: 플러그인 대신 전역 스킬 `~/.omp/agent/skills/harness/SKILL.md`로 동일 메타 스킬을 제공한다 (규약 문서 사본을 스킬 디렉토리에 내장 — `skill://harness/HARNESS_CONVENTION.md`). 프로젝트 루트에 `HARNESS_CONVENTION.md`가 있으면 프로젝트 로컬 문서가 우선한다.

---

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
    │   .omp/progress.json, _workspace/ 확인, resume/신규 결정
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
    ├── .omp/progress.json 리셋
    └── Git 커밋
```

### 6.3 Phase 간 데이터 흐름

각 Phase 간 데이터는 **`_workspace/` 디렉토리의 마크다운 파일**로 전달된다:

- 컨텍스트 단절 없이 Phase 간 연속성 보장
- Git으로 추적 가능 → 다른 PC에서도 작업 재개 가능
- 감사 추적(audit trail) 제공

에이전트 간 직접 통신(`hub` tool)은 **작업 진행 중**(양쪽 에이전트가 모두 살아 있는 동안)의 조정에만 보조적으로 사용한다. 완료 보고를 낸 에이전트의 재소환은 금지되며(§4.6), 후속 작업은 `_workspace/` 산출물을 전달해 **신규 에이전트**에게 위임한다. 오케스트레이터는 최종 결과 수신 후 즉시 등록 해제를 시도한다 — `hub cancel`. `hub` 도구 미제공 세션에서는 자동 해제가 불가하므로(`proc kill`은 parked 등록에 무력, §4.6) Agent Hub UI(`x: kill`) 수동 정리를 최종 보고에 안내한다.

### 6.4 진행 상태 관리

`progress.json`으로 현재 Phase를 추적한다 (Git 관리):

**세션 todo 동기화**: 오케스트레이터는 작업 시작 시 Phase 구조로 세션 todo를 init한다. 갱신 트리거 2가지: ① **에이전트 결과 수신 직후의 첫 도구 호출 = todo done** — 다음 스폰·검증·문서 작업보다 반드시 먼저 수행한다(이 순서를 놓치는 것이 누적 누락의 주된 원인이다), ② `progress.json` 갱신 시 반드시 세트 갱신. 터미널 TODO 위젯은 자동 추적이 아니라 todo 호출 기준으로만 표시된다.

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
  1. .omp/progress.json 확인 → currentPhase: null → 새 작업 모드
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
Developer(@developer 롤):
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
Reviewer(@reviewer 롤):
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
Developer(@developer 롤):
  Reviewer 지적 사항 수정:
  1. valid_begin_time null 체크 추가 → INVALID_VALID_PERIOD 에러 반환
  2. organizationRepository.existsByMasterAccountIdAndId() 호출 추가 → 
     ORGANIZATION_NOT_FOUND 에러 반환
  
  ※ 리뷰 지적 외 코드는 건드리지 않음
```

#### Phase 7: 테스트

```
Tester(@developer 롤):
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

오케스트레이터는 **플랜에 대한 사용자 승인을 받기 전까지 어떤 에이전트도 스폰하지 않는다.** 이 게이트는 작업 규모(Full/Standard/Fast Path)와 무관하게 모든 파이프라인에 공통 적용되며, §6.1의 Phase 생략 규칙으로도 생략되지 않는다.

#### 시점

| 파이프라인 | 게이트 시점 | 플랜 산출물 |
|:---|:---|:---|
| Full | Phase 1 완료 직후, Phase 2 진입 전 | `_workspace/01_plan.md` |
| Standard | Phase 1 완료 직후, Phase 3 진입 전 | `_workspace/01_plan.md` |
| Fast Path | Phase 3 진입 전 | 채팅 요약 플랜(변경 파일·변경점 요약) — `01_plan.md` 생략 가능 |

#### 절차

1. 플랜 저장 — Full·Standard는 `01_plan.md` 작성, Fast Path는 간이 플랜을 채팅에 출력
2. `progress.json` 갱신 — `"currentPhase": "awaiting_approval"` + 세션 todo 갱신(§6.4)
3. 플랜 보고 출력 — 반드시 포함할 항목:
   - 작업 규모(pipelineType)와 진행할 Phase 순서
   - 각 에이전트(Developer/Reviewer/Tester)에게 내릴 지시 요약
   - 변경 예상 파일 목록
   - 리스크·모호점(있으면)
4. 보고 마지막에 승인 요청("플랜을 승인하시겠습니까?")을 명시하고 **턴을 종료한다**

**강제 수단**: omp에는 플랜 승인 네이티브 프리미티브가 없다(§7.1의 승인은 도구 권한 승인으로 별개다). 턴을 종료하면 사용자 응답 전까지 다음 Phase가 물리적으로 실행될 수 없으므로, **턴 종료가 이 게이트의 강제 메커니즘이다.** "플랜 보고 후 그대로 계속 진행"은 금지된다.

#### 승인 응답 분기

| 사용자 응답 | 처리 |
|:---|:---|
| 승인 ("진행", "OK", "승인" 등 긍정) | `progress.json`을 다음 Phase로 갱신하고 게이트 이후 Phase부터 자동 진행. **재승인은 불필요** — 이후 파이프라인(리뷰·테스트·수정 루프 포함)은 자동으로 진행한다 |
| 수정 요청 | Phase 1(Fast Path는 간이 플랜) 재계획 → 재보고 → 게이트 재통과 |
| 중단 | `progress.json` 리셋 후 종료 |

#### 세션 재개

`progress.json`의 `currentPhase`가 `awaiting_approval`이면(세션 재개, 타 PC `git pull` 후 모두 포함), 플랜(`01_plan.md` 또는 직전 대화)을 요약 재보고하고 승인 대기 상태로 진입한다. 승인 없이 Phase를 진행하지 않는다.

#### 컨텍스트 압축 대비 보강 (스티키 미러링)

컨텍스트 압축 후에도 게이트가 유지되도록, 하네스 구성 시(§9.2 5단계) 다음 두 곳에 규칙을 미러링한다:

1. 오케스트레이터 SKILL.md의 하드 룰 섹션
2. `.omp/RULES.md`(스티키 규칙):

```markdown
- 오케스트레이터는 사용자 승인 전 에이전트를 스폰하지 않는다(§6.13).
  progress.json currentPhase=awaiting_approval 상태에서는 플랜 재보고 후 승인 대기한다.
```

---

## 7. 설정 및 권한 (Settings)

### 7.1 승인 및 권한

omp는 프로젝트 권한 파일을 사용하지 않고 자체 승인 모델로 도구 사용을 제어한다. 세션 시작 시 권한 모드를 선택하고, 신뢰하는 명령어는 승인 프롬프트에서 "항상 허용"으로 저장한다.

- **빌드/테스트/실행 명령어**: `{프로젝트 빌드 명령어}`, `{프로젝트 테스트 명령어}` 등 프로젝트 표준 명령어를 초기 세션에서 항상 허용으로 등록해 둔다
- **Git 명령어**: 커밋·푸시는 `git-deploy` 스킬의 안전 장치(브랜치 확인, 민감 파일 검사)를 거친 후 실행한다
- **파일 쓰기**: 프로젝트 디렉토리 내 쓰기는 허용 범위로 두고, 프로젝트 외부(`~` 등) 쓰기는 승인을 요구한다

### 7.2 권한 부여 원칙

| 원칙 | 설명 |
|:---|:---|
| **필요 최소 권한** | 실제로 사용하는 명령어만 화이트리스트에 추가 |
| **구체적 패턴** | 와일드카드(`*`)는 가능한 좁게 |
| **Git 관리는 신중히** | `git commit`, `git push`는 배포 스킬을 통해서만 수행 |
| **민감 파일 보호** | `.env`, `*.p12`, `*.jks` 등은 커밋 전 검사 |

### 7.3 권한 누적 관리

settings.local.json은 실제 작업을 진행하면서 **필요한 명령어를 발견할 때마다 누적**된다. 최초에는 핵심 명령어만 등록하고, 작업하면서 자연스럽게 확장한다.

---

## 8. 작업 디렉토리 및 컨텍스트 관리

### 8.1 _workspace/ 디렉토리

`_workspace/`는 모든 Phase의 중간 산출물을 저장한다. **Git으로 관리**한다.

**파일 네이밍**: `{phase#}_{description}.md`

| 파일 | Phase | 내용 |
|:---|:---|:---|
| `01_plan.md` | Phase 1 | 작업 범위, 대상 파일, 관련 Rule ID |
| `02_prd_update.md` | Phase 2 | 갱신된 PRD/AGENTS.md 섹션 목록 |
| `03_implementation.md` | Phase 2 | 변경 파일 목록 및 요약 |
| `05_review.md` | Phase 3 | 리뷰 상태(APPROVED/CHANGES_REQUESTED), 이슈 목록 |
| `07_test_report.md` | Phase 5 | 테스트 통과/실패 건수, 실패 상세 |
| `08_run_report.md` | Phase 6 | 실행 성공/실패, WARN 분류 |

### 8.2 작업 재개 전략

1. **Git Clone 후**: `.omp/progress.json` → `currentPhase`의 다음 Phase부터. 단 `awaiting_approval`이면 플랜 요약 재보고 후 승인 대기부터 재개한다(§6.13)
2. **기존 PC에서 새 작업**: `_workspace/` → `_workspace_prev/`로 이동 후 Phase 1부터
3. **부분 재실행**: 해당 Phase만 재실행, 연관 산출물만 교체

---

## 9. 새 프로젝트 설정 가이드

### 9.1 사전 조건

- omp가 설치되어 있을 것
- Git 저장소가 초기화되어 있을 것
- 프로젝트의 기본 구조가 갖춰져 있을 것
- PRD.md 초안이 작성되어 있을 것 (최소한 기능 목록과 Rule ID)

### 9.2 단계별 설정

#### 0단계: omp 런타임 확인

omp(oh-my-pi)가 설치되어 있고 `~/.omp/agent/config.yml`(전역)에 `modelRoles`가 정의되어 있는지 확인한다. **프로젝트 `.omp/config.yml`은 생성하지 않는다** — 모델 차등화는 전역 config 하나로 관리한다(§1.7).

#### 1단계: AGENTS.md 작성

[2. AGENTS.md 섹션](#22-필수-섹션)의 필수 섹션을 채운다. 이 파일이 하네스의 근간이다. 루트 `AGENTS.md`를 작성하고, `.omp/AGENTS.md` 진입점에서 `@../AGENTS.md`로 import 한다.

#### 2단계: PRD.md 작성

[3. PRD.md 섹션](#32-필수-섹션)의 구조에 따라 기능 명세를 작성한다. 최소한:
- 4절 기능 명세 (API 엔드포인트별)
- 7절 비즈니스 규칙 (Rule ID 포함)
- 8절 에러 코드

#### 3단계: `.omp/` 디렉토리 생성

```bash
mkdir -p .omp/agents
mkdir -p .omp/skills
```

이어서 `.omp/AGENTS.md` 진입점을 생성한다(본문 첫머리에 `@../AGENTS.md` import, §1.7). **`.omp/config.yml`은 생성하지 않는다** — modelRoles는 전역 `~/.omp/agent/config.yml`에서만 관리한다(§1.7).

#### 4단계: 에이전트 정의 파일 작성

`.omp/agents/` 아래 3개 에이전트를 생성한다. 부록의 스켈레톤을 복사하여 프로젝트에 맞게 수정한다.

**모델 지정 규칙** (롤 앨리어스, §4.2):
- `{project}-developer.md` → `model: "@developer"`
- `{project}-reviewer.md` → `model: "@reviewer"`
- `{project}-tester.md` → `model: "@developer"`

#### 5단계: 스킬 정의 파일 작성

`.omp/skills/` 아래 5~6개 스킬을 생성한다:

```
.omp/skills/{project}-orchestrator/SKILL.md
.omp/skills/{project}-business-rules/SKILL.md
.omp/skills/{project}-feature-dev/SKILL.md
.omp/skills/{project}-review-checklist/SKILL.md
.omp/skills/{project}-test-patterns/SKILL.md
.omp/skills/{project}-git-deploy/SKILL.md       # 선택
```

오케스트레이터 SKILL.md의 에이전트 호출 문법은 omp task tool로 통일한다(§1.7).
오케스트레이터 SKILL.md에는 사용자 승인 게이트(§6.13)를 하드 룰로 포함하고, `.omp/RULES.md`에도 동일 규칙을 스티키로 미러링한다.

#### 6단계: 전역 harness 메타 스킬 확인

전역 `~/.omp/agent/skills/harness/` 스킬이 있으면 이후 하네스 점검·확장·동기화에 활용한다(`/skill:harness`). 없으면 전역 스킬 저장소에서 설치한다.

#### 7단계: 작업 디렉토리 생성

```bash
mkdir -p _workspace
```

#### 8단계: 엔드-투-엔드 검증

간단한 기능(예: Health check API)으로 Phase 0→7 전체 파이프라인 검증.

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
| **Phase 3 첫 리뷰 통과율** | APPROVED / 전체 리뷰 횟수 | 60% 이상 | Developer 체크리스트 강화, PRD 명확화 |
| **되먹임 루프 횟수** | Phase 5→6→5 반복 횟수 | 평균 0.5회 이하 | BLOCKER 우선 리뷰 전략 적용 |
| **Reviewer 오탐률** | 리뷰 지적 중 실제 버그가 아니었던 비율 | 10% 미만 | review-checklist에 경계 조건 명확화 |
| **테스트 커버리지** | 프로젝트 커버리지 도구 | 80% 이상 (신규 코드) | test-patterns에 누락 시나리오 추가 |
| **Phase 6 실패율** | 실행 검증 실패 / 전체 실행 횟수 | 5% 미만 | Phase 4 검증 강화 |
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

1. `git clone`
2. omp 실행 → AGENTS.md 자동 참조
3. `.omp/progress.json` → 재개 지점 인식
4. 세션 재개: `omp -c` 또는 `omp -r` (피커)

---

## 11. Anti-Patterns — 하지 말아야 할 것

### 11.1 에이전트 관련

| Anti-Pattern | 문제점 | 올바른 접근 |
|:---|:---|:---|
| **오케스트레이터가 직접 코드 수정** | 오케스트레이터는 높은 수준의 통제만 해야 함. 코드 수정 시 컨벤션 일관성 깨짐 | 반드시 Developer 에이전트에게 위임 |
| **Reviewer가 코드 스타일만 지적** | 고추론 모델의 추론 능력을 낭비. 정작 중요한 비즈니스 로직 검증 누락 | 코드 스타일은 Phase 4에서 기계적으로 처리 |
| **Developer·Tester에 고추론 모델 사용** | 비용 낭비. 코드 생성에는 코드 생성 특화 모델로 충분 | Developer·Tester는 반드시 `model: "@developer"` |
| **Reviewer에 저비용 코드 생성 모델 사용** | 비즈니스 로직 검증 품질 저하, 오탐 증가로 신뢰도 하락 | Reviewer는 반드시 `model: "@reviewer"` |
| **에이전트에 너무 많은 스킬 할당** | 컨텍스트 분산, 핵심 지시사항 희석 | 에이전트당 2개의 스킬 (business-rules + 도메인별 가이드 1개) |
| **Tester가 테스트 코드 정리를 하지 않음** | Phase 4는 구현 코드만 정리하므로, 테스트 코드에 미사용 import·변수가 누적됨 | Tester는 Phase 7 완료 전에 테스트 소스 자체 정리 필수 |

### 11.2 프로세스 관련

| Anti-Pattern | 문제점 | 올바른 접근 |
|:---|:---|:---|
| **모든 작업에 Full Pipeline** | 단순 오타 수정에 Phase 1~9 전부 거치면 생산성 저하 | [6.1 작업 규모 판별](#61-작업-규모-판별-phase-선택) 기준 적용 |
| **구현 후에 PRD 업데이트** | Developer가 잘못된(오래된) 명세를 보고 구현 | Phase 2를 Phase 2보다 반드시 먼저 실행 |
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
| **하네스 (Harness)** | omp의 에이전트, 스킬, 설정, AGENTS.md를 유기적으로 조합한 개발 자동화 체계 |
| **에이전트 (Agent)** | 특정 역할(구현, 리뷰, 테스트)에 특화된 omp 서브 에이전트 |
| **스킬 (Skill)** | 에이전트가 작업 시 참조하는 도메인 지식 패키지 |
| **오케스트레이터** | 전체 개발 프로세스(Phase 0~9)를 통제하는 최상위 스킬 |
| **Phase** | 오케스트레이터가 관리하는 개발 프로세스의 한 단계 |
| **PRD.md** | 제품 요구사항 명세. 기능, 규칙, 에러 코드의 백과사전 |
| **Rule ID** | PRD 7장에 정의된 비즈니스 규칙 식별자 (예: `US-001`) |
| **되먹임 루프** | Phase 5(리뷰)→4(수정)→3(재리뷰) 반복. 최소화 대상 |
| **Full Pipeline** | Phase 0~9 전체를 거치는 대규모 작업 모드 |
| **Fast Path** | Phase 3→7만 거치는 소규모 작업 모드 |

### 부록 B: 전체 파일 트리

```
{project}/
├── AGENTS.md
├── PRD.md
├── ARCHITECTURE_CONVENTION.md    (존재 시 — 사내 아키텍처 표준)
├── HARNESS_CONVENTION.md         (이 문서 — 사내 하네스 표준)
├── CHANGELOG.md
│
├── .omp/                           (omp 하네스 루트 — §1.7)
│   ├── AGENTS.md                   @../AGENTS.md import
│   ├── RULES.md                    스티키 강제 규칙 (선택)
│   ├── config.yml                  modelRoles (선택)
│   ├── progress.json
│   ├── agents/
│   │   ├── {project}-developer.md   (model: "@developer")
│   │   ├── {project}-reviewer.md    (model: "@reviewer")
│   │   └── {project}-tester.md      (model: "@developer")
│   │
│   └── skills/
│       ├── {project}-orchestrator/
│       │   └── SKILL.md
│       ├── {project}-business-rules/
│       │   └── SKILL.md
│       ├── {project}-feature-dev/
│       │   └── SKILL.md
│       ├── {project}-review-checklist/
│       │   └── SKILL.md
│       ├── {project}-test-patterns/
│       │   └── SKILL.md
│       └── {project}-git-deploy/
│           └── SKILL.md
│
└── _workspace/
    ├── 01_plan.md
    ├── 02_prd_update.md
    ├── 03_implementation.md
    ├── 05_review.md
    ├── 07_test_report.md
    └── 08_run_report.md
```

### 부록 C: 에이전트 스켈레톤

**스켈레톤 frontmatter 표준** — `model`은 롤 앨리어스로 지정한다: C.1/C.3(developer·tester) → `"@developer"`, C.2(reviewer) → `"@reviewer"`. 본문은 에이전트 역할에 맞게 수정한다:

```markdown
---
name: {project}-{role}
description: {프로젝트명} {역할 한글명}. {주요 업무 설명}.
model: "@developer"
autoloadSkills:
  - {할당 스킬 목록}
---
```

#### C.1 Developer (model: "@developer")

```markdown
---
name: {project}-developer
description: {Project} 기능 구현 전문가. {기술 스택} 기반의 {구현 대상}을 PRD 및 AGENTS.md 규칙에 맞게 생성/수정한다.
model: "@developer"
autoloadSkills:
  - {project}-business-rules
  - {project}-feature-dev
---

# {Project} Developer

## 핵심 역할

{3~5문장}

## 작업 원칙

1. **항상 PRD와 AGENTS.md를 먼저 확인한다**
2. **레이어 순서대로 구현한다**: {프로젝트 레이어 순서}
3. **기존 코드와 일관성을 유지한다**
4. **문서화를 빼먹지 않는다**
5. **데이터 무결성을 보장한다**

## 구현 체크리스트

- [ ] {레이어 1}: {체크리스트}
- [ ] {레이어 2}: {체크리스트}
...

## 입력/출력 프로토콜

- **입력**: 구현할 기능 명세, 관련 Rule ID, 참고 코드 경로
- **출력**: 생성/수정 파일 목록과 변경 요약
- **중간 산출물**: `_workspace/` 디렉토리

## 에러 핸들링

- 빌드 에러 → {빌드 명령어} 실행하여 원인 파악 후 수정
- 비즈니스 규칙 충돌 → Reviewer에게 질의
- 모호한 요구사항 → 오케스트레이터에게 명확화 요청

## 협업

- Reviewer의 피드백을 받으면 해당 내용만 수정한다.
- Tester의 실패 보고를 받으면 원인을 분석하고 수정한다.

## 이전 산출물이 있을 때의 행동

- `_workspace/`가 존재하면 이전 결과를 읽고 중복 작업을 피한다.
```

#### C.2 Reviewer (model: "@reviewer")

```markdown
---
name: {project}-reviewer
description: {Project} 코드 리뷰 전문가. PRD 비즈니스 규칙, AGENTS.md 아키텍처, 데이터 무결성을 기준으로 구현 코드를 검증하고 개선점을 제시한다.
model: "@reviewer"
autoloadSkills:
  - {project}-business-rules
  - {project}-review-checklist
---

# {Project} Reviewer

## 핵심 역할

{3~5문장}

## 작업 원칙

1. **PRD 비즈니스 규칙이 최우선 기준이다**
2. **데이터 무결성을 반드시 확인한다**
3. **심각도로 구분한다**: BLOCKER > CRITICAL > WARNING
4. **코드 스타일보다 정합성에 집중한다**
5. **건설적이고 구체적인 피드백을 제시한다**

## 리뷰 체크리스트

### 1. {레이어 1}
- [ ] {체크리스트}
...

## 입력/출력 프로토콜

- **입력**: 리뷰 대상 파일 경로, 변경 코드, 관련 PRD 섹션
- **출력**: `{severity, rule_id, file:line, description, suggestion}` 이슈 목록
- **리뷰 상태**: APPROVED / CHANGES_REQUESTED

## 협업

- Developer에게 건설적 피드백 전달
- Tester에게 중점 테스트 영역 제안
```

#### C.3 Tester (model: "@developer")

```markdown
---
name: {project}-tester
description: {Project} 테스트 전문가. {테스트 프레임워크} 기반으로 단위/통합 테스트를 작성·실행한다. 비즈니스 규칙의 경계 조건과 예외 케이스를 중점 검증한다.
model: "@developer"
autoloadSkills:
  - {project}-business-rules
  - {project}-test-patterns
---

# {Project} Tester

## 핵심 역할

{3~5문장}

## 작업 원칙

1. **비즈니스 규칙을 테스트한다**
2. **계층별 적절한 테스트를 작성한다**
3. **테스트는 독립적이고 반복 가능해야 한다**
4. **실패 시 반드시 원인(버그 vs 테스트 오류)을 구분한다**
5. **커버리지보다 테스트 품질**
6. **테스트 코드도 정리 대상이다** — 테스트 작성 완료 후 미사용 import, 미사용 변수, 미사용 private 멤버를 제거한다. 테스트 소스에 대해서도 Phase 4와 동일한 수준의 코드 정리를 자체 수행한다. 프로젝트 표준 들여쓰기(§6.5 — Ruby·JS·HTML·ERB 2칸, 그 외 4칸)도 준수한다.

## 테스트 체크리스트

### {계층 1} 테스트
- [ ] {체크리스트}
...

### 테스트 코드 품질 (Phase 7 완료 전 자체 점검)
- [ ] 테스트 소스에서 미사용 import 제거
- [ ] 테스트 소스에서 미사용 지역 변수 제거
- [ ] 테스트 소스에서 미사용 private 필드/메서드 제거
- [ ] 프로젝트 표준 들여쓰기 준수 확인 (§6.5: Ruby·JS·HTML·ERB 2칸, 그 외 4칸, 탭 금지)
- [ ] `{컴파일 명령어}`(또는 동등 명령) 통과 확인

## 입력/출력 프로토콜

- **입력**: 테스트 대상, 기능 요약, 중점 시나리오
- **출력**: 테스트 실행 보고서 (통과/실패, 실패 상세, 원인 분류)

## 협업

- Developer에게 실패 정보 전달 (버그인 경우)
- Reviewer가 지적한 위험 영역 중점 테스트
```

---

> **이 문서는 사내 모든 프로젝트의 omp 하네스 구성 기준입니다.**
> 프로젝트별 편차가 필요한 경우, 이 문서의 원칙 범위 내에서 AGENTS.md에 예외 사항을 명시하세요.
>
> **변경 이력:**
> | 날짜 | 버전 | 변경 내용 |
> |------|------|----------|
> | 2026-08-05 | 1.0.0 | 최초 제정 — SentraPass 하네스 기반 |
> | 2026-08-05 | 1.1.0 | 모델 전략 명확화(Developer·Tester=코드 생성 특화, Reviewer·Orchestrator=추론 특화), Phase 생략 규칙(Fast Path), PRD.md 표준 구조, Phase 4 언어 중립화, 되먹임 루프 최소화 전략, 병렬 실행 가이드, Anti-Patterns, 하네스 효과성 메트릭, 메타 스킬 개념 추가 |
> | 2026-08-05 | 1.2.0 | 트리거 메커니즘(description 기반 자동 매칭, AGENTS.md 트리거 섹션 패턴), Phase별 완료 기준(Definition of Done), Git 사전 상태 점검, 구체적인 실행 예시(Narrative Walkthrough: Person API 구현 Full Pipeline) 추가 |
> | 2026-08-05 | 2.0.0 | **Phase 번호 체계 개편** — 소수점(1.5, 2.5)을 순차 정수(0~9)로 통일. Phase 4(코드 정리) 범위 확장: 미사용 변수·private 멤버 제거, 테스트 코드 정리, 들여쓰기 4칸(space) 표준 명시 |
> | 2026-08-28 | 2.1.0 | **omp(oh-my-pi) 런타임 호환** — §1.7 런타임 매핑 신설(개념 매핑 표, modelRoles 롤 앨리어스, 공존 전략), omp 파일 트리·에이전트 frontmatter(`@롤` 앨리어스, `autoloadSkills`)·스킬 위치 전략·설정 가이드 병기, 메타 스킬의 전역 omp 스킬(~/.omp/agent/skills/harness) 명시 |
> | 2026-08-28 | 3.0.0 | **omp(oh-my-pi) 단일 런타임화** — 듀얼 런타임 개념 전면 제거. §1.7 omp 구성 표준 재정의(단일 컬럼 표 16행), 에이전트 frontmatter omp 전용(`model: "@롤"`, `autoloadSkills`), task tool 스폰 문법·Agent Hub 통신·`/skill:` 강제 호출, §7.1 omp 자체 승인 모델로 재작성, 스킬 위치 `.omp/skills/` 단일 소스, §9.2 omp 구성 절차, 부록 B/C omp 전용 개정, 전역 harness 메타 스킬 omp 전용화 |
> | 2026-09-14 | 3.1.0 | **서브에이전트 일회성 스폰 원칙 신설(§4.6)** — 작업마다 task tool 신규 스폰 의무화, 완료 에이전트 `hub send` 재소환 금지, 최종 결과 수신 후 `hub cancel` 등록 해제. §1.7 통신 행·§6.3 데이터 흐름 갱신 |
> | 2026-09-14 | 3.1.1 | **modelRoles 전역 단일 관리로 정책 변경** — 프로젝트별 `.omp/config.yml` 생성 금지, 전역 `~/.omp/agent/config.yml`의 `modelRoles`만 사용 (§1.4·§1.7·§9.2). 설정 단일화로 프로젝트 간 모델 롤 일관성 유지 |
> | 2026-10-01 | 3.1.2 | **세션 todo 동기화 규칙 신설(§6.4)** — 오케스트레이터가 매 Phase 전환 시 세션 todo를 done/start로 갱신 의무화. TODO 위젯은 todo 호출 기준 표시이며 자동 추적이 아님을 명문화 (sentinel-demo 하네스 운영 경험 반영) |
> | 2026-10-01 | 3.1.3 | **완료 에이전트 해제 수단 명시(§4.6·§6.3·§1.7)** — 결과 수신 즉시 해제 의무화, `hub cancel` 미제공 런타임에서는 `proc://<에이전트ID>/kill` 취소를 대안 해제 수단으로 고정. 해제 생략 → 로스터 잔존·재소환 사고 경로 명문화 (sentinel-demo 하네스 운영 경험 반영) |
> | 2026-10-01 | 3.1.4 | **3.1.3 정정 — proc kill은 parked 등록 해제 불가(§4.6·§6.3·§1.7)** — `proc://<id>/kill`은 실행 중 세션만 취소하며 완료(parked) 에이전트의 로스터 등록은 잔존(4건 실측: not found). `hub` 미제공 세션은 Agent Hub UI `x: kill` 수동 정리 + 오케스트레이터의 잔존 안내 의무로 대체 |
> | 2026-10-01 | 3.1.5 | **세션 todo 갱신 트리거 절차형 명시(§6.4)** — '에이전트 결과 수신 직후 첫 도구 호출 = todo done'을 1순위 트리거로 고정(누적 누락의 실측 실패 모드 반영), progress.json 세트 갱신 유지 (sentinel-demo 하네스 운영 경험 반영) |
> | 2026-10-08 | 3.1.6 | **사용자 승인 게이트 신설(§6.13)** — 모든 작업 규모에서 플랜 보고 후 사용자 승인 전 에이전트 스폰 금지. 턴 종료를 강제 수단으로 고정, progress.json `awaiting_approval` 상태·재개 규칙 도입, §1.3·§5.3·§6.1·§6.2·§6.4·§6.10·§6.12·§8.2·§9.2·§11.2 갱신, 오케스트레이터 SKILL.md·`.omp/RULES.md` 미러링 의무화 |
> | 2026-10-08 | 3.2.0 | **들여쓰기 표준 언어별 이원화(§2.2·§6.5·부록 C.3)** — Ruby·JavaScript·HTML·ERB를 2칸(space) 표준으로 변경, 그 외 언어는 4칸(space) 유지. 탭 문자 금지 공통. Prettier 예시 `--tab-width 2`로 갱신 |
