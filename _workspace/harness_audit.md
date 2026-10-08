# 받을돈 하네스 구성 보고서

- **일자**: 2026-10-08
- **모드**: A (신규 구성) — 하네스 메타 스킬(`skill://harness`)
- **기준 규약**: HARNESS_CONVENTION v3.2.0 (내장 사본 → 프로젝트 루트로 복사, Git 관리 전환)
- **런타임**: omp (전역 `~/.omp/agent/config.yml` modelRoles 사용 — 프로젝트 `.omp/config.yml` 생성 안 함)

## 구성 전 감사 (Phase 0)

| 항목 | 상태 | 조치 |
|:---|:---|:---|
| HARNESS_CONVENTION.md | ❌ 루트 없음 | 루트 복사 완료 |
| AGENTS.md / .omp/AGENTS.md | ❌ 누락 | 신규 작성 |
| 오케스트레이터 스킬 | ❌ 누락 | 신규 작성 |
| 에이전트 3종 | ❌ 누락 | 신규 작성 |
| 도메인 스킬 4종 + git-deploy | ❌ 누락 | 신규 작성 |
| RULES.md / progress.json / _workspace/ | ❌ 누락 | 생성 |
| 전역 modelRoles | ✅ planner/reviewer=glm-5.3, developer=glm-5.3-flash:high | 확인만 |
| 메타 스킬 harness (전역) | ✅ 설치됨 | — |

## 구성 결과

```
AGENTS.md                          지식 단일 소스 (Rule ID 색인·트리거 섹션 포함)
HARNESS_CONVENTION.md              v3.2.0 사본
.omp/AGENTS.md                     진입점 (@../AGENTS.md import + omp 보강)
.omp/RULES.md                      스티키 8종 (승인 게이트 미러링 포함)
.omp/progress.json                 초기 상태 (currentPhase: null)
.omp/agents/badeuldon-developer.md model: @developer + business-rules, feature-dev
.omp/agents/badeuldon-reviewer.md  model: @reviewer  + business-rules, review-checklist
.omp/agents/badeuldon-tester.md    model: @developer + business-rules, test-patterns
.omp/skills/badeuldon-orchestrator/      Phase 0~9, 승인 게이트 하드 룰, task tool 문법
.omp/skills/badeuldon-business-rules/    P1~P5, 도메인별 Rule ID 색인, 외부 서비스
.omp/skills/badeuldon-feature-dev/       Rails 8.1 레이어 순서·템플릿·품질 게이트
.omp/skills/badeuldon-review-checklist/  레이어별 점검 + Rule ID 매핑 + 심각도
.omp/skills/badeuldon-test-patterns/     minitest 계층·Rule ID 시나리오·외부 API stub
.omp/skills/badeuldon-git-deploy/        커밋·푸시 안전 장치
_workspace/                        Phase 산출물 (본 보고서 포함)
```

## 검증 결과 (2026-10-08 실시)

- 에이전트 3종 frontmatter: name·model 롤 앨리어스·autoloadSkills 참조 무결 ✅
- 스킬 6종 frontmatter: name = 디렉토리명, description 트리거 키워드 포괄 ✅
- `.omp/AGENTS.md` import 구문, `progress.json` 유효 JSON(currentPhase: null) ✅
- 프로젝트 `.omp/config.yml` 미생성 (규약 §1.7 준수) ✅

## 프로젝트 특화 반영

- Rails 8.1 + ERB + Hotwire + Tailwind + minitest + Solid 3종 + Kamal (ARCHITECTURE_CONVENTION v1.0.0 연동)
- PRD v0.17 Rule ID 체계(AUTH~DESIGN 25개 접두어)를 스킬·에이전트에 매핑 — Rule ID 신설 불필요
- 도메인 하이라이트: 발송 멱등성(SEC-5), 발송 창(REM-3), 5통 상한(REM-12), 채무자 무가입(P3), 뷰어 화이트리스트(VIEW-8), KST 고정(TIME-1)
- 품질 게이트: `bin/ci`(RuboCop + Brakeman + test)를 완료 보고 조건으로 규정

## 다음 단계 (권장)

1. Git 커밋으로 하네스 자산 추적 시작 (`.omp/`, `_workspace/`, `AGENTS.md`, `HARNESS_CONVENTION.md`)
2. 첫 기능(F-AUTH 등)을 `/skill:badeuldon-orchestrator` 로 검증 — 엔드-투-엔드 파이프라인 확인
