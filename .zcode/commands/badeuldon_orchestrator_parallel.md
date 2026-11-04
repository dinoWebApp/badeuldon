---
description: "받을돈 개발 하네스 실행 — 병렬 배치 일반 모드"
model: "account:zai-individual-coding-plan/GLM-5.3"
skills: "badeuldon-orchestrator"
---

병렬 배치(일반) 모드로 작업한다. 동일한 `badeuldon-orchestrator` 스킬의 전체 규칙(Phase 0~9, 승인 게이트, 산출물 규칙)과 HARNESS_CONVENTION §6.14 병렬 배치 파이프라인 규칙을 따른다 — 병렬 배치 절이 일반 Phase 절차에 우선 적용된다.

- 사용자 승인 전 Developer/Reviewer/Tester 서브에이전트를 호출하지 않는다. 배치 플랜(병렬 그룹·파일 소유권 표) 보고 후 턴을 종료하고 사용자의 태스크 선택·승인을 기다린다.
- 호출 프로필(일반): `badeuldon-developer`, `badeuldon-reviewer`, `badeuldon-tester`.
- 병렬 안전 판정(§6.14 3조건 — 파일 소유권 분리·의존 없음·공유 파일 비수정)을 통과한 태스크만 Phase 3-P에서 동시 스폰한다(동시성 상한 기본 3).
- 진행 상태는 `.zcode/progress.json`(`pipelineType: "parallel"` + `parallelTasks`), 태스크별 산출물은 `_workspace/parallel/<task-id>/`에 기록한다.

작업 요청: $ARGUMENTS
