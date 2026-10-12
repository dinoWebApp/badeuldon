# 05_review.md — F-SHARE 열람 추적 + F-VIEW 채무자 뷰어(표면 ③) + 링크 UI

- **일자**: 2026-10-12 (Phase 5 — Reviewer)
- **리뷰 대상**: git 변경분 신규 8(migration·ViewEvent·TrackService·ViewerController·clipboard_controller.js·viewer 레이아웃·show·expired) + 수정 7(invoices_controller·base_helper·invoices_helper·invoice.rb·app invoices show·routes·schema)
- **검증 방법**: 전 파일 원문 열독 + PRD v0.18.5 §6.4/6.5/6.11·§7 원문 대조 + grep 전수(앵커·호출 경로·noindex) + 경합/전이 논리 검증. 구현 보고 러너 실측(35/35)은 개발자 산출물로 참조.

## Status: APPROVED

**BLOCKER·CRITICAL 없음.** 토큰 보안(존재 누설 방지·404 통일·엔트로피), VIEW-8 화이트리스트, INV-4/5/6 전이 정합성, 소유권 격리, 트랜잭션·원자성 구조가 전부 코드 수준에서 확인됐다. 이슈 #1~#4는 전부 WARNING이며 (a) 실기 QA 확인 #1, (b) 문서화된 결정의 후속 하드닝 #2·#3, (c) 운영 문서화 #4 — 어느 것도 Phase 7 진입 전 코드 수정을 요구하지 않는다. 기존 테스트 실패 2건은 명세 이행분(§이전 이슈 추적 하단)으로 Tester 갱신 대상이다.

---

## 1. 이슈 목록

| # | Severity | Rule ID | File:Line | 설명 | 수정 제안 |
|---|----------|---------|-----------|------|-----------|
| 1 | WARNING (확인 요청) | VIEW-1 | `app/controllers/application_controller.rb:4` | `allow_browser versions: :modern`이 뷰어에도 적용 — 구형 Android WebView/Chrome(<120) 기기의 채무자는 406으로 청구서 자체를 볼 수 없다(VIEW-1 필수 QA 항목 위반 가능). 단 (a) 전 표면 공통 기존 정책(이번 diff 아님), (b) iOS 인앱(WKWebView)은 UA가 `Safari/604.1` 빌드 토큰을 보고해 `:modern` 임계값을 대부분 통과한다는 점에서 실피해는 Android 구형 단말로 국한 가능. 거래처 담당자 연령대(DESIGN-6 전제)를 고려하면 단말 다양성 확보 QA가 필수. | 실기 QA 우선(아래 Tester 영역 2-c). 406 재현 시 표면 ③만 완화 — `ViewerController`에서 `skip_before_action :verify_browser` 후 `allow_browser versions: <하위 세트>` 재적용(정책 결정은 오케스트레이터) |
| 2 | WARNING | SHARE-3 | `app/services/view_events/track_service.rb:17` | 동시 첫 열람 경합(커밋 전 2요청)에서 `view_events.none?`가 양쪽 모두 true → `first=true` 이벤트가 중복 기록될 수 있음(열람 횟수 +1·"최초 열람" 시각 오차 ms). **상태 전이는 조건부 UPDATE(`mark_viewed!`)로 정확히 1회 보장** — INV-4 무결성은 영향 없음. 구현 보고 기술 노트 3에 명시 인지된 결정. | 코드 수정 불요(문서화된 결정). 후속 하드닝 권장: 부분 유니크 인덱스 `ON view_events (invoice_id) WHERE first` + `ON CONFLICT` 처리, 또는 REM 도입 시 경합 관측 후 결정 |
| 3 | WARNING | SHARE-3·REM-4 | `app/models/view_event.rb:11` | UA 판별이 봇/프리뷰 크롤러를 분류하지 않음 — U1이 링크를 Facebook·Slack 등 미리보기 크롤이 있는 채널로 붙여넣으면(facebookexternalhit 등) 비인간 요청이 ViewEvent로 기록되고 **issued→viewed가 오염**될 수 있음. 향후 SHARE-5 문구 분기(REM-4)·SHARE-4 알림이 이 상태에 의존. KakaoTalk 자체 채팅은 URL 미리보기 크롤을 하지 않아 기본 여정(카톡 전달)은 무관. | 후속(REM 파이프라인 전): 전이 트리거에서 봇 UA(bot/crawler/preview 패턴) 제외 또는 별도 마킹. 이번 범위 수정 불요 |
| 4 | WARNING | SEC-3·P4 | `db/migrate/20261012000005_create_view_events.rb`(ip) | `ip` 평문 저장(limit 45) + Rails 기본 요청 로그에 토큰 포함 URL(`GET /b/:token`)·IP가 평문 기록. 플랜 결정 #4로 명시 승인된 범위이나 (a) 보관 기간·이용 목적(알림·분석) 미문서화, (b) 운영 로그의 토큰·IP 접근 통제 방침 부재. | 지금은 기록만: 향후 SHARE-4 알림 연결 시점에 ViewEvent.ip의 보관 기간·목적을 PRD/운영 문서에 명시하고, 프로덕션 로그 마스킹 또는 접근 통제를 운영 체크리스트에 추가 |

### 확인 요청 (이슈 번호 없음 — 경미)

- **뷰어 품목 지연 로드**: `ViewerController`가 `includes(:client)`만 하고 items는 뷰에서 지연 로드(`viewer/show.html.erb:44`). 기존 ② 상세(`app/invoices/show.html.erb:174`)와 동일한 확립 패턴이라 위반으로 보지 않고, PERF-2(2초) 영향도 인덱스 단일 쿼리로 미미. 후속 표면 통일 시 `includes(:items, :client)` 일괄 반영 여지.
- **`_head` 공유 파셜의 기본 meta description**("프리랜서 수금 자동화 서비스 받을돈")이 뷰어에도 삽입되나 비표시 요소이고 noindex가 적용돼 VIEW-8(표시 요소 화이트리스트)·SURF-2 위반이 아님. 무시 가능.
- **PAY-3 조사**「'거래처명'으로」은 PRD §6.10 원문 그대로 — 모음 종결 사업명("OO아이오" 등)에서 조사가 어색해질 수 있으나 명세 충실이 우선. PRD 차원의 문구 개선 여지로만 기록.

---

## 2. VIEW-8 / SURF-2 화이트리스트 검증표 (최우선 전수)

허용 요소 (PRD §6.11 VIEW-8 원문: "청구 내용·응답 액션(PROMISE-1)·PDF 다운로드·VIEW-5 고지문으로 한정"):

| 요소 | 구현 위치 | 판정 |
|:---|:---|:---|
| 청구 내용(VIEW-3 전체 — 청구번호·발행일·만기일·품목 표·금액 분해·총액) | `viewer/show.html.erb:16-85` | ✅ |
| 입금 계좌 클릭 복사 + PAY-3 입금자명 안내 | `viewer/show.html.erb:90-112` | ✅ (응답 액션 도입 전 신규 허용 범위는 아니나 PAY-3이 PRD에 명시된 뷰어 구성 요소·계좌 복사는 VIEW-3 원문 항목) |
| VIEW-5 고지문 | `viewer/show.html.erb:115-119` — 원문과 문장별 일치 확인 | ✅ |
| 응답 액션 3종(PROMISE-1) | 미구현 — 플랜 후속 제외(F-PROMISE) 명시 | ✅ N/A |
| PDF 다운로드(VIEW-4) | 미구현 — 플랜 후속 제외 명시 | ✅ N/A |

금지 요소 (전수 grep·렌더 확인):

| 금지 요소 | 판정 | 근거 |
|:---|:---|:---|
| 서비스 내비게이션(메뉴) | ✅ 부재 | 전용 레이아웃 `layouts/viewer.html.erb` — app 레이아웃 미상속, 내비 없음 |
| 푸터·마케팅 콘텐츠 링크 | ✅ 부재 | 레이아웃·show 전체 훑음 — 문서형 푸터는 VIEW-5 고지문만 |
| 요금제·가입 유도 | ✅ 부재 | 가입/로그인/설치/입력 요구 전무(P3) — `allow_unauthenticated_access only: :show` |
| ③→① 링크(SURF-4) | ✅ 부재 | **grep 실측: show·expired·layout 3파일 `href` 0개**. 워드마크 "받을돈"은 `<p>` 텍스트(비링크). VIEW-6 화면에도 링크·연락처 없음 |
| 발행인(U1) 연락처·개인정보 | ✅ 부재 | 표시되는 U1 관련 값은 `issuer_display_name`(VIEW-2 허용 표시명)·`account_holder`(입금 필수 — PAY)뿐. 이메일·개인 번호·성명 필드 미참조 |
| 채무자 입력 수집 | ✅ 부재 | 폼 요소는 계좌 복사 fallback readonly input(tabindex -1)뿐 — 제출 없음 |

부가: noindex(SURF-3) — `NOINDEX_PATH_PREFIXES "/b/"`(`application_helper.rb:4`)가 `_head` 경유 robots 메타 출력, `public/robots.txt` `Disallow: /b/` 유지 확인. 뷰어 렌더가 `layouts/_head`를 재사용해 자동 적용됨.

## 3. 토큰 시나리오 매트릭스 (VIEW-6 응답 통일 검증)

| 시나리오 | 조회 결과 | 상태코드 | 템플릿 | ViewEvent | 상태 전이 | 판정 |
|:---|:---|:---|:---|:---|:---|:---|
| ① 정상(발행 계열·미만료) | `find_by(token:)` hit | 200 | `viewer/show` | 기록(first=기존 0건 여부) | issued→viewed (최초 1회만) | ✅ |
| ② 미존재 토큰 | nil | 404 | `viewer/expired` | 없음 | 없음 | ✅ |
| ③ 만료(`token_expires_at ≤ now`) | hit | 404 | `viewer/expired` | 없음 | 없음 | ✅ |
| ④ 폐기(voided — token=nil) | **문자열 토큰은 NULL 미스치 → miss** | 404 | `viewer/expired` | 없음 | 없음 | ✅ |
| ⑤ 재발급 이전 토큰 | miss(신규 토큰으로 교체됨) | 404 | `viewer/expired` | 없음 | 없음 | ✅ |
| (보너스) 초안 | token=nil → miss | 404 | `viewer/expired` | 없음 | 없음 | ✅ 발행 계열만 뷰어 진입 |

- **본문 동일성**: ②③④⑤는 전부 동일 분기(`return render :expired, status: :not_found`)·동일 템플릿·동일 레이아웃. 템플릿이 `@invoice`를 참조하지 않아 본문 차이 없음(제목 "링크를 열 수 없습니다 — 받을돈" 고정). 요청별 랜덤 요소는 CSRF 메타뿐 — 비교 시 제외(구현 보고 러너 실측과 동일 기준).
- **엔트로피(SHARE-1/SEC-1)**: `SecureRandom.urlsafe_base64(32)` ≈ 256bit(43문자). 열거 무의미 — 플랜 리스크 노트대로 `find_by(token:)` DB 색인 조회 구조에서 secure_compare의 실익이 없다는 판단에 동의하며, 존재 누설은 응답 통일로 봉쇄.
- **SEC-1 3속성**: 추측 불가 ✓ / 유효기간 만료 ✓(`token_expires_at > Time.current`) / 수동 폐기 ✓(`void!` — SHARE-2의 "수동 폐기" 충족).
- **재발급 레이스**: 재발급은 토큰 교체만 하고 view_events·상태를 건드리지 않음 — 재발급 직전 열람 이벤트 유실 없음. 재발급 이전 링크로 이미 열린 화면(세션 없음)은 다음 요청부터 404.

## 4. 전이·무결성 검증 (INV-4/5/6·SHARE-3)

| 항목 | 검증 결과 |
|:---|:---|
| issued→viewed 원자성 | `Invoice#mark_viewed!`(`invoice.rb:155-158`) — `WHERE id=? AND status='issued'` 조건부 `update_all`. 동시 첫 열람에서도 **정확히 1회 전이**(경합 상세는 이슈 #2 — first 플래그만 중복 가능). `updated_at` 수동 갱신 포함 |
| 유일 진입 경로 | `mark_viewed!` 호출처 grep 전수 — `ViewEvents::TrackService`만. 컨트롤러·모델 다른 경로 없음 |
| viewed 후 재열람 | `first=false` 이벤트만 추가, `mark_viewed!`가 0행 반환 → 상태 불변 |
| 비-issued 상태 안전성 | paid·promised 등에서 `none?`가 true여도 조건부 UPDATE가 0행 → 우회 전이 불가. 발행계열만 뷰어 접근(초안·무효는 토큰 부재/폐기) |
| INV-5 무충돌 | `status`·`token`은 `PROTECTED_CONTENT_COLUMNS`(`invoice.rb:27-31`) 외. `mark_viewed!`는 `update_all`이라 콜백 자체를 우회하고, `regenerate_token!`는 `save`가 가드를 통과(보호 컬럼 무변경 — `recalculate_amounts` 재산산도 동일값) |
| INV-6 | `void!` token=nil 즉시 폐기 → 뷰어 404 수렴(매트릭스 ④). `regenerate_token!`는 draft/voided 이중 거부(모델 가드 `invoice.rb:142-145` + `linkable` 스코프 컨트롤러 404). voided 건 ② 링크 영역 미노출(`token.present?` 분기) |
| 트랜잭션 | `TrackService#call`이 ViewEvent create! + 전이를 단일 트랜잭션으로 확정 — 기록 없는 전이·전이 없는 기록 불가(P4: 실패는 예외 전파로 뷰어 성공 응답 차단) |
| SHARE-3 기록 | `first`(0건 기준)·`device`(UA 대략 판별 — UA 부재 시 PC)·`viewed_at`(Time.current, TZ=Seoul — TIME-1)·`ip`(remote_ip). PRD "최초/재열람 시각, 대략적 디바이스" 충족, ip는 결정 #4 |
| void 병행 레이스 | 열람 트랜잭션과 `void!`의 행 잠금 순서와 무관하게 최종 상태는 voided 승리(전-row UPDATE) — ViewEvent는 잔존(P4 이력 보존), 불가능 상태 조합 없음 |

## 5. 아키텍처·UI 품질 준수

- **Skinny controller**: `ViewerController#show` 7줄(조회→가드→위임). `regenerate_token` 성공 303/실패 422 + `render :show` — Turbo 규약·기존 issue/void 패턴 일관.
- **Service(§3.5)**: 저장소 첫 Service — 2개 모델 쓰기+트랜잭션 도입 기준 충족. `#call` 진입점, 생성자는 데이터만(invoice·user_agent·ip·viewed_at 기본값) — Job/콘솔 재사용 가능. 예외 조용한 rescue 없음.
- **before_action 순서**: `set_*_invoice`(6-9행) → `set_view_events`(12행) 선언 순 보전 — 422 재렌더 시 show 템플릿 @변수 완비(기술 노트 6 상황 재현 구조 확인).
- **의존 방향(§4.2)**: Controller→Service→Model 단방향. Model→Service 역참조 없음. View에서 쿼리 메서드 호출 없음(association 지연 로드는 기존 패턴 — 확인 요청 참조).
- **Stimulus**: clipboard 1개 — UI 동작만(복사 피드백·fallback 선택), 도메인 로직 없음, disconnect 타이머 정리·중복 flash 방지 구조 확인.
- **DESIGN-4/6·AGENTS UI 기준**: 흰 배경 문서형·색 최소(무채색 + emerald 액센트) ✓, body 17px·min-h-11 터치타깃·focus-visible 링 ✓, 금액 tabular·총액 대형 위계 ✓, 원천징수 「입금하실 금액」 지급액 관점 안내(P1 톤 — 100,000+10,000−3,300=106,700 분해 구조 확인) ✓. 크림·아이보리 배경 기준은 ② 표준이며 ③은 DESIGN-4가 명시하는 흰 배경 예외 — 정합.
- **라우트(SURF-1)**: `scope "/b"` 표면 블록, `patch :regenerate_token` member — 커스텀 액션 정당화(SHARE-2 수동 재발급). urlsafe 토큰(무점)이라 `/:token` 포맷 스푸핑 여지 없음.

## 6. Rule ID 준수 매핑 (요약)

SHARE-1 ✓(256bit·열거 무의미) / SHARE-2 ✓(만기+60일 end_of_day·재발급 시 유효기간 유지·수동 폐기=void) / SHARE-3 ✓(§4) / **SHARE-4 연기(결정 #1 — 채널 미계약, ViewEvent·뱃지로 인지·근거 확보)** / SHARE-6 ✓(링크 복사만 — 결정 #2) / VIEW-1 △(이슈 #1 실기 QA 대기) / VIEW-2 ✓(원문 일치) / VIEW-3 ✓(구성 전항목) / VIEW-5 ✓(원문 일치) / VIEW-6 ✓(원문 일치·안내만) / VIEW-8·SURF-2 ✓(§2) / INV-4 ✓ / INV-5 ✓(무충돌) / INV-6 ✓ / PAY-3 ✓(원문 일치) / SURF-1 ✓ / SURF-3 ✓(noindex+robots) / SURF-4 ✓(href 0) / DESIGN-4·6 ✓ / P2 ✓(U1 개인정보 미노출) / P3 ✓(무가입·무입력) / P4 ✓(열람 기록·실패 전파) / P5 ✓(고지문) / TIME-1 ✓(TZ=Seoul·Time.current) / SEC-1 ✓ / SEC-3 △(ip — 결정 #4, 이슈 #4 문서화 권고) / PERF-2 — 시스템 테스트 계측 대기(전역 CSS·CDN 폰트 분할은 SURF-6 기술부채로 AGENTS 로드맵 기록됨).

**범위 준수**: 플랜 외 앱 코드 변경 없음(PRD 버전 bump·진행 문서 제외). 후속 제외(SHARE-4 발송·SHARE-5 분기·VIEW-4 응답/PDF·VIEW-7·INV-7) 미구현 확인 — 데드 코드·스텁 없음.

## 7. 이전 리뷰(F-INV `_workspace_prev/05_review.md`) 이슈 추적

| # | 이전 이슈 | 상태 |
|---|:---|:---|
| 1 | 무효 건 부제 데드 브랜치 | ✅ 해결 — `voided_at.present?` 우선 분기로 수정됨(현 `app/invoices/show.html.erb:17-25`) |
| 2 | INV-3 프리필 초안작성일+30일 | ✅ 해결 — `reset_due_on_if_prefilled`(발행일+30 재계산) |
| 3 | PLAN-1 무효 포함 해석 미승인 | ✅ 해결 — `_workspace_prev/02_prd_update.md:25-28` 승인 목록 편입 |
| 4 | 위조 items_attributes 500 | ✅ 해결 — `item_ids_owned?` 사전 검증 |
| 5 | INV-5 모델 가드 부재 | ✅ 해결 — `enforce_issued_content_immutable` before_update |
| 6 | 품목 행 수 상한 없음 | ✅ 해결 — `MAX_ITEMS=100`(모델+JS) |
| 7 | 금액 컬럼 PG 이식 int4 오버플로 | △ 권고 유지 — schema 여전 `t.integer`(SQLite 8바이트라 현 무해). PG 배포 결정 시 `limit: 8` 일괄 마이그레이션 |

기존 테스트 실패 2건(`invoices_controller_test.rb:44` 토큰 미노출 어설션 / `:442` 「대기 중」 2개 어설션)은 본 Phase의 명세 이행분(링크 영역 개봉·뷰어 뱃지 분리) — Phase 7 Tester가 스펙을 신규 명세로 갱신.

## 8. Tester에게 제안하는 중점 테스트 영역

### a. 컨트롤러/통합 (minitest)
1. **토큰 매트릭스 5종+초안**: §3 표 그대로 — 404 본문 동일성은 `<main>` 영역 기준 비교(CSRF 메타·request id 제외)로 ②③④⑤ 무차이 검증.
2. **전이**: 최초 열람 issued→viewed 1회(이벤트 first=true), 재열람 viewed 유지(first=false·횟수 증가), 미열람 상태 유지(만료 링크·무효 링크는 이벤트 0건).
3. **경합(이슈 #2 회귀 방지)**: 2스레드 동시 GET — `Invoice.reload.status=viewed` 보장(전이 1회)은 반드시 통과, first 중복 가능성은 허용 범위로 명시.
4. **재발급**: 303 + 신규 토큰·`token_expires_at` 불변, 이전 토큰 404(본문 동일), 기존 ViewEvent 잔존, 타 사용자 id·draft/voided id PATCH → 404(linkable 스코프). per-form CSRF 유의(기술 노트 1 — 해당 폼 토큰 사용).
5. **422 재렌더**: set_view_events 순서 보전 — issue/void/regenerate 실패 경로에서 show가 @view_events로 정상 렌더(기술 노트 6).
6. **device·시각**: 모바일 UA/PC UA/UA 부재(→pc) device 판별, viewed_at·열람 이력 KST 표시(`display_datetime`).
7. **noindex(SURF-3)**: `/b/*` robots 메타 출력 + 랜딩 noindex 없음 회귀 + robots.txt.
8. **기존 실패 2건 갱신**: 발행 상세 전체 URL(토큰 포함) 노출 어설션, viewed 뱃지 「열람」 분리 어설션.

### b. 시스템 테스트 (capybara 신설 — 플랜 결정 #3)
`test/application_system_test_case.rb`·`test/system/` 미생성 — 먼저 케이스 파일 생성(selenium-webdriver 4.50 Selenium Manager, 로컬 Chrome 필요).
1. **뷰어 여정 E2E**: 발행 → 링크 복사(clipboard mock) → 뷰어 렌더(VIEW-2/3/5 문구·금액 분해) → 계좌 카드 탭 → 「복사됨」 피드백 → ② 새로고침 「열람」 뱃지·열람 이력 표시.
2. **VIEW-8 DOM 검증**: 뷰어 렌더에서 `a[href]` 0개·내비/푸터 셀렉터 부재 — 회귀 감지 자동화.
3. **클립보드 fallback**: `navigator.clipboard` 거부 환경에서 source 선택 + 「선택됨 — 복사해 주세요」 라벨(iOS `select()` 쿼크 포함 관찰).
4. **VIEW-6 여정**: 만료 링크 → 안내 문구·링크 없음 확인.

### c. 수동 실기 QA (VIEW-1 필수)
1. **카카오톡 인앱**(Android 최신·Android 구형 WebView·iOS): 레이아웃·계좌 복사·버튼 동작 + **이슈 #1 allow_browser 406 재현 여부** — 구형 단말에서 406이 확인되면 표면 ③ 완화를 오케스트레이터에 보고.
2. **PERF-2**: 인앱 첫 화면 2초 계측(CDN 폰트·전역 번들 로드 포함).
