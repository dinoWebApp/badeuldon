---
description: "받을돈 개발 하네스 실행 — 일반 모드"
model: "account:zai-individual-coding-plan/GLM-5.3"
skills: "badeuldon-orchestrator"
---

일반 모드로 작업한다. 동일한 `badeuldon-orchestrator` 스킬의 전체 규칙(Phase 0~9, 승인 게이트, 산출물 규칙)을 따른다.

- 사용자 승인 전 Developer/Reviewer/Tester 서브에이전트를 호출하지 않는다. 플랜 보고 후 `AskUserQuestion` 선택 질의(승인/수정/중단)로 승인을 받는다 — 승인 선택 전 스폰 금지, 승인 시 같은 턴 진행, 질의 불가 시 텍스트 폴백 후 턴 종료(§6.13).
- 호출 프로필(일반): `badeuldon-developer`, `badeuldon-reviewer`, `badeuldon-tester`.
- 진행 상태는 `.zcode/progress.json`, 산출물은 `_workspace/`에 기록한다.

작업 요청: $ARGUMENTS
