@../AGENTS.md

# omp 런타임 보강

위 import로 루트 `AGENTS.md`(지식 단일 소스)를 로드했다. 아래는 omp 런타임에서 하네스를 구동하기 위한 추가 지시다.

## 전문 에이전트

- 위치: `.omp/agents/`
- `badeuldon-developer` (model: @developer) — 기능 구현·수정
- `badeuldon-reviewer` (model: @reviewer) — 비즈니스 규칙·아키텍처 검증
- `badeuldon-tester` (model: @developer) — 테스트 작성·실행

## 에이전트 스폰 문법 (task tool)

```json
{ "tasks": [ { "agent": "badeuldon-developer", "task": "구현 지시 전문 (맥락·Rule ID·산출물 경로 포함)" } ] }
```

- 에이전트는 매 작업 **신규 스폰**(일회성). 완료 보고 후 재소환 금지, 후속 작업은 `_workspace/` 산출물을 전달해 새로 스폰한다.
- 에이전트 간 협력은 진행 중(양쪽 살아 있을 때)에만 Agent Hub(`Alt+A` / hub tool) 허용.

## 스킬 강제 호출

- 모든 개발 작업 요청은 `/skill:badeuldon-orchestrator` 로 라우팅한다 (AGENTS.md 트리거 섹션 참조).
- 배포 요청은 `/skill:badeuldon-git-deploy`.

## 경로

- 프로젝트 스킬: `.omp/skills/` (orchestrator, business-rules, feature-dev, review-checklist, test-patterns, git-deploy)
- 진행 상태: `.omp/progress.json` (위치 불변)
- 작업 산출물: `_workspace/` (`01_plan.md` … `08_run_report.md`)
- 스티키 강제 규칙: `.omp/RULES.md`
- **프로젝트 `.omp/config.yml`은 생성하지 않는다** — modelRoles는 전역 `~/.omp/agent/config.yml`에서 단일 관리한다.
