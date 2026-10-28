---
description: "받을돈 개발 하네스 실행 — 일반 모드"
model: glm-5.3
skills: "badeuldon-orchestrator"
---

일반 모드로 작업한다. 동일한 `badeuldon-orchestrator` 스킬의 전체 규칙(Phase 0~9, 승인 게이트, 산출물 규칙)을 따른다.

- 사용자 승인 전 Developer/Reviewer/Tester 서브에이전트를 호출하지 않는다. 플랜 보고 후 턴을 종료하고 승인을 기다린다.
- 호출 프로필(일반): `badeuldon-developer`, `badeuldon-reviewer`, `badeuldon-tester`.
- 진행 상태는 `.zcode/progress.json`, 산출물은 `_workspace/`에 기록한다.

작업 요청: $ARGUMENTS
