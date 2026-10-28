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
| AUTH | 계정·인증 | 이메일/비밀번호만(OAuth 폐기, AUTH-1), 비밀번호 재설정(AUTH-8), 관리자는 전용 계정+2FA(AUTH-7) |
| ONB | 온보딩 | 가입→첫 발행 3분 플로우 |
| CLIENT | 거래처·품목 | 거래처 CRUD, 지급 성적표 |
| INV | 청구서 | 상태 전이, 만기 기본 +30일(INV-3), 발행 후 수정 불가(INV-5) |
| SHARE | 공유 링크 | 추측 불가 토큰, 최초 열람 즉시 알림(SHARE-4) |
| REM | 리마인더 시퀀스 | 서비스 명의 발신(REM-1), 4단계 톤, 평일 09-18시만(REM-3), 건당 5통 상한(REM-12·PLAN-3) |
| PROMISE | 응답(약속) 수집 | 무가입 응답, 약속 등록→시퀀스 재스케줄, 채무자 마감 권한 없음(PROMISE-7) |
| PAY | 입금 처리 | 원클릭 마감, 부분입금 잔액 재계산, 계좌조회 자동화 금지(PAY-5) |
| DASH | 대시보드 | 오늘의 액션, 연체일 내림차순 |
| PLAN | 구독·과금 | Free 3건/5거래처, Plus 9,900원, 수금 패스, 포트원(KG이니시스) |
| VIEW | 채무자 뷰어 | 비로그인, 인앱 브라우저 QA 필수(VIEW-1), 마케팅 요소 금지(VIEW-8) |
| NOTI | 알림(프리랜서 향) | 솔라피 채널 공유 |
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


## UI 품질 기준 (모든 표면 구현에 강제)

- **F-DESIGN 철저 반영**: 모든 UI는 PRD §7.3(DESIGN-1~7)과 레퍼런스 벤치마킹 포인트(Stripe 절제·타이포 위계 / 토닥 온기 / 볼타 B2B 여백·정보 위계 / 토스 송금 모바일 UX)를 구현에 반영한다. "최소 골격"이어도 완성도 기준은 동일하다 — 뼈대만 노출하는 구현 금지.
- **표준 스택**: Pretendard 국문 폰트(CDN), 크림·아이보리 배경 + 딥 그린 액센트(DESIGN-2), 상태색 3종(연체 주황/대기 중립/완료 녹색), 타이포 사이즈 위계·여백 리듬·인터랙션 디테일(hover/focus 링/섀도/트랜지션) 필수.
- **문구 원칙**: 마케팅 문구는 LP-12(P1~P5·금지 표현) 준수, 발신 문구는 REM-2 단계별 톤 준수 — 신규 창작 문구는 Reviewer가 집중 검증한다.
- **리뷰 의무**: Phase 5 리뷰는 기능 정합성과 함께 디자인 기준 준수(레이아웃 위계·간격 일관성·접근성 터치 타깃·DESIGN-6)를 검증 항목에 포함한다. 미달 시 WARNING 이상으로 지적한다.

## 테스트 전략

- 프레임워크: minitest + fixtures. 계층: 모델(검증·상태 전이·Rule ID 시나리오) → 서비스/쿼리(비즈니스 로직) → 컨트롤러(통합) → 시스템(브라우저 E2E, 뷰어 인앱 브라우저 동작 포함)
- Rule ID별 정상/경계/예외 시나리오 도출이 원칙(Tester는 PRD §6~7 기준)
- 게이트: `bin/ci`(RuboCop 0에러 + Brakeman 0경고 + 테스트 전체 통과) 통과 전까지 커밋/병합/배포 불가
- 외부 API(솔라피·포트원)는 테스트에서 stub/wrapper 주입 — 실 호출 금지

## 하네스: 받을돈 개발 자동화 (ZCode Desktop)

**목표:** PRD 비즈니스 규칙과 ARCHITECTURE_CONVENTION 아키텍처를 준수하는 코드의 구현·리뷰·테스트를 자동화한다.

**진입점(일반/절약 명령어 2개):** 아래에 해당하는 모든 요청은 **반드시** 오케스트레이터 명령어로 실행한다(사용자가 직접 명령어를 선택하는 것이 가장 확실하다):
- 일반 모드: `/badeuldon_orchestrator <요청>` — 메인 GLM-5.3, 프로필 `badeuldon-developer/reviewer/tester`
- 절약 모드: `/badeuldon_orchestrator_lite <요청>` — 메인 GLM-5.3-Flash, 프로필 `-lite` 3종
- 두 명령어는 같은 `badeuldon-orchestrator` 스킬(Phase 0~9)을 로드한다. 절약 모드도 승인 게이트·보안·테스트 기준은 동일하다.

대상 작업:
- 기능 구현, 코드 수정, 리팩터링, 버그 수정
- 코드 리뷰, 테스트 작성, 디버깅
- API/라우트 설계, 데이터베이스 마이그레이션, 비즈니스 로직 검증
- 위 작업의 후속 요청 (수정, 보완, 개선, 리팩터링, 재실행, 업데이트)

단, 순수한 문서 내용 확인 질문("~가 무슨 뜻이야?", "~는 어디에 있어?")은 직접 응답 가능.

**구성 요소**(모두 워크스페이스 전용 — 플러그인·마켓플레이스 불필요, Git 추적): 명령어 2개(`.zcode/commands/`) · 공통 오케스트레이터 스킬 + 참조 스킬 5종(`.zcode/skills/` — business-rules, feature-dev, review-checklist, test-patterns, git-deploy) · 서브에이전트 프로필 6개(`.zcode/agents/`) · 진행 상태(`.zcode/progress.json`). 플러그인 경로는 폐기 — 플러그인에는 워크스페이스 스코프가 없어 전역 적용되고, `agents` 필드는 실행되지 않음이 실측됨(HARNESS_CONVENTION v4.0.3). 하네스 신규 구성·점검·동기화는 전역 `$harness` 메타 스킬로.

**배포:** "git 배포", "커밋", "푸시", "배포", "push" 요청 시 `badeuldon-git-deploy` 스킬을 사용하라.

**에이전트 스폰:** 오케스트레이터만 Agent tool로 스폰한다(`subagent_type`으로 모드별 프로필 지정 — 일반 `badeuldon-developer` 등, 절약 `badeuldon-developer-lite` 등). **승인 게이트**: 플랜 보고 후 턴 종료, 승인 전 스폰 금지 — 이 규칙은 AGENTS.md·`badeuldon-orchestrator` 스킬·양쪽 명령어 3곳에 공통 반영한다.

**변경 이력:**
| 날짜 | 변경 내용 | 대상 | 사유 |
|------|----------|------|------|
| 2026-10-08 | 초기 하네스 구성 | 전체 | 신규 구축 (HARNESS_CONVENTION v3.2.0 기준) |
| 2026-10-29 | omp → ZCode Desktop 하네스 전환 | 전체 | 런타임 전환 (HARNESS_CONVENTION v4.0.1) — 명령어 2개·공통 스킬·프로필 6개·로컬 플러그인 marketplace·`.zcode/progress.json` 도입, omp 파일 제거 |
| 2026-10-29 | 플러그인 설치/명령어 발견 실측 수정 | 하네스 | ① marketplace.json `pluginRoot` 미지원 → 루트 기준 상대경로 ② 서브에이전트 프로필을 `.zcode/agents/`로 이동(플러그인 agents 필드는 미실행 실측) — 새 세션에서 명령어·에이전트 발견 확인 필요 |
| 2026-10-29 | 플러그인 → 워크스페이스 전용 리소스 전환 | 하네스 | 플러그인이 워크스페이스 스코프 없이 전역 적용됨이 실측됨(HARNESS_CONVENTION v4.0.3) — 명령어를 `.zcode/commands/`, 스킬을 `.zcode/skills/`로 이동, 플러그인 언인스톨·마켓플레이스 등록 제거, `.zcode/harness-marketplace/` 삭제. git clone만으로 하네스 완결 |

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

- **완료**: Rails 8.1 스켈레이션, 하네스 구축 + E2E 검증, F-AUTH 인증(OAuth 폐기·Q8), 랜딩 전체 + UI 품질 기준 + AUTH-1.3 프로필(v0.18.1), /app 대시보드 뼈대(v0.18.2), F-CLIENT(v0.18.3), F-INV 청구서(v0.18.4), F-SHARE+F-VIEW 뷰어 개봉(v0.18.5), F-PROMISE 응답 수집(v0.18.6), F-PAY 입금·MVP 수금 루프 완결(v0.18.7), 랜딩 헤드라인 교체·푸터 사업자·LP-5 버블 UI(v0.19), 로그인 UX(원클릭 복귀), **F-PLAN 구독·과금**(`2026-10-15`, PRD v0.20 — Subscription(체험→활성→해지→만료·빌링키·1人1구독)·Order·PaymentPass(10건·90일·with_lock), 결제 래퍼(초기 TossPayments → 포트원(KG이니시스) 전환, stub 가능·웹훅 회복), 한도 전환(Free 5/3→Plus 무제한·수금 패스 소비), 자동 갱신 Job(with_lock·멱등키), 웹훅 POST /webhooks/portone(결제 재조회 검증), /app/billing UI·사이드바. 테스트 484건. 리뷰 BLOCKER 1+CRITICAL 6 수정)
- **구현됨 상세**: `_workspace_prev/`(로그인 UX)·`_workspace/`(F-PLAN) 산출물 참조
- **진행 중**: 없음
- **예정**: F-REM(솔라피 연동 — 알림톡 템플릿 검수 승인 2026-10-29, SHARE-4·PROMISE-4/7·PAY-4 알림, SHARE-5 문구 분기, VIEW-7 수신거부, PROMISE-3 재스케줄, overdue 저장화) → F-DASH 나머지(DASH-5/6) → F-ADMIN → F-LEGAL/REF/TAX → CLIENT-3/4·PROMISE-5 → INV-7·PDF → 부분입금 오기록 정책 → LP-11 콘텐츠 허브·블로그. 기술 부채: dunning(결제 실패 재시도), 환불 처리(포트원 콘솔 수동), 웹훅 data 필드 [INFERENCE] 라이브 실측 필요, Pretendard 셀프호스팅, 이메일 서비스, ko locale, 관리자 계정, 약관·개인정보 문서, 후기, Stimulus 분리, ViewEvent 하드닝, 봇 UA 필터, 인앱 실기 QA
- **작업 재개 가이드**: `.zcode/progress.json`의 `currentPhase` 확인 → `awaiting_approval`이면 플랜 재보고 후 승인 대기, 그 외에는 다음 Phase부터 재개. 산출물은 `_workspace/`.

### 운영 배포 운영 노트 (2026-10-14 실측)

- **배포 전 커밋 필수** — Kamal 버전 태그 = git HEAD SHA, 미커밋 변경은 이전 이미지 재배포됨
- **buildx 빌더**: `config/buildkitd.toml`(HTTP 레지스트리 허용)을 넣은 `kamal-local-docker-container` 빌더 재생성으로 해결 — 빌더 삭제 시 이 파일로 재생성 필요
- **cloudflared**: 호스트 네트워크 단일 복제(컨테이너) — bridge망 복제는 localhost 불일치로 502. CF 대시보드 서비스 URL은 `http://localhost:3000`(https 아님)
- **공개 표면 브라우저**: `AllowAllBrowsers` concern(랜딩·인증 3종·뷰어) — /app·/admin만 `:modern`
- 후속: 터널 토큰 로테이션 권장(프로세스 목록 노출 이력) · HSTS는 CF 엣지 설정 권장
