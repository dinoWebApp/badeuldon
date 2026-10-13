# 07_test_report.md — F-PROMISE 응답(약속) 수집 Phase 7 테스트

- **일자**: 2026-10-13 · **테스터**: PromiseTester
- **대상**: `_workspace/03_implementation.md`(Phase 6 수정 3건 포함) 구현 전체 — 응답 4종 접수, 금요일 산정(결정 #1), INV-4 전이, 비인증 경로 보안, PROMISE-6/7, DASH-2, rate_limit
- **기준**: PRD v0.18.6 §6.7(175-178 버튼 원문 대조 확인)·§6.11·§6.9·§6.4, `_workspace/05_review.md` §Tester 9건
- **코드 수정**: 0건(규칙 준수 — 실패는 전부 원인 분류 후 보고). 신규 테스트 파일 8종 + fixture 1종

## Status: 코드 버그 1건 검출 → Developer 수정 완료 → **전 스위트 GREEN**

- **BLOCKER 1(코드 버그)**: `ViewerController#create` 전 POST 경로 500 — Developer 수정(키워드 명시 추출) 랜딩 후 **재실행 전부 통과**(§6). 테스트 오류 4건은 자체 수정하여 해소(`answered?` 부재 메서드 2건·스코프 기대값 누락 1건·프로필 미완료 사용자 가드 간섭 1건)

## 1. 실행 결과 요약 (최종 — 코드 수정 반영 후 재실행)

| 스위트 | runs | 통과 | 실패 | 오류 | 비고 |
|---|---|---|---|---|---|
| 전체 `bin/rails test` | **323** | **323** | **0** | **0** | 기존 258건 회귀 0 + 신규 65건 전부 통과 (1,913 assertions) |
| 시스템 `bin/rails test:system` | **4** | **4** | **0** | **0** | 기존 3건 + 신규 응답 여정 1건 |
| `bin/rubocop`(전체) | 92 files | — | — | — | **0 offenses** |
| `bin/rails zeitwerk:check` | — | — | — | — | 통과 ("Otherwise, all is good!") |

### 파일별 결과

| 파일 | runs | 결과 |
|---|---|---|
| `test/models/promise_test.rb` (신규) | 22 | **22/22 PASS** — 금요일 산정 5분기+주말 금지+주입 덮어쓰기, date_selected 당일/어제/빈값, memo 0/2,000/2,001, kind별 정규화 4종, 1문의 1답변, 스코프 |
| `test/services/promises/register_service_test.rb` (신규) | 13 | **13/13 PASS** — 4종 접수·INV-4 전이·PROMISE-7 상태 불변·paid/voided/연체 시도(설계 의도)·재응답·조건부 UPDATE 멱등·트랜잭션 롤백·위조 kind·과거 차단 |
| `test/controllers/viewer_promises_test.rb` (신규) | 15 | **15/15 PASS** — 렌더 3건 + POST 12건(4종 등록 303·과거 422·위조 422·주입 무시·재응답·이중 제출) |
| `test/controllers/app/promises_controller_test.rb` (신규) | 6 | **6/6 PASS** — 답변 303·뷰어 표시·재답변 422 flash.now(Phase 6 #2)·빈 답변 422·타인 문의 404·이력 최신 배지 렌더 |
| `test/controllers/app/dashboards_actions_test.rb` (신규) | 5 | **5/5 PASS** — 마감 대기/답변 대기 카드·소멸 조건 2종·소유권 격리·빈 상태 회귀 |
| `test/controllers/viewer_promises_rate_limit_test.rb` (신규) | 4 | **4/4 PASS** — 유효 토큰 11회째 429·토큰별 분리·무효 토큰 카운트(404 가드 선행)·GET 미적용 |
| `test/system/viewer_promise_test.rb` (신규) | 1 | **1/1 PASS** — 버튼→감사 화면→③ 복귀 여정 + promised 전이·금요일 산정 실측 |

## 2. 코드 버그 — `ViewerController#create` 전 POST 500 (검출 → Developer 수정 완료 → 재검 PASS)

**판정: 코드 버그(테스트 오류 아님). 코드 수정 금지 원칙에 따라 직접 수정하지 않고 Main에 Developer 수정 위임 보고 → Developer 수정(`viewer_controller.rb` — 키워드 명시 추출) 랜딩 후 재실행 전부 통과.**

- **증상**: 수정 전 `RegisterService.new(invoice: @invoice, **promise_params)`가 실제 POST 전부에서 `ArgumentError (missing keyword: :kind)` → 500. 응답 접수 기능이 런타임에서 동작하지 않았다.
- **원인(실측 확정)**: 프로젝트 런타임 **Ruby 4.0.7**에서 문자열 키 double-splat이 symbol 키워드에 바인딩되지 않는다. 최소 재현(바닐라 ruby): `def m(kind:); end; m(**{"kind"=>"x"})` → `ArgumentError`. `params.expect(promise: [...])`는 string-keyed Parameters를 반환하므로 kind가 전달되지 않는다. Ruby 3.x 자동 변환에 의존하던 코드로, 서비스 직접 호출(러너 실측)·정적 검토(리뷰)로는 검출되지 않았다.
- **검출 경로**: Phase 7 신규 통합 테스트(컨트롤러 POST 계층) — 기존 스위트에 viewer#create POST 테스트가 없어 미검출이었다.
- **수정 내용**: `kind: promise_params[:kind], promised_on: promise_params[:promised_on], memo: promise_params[:memo]` 명시 추출(스플랫 사이트는 앱 전체에서 이곳이 유일 — grep 실측). kind 누락 등 이례 입력도 기존 InvalidResponse(422) 계약으로 수렴 — 위조 kind 422 테스트가 회귀 가드.
- **재검**: §6 재실행 목록 전부 PASS — viewer POST 12건·rate_limit 유효 토큰 2건·시스템 여정 1건 포함 전 스위트 0 failures/0 errors.

## 3. 시나리오별 결과 — 지시 시나리오 대응

### 응답 4종(뷰어 경로) — **PASS(POST 계층 포함)**
| 시나리오 | 결과 | 근거 |
|---|---|---|
| this_week 등록 303·감사 화면·전이 | **PASS** — 303 PRG → 감사 화면(폼 0건) → promised 전이·이력 1건 | viewer_promises_test |
| PROMISE-1 원문 버튼 문구 렌더 | **PASS** — PRD §6.7 175-178 원문 4종과 1자 일치(assert_select) | viewer_promises_test |
| date_selected 당일·미래 | **PASS** — 10-16(당일)·10-30(미래) 303, 저장값 확인 | viewer_promises_test |
| paid_report | **PASS** — 303 접수·상태 issued 불변·약속일 nil | viewer_promises_test |
| inquiry memo 필수·빈값 422 | **PASS** — 빈값 422 + 안내 문구 + 잔재 0, 메모 정상 등록 303 | viewer_promises_test |
| P3 개인정보 필드 부재 렌더 | **PASS** — password/email input 0건, 무가입 문구, 완료 화면 앵커 ③→③ 한정 | viewer_promises_test |

### 금요일 산정(travel_to, KST) — **5분기 전부 PASS**
| 접수일 | 기대 | 실측 |
|---|---|---|
| 2026-10-12(월) | 10-16(금) | 10-16 ✓ |
| 2026-10-14(수) | 10-16(금) | 10-16 ✓ |
| 2026-10-16(금) | **당일 10-16** | 10-16 ✓ |
| 2026-10-17(토) | 10-23(다음 주 금) | 10-23 ✓ |
| 2026-10-18(일) | 10-23 | 10-23 ✓ |

- 약속일 주말 금지(REM-3 정합)·클라이언트 주입값(1999-01-01) 서버 덮어쓰기 — 모델·서비스·컨트롤러 3계층 검증(컨트롤러 this_week POST 저장값 실측 포함).

### 과거 날짜 — 서버 재검증 — **PASS(3계층)**
- 어제 지정(min 속성 우회 POST) → 422 + 「입금 예정일은 오늘 또는 그 이후」 + 상태·이력 무변화: POST 계층 실측 포함, 모델(어제 차단·당일 허용)·서비스(InvalidResponse·잔재 0) 계층 동일 확인.

### 전이(INV-4)
| 시나리오 | 결과 |
|---|---|
| issued→promised(this_week) | **PASS**(서비스) |
| viewed→promised(date_selected) | **PASS**(서비스) |
| paid·voided 청구서 약속 시도 | **PASS — 설계 의도 확인**: 전이 없음(조건부 UPDATE 0행)·Promise 이력은 기록됨(이력 추가형 설계). 뷰어 진입 자체는 토큰 가드가 차단하므로 실제 도달 불가 경로다 |
| 연체(저장 상태) 약속 시도 | **PASS — 리뷰 이슈 #4 재확인**: promised 전이 불가·이력 기록. F-REM 백로그 사안으로 현행 유지가 리뷰 확정과 일치 |
| 동시 응답 원자성(전이 1회) | **PASS** — `mark_promised!` 2회 호출 시 2회째 false(0행 갱신), 이중 POST 시 전이 1회·이력 2건. 전이 단계 강제 실패 주입 시 기록까지 롤백(1트랜잭션 실측) |
| 재약속 — 이력 2건·최신 표시 | **PASS** — fixture 2건 청구서에 제3의 응답 추가 → 이력 3건·`created_at desc, id desc` 첫 행이 최신, app 상세 「최신」 배지 첫 행 렌더 확인 |

### PROMISE-7 — **PASS**
- paid_report 접수 후 청구서 상태 불변(issued/promised 어느 쪽도) — 서비스 계층.
- DASH-2 「마감 대기」 카드 표시(델타파트너스 · 330,000원 + 안내 문구 + 청구서 링크).
- **표시 소멸 조건(설계 확인·기록)**: 카드 조건은 `unsettled ∩ paid_report` — 마감 확정(paid) 전까지 **카드가 지속되는 것이 정당**하다. 마감 자체는 PAY 도메인(후속)으로 U1 확인 경로만 존재하며, paid 전환 시 카드 소멸을 실측으로 확인(테스트: `update!(status: :paid)` → 카드 0건·답변 대기 카드는 유지). PRD ② U1 알림은 02 승인 해석대로 DASH-2 표시로 갈음.

### PROMISE-6 — **5/5 PASS**
- 답변 등록 303 + notice 「…거래처가…」(Phase 6 #3 용어) + answered_at KST 기록.
- 뷰어 「발행인 답변」 표시(답변 본문 + 답변 시각) — 답변 직후 실측 + fixture 기준.
- 재답변 차단 422 + **flash.now `#alert` 「문의에는 한 번만 답변할 수 있습니다」**(Phase 6 #2 — 기존 답변 값·시각 불변 확인).
- 빈 답변 422 + `#alert` 「답변 내용을 입력해 주세요」 + answered_at 불변.
- 타인 문의 답변 404(소유권 서브쿼리 격리 — 기록 무손상).
- DASH-2 답변 대기 카드 → `answer!` 성공 후 카드 소멸.

### 비인증 보안(Phase 6 #1 포함)
| 시나리오 | 결과 |
|---|---|
| paid_report + promised_on 주입 | **PASS** — 저장값 nil(U1 타임라인 약속일 행 오염 원천 차단), memo 주입도 nil |
| inquiry + promised_on 주입 | **PASS** — nil 저장·memo 보존 |
| this_week 조작값(1999-01-01) | **PASS** — 서버 금요일로 덮어쓰기, memo 무시 |
| answer·invoice_id 주입 | **PASS** — answer nil(U1 전용 파라미터 주입 불가)·invoice_id는 라우트 토큰으로만 결정 |
| 위조 kind(“hacker”/“0”/“”/nil) | **PASS** — POST 계층 422 + 일반 문구(enum 정보 누출 없음), 서비스 계층 동일 확인 |
| 무효 토큰 create·thanks | **PASS** — 열람과 동일 VIEW-6 404 |

### rate_limit — 05_review 기법 결과
- **기법**: 런타임 `Rails.cache` 교체는 무효(클래스 로드 시점 캡처) → **test 환경 스토어(NullStore)의 `#increment`만 MemoryStore로 위임**하는 런타임 주입으로 원래 rate_limit 선언을 그대로 통과. 사전 러너 실측으로 `ViewerController.config.cache_store.equal?(Rails.cache) == true` 확인(캡처 대상 = Rails.cache 동일 객체), 파일 수정 0건·setup 주입/teardown 복원.
- **실측**: 무효 토큰 10회 404 후 **11회째 429**(404 가드보다 rate_limit 선행 확인), 유효 토큰 10건 후 **11회째 429 + 기록 10건**, 타 토큰은 자기 카운터로 차단 없음(토큰별 분리), GET show 12회 미적용(only: :create). 전부 PASS.
- 기법 실패 시 스킵 사유 기록 요건 — **해당 없음(성공)**.

### DASH-2 분기 — 기존 어설션 회귀 포함 **PASS**
- 무액션(청구서 0건·타인 데이터만 존재) → 빈 상태 문구 유지(기존 어설션과 동일 결과).
- 유액션 → 빈 상태 소멸·카드만 렌더. 소유권 — delta 소유 회신/문의가 gamma 대시보드에 비노출.

## 4. 회귀

- 기존 258건: `promises.yml` 추가로 `fixtures :all`이 전 테스트에 Promise 행을 적재하지만 **기존 스위트 실패·오류 0건** — 충돌 소지 파일(뷰어 토큰 매트릭스·앱 상세·대시보드 빈 상태) 렌더 구조 사전 대조로 fixture 배치(delta_issued/overdue/paid/voided/draft는 응답 0건 유지) 설계.
- 최종: `bin/rails test` **323 runs / 1,913 assertions / 0 failures / 0 errors / 0 skips**, `bin/rails test:system` **4 runs / 0 failures / 0 errors**.
- `bin/rubocop` 전체 92 files **0 offenses**, `bin/rails zeitwerk:check` 통과(Developer 코드 수정 반영 후 전 게이트 재확인).

## 5. 원인 분류 총표

| 분류 | 건수 | 내역 |
|---|---|---|
| 코드 버그 | **1종(15건 재현)** | viewer#create 키워드 스플랫(Ruby 4.0 문자열 키 미바인딩) — §2. Developer 수정 위임 → 수정 → 재검 PASS |
| 테스트 오류 | 4건(자체 수정 해소) | `answered?` 부재 메서드 2건, 스코프 기대값이 비-답변 fixture 3건 누락 1건, beta(AUTH-1.3 미완료) 가드 간섭으로 404 검증 불가 → gamma 교체 1건 |

## 6. 재검 실행 이력(§2 수정 랜딩 후 — 전부 완료)

1. `test/controllers/viewer_promises_test.rb` POST 12건 — **PASS**(4종 등록 303·과거 422·위조 422·주입 무시·재응답·이중 제출)
2. `test/controllers/viewer_promises_rate_limit_test.rb` 유효 토큰 2건 — **PASS**(11회째 429·토큰별 분리)
3. `test/system/viewer_promise_test.rb` — **PASS**(버튼→감사 화면 여정 + promised 전이·금요일 산정)
4. 전체 `bin/rails test`(322 runs) + `bin/rails test:system`(4 runs) 재실행 — **0 failures / 0 errors 달성**
