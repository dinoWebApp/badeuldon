# AGENTS.md — 받을돈 (BadeulDon)

이 파일은 omp 에이전트가 이 저장소에서 작업할 때 참고할 가이드입니다. 프로젝트 지식의 단일 소스이며, 상세 명세는 PRD.md와 ARCHITECTURE_CONVENTION.md로 분리되어 있습니다.

---

## 프로젝트 개요

**받을돈** — 프리랜서의 청구서를 링크로 전달하고, 만기가 지나면 **서비스 명의로** 단계별 리마인더를 자동 발송하며, 거래처의 "입금 예정일 약속"을 버튼으로 받아내 수금을 완성하는 수금 자동화 서비스.

- 태그라인: "말하기 어려운 '돈 다오', 받을돈이 대신합니다."
- 핵심 가치: ① 열람 추적 ② 서비스 명의 자동 독촉(심리적 비용 이전) ③ 입금 약속 수집 ④ 거래처 지급 이력 자산화
- 사용자: U1 프리랜서(구매자, 로그인 대시보드) / U2 거래처 담당자(채무자, **가입·로그인 없음이 원칙**)
- 규제 경계(P5): 채권자 자신의 채권 안내 자동화 도구. 타인 채권 수임·전화/방문 추심·신용정보 조회 금지.

```
표면 ① 랜딩(/)          표면 ② 대시보드(/app)      표면 ③ 청구서 뷰어(/b/{토큰})   표면 ④ 관리자(/admin)
  가입 전환                U1 수금 루프               U2 열람·응답(비로그인)          운영자 전용(2FA)
      └────────────── 단일 도메인, 라우트 수준 분리(SURF-1) ──────────────┘
                          Rails 8.1 모놀리스 (ERB + Hotwire)
                  알림톡/SMS: 핵클 메시지 API · 결제: 토스페이먼츠 · 소셜 로그인: 카카오/네이버/구글
```

## 기술 스택

- **Ruby/Rails**: Rails 8.1.4, Ruby `.ruby-version` 참조 (Bundler)
- **DB**: SQLite 3 (dev/test) — Active Record
- **인프라(Solid 3종)**: Solid Queue(잡) · Solid Cache(캐시) · Solid Cable(실시간) — 전용 자식 DB 유지
- **프론트엔드**: ERB + Hotwire(Turbo + Stimulus) + Tailwind CSS(tailwindcss-rails), importmap(노드 의존 최소)
- **테스트**: minitest(Rails 기본) + fixtures(YAML) + capybara/selenium(시스템 테스트)
- **정적 분석**: RuboCop(rubocop-rails-omakase) · Brakeman · bundler-audit — `bin/ci`로 통합
- **배포**: Kamal + Docker + Thruster (`config/deploy.yml`)
- **외부 서비스**: 핵클 메시지 API(알림톡/SMS, REM-10), 토스페이먼츠(결제, PLAN-5), 카카오·네이버·구글 소셜 로그인(AUTH-1)

## 빌드 및 실행 명령어

```bash
bin/setup            # 의존성 설치 + DB 준비 (최초 1회)
bin/dev              # 개발 서버 (rails server + tailwind watch, Procfile.dev)
bin/rails test       # 전체 테스트
bin/rails test test/models/invoice_test.rb   # 개별 파일
bin/rubocop          # 린트 (Layout 자동 교정: bin/rubocop -a)
bin/brakeman         # 보안 정적 분석
bin/ci               # 커밋 전 게이트: rubocop 0에러 + brakeman 0경고 + test 통과
bin/rails zeitwerk:check   # 자동 로딩(파일/상수명) 검증
bin/jobs             # Solid Queue 잡 프로세스 (웹과 별도 실행)
```

## 데이터베이스

| 환경 | 전략 |
|:---|:---|
| development | SQLite `storage/development.sqlite3` |
| test | SQLite (자동 생성/초기화) |
| production | SQLite + Kamal 볼륨 (Solid 3종 전용 자식 DB 유지 — 병합 금지) |

- 마이그레이션은 `db/migrate/`에 UTC 접두 자동 생성명 유지, 커밋 필수. `db/schema.rb` 커밋 필수.
- 모든 일정·발송 기준 시간대는 **KST 고정(TIME-1)**.
- 스키마 상세는 PRD.md 데이터 모델 및 각 기능 명세 참조.

## 아키텍처

**ARCHITECTURE_CONVENTION.md (v1.0.0)를 우선 참조한다.** 요약:

- 계층: `Routes → Controller(얇게) → (Form/Service) → Model + Scope/Query → DB`, View는 컨트롤러 @변수만
- Service/Query/Form 도입 기준: 2개 이상 모델 쓰기·트랜잭션·외부 API → Service / 조인 2+·동적 조합 → Query Object / 모델 없는 복잡 입력 → Form Object
- 의존 방향 규칙(§4): Model→Service/Controller 금지, Service→params/Current 금지, View→쿼리 금지, Job은 Service/Model만 호출
- 도메인 분할: 네임스페이스 + 라우트 블록(`app/{services,queries,forms}/{도메인}/`), 도메인 간 결합은 공개 진입점만
- 응답 전략: 폼 성공 `303 see_other` + redirect, 실패 재렌더 `422`, 부분 갱신 Turbo Stream
- 잡: 인자는 스칼라 id만, 멱등 설계, `retry_on` 명시

## 핵심 비즈니스 규칙 (도메인별 Rule ID 색인)

전체 규칙은 **PRD.md §6~7** 이 단일 소스. Rule ID 형식 `{접두어}-{번호}`, 절대 재사용 금지.

| 접두어 | 도메인 | 핵심 하이라이트 |
|:---|:---|:---|
| AUTH | 계정·인증 | 소셜 로그인만(U1), 관리자는 전용 계정+2FA(AUTH-7) |
| ONB | 온보딩 | 가입→첫 발행 3분 플로우 |
| CLIENT | 거래처·품목 | 거래처 CRUD, 지급 성적표 |
| INV | 청구서 | 상태 전이, 만기 기본 +30일(INV-3), 발행 후 수정 불가(INV-5) |
| SHARE | 공유 링크 | 추측 불가 토큰, 최초 열람 즉시 알림(SHARE-4) |
| REM | 리마인더 시퀀스 | 서비스 명의 발신(REM-1), 4단계 톤, 평일 09-18시만(REM-3), 건당 5통 상한(REM-12·PLAN-3) |
| PROMISE | 응답(약속) 수집 | 무가입 응답, 약속 등록→시퀀스 재스케줄, 채무자 마감 권한 없음(PROMISE-7) |
| PAY | 입금 처리 | 원클릭 마감, 부분입금 잔액 재계산, 계좌조회 자동화 금지(PAY-5) |
| DASH | 대시보드 | 오늘의 액션, 연체일 내림차순 |
| PLAN | 구독·과금 | Free 3건/5거래처, Plus 9,900원, 수금 패스, 토스페이먼츠 |
| VIEW | 채무자 뷰어 | 비로그인, 인앱 브라우저 QA 필수(VIEW-1), 마케팅 요소 금지(VIEW-8) |
| NOTI | 알림(프리랜서 향) | 핵클 채널 공유 |
| LEGAL / REF / TAX | 법적 조치·추심·세금 | D+30 한정, 소개 화면만(REF-2), 제휴 발행 |
| SEC | 데이터·보안 | 토큰 엔트로피, 발송 멱등성(SEC-5) |
| PERF / TIME | 비기능 | 열람→알림 60초, 뷰어 2초, KST 고정 |
| ADMIN | 관리자 콘솔 | 2FA, 감사 로그(ADMIN-2), 운영 대시보드 |
| SURF / LP / BLOG / DESIGN | 표면·랜딩·블로그·디자인 | 단일 도메인, 뷰어 마케팅 무결성(SURF-2), noindex 정책(SURF-3) |

제품 원칙(모든 기능 판단의 상위 기준): **P1 관계 보존 최우선 · P2 미워지는 역할의 위임(개인 연락처 비노출) · P3 채무자 무가입 · P4 모든 발신은 기록 · P5 규제 경계 내**.

## API / 라우팅 컨벤션

- RESTful `resources` 기반, 커스텀 액션은 `member`/`collection`으로 정당화. URL에 동사 금지.
- 표면별 라우트 블록: `/`(랜딩), `/app`(대시보드), `/b/:token`(뷰어, 비로그인), `/admin`(namespace, ADMIN 롤)
- `/app`, `/b/*`, `/admin`은 noindex + robots 차단(SURF-3). 뷰어(③)→랜딩(①) 링크 금지(SURF-4).
- 경로 헬퍼 사용(URL 하드코딩 금지). 상태 전환 등 예외적 동사만 member로(예: `PATCH /app/invoices/:id/close`).
- 금지 표현 필터(REM-9): 사용자 편집 문구는 금지 표현 통과 시에만 저장·발송.

## 코딩 컨벤션

- **들여쓰기: 스페이스만 사용(탭 금지). Ruby·JavaScript·HTML·ERB는 2칸, 그 외 언어는 4칸** — RuboCop(omakase)이 단일 기준
- 네이밍: ARCHITECTURE_CONVENTION.md §5 (Service=`동사+목적어+Service`, 진입점 `#call`, `?`/`!` 메서드 규칙, enum 소문자 스네이크 등)
- 컨트롤러 액션 본문 10줄 이내, Strong Parameters는 `params.expect` + `private #xxx_params`
- 뷰에서 DB 쿼리/모델 클래스 메서드 호출 금지 — 표현 로직 3줄+ 는 헬퍼로
- 사용자 입력 출력은 `<%= %>` 기본 이스케이프 — `raw`/`html_safe` 금지(상수·신뢰 HTML만)
- 마이그레이션: `null: false`·`default`·인덱스 명시, `dependent:` 필수 명시

## 테스트 전략

- 프레임워크: minitest + fixtures. 계층: 모델(검증·상태 전이·Rule ID 시나리오) → 서비스/쿼리(비즈니스 로직) → 컨트롤러(통합) → 시스템(브라우저 E2E, 뷰어 인앱 브라우저 동작 포함)
- Rule ID별 정상/경계/예외 시나리오 도출이 원칙(Tester는 PRD §6~7 기준)
- 게이트: `bin/ci`(RuboCop 0에러 + Brakeman 0경고 + 테스트 전체 통과) 통과 전까지 커밋/병합/배포 불가
- 외부 API(핵클·토스페이먼츠)는 테스트에서 stub/wrapper 주입 — 실 호출 금지

## 하네스: 받을돈 개발 자동화

**목표:** PRD 비즈니스 규칙과 ARCHITECTURE_CONVENTION 아키텍처를 준수하는 코드의 구현·리뷰·테스트를 자동화한다.

**트리거:** 아래에 해당하는 모든 요청은 **반드시** `badeuldon-orchestrator` 스킬을 사용하라:
- 기능 구현, 코드 수정, 리팩터링, 버그 수정
- 코드 리뷰, 테스트 작성, 디버깅
- API/라우트 설계, 데이터베이스 마이그레이션, 비즈니스 로직 검증
- 위 작업의 후속 요청 (수정, 보완, 개선, 리팩터링, 재실행, 업데이트)

단, 순수한 문서 내용 확인 질문("~가 무슨 뜻이야?", "~는 어디에 있어?")은 직접 응답 가능.

**배포:** "git 배포", "커밋", "푸시", "배포", "push" 요청 시 `badeuldon-git-deploy` 스킬을 사용하라.

**에이전트 스폰:** 오케스트레이터만 task tool로 스폰한다 — `{"tasks":[{"agent":"badeuldon-developer","task":"..."}]}`. 승인 게이트(플랜 보고 후 턴 종료) 전 스폰 금지.

**변경 이력:**
| 날짜 | 변경 내용 | 대상 | 사유 |
|------|----------|------|------|
| 2026-10-08 | 초기 하네스 구성 | 전체 | 신규 구축 (HARNESS_CONVENTION v3.2.0 기준) |

## 구현 진행 상황 (로드맵)

- **완료**: Rails 8.1 스켈레이션 생성, PRD v0.17.1, ARCHITECTURE_CONVENTION v1.0.0, 하네스 구축 + E2E 파이프라인 검증(승인 게이트·에이전트 3종 스폰·리뷰·테스트·실행검증 전 Phase 통과)
- **구현됨**: 표면 ① 랜딩 루트 골격 — LP-1 히어로(Q6 확정 문구, CTA 비활성), SURF-1/3/4/6 준수, 통합 테스트 7건 (`2026-10-08`, `_workspace/` 참조). 후속: LP-2~13 섹션, F-AUTH 완료 시 CTA 연결, ② 구축 시 ① 전용 레이아웃 분리(리뷰 WARNING), Pretendard 도입
- **진행 중**: 없음
- **예정**: PRD §6 기능 명세 순차 구현 (권장 순서: F-AUTH → F-CLIENT → F-INV → F-SHARE → F-VIEW → F-REM → F-PROMISE → F-PAY → F-DASH → F-PLAN → F-ADMIN → F-LEGAL/REF/TAX → F-SURF/LP/BLOG 잔여)
- **작업 재개 가이드**: `.omp/progress.json`의 `currentPhase` 확인 → `awaiting_approval`이면 플랜 재보고 후 승인 대기, 그 외에는 다음 Phase부터 재개. 산출물은 `_workspace/`.
