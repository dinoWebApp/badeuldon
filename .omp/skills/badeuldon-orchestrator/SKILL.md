---
name: badeuldon-orchestrator
description: 받을돈(BadeulDon) 개발 오케스트레이터. 신규 기능 구현, 코드 수정, 리팩터링, 버그 수정, 테스트 작성, 코드 리뷰, 디버깅, 라우트·API 설계, 데이터베이스 마이그레이션, 비즈니스 로직 검증 등 받을돈 Rails 프로젝트의 모든 개발 작업을 조율한다. 받을돈 관련 개발 요청, 기능 구현, 코드 리뷰, 테스트 작성, 디버깅, 마이그레이션 요청 시 사용한다. 후속 작업(수정, 보완, 개선, 리팩터링, 재실행, 업데이트)도 처리한다.
---

# 받을돈 개발 오케스트레이터

## 이 스킬의 목적

사용자의 개발 요청을 Phase 0~9 파이프라인으로 통제하여, PRD 비즈니스 규칙과 ARCHITECTURE_CONVENTION 아키텍처를 준수하는 코드가 구현·리뷰·테스트되도록 보장한다. 오케스트레이터는 **절대 직접 코드를 수정하지 않는다** — 구현은 Developer, 검증은 Reviewer, 테스트는 Tester 에이전트에게 위임한다.

## 하드 룰 (절대 위반 불가)

1. **사용자 승인 게이트(§6.13)**: 플랜 보고 후 **턴을 종료**하고 승인을 기다린다. 승인 전 어떤 에이전트도 스폰하지 않는다. 이 게이트는 작업 규모와 무관하게 항상 적용되며, 승인 후에는 재승인 없이 파이프라인을 자동 진행한다. 세션 재개 시 `currentPhase=awaiting_approval`이면 플랜 요약 재보고 후 승인 대기.
2. **직접 구현 금지**: 코드 수정은 항상 Developer 에이전트 위임. 오케스트레이터는 문서 현행화(Phase 2)와 기계적 검증(Phase 4·8)만 직접 수행.
3. **일회성 스폰(§4.6)**: 모든 위임은 task tool로 신규 에이전트 스폰. 완료 보고한 에이전트 재소환 금지 — 후속 작업(리뷰 반영 수정, 재테스트)은 `_workspace/` 산출물을 지시서에 첨부해 새로 스폰한다. 최종 결과 수신 후 `hub cancel`으로 등록 해제를 시도(hub 미제공 세션은 최종 보고에 Agent Hub UI `x: kill` 수동 정리 안내).
4. **에이전트 호출 문법**: omp task tool 단일 문법만 사용한다.
5. **todo 동기화**: 에이전트 결과 수신 직후의 첫 도구 호출을 반드시 `todo done`으로 한다(누적 누락 방지). `progress.json` 갱신 시 세션 todo를 세트로 갱신.

## 에이전트 스폰 블록 (task tool)

```json
{ "tasks": [ { "agent": "badeuldon-developer", "task": "_workspace/01_plan.md 기준 구현 지시 전문 (관련 Rule ID, 대상 파일, 레이어 순서, 산출물 _workspace/03_implementation.md 명시)" } ] }
```

```json
{ "tasks": [ { "agent": "badeuldon-reviewer", "task": "리뷰 대상 파일 목록 + 관련 PRD 섹션·Rule ID + _workspace/03_implementation.md 첨부. 산출물 _workspace/05_review.md (status: APPROVED|CHANGES_REQUESTED)" } ] }
```

```json
{ "tasks": [ { "agent": "badeuldon-tester", "task": "테스트 대상 + 관련 Rule ID 시나리오 + _workspace/03_implementation.md 첨부. 산출물 테스트 파일 + _workspace/07_test_report.md" } ] }
```

에이전트는 맥락이 없는 새 세션이다 — 지시서에 목적·범위·Rule ID·파일 경로·기대 산출물을 자급자족하게 담는다.

## Phase 0 — 컨텍스트 확인 (오케스트레이터)

1. `.omp/progress.json` 읽기: `currentPhase != null`이면 resume 모드(해당 Phase부터), `awaiting_approval`이면 플랜 재보고 후 승인 대기.
2. `_workspace/` 존재 시 이전 작업 컨텍스트로 인식. 새 작업이면 직전 산출물 보존 후 초기화.
3. Git 사전 점검: `git status --short` — 소스에 uncommitted 변경 있으면 사용자에게 확인(커밋/포함/stash), 브랜치 확인.
4. PRD.md에서 요청 도메인의 기능·Rule ID 식별.
5. **작업 규모 판별** → `progress.json`에 `pipelineType` 기록:
   - **Full** (Phase 0→1→✋→2→3→4→5→6?→7→8→9): 새 도메인/엔티티, 새 라우트·화면, 비즈니스 로직 포함 기능, 마이그레이션, 3개+ 파일 변경
   - **Standard** (Phase 1→✋→3→5→7): 기존 로직 수정, 1~2 파일 기능 변경, 로직 버그 수정
   - **Fast** (Phase 1 간이→✋→3→7): 오타·문구·포맷·주석·설정값, 테스트만 추가
6. 세션 todo를 Phase 구조로 init.

## Phase 1 — 요구사항 분석 (오케스트레이터)

PRD에서 관련 기능 명세(§6~7)·Rule ID·에러 조건 추출, 대상 파일·마이그레이션 필요성 결정, PRD 갱신 필요 항목 식별. 산출물: `_workspace/01_plan.md` (작업 범위, 대상 파일, 관련 Rule ID, 에이전트 지시 요약, 리스크).

## ✋ 사용자 승인 게이트 (모든 규모 공통)

1. `progress.json`: `"currentPhase": "awaiting_approval"` + todo 갱신.
2. 플랜 요약 보고: pipelineType·진행할 Phase 순서, 각 에이전트 지시 요약, 변경 예상 파일 목록, 리스크·모호점.
3. "플랜을 승인하시겠습니까?" 출력 후 **턴 종료**. 승인("진행/OK/승인") 응답 시 다음 Phase부터 자동 진행(재승인 없음). 수정 요청 시 Phase 1 재계획.

## Phase 2 — 문서 현행화 ⚠️ 필수 (오케스트레이터)

PRD.md·AGENTS.md를 **구현보다 먼저** 갱신한다. "수정 사항 없음"은 불허 — 최소한 버전/최종 수정일이라도 갱신하고 그 사유를 기록. 신규 규칙은 Rule ID로 추가(기존 마지막 번호+1, ID 재사용 금지). 산출물: `_workspace/02_prd_update.md`.

## Phase 3 — 구현 (Developer 스폰)

ARCHITECTURE_CONVENTION 레이어 순서 준수 지시: 마이그레이션 → Model(+enum·scope·검증) → Form/Service(필요 시) → Controller → View(ERB/Hotwire) → Routes → Job(필요 시). 산출물: 소스 + `_workspace/03_implementation.md` (변경 파일 목록·요약·Rule ID별 구현 매핑).

## Phase 4 — 코드 정리 (오케스트레이터 직접, 기계적 검증)

구현 코드 전체(테스트는 Phase 7 Tester 자체 정리)에 대해:

```bash
bin/rubocop                       # 0 에러 (미사용 정의·포맷 검출)
bin/rails zeitwerk:check          # 자동 로딩 규약
bin/rails db:migrate              # 마이그레이션 정합성 (스키마 변경 시)
```

미사용 코드·포맷 위반은 직접 교정하거나 Developer 재스폰(신규)으로 반영.

## Phase 5 — 코드 리뷰 (Reviewer 스폰, @reviewer)

검증 기준: ① PRD Rule ID 정합성(최우선) ② 데이터 무결성·보안(토큰 엔트로피·멱등성·noindex·권한) ③ 아키텍처 준수(의존 방향·계층 규칙). 심각도: BLOCKER > CRITICAL > WARNING. 산출물: `_workspace/05_review.md`.

- APPROVED → Phase 7
- CRITICAL/WARNING → Phase 6 → Phase 7 (재리뷰 불필요)
- BLOCKER → Phase 6 → Phase 5 재리뷰 (루프 최대 2회, 초과 시 원인 분석 후 사용자 보고)

## Phase 6 — 수정 (Developer 신규 스폰)

`_workspace/05_review.md` 이슈만 최소 수정. 관련 없는 코드 절대 변경 금지.

## Phase 7 — 테스트 (Tester 스폰, @developer)

Rule ID별 정상/경계/예외 시나리오 → minitest 작성·실행. 테스트 코드 자체 정리(미사용 정의·포맷)는 Tester 책임. 실패 시 원인 분류: 코드 버그 → Phase 6, 테스트 오류 → Phase 7 재실행. 산출물: 테스트 파일 + `_workspace/07_test_report.md`.

## Phase 8 — 실행 검증 (오케스트레이터 직접)

```bash
bin/rails db:prepare && bin/dev 백그라운드 실행 → 시작 로그 확인
```

- 시작 완료 신호(Puma 부트) 확인, 에러 키워드·WARN 분류: [허용](프레임워크 안내) / [수정 필요](설정 누락 등 → Phase 4 회귀) / [주의](deprecated 등 기록).
- 라우트·마이그레이션이 있는 경우 해당 경로 실제 응답 확인. 산출물: `_workspace/08_run_report.md`.

## Phase 9 — 완료 보고 (오케스트레이터)

변경 파일 요약, 리뷰·테스트·실행검증 결과, 잔존 에이전트 안내 → AGENTS.md "구현 진행 상황" 갱신 → `progress.json` 리셋(`currentPhase: null`) → Git 커밋은 사용자 요청 시 `badeuldon-git-deploy` 스킬로.

## 데이터 흐름

Phase 간 데이터는 `_workspace/` 파일로 전달: `01_plan.md` → `02_prd_update.md` → `03_implementation.md` → `05_review.md` → `07_test_report.md` → `08_run_report.md`. 에이전트는 `_workspace/`가 있으면 이전 산출물을 읽고 중복 작업을 피한다.

## 에러 핸들링

| 상황 | 대응 |
|:---|:---|
| 에이전트 실패 | 1회 재시도(신규 스폰) → 재실패 시 해당 Phase 건너뛰고 완료 보고에 누락 명시 |
| 비즈니스 규칙 충돌/모호함 | PRD 원문 인용, 해석 모호하면 사용자 질의 |
| 마이그레이션/부트 실패 | 오류 로그 수집 → Developer 수정 위임 |
| 테스트 실패 | 코드 버그 vs 테스트 오류 구분 → 각각 Phase 6 / Phase 7 분기 |
| 리뷰 루프 2회 초과 | 사용자에게 상황 보고, 루트 원인(PRD 모호함/이해 부족/과잉 지적) 분석 |
