# 05_review.md — F-PROMISE 응답(약속) 수집 Phase 5 리뷰

- **일자**: 2026-10-13 · **리뷰어**: PromiseReviewer
- **대상**: git 변경분 신규 6(migration·Promise·RegisterService·App::PromisesController·helper·thanks 뷰) + 수정 8(viewer_controller·invoice.rb·routes·뷰 3·컨트롤러 2·schema)
- **입력**: 01_plan(결정 #1~#4)·02_prd_update(승인 해석)·03_implementation(§5 기술 노트)·PRD v0.18.6 §6.7/§6.11/§6.9/§6.4 원문 대조
- **방법**: 원문 대조 + 코드 전수 + 러너 독립 실측(금요일 산정) + rate_limit 스토어 소스 추적(actionpack 8.1.4·solid_cache 1.0.10)
- **참고**: `_workspace/05_review.md` 신규 작성(이전 없음). `_workspace_prev/05_review.md`는 F-SHARE 리뷰로 중복 지적 대상 아님.

## Status: APPROVED

- **BLOCKER 0 · CRITICAL 0 · WARNING 4** — Rule ID 정합성·보안·전이 무결성 전 항목 통과. WARNING 4건은 후속 반영 권고로 Phase 6 커밋 진행 가능.
- 스타일(RuboCop 85파일 0에러)·zeitwerk·migrate·기존 테스트 258 runs 0실패는 Phase 4 보고를 전제로 재검하지 않음.

## 이슈 목록

| # | Severity | Rule ID | File:Line | 설명 | 수정 제안 |
|---|----------|---------|-----------|------|-----------|
| 1 | WARNING | PROMISE-2(무결성 보조)·P4 | `app/models/promise.rb:28-32` · `app/controllers/viewer_controller.rb:57-59` | **비약속 kind의 필드 주입 허용**. `promise_params`가 kind 불문 `promised_on·memo`를 허용해, 조작 요청으로 `paid_report`에 `promised_on`을 넣으면 U1 타임라인(`app/invoices/show.html.erb:127` — `promised_on.present?`가 kind 불문)에 「이미 입금했어요」 행에 잘못된 **약속일이 표시**된다. 상태·DASH·금액 무결성은 무관(정상 UI로는 발생 불가). `this_week`에 memo 주입도 저장됨(표시 경로 없음). | 모델에 kind-필드 일관성 검증 추가: `promised_on`은 `this_week/date_selected`만, `memo`는 `inquiry`만 허용(불일치 시 errors). 또는 서비스에서 kind별 파라미터 정규화. |
| 2 | WARNING | PROMISE-6(UX 피드백) | `app/models/promise.rb:41-44` · `app/views/app/invoices/show.html.erb:149-151` | **`answer!`의 :base 에러 미표시**. 재답변 차단 안내 「문의에는 한 번만 답변할 수 있습니다」는 `errors.add(:base)`인데 폼 오류 표시는 `promise.errors.key?(:answer)` 분기뿐이라 화면에 노출되지 않는다. 스탤 탭·경쟁 제출 시 무피드백(재렌더된 최신 이력은 답변 완료로 보여 혼동은 적음, DB 무손상). | `:base` 에러도 폼 상단에 표시(`errors.key?(:answer) \|\| errors.key?(:base)` 분기 또는 full_messages 표시). |
| 3 | WARNING | P1(용어 일관성) | `app/controllers/app/promises_controller.rb:13` | **U1 대면 용어 불일치**. 답변 등록 notice 「**채무자**가 청구서 링크에서 확인할 수 있습니다」 — 같은 화면 폼 placeholder는 「**거래처**가 청구서 링크에서 확인합니다」(show.html.erb:146)이고 기존 U1 UI는 전부 「거래처」 용어. 채무자가 보는 문구가 아니므로 P1 위반은 아니나 같은 화면 내 이원화. | 「거래처가 청구서 링크에서 확인할 수 있습니다」로 통일. |
| 4 | WARNING | INV-4(후속 추적) | `app/models/invoice.rb:166-169` | **`mark_promised!` 조건(issued\|viewed)에 overdue 부재**. 현재는 연체가 파생 판정(저장 status는 issued/viewed 유지 — `scope :overdue`·`overdue?` 실측)이라 **실결함 없음**: 만기 경과 후 약속 접수 → 저장 status가 issued/viewed이므로 promised 전이가 정상 동작한다. 그러나 F-REM이 연체를 저장 상태로 전환하는 시점부터는 이 조건이면 **연체 건 약속이 promised로 전이 불가** — INV-4 `(연체\|약속대기)` 형제 구조상 연체→약속대기 회복 흐름이 자연스러운 만큼 후속 F-REM 리뷰 시 `:overdue` 추가 여부 재확인 필요. | F-REM 설계 시 `mark_promised!` 조건에 `:overdue` 포함 검토(본 Phase 수정 불필요). 본 이슈는 F-REM 백로그로 이관. |

## 금요일 산정 검증표 (PROMISE-1 this_week — 결정 #1) — 리뷰어 독립 실측

산식 `Promise#compute_this_week_promised_on`(`Date.current.beginning_of_week + (토·일 ? 11 : 4)`), `bin/rails runner` 실측(2026-10-12~18). `Date.beginning_of_week=monday` 실측, 앱 TZ=Seoul(`config.time_zone`) → `Date.current`=KST 접수일(TIME-1) ✓.

| 접수일(요일) | 승인 해석 기대 | 실측 결과 | 판정 |
|---|---|---|---|
| 2026-10-12 (월) — 평일 분기 | 이번 주 금 10-16 | 10-16 (금) | PASS |
| 2026-10-14 (수) — 평일 분기 | 이번 주 금 10-16 | 10-16 (금) | PASS |
| **2026-10-16 (금) — 당일 경계** | **당일 금(10-16)** — 결정 #1 「접수일 기준 이번 주 금요일」, 02 문서와 일치. 금 접수가 다음 주 금이 되는 해석 아님 | 10-16 (금, 당일) | PASS — 해석·구현 일치 |
| 2026-10-17 (토) | 다음 주 금 10-23 | 10-23 (금) | PASS |
| 2026-10-18 (일) | 다음 주 금 10-23 | 10-23 (금) | PASS |

- 3분기(평일/토/일) 전부 PASS. 약속일이 절대 주말이 되지 않아 REM-3 평일 발송 기준과 정합 ✓. Developer 러너 실측(03 문서 §2)과도 일치.
- `before_validation` 산정이므로 **클라이언트 promised_on 주입은 무시·덮어쓰기** 됨(보안 검증표 5번) ✓.

## 비인증 경로 보안 검증표 (집중 영역)

| # | 시나리오 | 검증 결과 | 판정 |
|---|---|---|---|
| 1 | **파라미터 화이트리스트** | viewer: `params.expect(promise: [:kind, :promised_on, :memo])`(viewer_controller.rb:57-59) — `answer`(U1 전용)·`invoice_id` 주입 불가(청구서는 라우트 토큰으로만 결정). app: `[:answer]`만. 중첩 배열·미포함 키 전부 차단 | PASS (잔여: 이슈 #1 kind별 정규화) |
| 2 | **rate_limit 운영 실효성** | `rate_limit to: 10, within: 10.minutes, by: →{params[:token]}`, `only: :create`. store 소스 추적: **production `:solid_cache_store`(solid_cache 1.0.10 — `increment` 지원, `entry_lock_and_write` 원자 RMU)** ✓ / **development `:memory_store`** ✓ / **test `:null_store` — `increment`가 nil 반환해 제한 미동작**(Developer가 03 §5에서 이미 인지·Phase 7 명시). 러너 실측: `ViewerController.config.cache_store`가 환경별 스토어 **인스턴스**로 확정 — rate_limit 기본 store는 **클래스 로드 시점에 캡처**되므로 테스트 런타임 `Rails.cache` 교체는 무효(Tester 제안 1 참조) | PASS (운영 실효. test 환경 제약은 Phase 7) |
| 3 | **무효 토큰 응답 경로 404** | `set_invoice` before_action이 show·create·promise_thanks 전 경로 공통(만료·폐기·미존재 전부 `:expired`+404로 수렴, 존재 여부 구분 없음). 기존 show 인라인 가드를 before_action으로 통합하면서 가드 조건(`link_accessible?`)은 원문 그대로 — 보호 범위 확대만 있고 축소 없음(diff 대조) | PASS |
| 4 | **kind 위조** | `RegisterService#call`이 `Promise.kinds.key?(@kind.to_s)` 사전 검사 → 미일치 시 `InvalidResponse` → 422 + 일반 문구 「응답을 처리할 수 없습니다. 다시 시도해 주세요」(enum·내부 정보 누출 없음). 정수 문자열("0")·배열·공백 전부 422 | PASS |
| 5 | **promised_on 조작** | this_week: 서버 before_validation 산정이 무조건 덮어쓰기(클라이언트값 무시). date_selected: 서버 검증 `promised_on >= Date.current`(어제 이전 차단·당일 허용 — 결정 #3). 뷰 `min:` 속성은 1차 방어일 뿐, 직접 POST에도 서버 재검증 | PASS |
| 6 | **대량 등록(스팸)** | 유효 토큰당 10회/10분 초과 시 429(실패 422도 카운트 — 폭주 포함). 무효 토큰 회전 공격은 rate_limit 키가 토큰 문자열이라 한도를 회전 우회할 수 있으나 DB 쓰기 없음(404 수렴) — IP 기반 인프라 레벨 제한은 범위 밖(플랜 D 리스크 명시된 트레이드오프) | PASS |
| 7 | **동시 등록(레이스)** | `RegisterService`가 `promise.save!`+`mark_promised!`를 **1 트랜잭션**으로 원자화. `mark_promised!`는 `status IN (issued,viewed)` 조건부 UPDATE 단일 쿼리 — 동시 this_week 2건이어도 전이 정확히 1회, Promise는 이력으로 2건(설계 의도). paid 청구서에 약속 시도 → 조건 불일치로 **paid 유지**. 이미 promised 재약속 → 무변경+이력 추가(결정 #4 이행) | PASS |
| 8 | **상태 오염(PROMISE-7)** | paid_report·inquiry는 `mark_promised!` 호출 경로 자체가 없음(`if promise.this_week? \|\| promise.date_selected?`) — 채무자 회신으로 마감 상태 변경 불가 구조가 코드 경로 차단으로 보장됨. 마감은 PAY·U1 확인으로 이관(이번 범위 회신 기록+DASH-2 표시까지 — 02 승인 해석) | PASS |
| 9 | **XSS·로그** | 신규·수정 파일 `raw`/`html_safe`/logger 출력 0건(grep 실측). ERB 기본 이스케이프, `whitespace-pre-line`+`<%= %>`로 memo·answer 안전 렌더 | PASS |
| 10 | **noindex(SURF-3)** | `layouts/_head`의 `NOINDEX_PATH_PREFIXES ["/app","/b/","/admin"]` 경로 접두 판정 → thanks(`/b/:token/promises/thanks`) 포함 전 /b/* noindex 유지, viewer 레이아웃 _head 사용 확인 | PASS |

## Rule ID 준수 매핑

| Rule ID | 구현 확인 | 판정 |
|---|---|---|
| **PROMISE-1** | 버튼 4종 원문 대조(PRD §6.7:174-178 ↔ viewer/show.html.erb:150,154,161,177 ↔ promises_helper.rb): 「이번 주 내에 입금할게요」「입금 예정일 지정」(달력=native date input)「이미 입금했어요」「문의·이의 있어요」 — **4종 전부 원문과 동일**, U1 라벨도 동일 어휘 인용 | ✓ |
| **PROMISE-2** | 비가입·무입력: 파라미터 3종 뿐, 개인정보 필드 전무, 토큰 보유=권한. 완료 화면은 PRG GET으로 이중 접수 방지 | ✓ |
| **PROMISE-6** | 1문의 1답변: `answer!`가 무답변 inquiry에 1회 한정(answered_at 유일 기록 경로), 답변 후 폼 미표시·재답변 가드, 뷰어 「발행인 답변」 서비스 경유 표시, DASH-2 답변 대기, 연락처 노출 없음(P2) | ✓ (피드백 갭: 이슈 #2) |
| **PROMISE-7** | paid_report 상태 불변(호출 경로 차단 — 검증표 8) + DASH-2 마감 대기. 알림 문구 원문은 카드 문구 「거래처가 「이미 입금했어요」라고 회신했습니다. 확인 후 마감해 주세요」로 의미 동등 대체(알림 발송 자체는 02 승인 연기) | ✓ |
| **PROMISE-3(범위 한정)** | promised 전이+약속일 저장까지만 — 재스케줄(D-1/D+1)은 REM 후속, 플랜·02 문서와 일치 | ✓(범위 준수) |
| **INV-4** | `mark_promised!` issued\|viewed→promised 조건부 원자 UPDATE(`mark_viewed!` 동일 패턴). 후속 F-REM 연체 저장화 시 조건 재검토(이슈 #4) | ✓ |
| **INV-5** | status는 보호 컬럼 아님 — 약속 전이와 본문 불변 가드 무충돌(draft만 편집 스코프 유지) | ✓ |
| **VIEW-4/8·SURF-2/4** | 응답 액션·답변 표시는 화이트리스트 허용 요소. 마케팅·내비·③→① 링크 0(완료 화면 링크는 ③→③ 복귀뿐), 전용 레이아웃 유지 | ✓ |
| **DASH-2** | 마감 대기 = `unsettled ∩ paid_report 존재`(partially_paid 포함 — PROMISE-7 합산 유도와 정합, paid·voided 제외로 마감 완료·폐기 오표시 없음), 답변 대기 = unanswered inquiry, 둘 다 Current.user 스코프(서브쿼리 — 타인 데이터 비노출 확인). 무액션일 때만 기존 빈 상태 유지 | ✓ |
| **P1** | 신규 창작 문구 전수: 「이 청구서에 응답하기」·감사 화면·에러 문구 전부 요구·압박·법적 언급 0, 존중 어조. U1 대면 용어 이원화만 이슈 #3 | ✓ (W1건) |
| **P3** | 응답 플로우 전체 가입·로그인·개인정보 요구 전무(`allow_unauthenticated_access` show·create·thanks) | ✓ |
| **P4** | 재응답 이력 전부 보존(레코드 추가형), 사용자 삭제 경로 없음(routes: promises `only: []`+answer만). `dependent: :destroy`는 초안 삭제시에만 발동 가능 — 초안은 토큰 없어 응답 생성 자체가 불가하므로 실질 발동 없음 | ✓ |
| **TIME-1** | 산정·검증 전부 `Date.current`/`Time.current`(앱 TZ Seoul), 금요일 산정 독립 실측 통과 | ✓ |
| **SEC-5** | 발송 로직 부재(REM 후속)로 해당 없음 — 03 문서 명시와 일치 | N/A(정당) |

**아키텍처(ARCHITECTURE_CONVENTION)**: Service `#call`+키워드 생성자(Current/params 무의존) ✓, 1트랜잭션 ✓, 명시적 예외(`InvalidResponse`)·조용한 rescue 없음 ✓, 컨트롤러 액션 10줄 이내·`params.expect`·303/422 규약 ✓, 뷰 쿼리 없음(@변수 소비) ✓, 도메인 간 결합은 공개 진입점(RegisterService·`Promise#answer!`) 경유 ✓, 라우트는 SURF-1 표면 내(member 액션 정당화 주석) ✓, 소유권 `Current.user.invoices` 서브쿼리 격리 ✓, DESIGN-4/6(문서 카드·min-h-11 터치타깃·focus-visible) 유지 ✓.

**범위 준수**: 플랜 외 파일 미변경(git diff 대조 —PRD 버전·_workspace 문서 제외), 후속 제외(PROMISE-3 재스케줄·PROMISE-4/7 발송·PROMISE-5·PDF·스레드) 미구현 확인. 기존 테스트 1줄 미수정(git status — test/ 변경 0건).

## Tester에게 제안하는 중점 테스트 영역

1. **rate_limit 회귀 (03 §5 주의점 — 구체 방법)**: rate_limit 기본 store는 **클래스 로드 시점에 캡처된 인스턴스**(`ViewerController.config.cache_store` — 러너 실측)라 **테스트 런타임의 `Rails.cache = MemoryStore.new` 교체는 무효**. 방법: ① `config/environments/test.rb`의 `cache_store`를 `:memory_store`로 변경한 뒤 요청 스펙에서 유효 토큰 POST 11회 → 11번째 `assert_response :too_many_requests`, 케이스 간 `Rails.cache.clear`(teardown) — 또는 ② test 환경 유지 시 rate_limit 검증만 별도 환경 실행. 유효 토큰·무효 토큰 각각 카운트 분리(by: token) 확인.
2. **금요일 산정 3분기+당일**: `travel_to` 월·수·금(당일)·토·일 접수 → this_week promised_on이 이번 주 금(금 접수=당일)/다음 주 금인지, 절대 주말이 아닌지(검증표 값 그대로 재사용 가능). 클라이언트가 this_week에 `promised_on`을 심어 POST해도 서버 산정치로 덮어쓰이는지.
3. **과거 예정일 차단(결정 #3)**: 직접 POST로 `min:` 속성 우회(어제·임의 과거) → 422 + 청구서 상태·이력 무변화, 당일 허용.
4. **PROMISE-7**: paid_report 접수 후 invoice.status 불변(issued/viewed/promised 어느 쪽이어도) + DASH-2 「마감 대기」 카드 표시 + paid 전환(마감) 후에는 카드 소멸(`unsettled` 제외) — 마감은 U1 확인 경로만.
5. **PROMISE-6 1문의 1답변**: 답변 등록 303·뷰어 「발행인 답변」 표시(answered_at 포함)·답변 후 재답변 차단(이슈 #2 — 무응답 확인 포함)·무답변 문의만 폼 표시·answered/unanswered 스코프.
6. **전이 원자성**: this_week/date_selected 각 issued·viewed 양쪽에서 → promised; 재약속(2회 응답) 시 이력 2건 보존+「최신」 배지 첫 행; paid 상태 청구서에 this_week POST → 상태 paid 유지·이력만 추가; 이중 클릭(동시 POST) 후 상태·이력 정합.
7. **비인증 경로**: 위조 kind(문자열·정수형)→422 일반 문구, 무효/만료/폐기 토큰의 create·thanks → 404(VIEW-6), PRG 후 새로고침 재제출 없음, 소유권 — 타인 청구서 promise에 answer PATCH → 404.
8. **P3/VIEW-8**: 응답 플로우 렌더에 가입·개인정보 입력·③→① 링크 0건, thanks 화면 링크는 ③→③ 복귀뿐, noindex(thanks 포함).
9. **DASH-2 빈 상태 분기**: 마감 대기·답변 대기 모두 없을 때 기존 「오늘 할 일이 없습니다」 유지, 하나만 있을 때 해당 카드만.
