# 07_test_report.md — F-SHARE 열람 추적 + F-VIEW 뷰어 + 링크 UI 테스트 (Phase 7)

- **일자**: 2026-10-12
- **작성자**: ViewerTester (badeuldon-test-patterns 준거)
- **대상**: F-SHARE 열람 추적·F-VIEW 채무자 뷰어(표면 ③)·발행 상세 링크 UI + **저장소 첫 시스템 테스트(capybara) 도입**
- **시나리오 기준**: `_workspace/03_implementation.md` §2·§4·§5, `_workspace/05_review.md` §3·§7·§8, PRD SHARE-1/2/3·VIEW-2/3/5/6/8·INV-4/6·PAY-3·SURF-1/3/4
- **코드 수정**: **0건** (리뷰 APPROVED — 발견 이슈 전부 테스트 오류로 자체 수정, §4)

---

## 1. 최종 결과

| 항목 | 결과 |
|:---|:---|
| `bin/rails test` 전체 회귀 | **256 runs, 1,548 assertions, 0 failures, 0 errors, 0 skips** ✅ (시드 2회 재실행 동일) |
| `bin/rails test:system` | **3 runs, 17 assertions, 0 failures, 0 errors, 0 skips** ✅ (첫 도입) |
| 기존 대비 | 228 runs(실패 2건) → 256 runs(실패 0건) — 신규 +28 케이스, 시스템 +3 케이스 |
| `bin/rubocop` | **80 files inspected, no offenses** ✅ |
| 코드 수정 | **0건** |
| 외부 API 실호출 | 0건 (대상 로직에 핵클·토스 호출 없음 — stub 불필요) |
| 테스트 DB 오염 | 없음 — 경합 테스트 자체 청소 확인(9개 DB 전수 `viewer-race` 잔존 0) |

### 신규·갱신 파일

| 파일 | 내용 |
|:---|:---|
| `test/controllers/viewer_controller_test.rb` | **신규 14 케이스** — 토큰 매트릭스 5종+초안·최초/재열람 추적·device 판별·VIEW-6 404 본문 무차이·VIEW-8 앵커 0·noindex·원천징수 안내 |
| `test/services/view_events/track_service_test.rb` | **신규 6 케이스** — 서비스 단위(first 플래그·재기록·비-issued 가드)·UA 판별 경계·조건부 UPDATE 계약·**2스레드 실시간 경합**(별도 클래스) |
| `test/controllers/app/invoices_controller_test.rb` | **갱신 2건**(§2) + **신규 8 케이스** — 재발급 303·turbo_confirm·소유권·linkable 스코프·만료 임박/만료 분기·열람 이력 요약 |
| `test/application_system_test_case.rb` · `test/system/viewer_test.rb` | **신규(첫 시스템 테스트)** 3 케이스 — 뷰어 여정·clipboard 복사·fallback·VIEW-6 여정·VIEW-8 DOM |
| `test/fixtures/view_events.yml` | 신규 — delta_viewed 열람 이력 2건(최초 mobile·재열람 pc) |
| `test/fixtures/invoices.yml` | `token_expires_at` 8건 KST 오프셋 명시(§4 #2·#3 — 기존 어설션 영향 0 사전 확인) |

---

## 2. 기존 실패 2건 갱신 (명세 이행분 — 03 §4)

| 기존 테스트 | 갱신 내용 | 결과 |
|:---|:---|:---|
| `상세는 …토큰을 노출하지 않는다`(어설션 :64) | → **「상세는 청구 정보·계좌·품목·금액 내역과 공유 링크 UI를 렌더한다 (INV-1·SHARE-1/6)」** — readonly input에 전체 URL(`viewer_url(token)`) 표시·복사 버튼(`data-action='clipboard#copy'`)·재발급 버튼(`turbo_confirm` 문구 포함) 어설션으로 대체 | ✅ |
| `목록 상태 뱃지는 …`(어설션 :451) | 「대기 중」 count 2→**1**(delta_due_soon만 — delta_issued는 파생 연체로 주황) + **「열람」 count 1** 신설(viewed 뱃지 분리 — delta_viewed) | ✅ |

---

## 3. 시나리오별 결과 (Rule ID → 검증)

### 3.1 토큰 매트릭스 5종 + 초안 (VIEW-6 응답 통일) — 전부 통과

| 시나리오 | 접근 | 결과 |
|:--|:--|:--|
| ① 정상 발행건 | 200·VIEW-2 헤더(발행인 표시명)·청구번호·품목·금액 분해·계좌 카드·PAY-3·VIEW-5 고지 | ✅ |
| ② 만료 | `travel_to` 만료 경과 → 404 + VIEW-6 문구, **전이·이벤트 0건** | ✅ |
| ③ 폐기(voided) | `void!` 후 이전 토큰 → 404 + VIEW-6, 이벤트 0건 | ✅ |
| ④ 미존재 | 랜덤 43자 → 404 + VIEW-6, 이벤트 0건 | ✅ |
| ⑤ 재발급 이전 | `regenerate_token!` 후 이전 토큰 → 404 + VIEW-6 | ✅ |
| (보너스) 초안 | `token`·`token_expires_at` nil 단언 — 뷰어 진입 자체 불가 | ✅ |

- **본문 무차이(누설 금지)**: ②③④⑤의 `<main>` 영역을 추출해 비교 — **uniq 1**(CSRF 메타 등 요청별 랜덤 요소 제외 기준, 05_review §3과 동일). 4건 모두 404.
- **초안·무효 링크 미노출**: voided 상세 `h2 "청구서 링크"` 0건(INV-6).

### 3.2 최초 열람·재열람 추적 (INV-4·SHARE-3) — 통과
- **최초**: 200 + `issued→viewed` 전이 + 이벤트(`first=true`·device·ip 127.0.0.1·`viewed_at` = frozen KST — TIME-1)
- **재열람**: 이벤트 2건(2번째 `first=false`·UA별 device)·**상태 유지·중복 전이 없음**
- **viewed 상태 재방문**: fixtures 2건 + 신규 1건 = 3건, `first=false`, 상태 viewed 유지
- **비-issued 가드(서비스 단위)**: paid 건에 TrackService 호출 → 이벤트는 기록, **상태는 paid 유지**(조건부 UPDATE 0행)
- **조건부 UPDATE 계약**: `mark_viewed!` 1회차 true(1행) → 2회차 **false(0행)** — 동일 전이 정확히 1회(이슈 #2의 핵심 계약)

### 3.3 동시 첫 열람 경합 (이슈 #2 회귀 방지) — 통과
- **2스레드 동시 TrackService 호출**(게이트로 동시 진입 유도, 스레드별 독립 커넥션) → 양쪽 `:ok`(예외 0)·최종 상태 **viewed**(전이 1회)·이벤트 1~2건(`first=true` 중복은 문서화된 허용 범위로 명시)·`first=true` 이벤트 반드시 존재
- 트랜잭션 롤백이 불가한 실커밋 경합이므로 **별도 클래스**(`use_transactional_tests = false`)로 자체 시드·자체 청소(teardown에서 view_events→invoice_items→invoice→client→session→user FK 순 삭제)
- **5회 반복 실행 안정**(1 runs 6 assertions × 5 전부 통과)

### 3.4 device 판별·시각 (SHARE-3·TIME-1) — 통과
- 모바일 UA(iPhone 17.2)→`mobile`, 데스크톱 UA(Chrome 120)→`pc`, **UA 부재·빈값→pc**(서비스 단위)
- `viewed_at` 주입 시각 그대로 기록 — `Time.zone.parse`와 정확 일치(UTC 시프트 없음)
- 발행 상세 열람 이력 요약: 「최초 열람 2026-09-06 09:30」·「최근 열람 2026-09-20 18:05」·「2회」 — KST 표기, 이력 0건이면 요약 미렌더

### 3.5 링크 UI·재발급 (SHARE-1/2/3·표면 ②) — 통과
- **발행 상세 링크 영역**: 전체 URL readonly 표시·복사 버튼·재발급 버튼(`turbo_confirm` 문구 정확 일치·`_method=patch`)
- **재발급 PATCH**: **303** + 새 토큰 43자·**`token_expires_at` 불변**(유효기간 유지)·상태 promised 유지·기존 ViewEvent 잔존 → 이전 토큰 404(VIEW-6)·신규 토큰 200
- **소유권 격리**: 타 사용자(gamma) 재발급 PATCH → **404**·토큰 무변경
- **linkable 스코프**: 초안·voided 재발급 PATCH → **404**(INV-6)
- **만료 표기 3분기**: 만료 7일 이내 「만료 임박 — 2026-11-30까지 열람할 수 있습니다.」/ 경과 「링크 만료 — 유효기간(만기일 + 60일)이 지났습니다.」/ 정상 구간 표기 없음

### 3.6 VIEW-8·SURF-3·PAY-3 — 통과
- 뷰어 본문(정상·무효 모두) **`a[href]` 0개**·`nav` 0개·「로그인」 문구 0건(SURF-4 ③→① 차단)
- noindex 메타 정상·무효 응답 모두 1건·content에 `noindex`(SURF-3) — robots.txt `/b/` 차단은 기존 `surf3_indexing_test` 회귀로 유지
- 원천징수 건 뷰어: 「원천징수 (공급가액의 3.3%)」 −1,650원·**「입금하실 금액」 53,350원**·안내 문구(P1 지급액 관점)

### 3.7 시스템 테스트 (첫 도입 — §5 환경 구성) — 3건 통과
1. **뷰어 여정 E2E**: 발행 링크 접속 → VIEW-2 헤더·청구번호·품목·총액·PAY-3·VIEW-5 고지 표시 → **clipboard `writeText` 스텁으로 실제 전달값 단언**(「신한은행 110-234-567890 김델타」) + 「복사됨」 피드백 → **`a` 요소 0개**(VIEW-8)
2. **클립보드 fallback**: `writeText` 거부 재현 → source 선택(`window.getSelection()` 값 단언) + 「선택됨 — 복사해 주세요」 라벨(05_review §8-b 3)
3. **VIEW-6 여정**: 무효 토큰 → 안내 2문구·청구 내용 미노출·앵커 0개

---

## 4. 원인 분류 — 개발 중 실패 이력 (전부 테스트 오류, 코드 버그 0건)

| # | 증상 | 원인 | 분류 |
|:--|:---|:---|:---|
| 1 | VIEW-5 고지문 `assert_select "p", text:` 불일치 | 고지 `<p>`는 두 문장을 `<br>`로 구분한 단락 — 정확 일치 어설션이 부적합, regex로 수정 | 테스트 오류 |
| 2 | 열람 이력 표기 09:30 기대 ≠ 실제 18:30 | **fixture 무오프셋 datetime 문자열은 UTC로 저장**(KST 표기 9시간 시프트 — 실측 확인) → `viewed_at`에 `+0900` 명시 | 테스트 오류(설계 정정) |
| 3 | 만료 임박 표기 불일치(기대 11-30 ≠ 실제 12-01) | #2와 동일 원인 — `token_expires_at` 무오프셋 저장 시 KST 다음 날이 됨. **`invoices.yml` 8건에 `+0900` 명시**(모델 발행값 = 만기일 end_of_day KST와 의미 일치). 기존 어설션은 `token_expires_at`을 발행 생성 경로(모델 생성값)에서만 비교해 영향 0 — 전수 grep 확인 | 테스트 오류(설계 정정) |
| 4 | 타 사용자 재발급 테스트 TypeError | `assert_no_difference`는 수치 전용(토큰 String에 산술 시도) → before/after 캡처·`assert_equal`로 수정 | 테스트 오류 |
| 5 | 경합 teardown FK 제약 실패 | `delete_all`은 `invoice_items` 연쇄 삭제를 우회 → teardown에 `invoice_items` 선삭제 추가 | 테스트 오류 |

추가 확인(이슈 없음): 05_review §8-a 5번 「422 재렌더 시 set_view_events 순서」는 재현 가능한 실패 경로가 void·재발급에 없음(스코프 before_action이 초안·무효를 404로 선차단)·issue 422의 초안은 이벤트 0건이 구조적으로 확정 — 기존 「4번째 발행 422」 회귀 테스트가 `render :show` 경로를 통과해 간접 검증됨.

---

## 5. 시스템 테스트 환경 구성 내역

| 항목 | 구성 |
|:---|:---|
| 케이스 베이스 | `test/application_system_test_case.rb` 신설 — `ActionDispatch::SystemTestCase` |
| 드라이버 | `driven_by :selenium, using: :headless_chrome, screen_size: [430, 932]` — **모바일 뷰포트 고정**(VIEW-1 모바일 우선·DESIGN-6) |
| 브라우저 | 로컬 **Google Chrome 154.0.8037.98**(macOS arm64) headless |
| 드라이버 관리 | **Selenium Manager 자동**(selenium-webdriver 4.50.0) — chromedriver 별도 설치·PATH 설정 불필요, 최초 실행 시 `~/.cache/selenium` 캐시 생성 |
| 앱 서버 | Puma 8.0.2 in-process(Capybara 기동, 127.0.0.1 랜덤 포트) |
| 데이터 | 기존 fixtures 그대로(`fixtures :all`) — 별도 시드 불필요 |
| 클립보드 | 권한 프롬프트 회피를 위해 `navigator.clipboard.writeText`를 `execute_script`로 스텁 — **실제 전달값을 `evaluate_script`로 단언**(권한 플래그·OS 설정 의존 제거) |
| 헤드리스 실패 | 없음 — pty 환경 변수·가시 브라우저 대체 불필요, 통합 테스트 대체 없이 브라우저 E2E로 완주 |

---

## 6. fixtures 설계 노트

- **`view_events.yml` 신규**: delta_viewed에만 2건(최초 `first=true·mobile`·재열람 `first=false·pc`). issued 계열(delta_issued 등)은 **0건 기준**을 유지해 최초 열람(`first=true`)·만료·폐기 시 「이벤트 0건」을 검증. ip는 RFC 5737/10064 문서화 대역
- **delta 소유 원칙 유지**: alpha·beta는 기존 테스트가 삭제를 단언하므로 이벤트를 붙이지 않음(전 Phase §6 계승)
- **KST 오프셋 명시(TIME-1)**: fixture의 datetime 무오프셋 문자열은 UTC로 직렬화된다(실측 — §4 #2·#3). `token_expires_at`은 모델 발행값과 동일한 의미(만기일 end_of_day KST)로 8건 정정, `viewed_at` 2건 신규 작성 시 오프셋 포함. 헤더 주석에 사유 기록
- **경합 테스트는 fixtures 미사용**: 커밋이 필요해 자체 시드(전용 이메일 사용자·거래처·발행건) + teardown FK 순서 삭제 — 전체 스위트와 DB 오염 없음(9개 DB 잔존 0 확인)

---

## 7. Tester 완료 전 자체 점검

- [x] 관련 Rule ID별 정상/경계/예외 커버 — SHARE-1(토큰 43자·정상 열람)·SHARE-2(만료 경계·재발급·유효기간 유지·만료 임박 7일 분기)·SHARE-3(최초/재열람·device·ip·viewed_at·이력 요약)·VIEW-2/3/5(문구·분해·고지)·VIEW-6(4종 404 본문 무차이·링크 없음)·VIEW-8(앵커 0·nav 0)·INV-4(전이 1회·초안 노출 불가)·INV-6(voided 폐기·재발급 거부·링크 미노출)·PAY-3(입금자명)·SURF-3(noindex)·SURF-4(③→① 없음)·TIME-1(travel_to·viewed_at·이력 KST)
- [x] 외부 API 실호출 0건
- [x] 미사용 정의 0건·`bin/rubocop` **no offenses**(80 files)·들여쓰기 2칸
- [x] 전체 회귀 — `bin/rails test` **256 runs 0 failures**(시드 2회)·`bin/rails test:system` **3 runs 0 failures**
- [x] 경합 테스트 5회 반복 안정·테스트 DB 잔존 0
- [x] 실패 원인 분류 — §4(테스트 오류 5건 자체 수정, 코드 버그 0건)
- [x] 05_review §8-a 1~8·§8-b 1~4 중점 영역 전부 커버(§8-a 5는 구조적 도달 불가 — §4 말미 근거 기록)
