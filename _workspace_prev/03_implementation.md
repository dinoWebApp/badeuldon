# 03_implementation.md — F-PROMISE 응답(약속) 수집 구현

- **일자**: 2026-10-13
- **범위**: `_workspace/01_plan.md` 승인 플랜 전체 (A-1~A-4) · 후속 제외 항목(PROMISE-3 재스케줄, PROMISE-4/7 발송, PROMISE-5, PDF, 답변 알림)은 미구현 확정 준수
- **기준 문서**: PRD v0.18.6 §6.7·§6.11·§6.9·§6.4, `_workspace/02_prd_update.md` 승인 해석

## 1. 변경 파일

### 신규
| 파일 | 내용 |
|---|---|
| `db/migrate/20261013000001_create_promises.rb` | promises 테이블 — invoice FK(references, null: false), kind(null: false), promised_on(date, null 허용), memo/answer(text), answered_at, timestamps. invoice_id 인덱스 + FK |
| `app/models/promise.rb` | kind enum 4종, answered/unanswered 스코프, kind별 검증, this_week 약속일 산정(before_validation), `answer!`(PROMISE-6 유일 기록 경로) |
| `app/services/promises/register_service.rb` | 응답 접수 단일 진입점 — Promise 저장 + INV-4 전이를 1트랜잭션으로. 실패는 `InvalidResponse`(실패 Promise errors 동봉) |
| `app/controllers/app/promises_controller.rb` | `#answer` — 무답변 inquiry 답변 등록. 소유권은 `Current.user.invoices.select(:id)` 서브쿼리로 격리 |
| `app/helpers/app/promises_helper.rb` | `promise_kind_label` — PROMISE-1 버튼 원문을 U1 화면 라벨로 인용(P1 어휘 일치) |
| `app/views/viewer/promise_thanks.html.erb` | 완료 화면 — 「감사합니다. 발행인에게 전달했습니다.」 + 청구서 복귀 링크(③→③) |

### 수정
| 파일 | 내용 |
|---|---|
| `app/models/invoice.rb` | `has_many :promises, dependent: :destroy` + `mark_promised!`(issued\|viewed→promised 조건부 UPDATE 원자 전이 — `mark_viewed!` 패턴 재사용) |
| `app/controllers/viewer_controller.rb` | `set_invoice` before_action으로 토큰 가드 통합(열람·응답·완료 전 경로 공통 — 만료·폐기·미존재 동일 404), `create`(POST 접수 → 303 PRG, 실패 422 재렌더), `promise_thanks`, **rate_limit 토큰당 10회/10분(:create 한정)**, show가 답변 표시용 `@answered_inquiries`·폼 베이스 `@promise` 적재 |
| `app/controllers/app/invoices_controller.rb` | `set_promises`(최신 우선) before_action — 422 재렌더 대응은 `set_view_events`와 동일 취지 |
| `app/controllers/app/dashboards_controller.rb` | `load_action_items` — DASH-2 마감 대기·답변 대기 실데이터 쿼리 |
| `app/views/viewer/show.html.erb` | PROMISE-6 발행인 답변 표시 섹션 + VIEW-4 응답 액션 섹션(버튼 4종 — PROMISE-1 원문 문구) |
| `app/views/app/invoices/show.html.erb` | 응답·약속 이력 타임라인(최신 우선 + 「최신」 배지, 약속일·접수시각·문의 메모·답변 상태) + 무답변 inquiry 답변 폼 |
| `app/views/app/dashboards/show.html.erb` | DASH-2 — 마감 대기·답변 대기 조건부 카드, 무액션일 때만 기존 빈 상태 유지 |
| `config/routes.rb` | `viewer_promises`(POST /b/:token/promises), `viewer_promise_thanks`(GET …/thanks), `answer_app_promise`(PATCH /app/promises/:id/answer) |

## 2. 핵심 구현 지점

### INV-4 전이(issued|viewed→promised)
- `Invoice#mark_promised!` — `status IN (issued, viewed)` 조건부 UPDATE 단일 쿼리로 원자화(동시 응답에서도 1회 적용). `mark_viewed!`와 동일 패턴이며 status는 INV-5 보호 컬럼이 아님 → 본문 불변 가드와 무충돌.
- 실행 지점: `Promises::RegisterService#call` — `promise.save!`와 동일 트랜잭션. **this_week·date_selected만** 호출, paid_report·inquiry는 호출 자체가 없어 상태 불변(PROMISE-7). 이미 promised인 재응답은 조건 불일치로 무변경(이력은 계속 쌓임).

### 「이번 주」 금요일 산정(결정 #1)
- 지점: `Promise#compute_this_week_promised_on`(before_validation, this_week 한정) — **서버가 KST 접수일 기준 산정, 클라이언트 입력 일절 수신 안 함**(PROMISE-2).
- 산식: `Date.current.beginning_of_week + (토·일 ? 11 : 4)` — 주 시작 월요일 기준. 월~금 접수 → 이번 주 금요일(+4), 토·일 접수 → 다음 주 금요일(+11). REM-3 평일 발송 기준과 정합(약속일이 주말이 되지 않음).
- 실측(러너): 수 10-14→10-16, 금 10-16→10-16(본일), 토 10-17→10-23, 일 10-18→10-23 전부 통과.

### 약속 변경(재응답)
- 이력 보존: 기존 Promise 레코드 유지, 새 레코드 추가(P4 — 응답 이력 영구 기록).
- 최신 기준: U1 타임라인·뷰어 데이터 모두 `order(created_at: :desc, id: :desc)` — 첫 행(최신)이 현재 약속 기준이며 「최신」 배지로 표시.

### 뷰어 응답 경로(P3·VIEW-8)
- 버튼 4종은 PROMISE-1 **원문 문구** 그대로. 즉시 응답 2종은 `button_to`, 입력 2종은 `<details>` 네이티브 접기 + native date input(min=오늘) — **JS 없이 카카오톡 인앱에서 동작**(VIEW-1).
- P3 검증: 파라미터 화이트리스트는 `kind·promised_on·memo`뿐 — `answer`(U1 전용)는 채무자 경로에 절대 없음. 렌더 실측에서 가입·개인정보 유도 문구 0건.
- 완료 화면은 GET으로 PRG 전환해 재제출·이중 접수 방지. 만료·폐기 토큰은 응답·완료 경로도 `set_invoice` 가드로 동일 404.
- 스팸 방지: `rate_limit to: 10, within: 10.minutes, by: -> { params[:token] }`(Rails cache 기반, :create 한정 — 콜백 등록 실측 확인). 초과 시 Rails 기본 429.

### DASH-2 첫 실데이터
- 마감 대기: `invoices.unsettled.where(id: Promise.paid_report.select(:invoice_id))` — 입금 완료 회신이 있고 미마감(paid·voided 제외)인 청구. 마감 자체는 PAY 도메인(후속).
- 답변 대기: `Promise.inquiry.unanswered` — 청구서 상세 답변 폼으로 연결.

## 3. Rule ID 매핑

| Rule ID | 구현 |
|---|---|
| PROMISE-1 | `viewer/show.html.erb` 액션 섹션 — 원문 문구 4종(this_week/date_selected/paid_report/inquiry), `Promise` kind enum |
| PROMISE-2 | 토큰=권한 비인증 POST(`viewer#create`), 가입·개인정보 입력 전무(파라미터 3종 화이트리스트·렌더 실측), `promise_thanks` PRG |
| PROMISE-6 | `Promise#answer!`(1문의 1답변 — 무답변 inquiry 1회 한정, answered_at 유일 기록 경로), `App::PromisesController#answer`(303/422·소유권 격리), 뷰어 「발행인 답변」 표시, DASH-2 답변 대기 |
| PROMISE-7 | paid_report 접수 시 상태 불변 + DASH-2 마감 대기 카드 — 수금 마감은 PAY·U1 확인으로만(이번 범위는 회신 기록·표시까지). 알림 발송(②)은 채널 미계약으로 DASH-2 표시로 갈음(02 승인 해석) |
| INV-4 | `Invoice#mark_promised!` — issued\|viewed→promised 원자 조건부 전이 |
| VIEW-4 | 뷰어 응답 액션 섹션 개봉(버튼 4종 — PDF는 후속) |
| VIEW-8 · SURF-2/4 | 액션·답변 표시는 화이트리스트 허용 요소(응답 액션·청구 내용·고지문). 앵커 0개 렌더 실측, 전용 레이아웃 유지, 완료 화면 링크는 ③→③ 복귀뿐 |
| DASH-2 | 「마감 대기」「답변 대기」 조건부 카드 + 기존 빈 상태는 무액션일 때만 유지 |
| P1 | 완료 문구·에러 안내·버튼 문구 톤 준수(요구·압박 0), U1 라벨도 채무자 원문 어휘 인용 |
| P2 | 발행인 답변은 서비스 경유 표시 — 연락처·개인 번호 노출 요소 없음 |
| P3 | 응답 경로 전체 비가입·무입력(§2 뷰어 응답 경로 참조) |
| P4 | 재응답도 이력 전부 보존, `dependent: :destroy`는 초안 삭제 연쇄 한정(발행 계열은 삭제 불가) |
| TIME-1 | 산정·검증 전부 `Date.current`/`Time.current`(앱 TZ Seoul), 주말 약속일 회피(REM-3 정합) |
| SEC-5 해당 없음 확인 | 발송 로직 부재(REM 후속) — 기록 경로는 이력 추가형이라 멱등성 제약 대상 아님 |

## 4. 테스트 — 실패 예상 목록

- **없음.** `bin/rails test` **258 runs, 0 failures, 0 errors, 0 skips** — 기존 테스트 파일은 1줄도 수정하지 않았다.
- 신규 테스트는 작성하지 않음(지시 준수 — Phase 7 Tester 갱신 대상). 아래 러너 실측으로 대체 검증.

### 러너 실측(트랜잭션 롤백 — 잔재 0 확인: 실행 후 `Promise.count == 0`)
- 4종 등록 + 상태: this_week(issued→promised), date_selected(viewed→promised), paid_report·inquiry(상태 불변) — 24/24 PASS
- 금요일 산정 4분기: 수·금(본일)·토·일 접수 — PASS
- 과거 날짜 차단: 어제 지정 InvalidResponse, 당일 허용, 차단 건 상태·이력 무변화 — PASS
- 재응답: 이력 2건 보존 + 최신 기준 표시 — PASS
- 검증: 빈 문의·memo 2,001자·조작 kind → InvalidResponse — PASS
- 문의→답변: 등록·answered_at·재답변 차단·answered/unanswered 스코프 — PASS
- 소유권: 타인 청구서 응답은 `Current.user.invoices` 서브쿼리 스코프 밖 — PASS
- 렌더 실측: 뷰어 show(버튼 4종·min=오늘·발행인 답변·POST 경로·앵커 0개·가입 유도 0) + 완료 화면 문구·복귀 링크 — 11/11 PASS

## 5. 자체 점검 결과

| 게이트 | 결과 |
|---|---|
| `bin/rails zeitwerk:check` | 통과 ("Otherwise, all is good!") |
| `bin/rubocop` | **0 offenses** (85 files) |
| `bin/rails db:migrate` | 성공 — `db/schema.rb`에 promises 테이블·invoice_id 인덱스·FK 반영 확인 |
| `bin/rails test` | 258 runs / 1567 assertions / 0 failures / 0 errors / 0 skips |
| 러너 실측(롤백) | 비즈니스 로직 24/24 + 렌더 11/11 PASS, DB 잔재 0 |
| 뷰어 무결성 | 마케팅·내비·가입 유도 0, noindex 유지, 앵커 0(VIEW-8·SURF-3/4) |
| rate_limit 주의점 | test 환경 cache_store=null_store라 증분이 무시됨(차단 미동작) — Phase 7 테스트에서 rate_limit 회귀 검증 시 memory_store 주입 필요 |

## 수정 이력 (Phase 6)

- **일자**: 2026-10-13 · **범위**: `_workspace/05_review.md` WARNING 3건 최소 수정(#4는 F-REM 백로그 이관 — 미수정 확정). 리뷰 이슈와 1:1 대응, 범위 외 변경 없음(기존 테스트 파일 0건 수정).

### 이슈별 매핑

| 이슈 | 수정 내용 | 파일 |
|---|---|---|
| **#1** kind별 필드 일관성(무결성 보조) | `Promise`에 `before_validation :normalize_kind_fields` 추가 — date_selected 외 kind의 클라이언트 `promised_on`과 inquiry 외 kind의 `memo`를 **서버가 nil 강제 무시**로 통일(this_week는 기존 서버 산정 콜백이 덮어쓰므로 산정값 보존 위해 정규화 콜백을 먼저 선언). 검증 오류 대신 무시를 택한 이유: 위조 요청을 422로 막을 필요는 없고(정상 UI로는 발생 불가한 조작 입력) 저장 자체를 안전한 값으로 수렴시키는 편이 P4 이력 무결성에 충실. U1 타임라인(`show.html.erb:127` `promised_on.present?` 분기)이 「이미 입금했어요」 행에 위조 약속일을 표시하는 경로 원천 차단 | `app/models/promise.rb` |
| **#2** `answer!` :base 에러 미표시(PROMISE-6 UX) | `App::PromisesController#answer` 실패 분기에 `flash.now[:alert]` 추가 — 레이아웃 플래시(`layouts/_flash.html.erb`, application 레이아웃 렌더 확인)로 표시. 폼 인라인 표시 대신 플래시를 택한 이유: 422 재렌더 시 폼은 `load_invoice_show`가 재적재한 최신 이력으로 그려져 errors를 지니지 않고(인스턴스 불일치), 재답변 차단 건은 애초에 「답변 완료」로 렌더되어 폼이 그려지지 않음 — 페이지 수준 안내가 유일한 표시 지점. 문구는 `full_messages_for(:base).first \|\| errors[:answer].first` — :base는 접두사 없는 원문, :answer는 폼 인라인(`form_error_message`)과 동일 원문(러너 실측에서 `full_messages.first`는 「Answer 」 접두사 오염 확인 후 원문 방식으로 확정) | `app/controllers/app/promises_controller.rb` |
| **#3** U1 대면 용어 통일(P1) | 답변 등록 notice 「채무자가 청구서 링크에서 확인할 수 있습니다」→「**거래처**가 …」 — 같은 화면 폼 placeholder(show.html.erb:146)·기존 U1 UI 용어와 통일 | `app/controllers/app/promises_controller.rb` |
| **#4** `mark_promised!` overdue 조건 | **미수정 확정** — 연체는 파생 판정(저장 status는 issued/viewed 유지)이라 실결함 없음. F-REM 연체 저장화 시점에 조건 재검토(F-REM 백로그 이관 기록) | — |

### 자체 점검 (실측)

| 게이트 | 결과 |
|---|---|
| `bin/rubocop` | 0 offenses (전체 85 files + 수정 후 변경 2파일 재검) |
| `bin/rails zeitwerk:check` | 통과 ("Otherwise, all is good!") |
| 러너 실측(트랜잭션 롤백 — 잔재 `Promise.count=0`·신규 User 0) | **13/13 PASS** — #1: paid_report에 `promised_on=2026-12-01`+memo 주입 → 저장값 둘 다 nil(U1 타임라인 약속일 행 미표시 조건 확인), inquiry에 promised_on 주입 → nil·memo 보존. 회귀: this_week 조작값(1999-01-01) → 서버 산정 금요일로 덮어쓰기 유지, date_selected 클라이언트값 유지. #2: 첫 답변 성공 → 재답변 false + 플래시 식 산출값 「문의에는 한 번만 답변할 수 있습니다」 일치(답변 값 미변경), 빈 답변 false + 「답변 내용을 입력해 주세요」 일치. #3: 문자열 치환(edit 결과로 확인 — notice가 show.html.erb:146 placeholder와 동일 「거래처」 어휘) |
| 기존 테스트 | 미실행(지시 준수 — 서버 기동·테스트 작성 금지, Phase 7 Tester 대상). test/ 파일 변경 0건 |

## 수정 이력 (Phase 6b — 스플랫 버그)

- **일자**: 2026-10-13 · **범위**: Phase 7 Tester 실측 버그 1건(뷰어 등록 POST 전부 500) 최소 수정 — `app/controllers/viewer_controller.rb` 1파일, 범위 외 변경 없음(테스트 파일 0건 수정).

### 원인
- `ViewerController#create`(수정 전 `viewer_controller.rb:30`)가 `Promises::RegisterService.new(invoice: @invoice, **promise_params).call`로 스플랫. `promise_params`는 `params.expect`가 돌려주는 **문자열 키** `ActionController::Parameters`인데, Ruby 4.0에서 문자열 키 해시의 `**` 스플랫은 심볼 키워드로 바인딩되지 않는다 → `ArgumentError: missing keyword: :kind` → 앱 에러(500).
- Ruby 4.0.7 단독 재현: `def m(kind:); end; m(**{"kind"=>"x"})` → `ArgumentError: missing keyword: :kind`. 앱에서 `**params` 스플랫은 이 곳이 유일(Phase 7 Tester grep 확인).

### 수정
- 스플랫 제거, 키 명시 추출로 교체 — `kind:`/`promised_on:`/`memo:`를 `promise_params[...]`로 직접 바인딩(`ViewerController#create`).
- 명시 추출을 택한 이유: ① Ruby 버전별 스플랫 키 변환 의존 제거 ② kind 누락 등 이례 입력이 `ArgumentError`(500)가 아니라 서비스의 `InvalidResponse` 계약(기존 rescue → 422)으로 수렴. `to_h.symbolize_keys` 스플랫도 바인딩 자체는 해결하지만 `promise: {}` 입력 시 빈 해시 스플랫이 다시 `missing keyword` 500을 만들 수 있어 기각.

### HTTP 경로 실측(러너 통합 세션 — `bin/rails runner -e test`, 외부 트랜잭션 롤백 / Ruby 4.0.7)
| 단계 | 결과 |
|---|---|
| GET /b/:token (열람) | 200 |
| **POST /b/:token/promises (kind=this_week)** | **303 See Other — 500 소멸**, Location = thanks 화면(PRG) |
| 사후 상태 | invoice `issued→promised`(INV-4 전이), promise kind=this_week · promised_on=2026-10-16(화 10-13 접수 → 서버 산정 금요일, 결정 #1 산식 유지) |
| 잔재 | 롤백 후 검증용 Invoice 0 · User 0. test DB에 본 실측 이전부터 존재하던 타 건 5행은 미변경(본 실측 생성분 아님) |

### 자체 점검
- `bin/rubocop` **0 offenses**(92 files) · `bin/rails zeitwerk:check` 통과("Otherwise, all is good!")
- 실측용 임시 스크립트(`tmp/verify_splat_post.rb`)는 측정 직후 삭제 — 저장소 잔재 없음

