# AGENTS.md — 받을돈 (BadeulDon)

이 파일은 ZCode 에이전트와 받을돈 하네스 서브에이전트가 이 저장소에서 작업할 때 참고할 가이드입니다. 프로젝트 지식의 단일 소스이며, 상세 명세는 PRD.md와 ARCHITECTURE_CONVENTION.md로 분리되어 있습니다.

---

## 프로젝트 개요

**받을돈** — 프리랜서의 청구서를 링크로 전달하고, 만기가 지나면 **서비스 명의로** 단계별 리마인더를 자동 발송하며, 거래처의 "입금 예정일 약속"을 버튼으로 받아내 수금을 완성하는 수금 자동화 서비스.

- 태그라인: "독촉하기 어려울 때, 받을돈이 대신합니다."
- 핵심 가치: ① 열람 추적 ② 서비스 명의 자동 독촉(심리적 비용 이전) ③ 입금 약속 수집 ④ 거래처 지급 이력 자산화
- 사용자: U1 프리랜서(구매자, 로그인 대시보드) / U2 거래처 담당자(채무자, **가입·로그인 없음이 원칙**)
- 규제 경계(P5): 채권자 자신의 채권 안내 자동화 도구. 타인 채권 수임·전화/방문 추심·신용정보 조회 금지.

```
표면 ① 랜딩(/)          표면 ② 대시보드(/app)      표면 ③ 청구서 뷰어(/b/{토큰})   표면 ④ 관리자(/admin)
  가입 전환                U1 수금 루프               U2 열람·응답(비로그인)          운영자 전용(2FA)
      └────────────── 단일 도메인, 라우트 수준 분리(SURF-1) ──────────────┘
                          Rails 8.1 모놀리스 (ERB + Hotwire)
                  알림톡/SMS: 솔라피 메시지 API · 결제: 포트원(KG이니시스) · 인증: 이메일/비밀번호(Rails 표준, AUTH-1)
```

## 기술 스택

- **Ruby/Rails**: Rails 8.1.4, Ruby `.ruby-version` 참조 (Bundler)
- **DB**: SQLite 3 (dev/test) — Active Record
- **인프라(Solid 3종)**: Solid Queue(잡) · Solid Cache(캐시) · Solid Cable(실시간) — 전용 자식 DB 유지
- **프론트엔드**: ERB + Hotwire(Turbo + Stimulus) + Tailwind CSS(tailwindcss-rails), importmap(노드 의존 최소)
- **테스트**: minitest(Rails 기본) + fixtures(YAML) + capybara/selenium(시스템 테스트)
- **정적 분석**: RuboCop(rubocop-rails-omakase) · Brakeman · bundler-audit — `bin/ci`로 통합
- **배포**: Kamal + Docker + Thruster (`config/deploy.yml`)
- **외부 서비스**: 솔라피 메시지 API(알림톡/SMS, REM-10 — 2026-10-29 핵클→솔라피 전환, 템플릿 검수 승인), 포트원(KG이니시스 채널)(결제, PLAN-5). 인증은 이메일/비밀번호(Rails 표준 — OAuth 소셜 로그인 2026-10-12 폐기, AUTH-1·Q8)

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
| AUTH | 계정·인증 | 이메일/비밀번호만(OAuth 폐기, AUTH-1), 비밀번호 재설정(AUTH-8), 관리자는 전용 계정+2FA(AUTH-7), 휴대폰 SMS 인증 가입(AUTH-9) |
| ONB | 온보딩 | 가입→첫 발행 3분 플로우 |
| CLIENT | 거래처·품목 | 거래처 CRUD, 지급 성적표 |
| INV | 청구서 | 상태 전이, 만기 기본 +30일(INV-3), 발행 후 수정 불가(INV-5) |
| SHARE | 공유 링크 | 추측 불가 토큰, 최초 열람 즉시 알림(SHARE-4) |
| REM | 리마인더 시퀀스 | 서비스 명의 발신(REM-1), 4단계 톤, 평일 09-18시만(REM-3), 건당 5통 상한(REM-12·PLAN-3 — 2026-11-26 수동 발송 합산), 수신 거부는 재개 불가(VIEW-7), 재예약분 실행 정합(REM-3) |
| PROMISE | 응답(약속) 수집 | 무가입 응답, 약속 등록→시퀀스 재스케줄, 채무자 마감 권한 없음(PROMISE-7) |
| PAY | 입금 처리 | 원클릭 마감, 부분입금 잔액 재계산, 계좌조회 자동화 금지(PAY-5) |
| SALES | 영업 직원·추천·수수료 | 역할 이원화(sales 20%·12개월 캡 / officer 15%·무기한·타이틀), 추천 코드 주간 로테이션, 첫결제 20% 할인(Q24·Q12 재사용), 월 정산 스냅샷, /sales 대시보드 |
| DASH | 대시보드 | 오늘의 액션, 연체일 내림차순 |
| PLAN | 구독·과금 | Free 3건/5거래처, Plus 9,900원, 수금 패스, 포트원(KG이니시스), 관리자 환불 실행(PLAN-9 — 포트원 결제 취소 연동·즉시 전액 환불·구독 즉시 Free·수금 패스 10건 차감), 채널 키 환경 분리·결제 확정 검증(PLAN-5), 건당 상한에 수동 발송 합산·상한 도달 표시(PLAN-3·Q28) |
| VIEW | 채무자 뷰어 | 비로그인, 인앱 브라우저 QA 필수(VIEW-1), 마케팅 요소 금지(VIEW-8), 수신 거부 재개 불가(VIEW-7) |
| NOTI | 알림(프리랜서 향) | 솔라피 채널 공유 |
| LEGAL / REF / TAX | 법적 조치·추심·세금 | D+30 한정, 소개 화면만(REF-2), 제휴 발행, 전자세금계산서 바로빌 SOAP 연동(TAX-1/2)·건당 300원(Q21)·공동인증서 등록 필수·취소 과금 전제 |
| SEC | 데이터·보안 | 토큰 엔트로피, 발송 멱등성(SEC-5) |
| PERF / TIME | 비기능 | 열람→알림 60초, 뷰어 2초, KST 고정 |
| ADMIN | 관리자 콘솔 | 2FA, 감사 로그(ADMIN-2), 운영 대시보드, 환불 실행 콘솔(ADMIN-11 — owner 전용·확인 대화창) |
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


## UI 품질 기준 (모든 표면 구현에 강제)

- **F-DESIGN 철저 반영**: 모든 UI는 PRD §7.3(DESIGN-1~7)과 레퍼런스 벤치마킹 포인트(Stripe 절제·타이포 위계 / 토닥 온기 / 볼타 B2B 여백·정보 위계 / 토스 송금 모바일 UX)를 구현에 반영한다. "최소 골격"이어도 완성도 기준은 동일하다 — 뼈대만 노출하는 구현 금지.
- **표준 스택**: Pretendard 국문 폰트(CDN), 크림·아이보리 배경 + 딥 그린 액센트(DESIGN-2), 상태색 3종(연체 주황/대기 중립/완료 녹색), 타이포 사이즈 위계·여백 리듬·인터랙션 디테일(hover/focus 링/섀도/트랜지션) 필수.
- **문구 원칙**: 마케팅 문구는 LP-12(P1~P5·금지 표현) 준수, 발신 문구는 REM-2 단계별 톤 준수 — 신규 창작 문구는 Reviewer가 집중 검증한다.
- **리뷰 의무**: Phase 5 리뷰는 기능 정합성과 함께 디자인 기준 준수(레이아웃 위계·간격 일관성·접근성 터치 타깃·DESIGN-6)를 검증 항목에 포함한다. 미달 시 WARNING 이상으로 지적한다.

## 테스트 전략

- 프레임워크: minitest + fixtures. 계층: 모델(검증·상태 전이·Rule ID 시나리오) → 서비스/쿼리(비즈니스 로직) → 컨트롤러(통합) → 시스템(브라우저 E2E, 뷰어 인앱 브라우저 동작 포함)
- Rule ID별 정상/경계/예외 시나리오 도출이 원칙(Tester는 PRD §6~7 기준)
- 게이트: `bin/ci`(RuboCop 0에러 + Brakeman 0경고 + 테스트 전체 통과) 통과 전까지 커밋/병합/배포 불가
- 외부 API(솔라피·포트원)는 테스트에서 stub/wrapper 주입 — 실 호출 금지. **클라이언트 3종(솔라피·아웃바운드 메일·포트원)에 test 환경 실호출 차단 가드가 내장**돼 있다(대역 없이 호출하면 `TEST_GUARD`로 실패). 로컬 test 환경은 마스터 키가 있어 **운영과 같은 credentials를 로드**하므로, 잡(`DunningRetryJob`·`SubscriptionRenewalJob` 등)을 실행하는 테스트는 반드시 `with_portone_client`/`with_solapi_client`로 감싼다(2026-11-24 리뷰 중 포트원 운영 API 실요청 사고 — 거부되어 금전 이동 없음)

## 하네스: 받을돈 개발 자동화 (ZCode Desktop)

**목표:** PRD 비즈니스 규칙과 ARCHITECTURE_CONVENTION 아키텍처를 준수하는 코드의 구현·리뷰·테스트를 자동화한다.

**진입점(일반/절약 명령어 2개 + 병렬 배치 2개):** 아래에 해당하는 모든 요청은 **반드시** 오케스트레이터 명령어로 실행한다(사용자가 직접 명령어를 선택하는 것이 가장 확실하다):
- 일반 모드: `/badeuldon_orchestrator <요청>` — 메인 GLM-5.3, 프로필 `badeuldon-developer/reviewer/tester`
- 절약 모드: `/badeuldon_orchestrator_lite <요청>` — 메인 GLM-5.3-Flash, 프로필 `-lite` 3종
- 병렬 배치 일반: `/badeuldon_orchestrator_parallel <태스크 목록>` — 서로 독립된 다수 작업 일괄 처리(§6.14, 2026-11-04 채택)
- 병렬 배치 절약: `/badeuldon_orchestrator_parallel_lite <태스크 목록>` — 위의 절약 버전
- 네 명령어는 같은 `badeuldon-orchestrator` 스킬(Phase 0~9 + §6.14 병렬 배치 절)을 로드한다. 절약·병렬 모드도 승인 게이트·보안·테스트 기준은 동일하다.
- **프로필 모델 행렬(2026-11-04 사용자 확인·2026-11-23 reviewer GLM-5.4 상향)**: 위 "메인" 표기는 오케스트레이터 세션 모델 기준이며, 스폰 실체는 `.zcode/agents/` 프로필의 `model` 필드다 — developer 일반=GLM-5.3-Flash/high(lite=Flash/low) · reviewer 일반=GLM-5.4/high(lite=Flash/high) · tester 일반=GLM-5.3-Flash/high(lite=Flash/low). 위임 실측(§4.6)은 프로필 정의 대비 일치 여부로만 판정한다.

대상 작업:
- 기능 구현, 코드 수정, 리팩터링, 버그 수정
- 코드 리뷰, 테스트 작성, 디버깅
- API/라우트 설계, 데이터베이스 마이그레이션, 비즈니스 로직 검증
- 위 작업의 후속 요청 (수정, 보완, 개선, 리팩터링, 재실행, 업데이트)

단, 순수한 문서 내용 확인 질문("~가 무슨 뜻이야?", "~는 어디에 있어?")은 직접 응답 가능.

**구성 요소**(모두 워크스페이스 전용 — 플러그인·마켓플레이스 불필요, Git 추적): 명령어 4개(`.zcode/commands/` — 일반·절약 + 병렬 배치 일반·절약) · 공통 오케스트레이터 스킬(§6.14 병렬 배치 절 포함) + 참조 스킬 5종(`.zcode/skills/` — business-rules, feature-dev, review-checklist, test-patterns, git-deploy) · 서브에이전트 프로필 6개(`.zcode/agents/`) · 진행 상태(`.zcode/progress.json` — 병렬 시 `parallelTasks`). 플러그인 경로는 폐기 — 플러그인에는 워크스페이스 스코프가 없어 전역 적용되고, `agents` 필드는 실행되지 않음이 실측됨(HARNESS_CONVENTION v4.0.3). 하네스 신규 구성·점검·동기화는 전역 `$harness` 메타 스킬로.

**배포:** "git 배포", "커밋", "푸시", "배포", "push" 요청 시 `badeuldon-git-deploy` 스킬을 사용하라.

**에이전트 스폰:** 오케스트레이터만 Agent tool로 스폰한다(`subagent_type`으로 모드별 프로필 지정 — 일반 `badeuldon-developer` 등, 절약 `badeuldon-developer-lite` 등). **승인 게이트**: 플랜 보고 후 `AskUserQuestion` 선택 질의(승인/수정/중단) — 승인 선택 전 스폰 금지, 승인 시 같은 턴 진행(질의 취소·불가 시 텍스트 폴백 후 턴 종료, §6.13) — 이 규칙은 AGENTS.md·`badeuldon-orchestrator` 스킬·명령어 4종에 공통 반영한다.

**변경 이력:**
| 날짜 | 변경 내용 | 대상 | 사유 |
|------|----------|------|------|
| 2026-11-23 | 규약 v4.2.1 동기화 — 일반 모드 reviewer 모델 GLM-5.4 상향 | 하네스 | `badeuldon-reviewer` 프로필 `model`을 GLM-5.3→GLM-5.4로(추론 수준 high 유지). 메인·Developer·Tester·절약 모드는 기존 그대로(`GLM-5.4-Flash` 없음). 규약 사본 교체(v4.2.0 변경 이력 누락 행 소급 포함)·전역 harness 스킬 §3.3·§3.4 표 동기화. 모델 별칭은 없어 새 버전마다 ID를 직접 교체한다 |
| 2026-11-11 | 규약 v4.2.0 동기화 — 승인 게이트 선택 질의 전환 | 하네스 | §6.13 승인 게이트를 `AskUserQuestion` 선택 질의(승인/수정/중단·승인 시 같은 턴 진행·취소 시 텍스트 폴백)로 개정, §6.14 병렬 태스크 선택 multiSelect 명시 — 규약 사본 교체·오케스트레이터 스킬·명령어 4종·AGENTS.md 반영 |
| 2026-10-08 | 초기 하네스 구성 | 전체 | 신규 구축 (HARNESS_CONVENTION v3.2.0 기준) |
| 2026-10-29 | omp → ZCode Desktop 하네스 전환 | 전체 | 런타임 전환 (HARNESS_CONVENTION v4.0.1) — 명령어 2개·공통 스킬·프로필 6개·로컬 플러그인 marketplace·`.zcode/progress.json` 도입, omp 파일 제거 |
| 2026-10-29 | 플러그인 설치/명령어 발견 실측 수정 | 하네스 | ① marketplace.json `pluginRoot` 미지원 → 루트 기준 상대경로 ② 서브에이전트 프로필을 `.zcode/agents/`로 이동(플러그인 agents 필드는 미실행 실측) — 새 세션에서 명령어·에이전트 발견 확인 필요 |
| 2026-10-29 | 플러그인 → 워크스페이스 전용 리소스 전환 | 하네스 | 플러그인이 워크스페이스 스코프 없이 전역 적용됨이 실측됨(HARNESS_CONVENTION v4.0.3) — 명령어를 `.zcode/commands/`, 스킬을 `.zcode/skills/`로 이동, 플러그인 언인스톨·마켓플레이스 등록 제거, `.zcode/harness-marketplace/` 삭제. git clone만으로 하네스 완결 |
| 2026-10-29 | 규약 v4.0.5 동기화 | 하네스 | ① 명령어·프로필 `model`을 `providerId/modelId` 슬래시 형식으로 전환 — bare 이름은 model·thoughtLevel이 조용히 탈락(실측, §1.4 제약 3) ② Phase 3·5·7 위임 실측 절차·`_workspace/00_delegation_log.md` 신설(§4.6·§8.1) |
| 2026-11-04 | 규약 v4.1.1 동기화 — §6.14 병렬 배치 채택 | 하네스 | 병렬 배치 파이프라인(§6.14) 선택 확장 채택: 병렬 명령어 2종(`badeuldon_orchestrator_parallel[_lite]`) 신설, 오케스트레이터 스킬에 병렬 배치 절 추가, 로드맵에 병렬 후보 조합 블록·PRD에 분해 후보 기록 규칙 노트 신설(§6.14.11). 프로필 6개·명령어 2개는 v4.1.1 표와 전부 일치 확인(변경 없음). 사본 HARNESS_CONVENTION.md v4.0.5→v4.1.1 교체 |
| 2026-11-04 | 프로필 모델 행렬 명시 | 하네스 | "메인 GLM-5.3/절약 Flash" 서술 오독 방지 — 프로필 `model` 필드 실제 행렬(developer/tester 일반=Flash·reviewer 일반=GLM-5.3, 일반·절약 구분은 메인 세션+thoughtLevel)을 사용자 확인 후 진입점 절에 기록. 위임 실측 오탐 방지 기준 포함 |

## 배포 인프라 (운영 — 2026-10-14 구성 · **첫 배포 완료 7f9be0e**)

**도메인**: `badeuldon.kr` — Cloudflare가 SSL 종단(터널 방식, SSL 모드 설정 불필요)

```
사용자 → https badeuldon.kr → Cloudflare ─터널→ cloudflared(서버 도커 컨테이너)
  → http localhost:3000 → kamal-proxy(127.0.0.1:3000 바인딩·무중단 전환)
  → badeuldon-web(Puma) / badeuldon-job(Solid Queue — §11.3 분리)
 공유 레지스트리(registry:3, 100.98.162.61:5000 — 서버 인프라, Tailscale 인터페이스에만 바인딩)
```

- **서버 접근**: Tailscale `100.98.162.61`, SSH `kgj`(키 인증) — 공개 포트 0 (관리면 Tailscale·서비스면 CF 터널만)
- **SSL**: CF 종단 → 앱은 http 수신 — `production.rb`의 `assume_ssl`+`force_ssl` 필수. 실방문자 IP는 `CF-Connecting-IP` 헤더(ViewEvent 기록에 사용)
- **레지스트리(서버 공유 인프라)**: `100.98.162.61:5000`(HTTP — Tailscale 망 내) — **어느 앱에도 속하지 않는 독립 컨테이널**로 서버에서 직접 운영(`--name registry`, `--restart unless-stopped`, kamal 라벨 없음). badeuldon Kamal은 push/pull 대상으로만 참조(accessory 아님). 이 서버에 올릴 다른 서비스도 같은 레지스트리를 `image:` 이름으로 구분해 사용. 양단 Docker `insecure-registries` 등록 필요(서버 `/etc/docker/daemon.json` · 배포 PC Docker Desktop)
- **cloudflared 컨테이너**: `restart: unless-stopped` — Docker 재시작 시 자동 복귀
- **운영 명령**: `bin/kamal setup`(최초) · `deploy`(무중단) · `rollback` · `logs -f` · `console` · `app details`
- **데이터**: SQLite 도커 볼륨 `badeuldon_storage` — 서버 백업 필수(주기 dump, 추후 Litestream). 레지스트리 데이터는 호스트 바인드 `/home/kgj/registry/registry_data`(공유 — 앱별 구분 없음). `config/master.key`는 비밀번호 매니저 보관
- **크로스 빌드**: arm64 Mac → amd64 서버(`builder: arch: amd64`) — 첫 빌드 느림, 이후 캐시

## 구현 진행 상황 (로드맵)

- **완료**: Rails 8.1 스켈레이션, 하네스 구축 + E2E 검증, F-AUTH 인증(OAuth 폐기·Q8), 랜딩 전체 + UI 품질 기준 + AUTH-1.3 프로필(v0.18.1), /app 대시보드 뼈대(v0.18.2), F-CLIENT(v0.18.3), F-INV 청구서(v0.18.4), F-SHARE+F-VIEW 뷰어 개봉(v0.18.5), F-PROMISE 응답 수집(v0.18.6), F-PAY 입금·MVP 수금 루프 완결(v0.18.7), 랜딩 헤드라인 교체·푸터 사업자·LP-5 버블 UI(v0.19), 로그인 UX(원클릭 복귀), **F-PLAN 구독·과금**(`2026-10-15`, PRD v0.20 — Subscription(체험→활성→해지→만료·빌링키·1人1구독)·Order·PaymentPass(10건·90일·with_lock), 결제 래퍼(초기 TossPayments → 포트원(KG이니시스) 전환, stub 가능·웹훅 회복), 한도 전환(Free 5/3→Plus 무제한·수금 패스 소비), 자동 갱신 Job(with_lock·멱등키), 웹훅 POST /webhooks/portone(결제 재조회 검증), /app/billing UI·사이드바. 테스트 484건. 리뷰 BLOCKER 1+CRITICAL 6 수정), **표면①②③ 퍼블리싱 리뉴얼 + 랜딩 콘텐츠 재작성**(`2026-11-02`, PRD v0.23 — LP-14 시나리오 커버 섹션(약속 재조정·열람 분기·부분입금·입금 회신 정지 4카드+미니 목업)·LP-15 통제 안전장치 섹션(REM-11 사전 통보·REM-12 상한 종결·P4 기록) 신설, DESIGN-8 구성 강화(팔레트 유지·톤 변주·카드 위계·인터랙션), uibowl 관찰 반영(히어로 비대칭 목업·스텝 페이저). /app DASH-1/2 위계·상태색·사이드바 디테일, 뷰어는 VIEW-8 화이트리스트 내 class-only 정돈. 신규 파셜 _scenarios·_control·_message_bubble. 리뷰 CRITICAL 1+WARNING 6 반영, 테스트 496건(+6). 절약 모드 파이프라인 — 위임 실측 effort 토글링 이슈는 `_workspace/00_delegation_log.md` 참조). **LP-14 보강**(`2026-11-02`, PRD v0.24 — 발행 안내(SHARE-6)·마침 알림(PAY-4) 카드 추가 + U1 알림 스트립, 알림톡 16종 상황 커버 완성. Standard 파이프라인, 테스트 500건), **F-REM 리마인더 시퀀스 — 제품의 심장**(`2026-11-04`, PRD v0.26 — REM-9 폐기(Q9)·REM-13 약속 파기 종결(Q10)·PLAN-3 상한 산정 확정. 솔라피 래퍼(HMAC·fail-fast·stub 주입 체계), message_logs(발송 이력 P4·pending 슬롯 유니크 멱등 SEC-5·상한 5통 PLAN-3), 시퀀스 엔진(기본 트랙 D-1/D+1 열람분기/D+7/D+14·약속 트랙 promise_d1→promise_overdue 종결·부분입금 즉시), recurring 3종(07:00 overdue 저장화·09:00 사전통보 REM-11·14:00 발송 — 취소 창 5시간), 이벤트 알림 9종(issue_notice SHARE-6·noti_opened 60초 이내·noti_promise·noti_deposit_reply·noti_inquiry·noti_refusal VIEW-7 즉시 중단·partial_paid·paid_thanks 기본 켬·noti_promise_unkept), 뷰어 수신거부(VIEW-7·refusal kind), /app 발송 이력·수동 발송(REM-8 Free 포함)·보류/재개(REM-7 건·거래처)·재요청 재개 경로(REM-12/13). 리뷰 BLOCKER 2+CRITICAL 3 수정 후 재리뷰 APPROVED, 테스트 628건(+128))
- **구현됨 상세**: `_workspace_prev/`(LP-14 보강)·`_workspace/`(F-REM) 산출물 참조
- **진행 중**: 없음
- **예정**: **F-SALES 후속**(솔라피 send_sms 실발송 실측 — [INFERENCE] 바디 스펙·messageId 확인·admin/sales 첫 운영 데이터) → **TAX 실서비스 개시 절차**(TESTBED 실측 완료(2026-11-16 — 공통 API=서비스 asmx·Savon .body 파싱·-32001 실측)→ release_auth_key 실키 등록 완료 → **포인트 충전** → 실 BRN RegistCorp+GetCorpState 1회 스모크 → 오픈. 바로빌 계약서 체결 상태 확인 — 견적 유효 2027-02-13) → 알림톡 24종 전부 승인·등록 확인(2026-11-25 솔라피 API 직접 조회 — B-7 주간 수금 요약 v2는 11-19 승인, "n종 미등록"은 낡은 기록) →(TESTBED 실측 완료(2026-11-16 — 공통 API=서비스 asmx·Savon .body 파싱·-32001 실측)→ release_auth_key 실키 등록 완료 → **포인트 충전** → 실 BRN RegistCorp+GetCorpState 1회 스모크 → 오픈. 바로빌 계약서 체결 상태 확인 — 견적 유효 2027-02-13) → F-LEGAL/REF는 완료(완료 목록 참조) → **솔라피 라이브 실측 완결(2026-11-06 — 단일 발송 `message` 단수 바디·variables `#{}` 키·시그니처 HMAC(api_secret, date+salt)·성공 응답 messageId 캡처·발행→열람→noti_opened 체인 E2E 전부 확정. 레거시 4종 템플릿은 변수명 `#{발행인}` 치환)**, 후기, 인앱 실기 QA. **기술 부채 병렬 배치 완결(2026-11-09, §6.14 parallel 절약 모드 — PRD v0.27: Pretendard 셀프호스팅(Variable woff2·CDN 제거)·ko locale(rails-i18n 8.1·default_locale :ko·en.yml 한국어 블록 ko.yml 이식)·봇 UA 열람 제외(링크 프리뷰 계열 포함 12종·HeadlessChrome 보호)·거래처 삭제 가드(발행 이력 있으면 차단 — P4·마이그레이션 불요). 리뷰 APPROVED(B0·C0·W3), 테스트 647건(+4)), **F-DASH 나머지**(`2026-11-09`, PRD v0.28 — DASH-5 거래처별 지연 리포트(만기 대비 실입금일·마감 건 기준 — 리뷰 C-1에서 입금 행 가중 부호 반전 수정)·월간 수금 추이 12개월 CSS 그래프(터치 가시 라벨 W-1)·DASH-6 신고 주기별 집계표(확정신고 직전 분기·공급가액/부가세/수금 분리·세무 자문 아님 고지). **프로젝트 첫 Query Object** 도입(app/queries/reports/ 3종 — 규약 §3.2)·/app/report 리소스·사이드바 리포트 메뉴. 리뷰 CHANGES_REQUESTED→수정, 테스트 668건(+21))**, **F-ADMIN Run A — 관리자 기반 인프라**(`2026-11-10`, PRD v0.30 — admins·admin_sessions·audit_logs 3테이블(별도 계정·별도 세션 — AUTH-7)·TOTP 2FA(rotp+rqrcode·QR+수동 병기·**otp_secret encrypts 암호화**·재사용 방지)·5회 잠금+통보·신규 IP 알림·12h+2h 세션·재설정(전 세션 파기)·`Admins::ProvisionService` runner 절차·`/admin` 뼈대(noindex SURF-3)·감사 로그 5종 action. **Active Record encryption 최초 구성**(credentials). 리뷰 CHANGES_REQUESTED(B3·C2 — 컨트롤러 접착 코드 런타임 파탄)→수정→재리뷰 APPROVED, 테스트 716건(+48)), **후속: 수동 발송 스텝 경계 수정**(2026-11-10, PRD v0.33·Q11 — 운영 실측 버그: 만기 전 전 구간 수동 발송이 D-1 전용 문구("(내일)" 박힌 invoice_notice) 선택 → 만기 전날 이전 issue_notice·만기 전날만 D-1 문구·약속 트랙 동일 경계 + **수동 발송 템플릿 무관 총량 5통 하드리밋(Q11 — 수동 반복 1회성 우회 차단)·만기 도과~약속 전날 창 수동 미지원(안내)**. 리뷰 C2(상한 우회·과거 날짜 발송)→수정, 테스트 883건(+7))**, **F-ADMIN Run B**(`2026-11-10`, PRD v0.31 — §6.14 병렬 배치(T-B1 대시보드/ADMIN-5 Query 5종·T-B2 감사 로그 뷰+회원 관리/ADMIN-2·3·T-B3 결제·매출/ADMIN-4 3태스크 fan-out·3-S 결선). users.status 정지(로그인 차단+세션 파기)·플랜 수동 변경 규칙(활성→체험 금지·연장 1~12개월)·환불 사유 기록(orders.refunded_at·PG 콘솔 수동 병기)·MRR/북극성/퍼널/알림톡 발송량 지표. 리뷰 CHANGES_REQUESTED(B1 환불 폼 불일치·W5)→통합 수정→재리뷰 APPROVED, 테스트 783건(+67). **Run C 이관: 쿠폰·프로모션·롤 부여 해제 콘솔·계정 삭제·데이터 파기**(03 문서 Phase 6 절))**, **F-ADMIN 잔여**(`2026-11-10`, PRD v0.34 — §6.14 병렬 배치(T-C1 롤·계정 콘솔/ADMIN-1·AUTH-7.2 — admins 목록·생성·role 승강·잠금 해제 **owner 전용**·감사 4종+거부 4종·T-C2 쿠폰/ADMIN-4·Q12 — Plus 첫 결제 1회 할인(percent/amount·한도·만료)·예약→소비 2단계(used_count 결제 성공 시 원자 증가)·무효 쿠폰 결제 중단·재과금 정상가·T-C3 계정 삭제·데이터 파기/ADMIN-3·Q13 — 미수 차단·연쇄 삭제 전수·**감사 로그 보존**(이메일 스냅샷)·이메일 타이핑 2중 확인·3-S 결선 routes+nav). **Active Storage 첫 도입 후속**: audit_logs.admin_id nullable(U1 행위 감사 coupon_redeemed). 리뷰 CHANGES_REQUESTED(B1 감사 뷰 500·C2 웹훅 settle 쿠폰 미정산)→통합 수정→재리뷰 APPROVED, 테스트 941건(+5·코드 버그 0). **F-ADMIN 완결 — 잔여는 ADMIN-10(LP-11 블로그 통합)뿐**))**, **LP-11 콘텐츠 허브·블로그 + ADMIN-10 콘텐츠 메뉴**(`2026-11-11`, PRD v0.37 — §6.14 병렬 재판정 2단계 혼합(T-E1 블로그 코어 선행 단독→T-E2 도구 3종·T-E3 허브·T-E4 예약 발행 fan-out+3-S 결선). **BLOG-1~8 전체**: blog_posts+blog_slug_redirects(301)·마크다운(kramdown)+sanitize allowlist·렌더 HTML 별도 저장(Q18)·5클러스터 카테고리 고정 enum(Q19)·4상태·예약 발행(publish_at+매분 Job — Q20)·/blog 허브(5클러스터 네비·도구 카드·CTA)·상세(목차·JSON-LD·OG·canonical·관련 글 3·공유 버튼)·**블로그·도구 색인 허용(SURF-3 예외)**·sitemap.xml·AS 썸네일/OG. **ADMIN-10 콘텐츠 메뉴 통합 완성**(공지+블로그 — 관리 표면 단일화). **무료 도구 3종**(LP-11·가입 없이): 독촉 문구 생성기(REM-2 4톤×3종 상수)·3.3% 계산기·청구서 양식 PDF(Prawn+TTF 재사용). 리뷰 CHANGES_REQUESTED(B1 multipart 누락 — 실첨부 E2E 재현·C1 예약 UI 부재·C2 경로형 미구현·C4 경고 미구현·W6)→수정→**재리뷰 APPROVED**, 테스트 1,081건(+13·코드 버그 0))**, **CLIENT-3/4·PROMISE-5**(`2026-11-10`, PRD v0.35 — 거래처 카드(누적 청구액·진행 중 건수·약속 이행 이력 목록)·지급 성적표(평균 지급 지연일=약속일 대비·이행률·6개월 경향 CSS·비교 배지 "평균보다 N일 빠른/느린 거래처"·약속 없는 거래처 null 처리·DASH-5와 구분 표기)·**발행 폼 거래처 선택 시 Turbo 성적표 요약 갱신**·쿼리 2종(clients 도메인 — PaymentScorecard·PromiseCompliance)·**약속 이행 파생 판정**(Q14 — 이행=paid+마감 입금일≤약속일·미이행=도과 후 미수 또는 지연 마감·판정 중·부분입금 행 가중 방지 DASH-5 C-1 선례)·마이그레이션 불요. 리뷰 CHANGES_REQUESTED(C-1 voided/draft 모집단 불일치·W-1 배지 색)→수정, 테스트 967건(+13·코드 버그 0))**, **INV-7 반복 청구 + PAY-6 수금완료 PDF**(`2026-11-11`, PRD v0.36 — §6.14 병렬 배치(T-D1 반복 청구·T-D2 PDF). recurring_invoices+recurring_invoice_items(스냅샷)·발행일 1~28·매월 N일 자동 발행(IssueJob 06:30 KST·issue! 재사용 — 채번/토큰/수금 패스/한도 상속)·직전 미수금 보류(Q16 PLAN-1 적용)·**NOTI-3 알림톡 2종 초안(B-5·Q15 — 등록 전 skipped(NO_TEMPLATE) 기록·등록 후 자동 활성화)**·PAY-6 수금완료 증빙 PDF(**Prawn+Pretendard TTF 번들 — OTF는 CFF로 Prawn 텍스트 전무 실측(Q17)**·paid 한정·마감 입금일 기재). 리뷰 CHANGES_REQUESTED(B1 계정 삭제 FK 파탄 — 연관 선언 순서·B2 PDF 텍스트 전무 — OTF 비호환·C1 이중 발행 창·C2 스캔 고착)→수정→**재리뷰 APPROVED**, 테스트 1,019건(+52·코드 버그 0))**, **F-LEGAL/REF**(`2026-11-11`, PRD v0.38 — §6.14 병렬 배치(T-F1 LEGAL·T-F2 REF). **LEGAL-1/2/3/4**: 내용증명 양식 PDF(Prawn+TTF 재사용 — 청구 내역·발송 이력·약속 이력(Q14)·부분입금 내역 자동 반영·LEGAL-3 고지문·LEGAL-4 직접 발송 안내)·**건당 5,000원**(포트원 단건 재사용 — orders.item_type 추가·결제 완료 후에만 다운로드·미결제 워터마크 미리보기)·**REF-1~4**: 추심 상담 소개 화면(D+30 도달 건 목록·P5 고지·자료 범위·레퍼럴 고지·제휴사 미계약 준비 중 안내)·invoices show D+30 배너. **TAX-1/2는 제휴 API 계약 후 별도 런 확정**. 리뷰 CHANGES_REQUESTED(B1 metadata 덮어쓰기 — 병합 전환·C1 워터마크 미구현 — 구현으로 정합화·C2 중복 결제 차단·W5)→수정→**재리뷰 APPROVED**, 테스트 1,103건(+15·코드 버그 0))**, **F-ADMIN Run C**(`2026-11-10`, PRD v0.32 — 공지 ADMIN-6/7(notices·notice_reads 복합 유니크·일반 배너 닫기=읽음·중요 팝업 확인 전 지속·/app/notice PRD 문언 경로)·티켓 ADMIN-8(tickets+ticket_messages 스레드·5분류·open/answered/closed·관리자 종료·사용자 재질문 open 복귀·AS 이미지 1장 5MB·rate_limit 5회/시간·**인증 서빙 전환 — AS 공개 리다이렉트 제거**)·FAQ ADMIN-9(LP-8 파셜 재사용)·**`noti_ticket_reply` 발송 연동**(Tickets::NotifyAnswerService — 티켓 전용 경로·NO_PHONE skip·MessageLog invoice nullable 완화+ticket_id·PLAN-3 밖). **Active Storage 첫 도입**(disk). 리뷰 CHANGES_REQUESTED(C-1 초안 mark_read 우회·W4)→수정→테스트 876건(+52·코드 버그 0))**, **TAX-1/2 전자세금계산서 발행**(`2026-11-16`, PRD v0.39 — Full·Sequential 절약 모드. **바로빌 SOAP 연동**(savon·TESTBED/RELEASE 전환·credentials barobill test/release_auth_key — Ruby SDK 부재·웹훅 없음→GetTaxInvoiceState 폴링). **건당 300원**(Q21 — 포트원 단건 재사용·orders.item_type tax_invoice 추가·결제 완료 후에만 발행·LEGAL 선례)·**공동인증서 등록 필수 전제**(사용자 확정 — 발행 설정 2단계: 사업자 정보 저장(RegistCorp·barobill_id "bd"+패딩 채번·-32000 흡수)→GetBaroBillURL(CERT) 팝업·**CheckCERTIsValid 실시간 검증 마킹** — 문서 재조사로 리스크 해소)·**취소 과금 전제**(사용자 확정 — 발행 전 미리보기·중복 발행 차단·발행 전 휴폐업 조회 필수 스코프)·paid 1건 1발행(invoice_id unique+가드)·부가세 포함/별건 행 정수 분해(Σ품목=합계 일치)·폴링 Job(retry 소진→failed)·취소(PATCH member)·TAX-2 승인번호 패널 4분기·마이그레이션 3건(users 7필드·clients ceo_name/corp_addr — business_number·contact_name·name·email 기존 재사용·tax_invoices)·사이드바 메뉴. 리뷰 CHANGES_REQUESTED(B0·C4 — 콜백 착지·이중 결제 가드·행 금액·폴링 failed 전이·W7)→수정→테스트 **1,183건(+80·0 failures)** — Tester 중점 11항목 전 커버·파셜 상대 경로 버그(B-1) 1건 Phase 6b 수정. **운영 전환 후속: 계약·RELEASE 키·회원사/인증서 운영 재등록·TESTBED 실발행 실측·[INFERENCE] 8건**(03 문서)), **기능 잔여·기술 부채 병렬 배치**(`2026-11-16`, PRD v0.41 — §6.14 parallel 절약 모드 6태스크(동시성 상한 3·2웨이브). **Q22 부분입금 오기록 정책**(과다입금=잔액 0 마감·초과분 감사 기록·환불 오프라인 / 마감 후 재입금=기록만·알림 없음)·**Q23 partial_paid 반복 재발송**(추가 입금마다 재발송·1회성·PLAN-3 제외 유지)·**REM-3 세부 지정 UI**(사용자별 허용 요일·시간대 — 고정 경계 평일 09~18 내 축소만·이월 규칙)·**NOTI-2 주간 다이제스트**(월요일 09:00 recurring·NO_TEMPLATE skip 선례·토글)·**PLAN-5 dunning**(결제 실패 D+1·3·7 재차감·3회 소진 cancelled→기간 말 만료·ADMIN-4 현황)·**ViewEvent 하드닝**(30분 중복 억제·IP/UA 정제 — SHARE-4 불변)·**경량 정리**(폰트 캐시 헤더 deploy.yml·en.yml 잔존 정리·Stimulus portone_shared 공통화)·통합 마이그레이션 1건(users 4·subscriptions 3·message_logs digest·view_events 인덱스). 리뷰 CHANGES_REQUESTED(B1 결제 경로 500·C3 dunning 해지 재차감·만료 미발동·W7)→수정→**재리뷰 APPROVED**→Tester 코드 버그 BUG-1~4+파생 2건 발견→수정→테스트 **1,241건(+58·0 failures)**), **F-SALES 영업 직원·추천·수수료 + 휴대폰 인증 가입**(`2026-11-19`, PRD v0.42 — Full·일반 모드·Sequential. **역할 이원화(Q24 사용자 확정)**: sales=20%·12개월 캡 / officer(감투·지인·타이틀 CRO/고문)=15%·무기한 — 시장 조사(20~30%·12개월 캡 지배·lifetime 소수·첫결제 first-month 최빌값 20%) 기반. `sales_reps`(role enum·title·rate 오버라이드 1~50)+별도 세션(3원 쿠키 격리)·`sales_referral_codes`(월요일 00:00 주간 로테이션 Job·현재 코드만 수용)·**첫결제 20% 쿠폰 자동 예약(Q12 인프라 재사용 — 결제 로직 0줄)**·`phone_verifications`(AUTH-9 SMS 인증·rate limit 번호 1/1분·3/1시간+IP 20/1시간·**C-1 세션 결합 3중 판정**)·users.phone 부분 유니크·`sales_commissions` 월 1일 정산 스냅샷(실차감액·환불 제외·upsert 멱등·paid 보존)·/sales 대시보드(타이틀·내 코드·내 사용자(표시명만)·월별 결제·이번달 수령 예정·연도 누적·noindex)·admin CRUD+unlock+수동 재생성+mark paid(감사). 리뷰 CHANGES_REQUESTED(B0·**C1** 인증-가입 결합·W8 — 판정: 이메일 미노출→표시명·IP 한도 완화 20/h)→수정(재리뷰 면제)→테스트 **1,385건(+141·0 failures)**·코드 버그 0. 후속: 솔라피 send_sms 실발송 실측([INFERENCE] 바디)·관찰 5건(07 보고서)), **F-EMAIL 자체 메일 API 연동**(`2026-11-20`, PRD v0.43 — Full·일반 모드. **자체 Outbound Mail API**(mail-api.veloloop.kr — Cloudflare Tunnel HTTP 공개·SMTP2GO 릴레이·사양 OUTBOUND_MAIL_API.md)·**커스텀 ActionMailer 배달 방식**(OutboundMail::DeliveryMethod — 기존 메일러 4종[재설정 2·잠금·신규 IP]과 deliver_later 호출부 **0줄 수정** 전환)·발신 badeuldon@veloloop.kr 강제·**Idempotency-Key=배달 잡 단위 키**(job.\<job_id\> — 새 이벤트 새 키·같은 잡 재시도만 멱등. 리뷰 C-1으로 내용 해시 방식 폐기 — 정적 본문 통보 영구 흡수 방지)·OutboundMail::DeliveryJob(retry_on retryable? 5회·비재시도 코드 버림)·credentials 등록 전 로그 폴백(NOTI-3 선례·무중단)·production default_url_options example.com→badeuldon.kr 교정(기존 재설정 링크 파탄 해소)·from 상수 폴백. 리뷰 CHANGES_REQUESTED(C1·W6)→수정→테스트 **1,438건(+39·0 failures)**. **운영 전제: 메일 서버 rake[client 생성·allow_sender] + credentials outbound_mail 블록{token,from_email,...} 등록 시 실발송 전환**·[INFERENCE] 5건 첫 실발송 시), **정책 문서·인프라·기술 부채 병렬 배치**(`2026-11-20`, PRD v0.44 — §6.14 4태스크. **T1 정책 문서 갱신**: 개인정보(휴대폰 필수·바로빌 제3자 제공·추천 어트리뷰션·공동인증서 바로빌 보관)·약관(내용증명 5,000원·세금계산서 300원·추천 20% 할인·세무 자문 아님)·환불(부가서비스 완료 후 불가) — 법무 검토 7건 목록(T1 03 문서)·terms 제4조 AUTH-9 미반영 관찰. **T2 인프라**: SQLite 백업 자동화(서버 스크립트·crontab 04:15 KST·30일 보존·docker exec sqlite3 .backup — 실측 4덤프 성공)+CF 터널 로테이션·HSTS 절차 문서화. **T3 기술 부채**: payments.note(Q22 과다입금 비고 구조화·감사 병행)·message_logs digest 부분 유니크(W-1 — already_sent_this_week? 쿼리 1:1)·routes except: :destroy(관찰⑤) — 통합 마이그레이션 1건. **T4 솔라피 잔액**: get_balance 래퍼(라이브 실측 200)+admin 대시보드 표시(5분 캐시·임계 5만원 주황 경고) — **운영 잔액 임계 미만·충전 필요**. **2026-11-23 정정**: 당시 기록("balance/point Integer 확정")은 불완전 실측이었다 — 응답은 11키·금액 소수이고 `balance`는 부가세 제외(예치금×0.9), `deposit`이 솔라피 콘솔에 보이는 예치금이다. 대시보드는 두 값을 함께 표시하고 경고는 부가세 제외 금액 기준. 리뷰 APPROVED(B0·C1[기존 admin 테스트 실호출 → stub 감싸기 해소]·W3)·테스트 **1,466건(+28·0 failures)**), **랜딩 전면 재구성 — LP-16 전 기능 커버**(`2026-11-19`, PRD v0.45 — Standard+·일반 모드·uibowl 관찰 기반. 11파셜→13섹션: 신규 _all_features(전 기능 12카드 그리드 — 반복 청구·세금계산서·내용증명·수금 패스·부분입금·수신거부·다이제스트·내보내기)+_sales_program(추천 20%·첫결제 20%·역할별 수수료)+features 앵커·FAQ 8→12(세금계산서·반복청구·추천코드·휴대폰 인증)+hero 배지. 리뷰 APPROVED(B0·C0·W2 — W-1 헤드라인 완화 '한눈에')→Tester 기존 갱신 3건+신규 10건·전체 1,477 runs 0 failures(+10)·LP-12 금지 표현 스캔 0. **2026-11-20 사용자 판정 조정(배포 406c17e 후 직접 수정)**: _sales_program 섹션·추천 코드 FAQ 제외(추천 프로그램은 비공개 영업 채널 — 공개 어필 금지)·'신규' 배지 제거(미구현 '예정' 배지만 유지)·'다이제스트'→'주간 수금 요약' 표기 통일 — 12섹션·CTA 3곳·FAQ 11항목), **세금계산서 발급 자격 차단·운영 준비 게이트**(`2026-11-24`, PRD v0.46·TAX-3·TAX-4·Q25·Q26 — Full·일반 모드·Sequential. **TAX-3** 간이과세·면세사업자는 전자세금계산서 발급 불가(영구 — **발행만 차단**, 과세 유형 선택·사업자 정보 저장·기존 발행 내역 조회·취소는 허용)·**차단 4지점**(청구서 상세 패널 발급 불가 카드 / 발행 화면 진입 new·create → **청구서 상세로 되돌림** / 주문 생성 전(300원 결제 전)·`CreateOrderService::IneligibleUser` / 발행 서비스 가드 `IssueService#verify_guards!` 첫 줄)·미결제 주문 상세는 결제 버튼 대신 안내·안내 문구는 **서비스 기준**("받을돈에서는 … 발급을 지원하지 않습니다" — 법령 원문 미대조·법적 예외 §64조의2는 미지원, 간이과세에 세무사 확인 고지)·판정·문구 단일 출처 `User#tax_invoice_eligible?`·`#tax_invoice_ineligibility_notice`. **TAX-4** 전역 스위치 `TAX_INVOICE_ENABLED`(**기본 꺼짐·fail-closed** — `config/initializers/tax_invoice.rb`가 부팅 시 `config.x.tax_invoice_enabled`에 고정, 판정은 `TaxInvoice.feature_enabled?` 단일)·꺼짐이면 사이드바 "전자세금계산서" 메뉴 비노출·청구서 상세 패널 "준비 중"(`TaxInvoice::FEATURE_DISABLED_NOTICE`)·발행 new·create와 발행 설정 전 액션은 대시보드로 리다이렉트·**결제 완료(paid) 주문의 조회·취소는 허용**·컨트롤러 concern `TaxInvoiceGate`. 청구서 상세 패널 판정 우선순위 기존 발행 기록 > paid_pending > 꺼짐 > 자격 없음 > 설정 미완료 > 거래처 사업자번호 없음 > ready. 리뷰 CHANGES_REQUESTED(B0·**C2** — new 미차단·미결제 주문 상세가 게이트 밖 결제 진입점)·W5 → 수정 → 테스트 **1,529건(+52·0 failures)**·시스템 13건 0실패·코드 버그 0. 마이그레이션·라우트 변경 없음. 후속 과제: 과세 유형 기본값(일반과세)을 그대로 둔 간이과세자의 발행 차단 강화·법적 예외 지원 여부·세금계산서 브라우저 E2E), **관리자 환불 실행 — 포트원 결제 취소 연동·구독 즉시 Free·수금 패스 차감**(`2026-11-25`, PRD v0.47·PLAN-9·ADMIN-11·Q27 — Full·일반 모드·Sequential. `Orders::RefundService`: 사전 가드 → 시도 감사 → PG 취소 → **재조회로만 전액 취소 확정**(결제 ID 일치·`amount.paid`·상태 `CANCELLED`·취소 합계 — 포트원 공식 OpenAPI v2 대조) → `with_lock` 트랜잭션에서 주문 `cancelled`+`refunded_at`·상품 되돌리기·성공 감사. Plus 주문은 구독 **즉시 Free**(빌링키·주기·dunning 재시도 상태 삭제·주문 행 빌링키 복사본 정리) / 수금 패스는 회원 보유 패스 중 만료 임박순 **10건 차감**(0에서 종료) / 내용증명·세금계산서는 발행물 그대로. 관리자 주문 상세 "결제 취소(환불) 실행"(owner 전용 — `require_owner`를 `Admin::BaseController`로 이동·확인 대화창·레거시 기록 건 분기). 기존 기록 전용 `mark_refunded` 라우트 폐기·웹훅은 무변경(멱등). 리뷰 CHANGES_REQUESTED(C-1 dunning 상태 잔존 → 카드 재등록 뒤 재차감 시도·C-2 PG 취소 뒤 확정 실패 시 감사 0건 → `order_refund_attempt`·`order_refund_failed` 감사 추가·W8) → 수정. **포트원 test 환경 실호출 차단 가드 추가**(리뷰 중 서브에이전트 실요청 사고 — 거부되어 금전 이동 없음 — 계기. 전체 테스트 실행마다 운영 API로 실요청하던 기존 테스트 결함 1건도 수정). 테스트 **1,582건(+52·0 failures)**·시스템 1건 신설(10/10)·코드 버그 0. 후속: **첫 실환불 1건으로 재조회 응답 필드 실측**·회원 환불 안내·감사 화면 환불 계열 action 라벨), **포트원 채널 키 환경 분리 + 결제 확정 검증 — 라이브 결제 전 보안 보강**(`2026-11-25`, PRD v0.48·PLAN-5 — 일반 모드·Standard로 시작해 리뷰 중 범위 확장·리뷰 루프 한도(2회) 초과 후 마감 리뷰 APPROVED. ① 채널 키 선택기 `PortOne::ChannelKey`(운영만 라이브·그 외 `*_test`·비운영에서 테스트 키 없으면 라이브 키로 대체하지 않음·환경 설정 플래그 `config.x.portone_live_channel`는 `production.rb`만 true, 판정은 반드시 `== true`)·호출처 4곳 교체·채널 키 없음 전용 예외 `MissingChannelKey`(갱신 잡은 그 구독만 건너뛰고 계속)·단건 결제 3곳 키 없음 안내. ② **결제 확정 검증**(기존 공백 — 재리뷰에서 발견): 승인 요청에 `totalAmount`·`isTest`·`currency` 전달, 확정점 `FulfillPassService`가 `PortOne::PaymentVerifier`로 **재조회한 결제 건**의 `amount.paid` == 주문 금액·`channel.type` == 환경 기대값(LIVE/TEST)·`currency` == KRW를 확인한 뒤에만 paid 확정(어긋나면 주문 failed + `PAYMENT_VERIFICATION_FAILED` 기록·회원은 "다시 결제하지 말고 문의" 안내·같은 청구/회원의 재주문 차단). **승인 응답은 `pgTxId`·`paidAt`만이라(공식 `ConfirmedPaymentSummary`) 승인 뒤 반드시 재조회** — 1차 구현은 승인 응답으로 검증해 정상 결제가 전부 실패 처리될 뻔했고 테스트 대역이 이를 가렸다(대역의 승인 응답 자동 채움은 삭제). 웹훅은 pending 주문만 paid로 확정(검증 실패·실패 주문이 뒤늦은 Paid 이벤트로 되돌려지는 우회 차단). ③ **운영 포트원 스토어 전환 포함**(사용자 확인: 의도 — credentials의 `store_id`·라이브 채널 키가 새 값, 기존 값은 `*_test`로 이동, `api_secret`은 새 스토어에서 유효를 직접 조회로 확인·운영 DB 주문 0·빌링키 0). 리뷰: B-1(credentials 값 변경)→R-1·R-2(기존 결제 검증 공백)→R2-1(웹훅 우회) 순으로 해소, 마감 리뷰 APPROVED(B0·C0·W4 반영). 테스트 **1,664건(+82·0 failures)**·시스템 15건·코드 버그 0. 후속: **첫 실결제 1건으로 결제 확정 검증 실측**(승인 응답 형태·재조회 `status`·`amount.paid`·`channel.type`·`currency` — 정상 결제가 검증에 막히면 즉시 중단)·포트원 콘솔 웹훅 URL(V2 실연동 탭에 운영 주소, V2 테스트 탭에는 없음)·`_test` 채널 2개 소속·로컬 결제창 브라우저 확인·검증 실패 주문의 관리자 재검증·환불 지원(현재는 runner로 상태 변경해 재주문 차단 해제))
- **수신 거부 청구 재개 차단 + 발송 상한에 수동 발송 합산 + 상한 도달 표시 + 재예약 실행 정합**(`2026-11-26`, PRD v0.49·Q28·VIEW-7·REM-3·REM-7·REM-11·PLAN-3 — 일반 모드·Full·Sequential, 사용자가 판단을 위임한 결함 2건("1번 2번은 자체적으로 판단해서 진행")). 런칭 테스트 체크리스트(`LAUNCH_TEST_CHECKLIST.md` §8) 작성 중 코드 대조로 발견: ① 수신 거부한 거래처의 청구·거래처에 「안내 다시 보내기」·「안내 재개하기」·목록 카드 「재개」가 보이고 요청도 "다시 진행합니다"로 답했지만 `refused_at`이 남아 발송이 영원히 없었다 → 버튼 미노출 + `resume_reminders`·`restart_reminders`(청구 건·거래처) 상태 변경 없이 거부(303+alert). ② 자동 시퀀스 상한이 시퀀스성 sent만 세어 발행 안내 문구로 수동 5통을 보낸 청구에도 다음 자동 단계가 발송됐다(채무자 6통째) → `MessageLog.counted_for_cap`(시퀀스성 템플릿 OR origin=manual)·판정 단일 출처 `Invoice#reminder_cap_reached?`, 상한 도달 청구는 상세에 「발송 상한에 도달했습니다」·「상한 도달」 배지(미수 청구만)와 버튼 행·「다음 안내」 미노출, `DispatchService#steps_due_today`에서 제외(09시 사전통보·재개 판정), 수동 상한만 도달은 「지금 1통 보내기」만 숨김, 종결 마킹 없음·자동 1회성은 계속 발송(Q10 유지). 파이프라인 중 찾아 고친 기존 결함(발송 경로): 창 밖 수동 발송의 예약 슬롯이 같은 템플릿의 과거 sent 이력 때문에 duplicate로 흡수돼 "다음 평일 9시 발송"이 조용히 취소되던 문제(슬롯 우선 재사용 — 채무자 향만), 창 시작 직전 1분 이내 접수분 누락(`in_flight?` — 예약 슬롯은 실행 시작 touch가 있을 때만 진행 중), 이미 보낸 자동 단계의 유령 「예정」 행. 시스템 테스트 로그인 헬퍼 공용화(`ApplicationSystemTestCase#log_in_as` — DOM 클릭, 파일별 정의 5건 제거). 리뷰 2회(1차 APPROVED B0·C0·W7 / 마감 CHANGES_REQUESTED B0·C1·W6 → 7차 수정, 규칙대로 재리뷰 없음). 테스트 **1,707건(+43·0 failures)**·시스템 20건·코드 버그 0. 운영 영향 없음(운영 DB 청구 0·pending 슬롯 0 — 읽기 전용 조회). **미결정(런칭 전 — `LAUNCH_TEST_CHECKLIST.md` §8)**: 회원 탈퇴 기능 부재 vs 약관(관리자 콘솔 계정 삭제만 있음)·수신 거부를 번호 단위로 막을지·대시보드 오늘의 액션 3종 미구현 vs 빈 화면 문구
- **작업 재개 가이드**: `.zcode/progress.json`의 `currentPhase` 확인 → `awaiting_approval`이면 플랜 재보고 후 선택 질의 재제시(§6.13 — 텍스트 폴백 허용), 그 외에는 다음 Phase부터 재개. 산출물은 `_workspace/`.
- **병렬 배치 후보 조합** (§6.14 채택 — 힌트이며 판정은 Phase 1-P 3조건이 우선):
  - 기술 부채 뭉치(독립 소규모 다수): Pretendard 셀프호스팅 · ko locale · 봇 UA 필터 · ViewEvent 하드닝 — 파일 소유권이 분리되어 병렬 유리 (이메일 서비스는 F-EMAIL 완료로 제거)
  - 랜딩 파셜 독립 보강 묶음(LP 계열 — 서로 다른 파셜 파일만 수정 시)
  - 후보 없음: F-REM(순차 의존 사슬 — 마이그레이션·라우트 결선·잡가 공유), F-ADMIN(관리자 롤·2FA가 전역 공유), 단일 공유 파일 중심 변경

### 운영 배포 운영 노트 (2026-10-14 실측)

- **배포 전 커밋 필수** — Kamal 버전 태그 = git HEAD SHA, 미커밋 변경은 이전 이미지 재배포됨
- **buildx 빌더**: `config/buildkitd.toml`(HTTP 레지스트리 허용)을 넣은 `kamal-local-docker-container` 빌더 재생성으로 해결 — 빌더 삭제 시 이 파일로 재생성 필요
- **cloudflared**: 호스트 네트워크 단일 복제(컨테이너) — bridge망 복제는 localhost 불일치로 502. CF 대시보드 서비스 URL은 `http://localhost:3000`(https 아님)
- **공개 표면 브라우저**: `AllowAllBrowsers` concern(랜딩·인증 3종·뷰어) — /app·/admin만 `:modern`
- 후속: 터널 토큰 로테이션 권장(프로세스 목록 노출 이력) · HSTS는 CF 엣지 설정 권장
- **관리자 운영 절차 (2026-11-10 Run A)**: 최초 계정 생성 `bin/rails runner 'Admins::ProvisionService.new(email: "...", password: "...", role: :owner).call'` · 잠금 해제 `bin/rails runner 'a=Admin.find_by(email: "..."); a.unlock!; AuditLogs::RecordService.call(admin: a, action: "unlock")'` — 공개 가입 경로 없음(AUTH-7.2). `/admin` 로그인은 2FA(TOTP) 필수 — 승인 앱 등록(QR·수동 시크릿 병기)
- **세금계산서 기능 스위치 운영 (TAX-4 — 2026-11-24)**: 기본 꺼짐이라 **배포 직후 운영에서 세금계산서 기능 전체(메뉴·발행·설정)가 잠긴다** — 의도된 동작. 로컬 개발에서 메뉴를 보려면 `TAX_INVOICE_ENABLED=true bin/dev`, 테스트는 기본 켬(`test/test_helper.rb`)에 끈 상태는 `with_tax_invoice_feature(false) { }` 헬퍼. **켜기**: `config/deploy.yml`의 `env.clear.TAX_INVOICE_ENABLED`를 `"true"`로 → 커밋·배포. **켜기 전 필수 확인**: 바로빌 운영 준비 완료(계약 체결·포인트 충전·법인 회원 등록 스모크) — 포인트 미충전 상태에서 켜면 사용자가 300원을 결제한 뒤 발행이 실패한다. **스위치를 끈 채로 배포할 때**: 운영 DB의 미결제 세금계산서 주문(`Order.pending.tax_invoices`)을 확인해 실패 처리 — 미결제 주문 상세는 결제 버튼 대신 안내를 보이지만 이미 열린 결제창은 막지 못한다. 랜딩의 세금계산서 소개는 스위치와 연동되지 않으므로 **외부 공개 전에 켜야 한다**.
- **관리자 환불 실행 운영 (PLAN-9·ADMIN-11 — 2026-11-25)**: 환불은 **반드시 관리자 페이지(주문 상세 "결제 취소(환불) 실행")에서, 최고 관리자(owner)만** — 포트원이나 KG이니시스 콘솔에서 직접 취소하면 회원의 구독·패스 권한이 그대로 남는다(KG이니시스 콘솔 환불은 포트원 상태가 `PAID`로 남아 이 기능으로 정산할 수도 없다). **첫 실행은 실제 결제 1건(실결제 검증용 수금 패스)으로** 하고 전액 취소 뒤 재조회 응답(`amount.paid` 유지·동기 취소 여부)을 확인한다. 실패 메시지·422가 떠도 **포트원 쪽에서는 환불이 실행됐을 수 있다** — 목록에서 "취소·환불"로 보이면 상세의 재실행 버튼으로 정산을 완료한다(시도·실패 감사가 남는다). 자동 갱신 스윕 시각(일 1회)에는 환불을 실행하지 않는다. 환불은 회원에게 알리지 않는다.
- **포트원 채널 키 환경 분리 (PLAN-5 — 2026-11-25)**: 운영만 라이브 채널 키(`channel_key_billing`·`channel_key_normal`), 로컬·테스트는 테스트 채널 키(`channel_key_billing_test`·`channel_key_normal_test`)를 쓴다. 선택은 단일 진입점 `PortOne::ChannelKey`(`.billing`·`.normal`)이 맡고, 라이브 여부는 환경 설정 플래그 `config.x.portone_live_channel`(`config/environments/production.rb`만 true — 미정의 환경은 테스트 채널, 규약 §9.4)로 정한다. 판정은 반드시 `== true` 비교다 — Rails 8.1의 `config.x`는 **정의되지 않은 키를 읽으면 nil이 아니라 빈 `OrderedOptions`(참으로 평가)**를 돌려주므로 truthy 검사로 바꾸면 모든 환경이 라이브가 된다. **비운영 환경에서 테스트 키가 없으면 라이브 키로 대체하지 않는다** — 결제 버튼·카드 등록은 비활성 안내, 빌링키 발급·차감은 API를 부르지 않고 전용 예외로 실패한다(갱신 잡은 그 구독만 건너뛰고 나머지를 계속 처리). 채널 키를 `credentials.dig(:portone, :channel_key_…)`로 직접 읽는 코드를 새로 만들지 않는다. 빌링키는 채널에 묶여 있어 로컬 DB에 다른 채널로 등록한 카드가 남아 있으면 다시 등록해야 한다.
- **포트원 결제 확정 검증 (PLAN-5 — 2026-11-25 재리뷰 반영)**: 단건 결제는 승인 요청에 `totalAmount`(주문 금액)·`isTest`(운영 false·그 외 true)를 보내고, 확정점 `Orders::FulfillPassService`가 `PortOne::PaymentVerifier`로 **결제금액 == 주문 금액·채널 종류 == 환경 기대값(LIVE/TEST)**을 확인한 뒤에만 paid로 확정한다. **검증 대상은 반드시 재조회한 결제 건이다** — 승인 요청(`POST /payments/{id}/confirm`)의 200 응답은 공식 `ConfirmedPaymentSummary`로 `pgTxId`·`paidAt`만 담고 있어 금액·채널이 없다(이 사실을 모르고 승인 응답으로 검증하면 정상 결제가 전부 실패 처리된다). 그래서 `PurchaseService`는 승인 성공 뒤 `get_payment`로 재조회하고, 승인은 됐는데 재조회가 실패하면 실패 확정하지 않고 pending으로 웹훅 회복을 연다. 테스트 대역도 이 형태를 그대로 재현해야 한다(승인 응답에 금액·채널을 자동으로 채워 주지 않는다). 어긋나면 발급·발행 없이 주문을 실패 처리하고 사유를 메타데이터·로그에 남긴다. 새 결제 확정 경로를 만들 때 이 검증을 우회하지 않는다(단건 결제 확정은 `FulfillPassService` 한 곳). **웹훅의 상태 동기화는 pending 주문을 paid로 확정할 때만 검증을 거친 확정점을 탄다** — pending이 아닌 주문의 상태는 paid로 바꾸지 않는다(검증 실패·실패 주문이 뒤늦은 `Transaction.Paid`로 되돌려지는 우회 차단 — 내용증명 다운로드는 `paid?`만 보므로 특히 중요). 검증 실패 주문(`status failed`·`paid_at` 없음·`metadata.code == "PAYMENT_VERIFICATION_FAILED"`·`metadata.verification.{reason,detail}` — 금액·채널·통화 중 어느 하나가 주문과 다름)은 관리자 환불 실행의 사전 가드 대상이 아니며 재발급 액션도 없다 — 변조 결제든 잘못 걸러진 정상 결제든 포트원 콘솔에서 환불하고 잘못 걸러진 건은 CS가 수동으로 재발급한다(후속 과제: 관리자 재검증·환불 지원). **같은 청구(내용증명·세금계산서) 또는 그 회원(수금 패스)에 해결되지 않은 검증 실패 주문이 있으면 새 주문 생성이 막힌다**(이중 결제 방지 — 상세 화면만이 아니라 주문 생성 3곳에서 가드). **해제 조건**: 그 주문이 더는 `failed`가 아니면 된다(예: 처리 뒤 runner로 `Order.find(id).update!(status: :cancelled)` — 감사를 남기려면 감사 로그 기록을 함께). 회원 안내는 자동 확인을 암시하지 않는다(관리자 알림·자동 재확인은 없다 — 회원이 문의해야 처리된다). 첫 실결제 때 승인 응답이 `pgTxId`·`paidAt`뿐인지, 재조회 응답의 `status`가 즉시 `PAID`인지·`amount.paid`가 주문 금액과 같은지·`channel.type`이 `LIVE`·`currency`가 `KRW`인지를 기록한다.
- **운영 포트원 스토어 전환 (2026-11-25 credentials 교체 — 사용자 확인: 의도됨)**: 2026-11-25 11:18에 편집된 `config/credentials.yml.enc`는 테스트 키 2개 추가만이 아니라 **운영이 쓰는 `portone.store_id`·`channel_key_billing`·`channel_key_normal` 값도 새 값으로 바뀌었다**(기존 값은 `*_test` 이름으로 이동, `api_secret`은 그대로 — HEAD와 복호화해 비교해 확인). **이 credentials를 배포하는 순간 운영 결제는 새 스토어·새 라이브 채널로 나간다.** 지금까지 운영 스토어의 결제 시도는 3건(모두 실패·수금 패스 4,000원)이고 운영 DB에 주문·카드 등록은 0건이라 넘어가는 데 막힘은 없다. 배포 전 확인 — ① `api_secret`이 새 스토어에서 유효: 2026-11-25 직접 조회로 확인(새 스토어 단건 조회 `404 PAYMENT_NOT_FOUND`, 존재하지 않는 스토어는 `403 FORBIDDEN`) ② **포트원 콘솔의 V2 실연동 탭 웹훅 URL에 `https://badeuldon.kr/webhooks/portone`을 등록하고, V2 테스트 탭에는 운영 주소를 두지 않는다**(웹훅 URL은 탭별로 설정된다 — 콘솔에서 미확인) ③ `_test` 채널 2개의 소속(사용자 확인: 새 스토어의 채널. 값은 이전 운영 채널 키와 같아서 로컬 결제창이 뜨는지 브라우저로 확인하기 전까지는 단정하지 않는다 — 포트원 콘솔에서 두 채널의 환경이 '테스트'로 표시되는지도 확인). 커밋은 **credentials를 코드 변경과 별도 커밋으로 분리**한다(롤백 단위). 테스트 채널에서 실제 결제가 일어나지 않는지도 브라우저 확인 전에는 단정하지 않는다.
- **발송 상한·수신 거부·예약 슬롯 운영 (2026-11-26 수정분)**: ① 청구 건당 상한 5통은 두 가지다 — 자동 상한(시퀀스성+수동 sent)과 수동 상한(채무자 향 sent 전체). 발행 안내·잔액·감사 안내는 상한 밖(Q10). 상한 도달 청구는 상세 화면에 「발송 상한에 도달했습니다」(미수 청구만), 종결 마킹은 없고 14시 스캔은 CAP_REACHED skip을 기록한다(P4). ② 수신 거부(`Client#refused_at`)는 회원이 되돌릴 수 없다 — 어떤 재개 요청도 상태 변경 없이 거부되고 발송도 REFUSED로 막힌다. ③ 발송 창(평일 09~18시) 밖 접수 발송은 "다음 평일 09시"에 실행된다(예약 슬롯 재사용) — 실행 시점에 가드가 막으면(상한·보류·수신 거부·마감) skip 사유가 이력에 남는다. 수동 2회 접수는 안내대로 2통이 나간다(수동 재발송 허용). ④ pending이 1일 넘게 남은 채무자 향 이력(유령 「예정」 행)이 보이면 결함 신호다 — `MessageLog.where(status: :pending).where('updated_at < ?', 1.day.ago)`로 확인한다(2026-11-26 운영 조회 0건).
- **외부 서비스 상태는 기록이 아니라 직접 조회해서 확인한다 (2026-11-25)**: 솔라피 템플릿 상태는 `GET /kakao/v2/templates?limit=20[&startKey=…]`(프로젝트 `Solapi::ClientService`의 HMAC 인증 그대로 — `templateList`·`nextKey` 페이지네이션, 항목의 `status`·`comments`로 승인 이력 확인)로 조회한다. 이 날 조회 결과 **24종 전부 `APPROVED`**이고 운영 credentials `solapi.template_ids`도 24종이다(가입 인증·주간 수금 요약·반복 청구 통보 2종·티켓 답변·세금계산서 통보 포함). 잔액은 `Solapi::ClientService#get_balance`(2026-11-25 예치금 8,535원·부가세 제외 7,682원). 문서·메모리의 "미등록·재제출 대기" 서술을 그대로 보고하지 말고 먼저 조회한다.
