---
name: badeuldon-review-checklist
description: 받을돈 코드 리뷰 체크리스트 스킬. 레이어별(Model/Service/Controller/View/Job/라우트) 점검 항목과 Rule ID 매핑, 심각도 기준(BLOCKER/CRITICAL/WARNING), 보안·데이터 무결성 점검 기준을 제공한다. 받을돈 코드를 리뷰할 때 사용한다.
---

# 받을돈 코드 리뷰 체크리스트

## 이 스킬의 목적

Reviewer가 비즈니스 로직 정합성에 집중해 체계적으로 리뷰하도록 레이어별 점검항목과 Rule ID 매핑을 제공한다. **코드 스타일은 Phase 4(RuboCop)가 이미 처리했다고 전제하고 스타일 지적을 최소화한다.** 출력 형식: `{severity, rule_id, file:line, description, suggestion}`.

## 심각도 정의

| 심각도 | 기준 | 예시 |
|:---|:---|:---|
| **BLOCKER** | 데이터 정합성 훼손, 보안 취약점, 런타임 에러 유발 | 마이그레이션 누락, 토큰 추측 가능, 권한 우회, SEC-5 미준수 |
| **CRITICAL** | 비즈니스 로직 오류, Rule 명백한 위반 | 상태 전이 오류(INV-4), 야간 발송 허용(REM-3), 채무자 마감 처리(PROMISE-7) |
| **WARNING** | 컨벤션 위반, 문서화 누락, 성능 개선 여지 | N+1, 뷰 로직 초과, noindex 누락(SURF-3) |

BLOCKER 발견 즉시 리뷰 중단·보고 → 수정 후 재리뷰. 출력은 `_workspace/05_review.md`에 status(APPROVED/CHANGES_REQUESTED)와 함께 기록.

## 1. 보안·데이터 무결성 (최우선 — 항상 전수 점검)

- [ ] 소유권 격리: `Current.user.invoices.find(...)` 패턴 — 타 사용자 자원 ID 직접 접근 차단
- [ ] 뷰어(/b/:token)는 토큰 조회만, 추측 불가 엔트로피(SHARE-1/SEC-1), 인증 요구 없음(P3)
- [ ] 관리자(/admin)는 ADMIN 롤 + 2FA 가드(AUTH-7/ADMIN-1), 관리 행위 감사 로그(ADMIN-2)
- [ ] 발송 멱등성: 동일 청구·동일 단계 정확히 1회(SEC-5) — 동시성(유니크 인덱스 등)도 확인
- [ ] noindex/robots: `/app`, `/b/*`, `/admin`(SURF-3)
- [ ] 사용자 입력 이스케이프: `raw`/`html_safe` 미사용, ERB 이스케이프 기본
- [ ] 민감 정보 노출 없음: U1 개인 번호·이름의 발신 노출(P2/REM-1), 로그에 토큰·계좌 평문 출력 금지

## 2. Model / 마이그레이션

- [ ] 상태 전이가 INV-4와 정확히 일치하는가 (불가능한 전이 코드 존재 여부)
- [ ] enum 정의·`dependent:`·`null: false`/인덱스 명시 (ARCHITECTURE_CONVENTION §3.1)
- [ ] 만기일 계산이 발행일+30일 기본(INV-3)·KST 기준(TIME-1)인가
- [ ] 금액 컬럼이 정수(원 단위) 또는 명시적 정밀도 decimal인가 — 부동소수 금액 금지
- [ ] Rule ID별 검증이 모델/서비스 적층에 실려 있는가 (예: US 관점의 uniqueness 등)

## 3. Service / 도메인 로직

- [ ] 진입점 `#call`, 생성자에 params/Current 무결(§3.5) — Job/콘솔 재사용 가능성
- [ ] 트랜잭션 경계: 여러 쓰기가 하나의 transaction 안에
- [ ] 외부 API(핵클·토스페이먼츠)가 wrapper로 캡슐화되어 테스트 대체 가능한가(REM-10/PLAN-5)
- [ ] 발송 창 검증(평일 09-18, REM-3), 상한 5통(REM-12/PLAN-3), 시퀀스 재스케줄(PROMISE-3) 로직 정합성
- [ ] 채무자 회신이 마감 상태를 변경하지 않는가(PROMISE-7)
- [ ] 예외가 사용자 정의 예외로 명시적이고 조용한 rescue 없는가

## 4. Controller / 라우트

- [ ] 액션 본문 10줄 이내, 인증/권한은 before_action
- [ ] `params.expect` 사용, 화이트리스트 누락 없음
- [ ] 성공 303/실패 422 응답 규약 — Turbo 폼 동작 전제
- [ ] 라우트가 표면 구조(①~④)와 일치, 커스텀 액션 정당화됐는가(SURF-1)
- [ ] Free/Plus 플랜 게이트가 필요 지점에 존재(REM-8, PLAN-1: 월 3건/거래처 5개)

## 5. View / Hotwire

- [ ] 뷰 쿼리 호출 없음, 표현 로직 3줄+는 헬퍼
- [ ] 뷰어(③) 요소 화이트리스트 준수(VIEW-8): 청구 내용·응답 액션·PDF·고지문(VIEW-5)만 — 내비·마케팅·③→① 링크 금지(SURF-4)
- [ ] 발신 문구가 단계별 톤 가이드 내인가(REM-2, P1) — 협박·법적 조치 언급 금지(Q2)
- [ ] 사용자 편집 문구에 금지 표현 필터 적용(REM-9)
- [ ] Frame id 컨벤션(dom_id/명사_복수), 파괴적 버튼 turbo_confirm
- [ ] 접근성: 터치 타깃·기본 글자 크기 상향(DESIGN-6)

## 6. Job / 비동기

- [ ] 인자가 스칼라 id만, 멱등 설계(§11.2)
- [ ] `retry_on` 명시, 조용한 rescue 없음
- [ ] 열람→알림 지연 60초 이내 구조(PERF-1, SHARE-4) — 동기 chain으로 지연 유발 않는가

## 7. 아키텍처 준수 (ARCHITECTURE_CONVENTION)

- [ ] 의존 방향 위반 없음(§4.2): Model→Service 금지, Service→params 금지, View→쿼리 금지
- [ ] 도메인 간 결합이 공개 진입점 경유(§4.3)
- [ ] 네이밍·파일 위치 규약(§5) — zeitwerk:check 통과 전제

## 리뷰 보고 형식

```markdown
# 05_review.md
## Status: APPROVED | CHANGES_REQUESTED
## 이슈 목록
| # | Severity | Rule ID | File:Line | 설명 | 수정 제안 |
|---|----------|---------|-----------|------|-----------|
## Rule ID 준수 매핑 (구현이 어떤 Rule을 반영했는지)
## Tester에게 제안하는 중점 테스트 영역
```
