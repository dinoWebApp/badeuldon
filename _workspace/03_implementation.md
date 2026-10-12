# 03_implementation.md — F-SHARE 열람 추적 + F-VIEW 채무자 뷰어(표면 ③) + 링크 UI

- **일자**: 2026-10-12
- **범위**: 플랜 `_workspace/01_plan.md` (결정 4건 반영) — ViewEvent 신규 엔티티, 표면 ③ 뷰어 개봉(/b/:token), 발행 상세 링크 UI, 열람 이력 요약, viewed 뱃지
- **후속 제외(미구현 확정)**: SHARE-4 U1 알림 발송(핵클 미계약 — 결정 #1, ViewEvent·viewed 전이로 근거 데이터 완비), SHARE-5 문구 분기(REM), VIEW-4 응답 버튼(F-PROMISE)·PDF, VIEW-7 수신 거부, INV-7

---

## 1. 변경 파일

### 신규
| 파일 | 내용 |
|:---|:---|
| `db/migrate/20261012000005_create_view_events.rb` | `view_events` 테이블 — `invoice_id`(FK·인덱스, `t.references null: false foreign_key: true`), `first`(boolean, default false), `device`(string mobile/pc), `ip`(string limit 45 — IPv6 최대, 플랜 결정 #4 기록), `viewed_at`(datetime, KST — TIME-1). 전 컬럼 `null: false` |
| `app/models/view_event.rb` | SHARE-3 기록 모델. `belongs_to :invoice`, `device` inclusion(mobile/pc), `viewed_at`·`ip` presence. `ViewEvent.device_from_user_agent(ua)` — UA 대략 판별 클래스 메서드(모바일 키워드 매칭, UA 부재 시 PC) |
| `app/services/view_events/track_service.rb` | **저장소 첫 Service**(§3.5 도입 기준 충족 — 2개 모델 쓰기 + 트랜잭션). `#call` 진입점, 생성자는 데이터만(invoice·user_agent·ip·viewed_at=Time.current 기본). 트랜잭션 안에서 ① `first = view_events.none?` ② ViewEvent create! ③ first이면 `invoice.mark_viewed!`. 실패는 예외 전파(기록 누락 상태로 뷰어 성공 응답 금지 — P4) |
| `app/controllers/viewer_controller.rb` | 표면 ③. `layout "viewer"` + `allow_unauthenticated_access only: :show`(VIEW-1·P3). `Invoice.includes(:client).find_by(token:)` → `link_accessible?`(토큰 일치·미폐기·미만료) → TrackService 호출. 무효 시 `render :expired, status: :not_found` |
| `app/views/layouts/viewer.html.erb` | 뷰어 전용 레이아웃 — 앱 내비·푸터·마케팅 일절 없음(VIEW-8·SURF-2), 흰 배경(body `bg-white text-[17px]` — DESIGN-4·6), `_head` 파셜 재사용(noindex·Pretendard·importmap 자동) |
| `app/views/viewer/show.html.erb` | VIEW-2 헤더(「받을돈을 통해 **발행인**님이 보낸 청구서입니다」 + 링크 아닌 워드마크 — SURF-4), VIEW-3(청구번호·발행일·만기일·품목 표·금액 분해 INV-2·총액 대형 tabular·계좌 복사 카드·PAY-3 입금자명 안내), VIEW-5 하단 고지 |
| `app/views/viewer/expired.html.erb` | VIEW-6 안내 화면 — 「링크가 만료되었거나 폐기되었습니다.」 + 「발행인에게 직접 연락해 주세요.」 링크·연락처 일절 없음(SURF-4·P2) |
| `app/javascript/controllers/clipboard_controller.js` | 복사 UI 전용 Stimulus(1개 — UI 동작만). `navigator.clipboard.writeText` 성공 시 라벨 「복사됨」 2초 피드백, 실패 시 source 선택 수동 복사 fallback(비보안 컨텍스트 대응 — 플랜 리스크 노트). 링크 복사(②)·계좌 복사(③) 공용 |

### 수정
| 파일 | 내용 |
|:---|:---|
| `app/models/invoice.rb` | `has_many :view_events, dependent: :destroy`(연쇄 삭제 — invoices 파괴 경로 전부 자동), `scope :linkable`(초안·무효 제외 — SHARE-2 재발급 스코프), `regenerate_token!`(새 토큰 교체로 기존 링크 즉시 무효, `token_expires_at` 유지, voided는 INV-6로 거부), `mark_viewed!`(INV-4 issued→viewed — status 단일 컬럼 **조건부 UPDATE**로 원자화, 동시 열람에서 정확히 1회 적용) |
| `app/controllers/app/invoices_controller.rb` | member `regenerate_token` 액션(성공 303/실패 422 — Turbo 규약) + `set_linkable_invoice`(linkable 스코프 = 소유권 격리 겸용) + `set_view_events` before_action(show·issue·void·regenerate_token — 422 재렌더에서도 show 템플릿 @변수 보장, 대상 조회 `set_*_invoice` **뒤** 실행) |
| `app/views/app/invoices/show.html.erb` | ① 공유 링크 영역(token 보유 시; voided는 INV-6로 미노출): 전체 URL readonly 표시 + 복사 버튼 + 재발급 버튼(`button_to` + `turbo_confirm` 「기존 링크는 즉시 무효화됩니다. 재발급하시겠습니까?」) + 만료 임박/만료 표시 ② 열람 이력 요약(최초·최근 열람 시각 `display_datetime`·횟수 — SHARE-3 U1 가시화). 상단 주석의 「링크 미노출(플랜 결정 #1)」은 본 Phase 결정으로 대체 |
| `app/helpers/app/invoices_helper.rb` | 뱃지 분리: `issued` → 「대기 중」 / `viewed` → **「열람」**(중립 톤 유지 — DESIGN-2 상태색 3종), `link_expiry_notice`(만료 7일 전 「만료 임박」+열람 가능일, 경과 시 「링크 만료」+주황) |
| `app/helpers/app/base_helper.rb` | `display_datetime` 추가(분 단위 KST — TIME-1) |
| `config/routes.rb` | 표면 ③: `scope "/b" { get "/:token" => "viewer#show", as: :viewer }`(SURF-1 표면별 블록), invoices member `patch :regenerate_token` |
| `db/schema.rb` | 자동 갱신(version `2026_10_12_000005`) |

---

## 2. 상태 전이·ViewEvent 구현 지점 (INV-4·SHARE-3)

| 항목 | 구현 | 가드 |
|:---|:---|:---|
| 열람 이벤트 기록 | `ViewEvents::TrackService#call` — 뷰어 유효 진입 1회마다 `ViewEvent(first: 기존 0건 여부, device: UA 판별, ip: request.remote_ip, viewed_at: Time.current)` | 트랜잭션으로 이벤트·전이 동시 확정. 컨트롤러는 유효 링크 판정 후 위임 |
| 최초 열람 전이 | `Invoice#mark_viewed!` — `WHERE id = ? AND status = issued` 조건부 `update_all(status: viewed, updated_at:)`, 반환값 = 적용 1행 여부 | **update!가 아닌 전용 전이 메서드**(지시 준수). status는 INV-5 보호 컬럼(`PROTECTED_CONTENT_COLUMNS`)이 아니므로 본문 불변 가드와 무충돌. 발행 계열 viewed 진입의 유일 허용 경로(TrackService만 호출). 동시 열람 경합에서도 1회만 적용(조건부 UPDATE 원자성) |
| 재열람 | 이벤트만 추가(`first: false`), 상태 viewed 유지·중복 전이 없음 | `mark_viewed!`는 issued일 때만 1 반환 |
| 링크 재발급 | `Invoice#regenerate_token!` — `token` 새 urlsafe_base64(32), **`token_expires_at` 미변경(만기일 유지 — 지시)** | 초안·무효 거부(모델), 컨트롤러는 `linkable` 스코프 조회(이외 404). 토큰은 INV-5 보호 컬럼 아님 |
| 링크 폐기 | 기존 `void!`(token=nil) 그대로 — voided 접근은 token 불일치로 VIEW-6 수렴 | INV-6 |

- **VIEW-6 응답 통일**: 미존재 토큰·만료·폐기(voided token nil)·재발급 이전 토큰 = 전부 동일 템플릿 + **404**. 존재 여부 구분 누설 금지(열거는 256bit 엔트로피로 무의미하나 동일 응답 유지 — 플랜 B안의 secure_compare는 `find_by(token:)` DB 색인 조회 구조상 실익이 없어 지시문 A-2(find_by + 유효성 체크)를 그대로 따름)
- **토큰 유효 판정**: `token_expires_at > Time.current`(KST — TIME-1) + `voided?` 부정. paid 상태도 유효기간 내 링크는 열람 가능(청구 내용 확인용 — SHARE-2 유효기간 규정 준수)

### 2.1 뷰어·UI 구현 노트

- **금액 분해 톤(P1)**: 원천징수 건은 총액 아래 「원천징수 (공급가액의 3.3%)」 −금액 + **「입금하실 금액」**(=net_amount, 지급액 관점 라벨) + 안내 문구 「원천징수 3.3%는 제외한 『입금하실 금액』만 입금해 주세요.」 — 지시의 "실수령액 관점·지급액 기준 안내" 반영. 실측: 100,000+부가 10,000 → 총액 110,000·원천 −3,300·입금하실 금액 106,700
- **계좌 카드(③)**: 카드 전체가 복사 버튼(터치 타깃 — DESIGN-6), 복사 텍스트는 「은행 계좌번호 예금주」, 피드백 「탭하여 복사」→「복사됨」. sr-only input으로 수동 선택 fallback
- **PAY-3**: 「입금 시 입금자명을 '<거래처명>'으로 입력해 주세요」 — 지시 문구 그대로
- **만료 표기(②)**: 만료 7일 전부터 「만료 임박 — YYYY-MM-DD까지 열람할 수 있습니다」, 경과 시 「링크 만료 — 유효기간(만기일 + 60일)이 지났습니다.」(주황 — 연체 상태색 계열). 재발급해도 유효기간은 만기일 기준 유지(지시 명시 — 해석: 재발급은 유출 대응 토큰 교체 수단, 유효기간 연장 아님)
- **SURF-2/4 준수 실측**: 뷰어 본문에 `<a href="/…">` 앵커 0개(러너 실측), 워드마크는 `<p>` 텍스트, 고지문·청구 내용 외 요소 없음. noindex 메타 출력 확인
- **en.yml 미수정 사유**: ViewEvent 검증 오류는 서비스가 항상 유효값을 주입해 사용자에게 노출되지 않음(위반 시 500) — 사용자 대면 문구가 아니므로 한글화 대상 아님

## 3. Rule ID 매핑

| Rule ID | 구현 지점 |
|:---|:---|
| **SHARE-1** | `/b/:token` 뷰어 — `find_by(token:)`(43자 urlsafe 256bit 토큰, 고유 인덱스 — 기존 발행 경로). 추측 불가·열거 무의미 |
| **SHARE-2** | `linkable` 스코프 + `regenerate_token!`(수동 재발급 — 기존 링크 즉시 무효·유효기간 유지), `link_expiry_notice`(만료 임박/만료 표시), 뷰어 만료 판정(`token_expires_at > Time.current`) |
| **SHARE-3** | `ViewEvent`(first·device·ip·viewed_at) + TrackService + 발행 상세 열람 이력 요약(최초·최근·횟수) + 목록 「열람」 뱃지 |
| **SHARE-4** | **연기(플랜 결정 #1)** — 발송 채널(NOTI-1 알림톡·핵클) 미계약. viewed 전이+뱃지+ViewEvent로 인지·근거 확보, 채널 계약 후 REM/NOTI 파이프라인에서 연결 |
| **SHARE-6** | 링크 복사만 제공(② 안내 문구 「카카오톡 등으로 직접 전달하세요」) — 서비스 명의 발송은 REM 시점(결정 #2) |
| **VIEW-1** | 비로그인 모바일 웹 뷰어(비인증 라우트·전용 레이아웃), 모바일 우선·17px·터치 타깃. **allow_browser 경계 노트**: `modern` 세트 = Safari 17.2+·Chrome 120+·Firefox 121+(actionpack 8.1 실측). 버전 미보고 UA는 허용, 구형 버전 보고 UA는 **전 표면 공통**으로 406(뷰어 한정 정책 아님 — 랜딩·앱 동일). 카카오톡 인앱 실기 QA(VIEW-1 필수 항목)에서 확인 필요 — Reviewer 인계 → **Phase 6b에서 뷰어 한정 게이트 해제(말미 수정 이력 참조)** |
| **VIEW-2** | 뷰어 헤더 「받을돈을 통해 **{issuer_display_name}**님이 보낸 청구서입니다」 + 받을돈 워드마크(링크 아님 — SURF-4) |
| **VIEW-3** | 청구번호·발행일(issued_at)·만기일(due_on)·품목 표(설명·수량·단가·금액)·금액 분해(공급가액·부가세·원천징수·실지급 — INV-2, 총액 대형 tabular)·입금 계좌 카드(클릭 복사 + 복사됨 피드백, Stimulus 1개)·PAY-3 입금자명 안내 |
| **VIEW-5** | 하단 고지 「본 청구서는 발행인이 직접 발행했습니다. 본 서비스는 채권 추심 업무를 수행하지 않습니다.」 (P5) |
| **VIEW-6** | 만료·폐기·미존재·재발급 이전 링크 → 동일 안내 화면(문구 지시 원문 그대로) + 404. 링크·발행인 연락처 미노출(SURF-4·P2) |
| **VIEW-8 / SURF-2** | 뷰어 화면 요소 = 청구 내용·계좌 복사(응답 액션 전신)·PAY-3 안내·고지문뿐. 내비·푸터·마케팅·가입 유도·③→① 링크 0개(러너 앵커 검증 포함) |
| **INV-4** | `mark_viewed!` issued→viewed 전이(§2) + 목록·상세 「열람」 뱃지 |
| **INV-5** | 무충돌 확인: status·token은 `PROTECTED_CONTENT_COLUMNS` 외 — `mark_viewed!`·`regenerate_token!` 저장 시 본문 불변 가드 통과(러너 실측) |
| **INV-6** | voided 재발급 거부(모델 가드 + linkable 스코프 404), voided 링크 영역 미노출, voided 토큰 접근 → VIEW-6 |
| **PAY-3** | 뷰어 입금자명 표준 힌트(거래처명 스냅샷) |
| **SURF-1** | 표면 ③ 라우트 블록 `scope "/b"` — 단일 도메인 경로 분리 |
| **SURF-3** | `/b/*` noindex: 기존 `NOINDEX_PATH_PREFIXES "/b/"` 경유 `_head` robots 메타(러너 실측 출력 확인) + `public/robots.txt` `Disallow: /b/`(기존 유지 — 회귀 테스트 통과) |
| **SURF-4** | 뷰어 ③→① 링크 0개, VIEW-6에도 링크 없음, 워드마크는 비링크 텍스트 |
| **DESIGN-4** | 뷰어 전용 레이아웃 — 흰 배경·타이포 중심·색 최소(무채색 위주 + 액센트 최소) |
| **DESIGN-6** | 기본 글자 크기 상향(body 17px), 터치 타깃 min-h-11(복사·재발급 버튼), 모바일 우선 단일 컬럼 |
| **P3** | 뷰어 전 구간 가입·로그인·개인정보 입력 요구 없음(`allow_unauthenticated_access`) |
| **P4** | 열람도 기록(ViewEvent) — 기록 실패 시 뷰어 성공 응답 없음(예외 전파) |
| **TIME-1** | `Time.current`·`Date.current`(앱 TZ=Seoul) — 만료 판정·viewed_at·만료 임박 계산 |

## 4. 실패 예상 테스트 목록 (기존 테스트 수정 없음 — Phase 7 Tester 갱신 대상)

`bin/rails test` 실측: **228 runs, 1348 assertions, 2 failures, 0 errors, 0 skips** — 실패 2건 모두 본 Phase가 의도적으로 대체한 이전 스펙의 어설션이다.

| # | 테스트 | 파일:행 | 사유 |
|:---|:---|:---|:---|
| 1 | `상세는 청구 정보·계좌·품목·금액 내역을 렌더하고 토큰을 노출하지 않는다 (INV-1·SHARE-1)` | `test/controllers/app/invoices_controller_test.rb:44` (어설션 :64) | 이전 플랜 결정 #1(링크 미노출)이 본 Phase에서 뒤집힘 — 발행 계열 상세에 링크 영역이 노출되며 본문에 전체 URL(토큰 포함)이 표시된다(SHARE-1/6 개봉). 어설션 `assert_no_match(/토큰/)`은 이제 무효 |
| 2 | `목록 상태 뱃지는 상태색과 연체일·tabular 금액을 표기한다 (DESIGN-2·5)` | `test/controllers/app/invoices_controller_test.rb:442` (어설션 :451) | viewed 뱃지가 「대기 중」→「열람」으로 분리(SHARE-3 가시화). `assert_select "span", text: "대기 중", count: 2` → 실측 1(delta_due_soon만, delta_viewed는 「열람」) |

유지 확인(통과): 무효 본 상세(`main form.button_to` count 0 — voided는 링크 영역·재발급 버튼 미노출), 발행 본 상세(무효 처리 버튼 1 — 링크 영역 추가로 count 어설션 깨지지 않음), INV-2 원천징수 표기, 404 스코프, PLAN-1, FK 연쇄 삭제(view_events 연쇄 포함), SURF-3 색인 회귀 등 나머지 226건.

## 5. 자체 점검 결과

| 항목 | 결과 |
|:---|:---|
| `bin/rubocop` | **0 offenses** (76 files) |
| `bin/rails zeitwerk:check` | 통과("Otherwise, all is good!" — test/mailers/previews 안내는 기존 상태) |
| `bin/rails db:migrate` | 성공 — `db/schema.rb` version `2026_10_12_000005` 갱신, `db:test:prepare` 완료 |
| `bin/rails test` | 228 runs, 1348 assertions, **2 failures(§4 의도된 것)**, 0 errors, 0 skips |
| 뷰어 여정 러너 실측 | **35/35 PASS**(`/tmp/phase_share_view_check.rb` — 롤백 트랜잭션, 종료 시 잔존 0 확인) |
| 서버 기동·테스트 작성 | 하지 않음(지시 준수) — Phase 7 Tester 인계 |

### 러너 실측 시나리오 (§지시 자체 점검 4종 전부 포함)

| 시나리오 | 실측 | 결과 |
|:--|:--|:--|
| 최초 열람(모바일 UA) | 200 + ViewEvent(first=true·mobile·ip 기록) + **issued→viewed 전이** + VIEW-2/5 문구·PAY-3·noindex·앵커 0개 | PASS |
| 재열람(PC UA) | 200 + ViewEvent(**first=false**·pc) + **viewed 유지**(이벤트 2건·중복 전이 없음) | PASS |
| 미존재 토큰 | 404 + VIEW-6 문구 | PASS |
| 만료 토큰 | 404 + VIEW-6, 미존재와 **본문 동일**(누설 금지 — `<main>` 기준, 요청별 CSRF 메타 랜덤성은 제외) | PASS |
| 링크 UI(②) | 전체 URL 표시·clipboard 컨트롤러·재발급 turbo_confirm | PASS |
| 재발급 PATCH | 303, 토큰 교체 + **유효기간 유지**, 이전 링크 → VIEW-6 404, 신규 링크 정상 열람 | PASS |
| 열람 이력 요약 | 최초·최근 열람·횟수(3회) 표기 | PASS |
| 무효 건 | 발행 본 링크 영역 존재 → void! 후 **미노출**, 이전 토큰 → VIEW-6 404 동일 응답 | PASS |
| 목록 뱃지 | viewed 건 「열람」 표기 | PASS |
| 회귀 | 대시보드 200, 랜딩 200 + noindex 없음 | PASS |
| 격리 | 타 사용자 스코프 재발급 대상 없음·RecordNotFound, 무효 건 linkable 제외 | PASS |

### 기술 노트 (Tester·후속 참조)

1. **per-form CSRF 토큰**(Rails 기본): 통합 세션에서 상태 변경 PATCH는 해당 폼(action 일치)에서 추출한 토큰을 써야 한다 — 타 폼 토큰은 `InvalidAuthenticityToken`(**422**, rescue_responses 매핑)로 거부된다. Tester가 member 액션 테스트 작성 시 `sign_in` 후 해당 버튼 폼 토큰 사용(또는 `spec` 세션 헬퍼)
2. **러너 통합 세션**: 요청마다 `ActiveSupport::ExecutionContext` Record 파손(이전 Phase 노트 6 재확인) — 요청 후 `IsolatedExecutionState[:active_support_execution_context]` 교체로 회피. 경로 전용 요청은 세션 `host`가 기본 `www.example.com`이라 dev HostAuthorization(403)에 막힌다 — `session.host = "localhost"` 필요(또는 전체 URL 사용)
3. **동시 열람 경합**: `first?`는 `view_events.none?` 기준이라 극히 드물게 중복 기록될 수 있으나, 상태 전이는 조건부 UPDATE로 정확히 1회(트랜잭션+원자성 — Tester 경합 테스트 시 참조)
4. **allow_browser 경계**(§3 VIEW-1 행): 구형 인앱 브라우저는 전 표면 공통 406 — 뷰어 별도 완화는 정책 변경이므로 이번 범위에서 하지 않음. 실기 QA 결과에 따라 별도 결정 필요 (**→ Phase 6b에서 뷰어 한정 해제 결정·반영 — 말미 수정 이력 참조**)
5. **시스템 테스트 환경 확인**: Gemfile test 그룹에 `capybara 3.40.0`·`selenium-webdriver 4.50.0` 존재. 단 **`test/application_system_test_case.rb`와 `test/system/` 디렉터리가 아직 없음** — 뷰어 여정(링크→렌더→복사) 시스템 테스트 도입 시(플랜 결정 #3) Tester가 먼저 시스템 테스트 케이스 파일 생성 필요. selenium-webdriver 4.5+는 Selenium Manager로 드라이버 자동 관리(로컬 Chrome 설치 필요 — capybara 설정은 Tester 담당)
6. **실패 시 422 재렌더**: issue·void·재발급 실패 경로도 `show` 템플릿을 재렌더하므로 `set_view_events`를 해당 액션에 함께 걸었다(대상 조회 before_action보다 **나중** 실행 — 순서 변경 금지)

---

## 수정 이력 (Phase 6b — VIEW-1 브라우저 정책)

- **일자**: 2026-10-12
- **계기**: Phase 8 실행 검증 실측 — 채무자 뷰어(/b/:token)가 카카오톡 인앱 UA(Safari/604.1 계열) 요청에서 **406 Not Acceptable**로 차단. `ApplicationController`의 `allow_browser versions: :modern` 상속이 원인(05_review WARNING #1 실증) — VIEW-1(인앱 완전 동작 필수 QA)·P3(브라우저 업그레이드 요구도 채무자 진입 장벽) 위반

### 실측 근거 (actionpack 8.1.4 러너 검증 — `ActionController::AllowBrowser::BrowserBlocker`)

| 항목 | 실측 |
|:---|:---|
| 차단 UA | iOS 16.6 + `Safari/604.1`(WebKit 빌드 토큰이 버전으로 파싱 → 16.6 < 17.2)·Android WebView `Chrome/111.0.5563.116`(111 < 120) → `:modern` **차단** = 카카오톡 인앱 실측 패턴 재현 |
| 면제 UA | `facebookexternalhit`(미등록 브라우저명 → 세트 미일치 면제)·버전 미보고 UA — 차단 경로는 버전 보고 UA 한정 |
| `versions: :all` | **미지원 확인** — `NoMethodError: undefined method 'with_indifferent_access' for an instance of Symbol`(BrowserBlocker `SETS`에 `:modern`만 존재) |
| 상속 해제 수단 | 상속된 before_action은 **익명 람다**(actionpack `allow_browser.rb:58`)라 `skip_before_action`으로 지목 불가 → 지시의「최소 우회」채택 |
| `versions: {}` 후보 | 기술적으로 무차단이나 콜백 체인에서 상속 :modern 람다가 **먼저 실행**되어 무효 — 오버라이드로 대체 |

### 수정

| 파일 | 내용 |
|:---|:---|
| `app/controllers/viewer_controller.rb` | private `def allow_browser(**); end` no-op 오버라이드 — 상속 람다가 호출하는 인스턴스 메서드를 대체해 **뷰어 표면에서만** 게이트 무효화(모든 브라우저·인앱 웹뷰 허용 — 뷰어는 정적 문서 페이지, 클립보드 수동 복사 fallback 존재). `ApplicationController` 미수정 — 랜딩·앱·관리자 `:modern` 정책 불변(git diff로 확인) |
| `test/controllers/viewer_controller_test.rb` | 회귀 2건 추가: ① 인앱 UA 2종(iOS 16.6 Safari/604.1·Android WebView Chrome/111)로 뷰어 200 + 본문 렌더(h1·총액·고지문) ② `facebookexternalhit` 크롤러 UA 200 + 가입 유도 없음(P3) — WARNING #1·#3 회귀 |

### 회귀 결과

| 점검 | 결과 |
|:---|:---|
| 신규 테스트(수정 적용) | 2 runs 통과 — 인앱·크롤러 UA 모두 200 렌더 |
| **구정책 변이 검증**(override 임시 비활성) | 신규 인앱 테스트가 **406 Not Acceptable로 실패** — 회귀 검출력 실증 후 복원(크롤러 UA는 구정책에서도 면제 경로라 통과하는 것이 정상) |
| `bin/rubocop` | **0 offenses** (80 files) |
| `bin/rails zeitwerk:check` | 통과 |
| viewer 테스트 전체(컨트롤러 17+2·시스템) | **19 runs, 148 assertions, 0 failures, 0 errors, 0 skips** |
