# 03_implementation — 세금계산서 발급 자격 차단·운영 준비 게이트 (2026-11-24, Developer)

플랜(01_plan.md) 설계 확정 사항을 그대로 구현했다. 라우트·마이그레이션 변경 없음.
결제 로직·바로빌 API 호출·과금 금액(300원) 변경 없음. 소유권 제한 3파일
(`Gemfile.lock`·`test/application_system_test_case.rb`·`test/test_helpers/capybara_chrome_compat.rb`)
미접촉 확인(git status 대조).

## 변경 파일 목록

| 구분 | 파일 | 요약 |
|:---|:---|:---|
| **생성** | `config/initializers/tax_invoice.rb` | TAX-4 — 부팅 시 `ENV["TAX_INVOICE_ENABLED"]`를 한 번 읽어 `Rails.application.config.x.tax_invoice_enabled`에 고정. `"true"`만 true(fail-closed). ENV 직접 읽기는 이 파일 한 곳 |
| 수정 | `app/models/tax_invoice.rb` | TAX-4 — `TaxInvoice.feature_enabled?` 클래스 메서드(단일 판정점, config.x만 읽음) |
| 수정 | `app/models/user.rb` | TAX-3 — `tax_invoice_eligible?`(general만 true)·`tax_invoice_ineligibility_notice`(간이과세·면세 문구 단일 출처). `tax_invoice_ready?` 바로 아래 배치 |
| 수정 | `app/services/tax_invoices/create_order_service.rb` | TAX-3 — `IneligibleUser` 예외 신설 + `call` 맨 앞 가드(주문 미생성 — 300원 결제 전 차단 핵심 지점) |
| 수정 | `app/services/tax_invoices/issue_service.rb` | TAX-3 — `verify_guards!` 맨 앞에 자격 가드(GuardFailed, 메시지는 User 단일 출처) |
| 수정 | `app/controllers/app/invoices_controller.rb` | TAX-3/4 — `set_tax_invoice_context` 판정 우선순위 재배열 + `@tax_invoice_guard_notice` 신설(뷰 문구 공급) |
| 수정 | `app/controllers/app/tax_invoices_controller.rb` | TAX-4 — `require_tax_invoice_feature`(new·create 한정 before_action), TAX-3 — `issue_guard_message` 맨 앞 자격 판정, create에 `IneligibleUser` rescue(안내 리다이렉트 수렴) |
| 수정 | `app/controllers/app/tax_invoice_settings_controller.rb` | TAX-4 — `require_tax_invoice_feature`(전 액션), TAX-3 — `set_tax_type_context`(show·update — 422 재렌더 대응)·`certificate_confirmed_notice`(완료 안내 조건화) |
| 수정 | `app/views/app/invoices/_tax_invoice_panel.html.erb` | `:feature_disabled`·`:tax_type_ineligible` 분기 추가(둘 다 버튼 없음 — client_missing 분기의 카드 톤·여백·타이포 동일), 헤더 주석 갱신 |
| 수정 | `app/views/app/tax_invoice_settings/show.html.erb` | 과세 유형 select 아래 발급 불가 안내(amber note 박스 — 기존 고지 박스와 동일 톤), `@tax_type_ineligible`·`@tax_type_notice` @변수만 사용 |
| 수정 | `app/helpers/app/base_helper.rb` | TAX-4 — `app_nav_items`를 3분할(앞 배열 + 조건부 전자세금계산서 항목 + 뒤 배열)해 메뉴 순서 유지, 꺼짐 시 비노출 |
| 수정 | `config/deploy.yml` | TAX-4 — `env.clear`에 `TAX_INVOICE_ENABLED: "false"` + 켜는 조건 주석(바로빌 계약·포인트 충전·법인 등록) |

테스트 파일은 작성·수정하지 않음(Tester 담당 — Phase 7).

## Rule ID별 구현 매핑

### TAX-3 — 차단 4지점(이중화)

| # | 지점 | 파일·메서드 | 동작 |
|:--|:---|:---|:---|
| ① | 청구서 상세 패널 | `App::InvoicesController#set_tax_invoice_context` → `_tax_invoice_panel.html.erb` `:tax_type_ineligible` 분기 | 발급 불가 안내(버튼 없음) — 문구는 `@tax_invoice_guard_notice` @변수로 공급 |
| ② | 발행 화면 진입 | `App::TaxInvoicesController` before_action `guard_issue_entry`(new·create 공용 — Phase 6 C-1 수정) | 자격 판정을 맨 앞에 두고 안내 문구와 함께 **청구서 상세**로 리다이렉트. ※초기 보고 오류 정정 — 당시 구현은 `issue_guard_message`가 `create` 전용이었고 `new`는 미차단이었다(리뷰 C-1 지적). 이 표는 Phase 6 수정 후 기준 |
| ③ | 주문 생성(결제 전) | `TaxInvoices::CreateOrderService.call` | 부적격이면 주문을 만들지 않고 `IneligibleUser` 상승 — 컨트롤러 create가 rescue해 `redirect_guard_message`로 수렴(500 아님) |
| ④ | 발행 서비스 가드 | `TaxInvoices::IssueService#verify_guards!` | 가드 순서 맨 앞(결제 완료 뒤 경로의 최종 방어선) — GuardFailed |

- 판정·문구 단일 출처: `User#tax_invoice_eligible?` / `User#tax_invoice_ineligibility_notice`
  (패널·컨트롤러·설정 화면·서비스 전부 이 두 메서드만 사용).
- 허용 유지 확인: 과세 유형 select(저장 허용 — `set_tax_type_context`는 안내만 공급)·사업자 정보
  저장(RegisterCorpService 무변경)·기존 발행 내역 조회(@tax_invoice 기록 존재 시 기존 분기 그대로)·취소(cancel 무변경).

### TAX-4 — 꺼짐 동작 4종 + 스위치

| 동작 | 파일·메서드 |
|:---|:---|
| 사이드바 메뉴 비노출 | `App::BaseHelper#app_nav_items` — `TaxInvoice.feature_enabled?` 조건부 |
| 패널 "준비 중" | `:feature_disabled` 분기 — "전자세금계산서 발행은 현재 준비 중입니다. 준비가 되면 이 화면에서 발행할 수 있습니다." (기존 발행 기록 있는 청구는 기록 표시가 우선 — 우선순위 최상단 유지) |
| new·create 직접 접속 차단 | `App::TaxInvoicesController#require_tax_invoice_feature` — 대시보드(`app_root_path`) 303 리다이렉트 + 동일 문구 flash |
| 설정 전 액션 차단 | `App::TaxInvoiceSettingsController#require_tax_invoice_feature` — 동일 |
| **허용 유지** | `App::TaxInvoicesController`의 `show`·`cancel` — before_action에서 제외(주석 명시) |

- 스위치 접근자: `config/initializers/tax_invoice.rb`(ENV 읽기) → `Rails.application.config.x.tax_invoice_enabled`
  → `TaxInvoice.feature_enabled?`(모델이 ENV을 직접 읽지 않음 — 테스트에서 config 값 교체로 토글 가능).
- fail-closed: `"true"` 문자열만 true. 미설정·그 외 값·오타 모두 false.

## 새로 만든 이름

- `config/initializers/tax_invoice.rb` — `Rails.application.config.x.tax_invoice_enabled`
- `TaxInvoice.feature_enabled?` — 클래스 메서드
- `User#tax_invoice_eligible?` / `User#tax_invoice_ineligibility_notice`
- `TaxInvoices::CreateOrderService::IneligibleUser` — 예외(message = 단일 출처 문구)
- `require_tax_invoice_feature` — before_action 가드 2개 컨트롤러에 동일 구현
- `@tax_invoice_guard_notice` / `@tax_type_ineligible` / `@tax_type_notice` — 뷰 공급 @변수
- `App::TaxInvoiceSettingsController#set_tax_type_context` / `#certificate_confirmed_notice`

## 스위치 사용법 (TAX_INVOICE_ENABLED)

| 환경 | 켜는 방법 |
|:---|:---|
| 로컬 개발 서버 | `TAX_INVOICE_ENABLED=true bin/dev` (미설정 시 꺼짐) |
| 테스트 | `TAX_INVOICE_ENABLED=true bin/rails test ...` — 또는 Tester가 test_helper에서 `Rails.application.config.x.tax_invoice_enabled = true` 기본 켬 헬퍼 추가(플랜 확정 사항) |
| 운영(Kamal) | `config/deploy.yml`의 `env.clear.TAX_INVOICE_ENABLED`를 `"true"`로 변경 → 커밋·`bin/kamal deploy` (변경 이력 남는 방식 — 켜기 전제: 바로빌 계약·포인트 충전·법인 등록 스모크) |

## 설계 판정 (플랜 대비 선택·보강)

1. **패널 `:feature_disabled` 문구에 한 문장 보강** — 지시 문구("…현재 준비 중입니다.") 뒤에
   "준비가 되면 이 화면에서 발행할 수 있습니다."를 덧붙였다. 이 분기는 발행 기록이 없는 paid 청구에만
   나타나므로 "기존 발행 내역은 그대로 확인" 류의 문구는 오히려 오해를 낳는다 — 최소한의 재진입 안내만 추가.
2. **`issue_guard_message`의 자격 문구는 조건식 내 직접 반환** — `return Current.user.tax_invoice_ineligibility_notice unless ...` 형태로 GuardFailed 문자열 리터럴 패턴과 통일.
3. **create의 rescue 수렴 경로** — `IneligibleUser`를 `redirect_guard_message(e.message)`로 처리해
   기존 가드 문구 경로(new 미리보기 + alert)와 동일 UX. feature 꺼짐 시엔 create 자체가 before_action에서
   차단되므로 이 경로에 도달하지 않는다.
4. **confirm_certificate 완료 안내** — 부적격 사용자에게는 "공동인증서 등록이 확인되었습니다. " + 단일 출처
   문구를 이어 붙였다(별도 변형 문구 신설 금지 — 문구 단일 출처 원칙 유지).
5. **helper에서 `TaxInvoice.feature_enabled?` 호출** — "뷰에서 모델 클래스 메서드 호출 금지"의 취지는
   DB 쿼리·비즈니스 로직 배제이고, 이 호출은 config 부트값 읽기(쿼리 없음)라 허용 판단. 지시서가
   이 접근자를 단일 판정점으로 명시했으므로 헬퍼·컨트롤러·서비스가 모두 이를 사용한다.
6. **`set_tax_invoice_context`에서 notice @변수는 자격 분기에서만 채움** — 다른 분기에서 nil 유지
   (패널의 tax_type 분기만 소비 — 불필요한 문구 노출 방지).

## 자가 검증 결과

| 명령 | 결과 |
|:---|:---|
| `bin/rails zeitwerk:check` | 통과 — "all is good!" |
| `bin/rubocop` (변경 app/config 파일 9개) | 9 files inspected, **no offenses** |
| `TAX_INVOICE_ENABLED=true bin/rails test` (tax_invoices·settings·services·invoices 4파일) | **98 runs, 584 assertions, 0 failures, 0 errors, 0 skips** — 기존 테스트 전부 회귀 없음 |
| 기본값(꺼짐) 동일 4파일 | **20 failures, 0 errors** — `tax_invoices_controller_test.rb` 12건 + `tax_invoice_settings_controller_test.rb` 8건 (전부 리다이렉트 목적지가 `/app`으로 바뀐 것 — 의도된 fail-closed 동작). `invoices_controller_test`·`test/services/tax_invoices/`는 꺼짐 상태에서도 통과 |
| `bin/rails runner` 판정 검증 | 꺼짐 기본값 false / config true 토글 true · general eligible=true, simplified·exempt=false · 문구 2종 단일 출처 출력 확인 · CreateOrderService `IneligibleUser`(주문 생성 전) · IssueService `GuardFailed` 확인 |

## 미해결·리스크

1. **테스트 환경 기본 켬 헬퍼 미구현** — 지시대로 Tester 영역. 꺼짐 기본값 상태에선 위 20건이 계속 깨진다
   (Tester가 test_helper에서 config 기본 켬 + 꺼짐 케이스 분리 예정).
2. **paid_pending 패널이 꺼짐에 가려짐** — TAX-4 우선순위(기존 기록 > 꺼짐 > …)에 따라 결제 후 SOAP 실패
   건(paid 주문만 있는 청구)은 꺼짐 동안 "준비 중" 카드로 표시된다. 주문 show 경로 자체는 살아있으나
   패널 링크가 사라져 접근성이 떨어진다(플랜 확정 우선순위를 그대로 따름 — 스위치를 켜면 복귀).
   ※보고 누락 정정 — "show 경로 살아있음"에는 **pending 주문의 결제 진입점**이 포함돼 있었다
   (리뷰 C-2 — 꺼짐·부적격 상태에서도 결제 버튼이 열려 있었다). Phase 6 C-2 수정(결제 진입 차단)과
   W-1 수정(paid_pending 우선순위 상향)으로 해소.
3. **랜딩 불일치** — 스위치 꺼진 채 외부 공개 시 랜딩의 세금계산서 카드·FAQ와 어긋남(플랜 리스크 3 그대로 —
   랜딩은 미연동, 런칭 전 켜기 전제).
4. **켜짐 + 포인트 미충전** — 스위치만 켜면 결제 후 발행 실패 가능(플랜 리스크 4 그대로).
5. **법적 근거 확인 수준** — 시행령 §70·§64조의2는 검색 자료 일치 기준(원문 직접 대조 못함) — 안내 문구에
   "세무사 확인" 고지로 흡수(플랜 확정 사항).

## Phase 6 수정 내역 (리뷰 반영 — 2026-11-24)

Reviewer 리뷰(`05_review.md` — BLOCKER 0·CRITICAL 2·WARNING 5)의 지시분을 전부 반영했다.
오케스트레이터 판정(`02_prd_update.md` "리뷰 반영 보완") 기준. 리뷰 이슈와 무관한 코드는 변경하지
않았고, 테스트 파일은 작성·수정하지 않았다(Tester 담당 — 리다이렉트 대상 변경으로 기존 가드 테스트의
갱신이 예상된다).

| 이슈 | 수정 내용 | 파일·이름 |
|:---|:---|:---|
| **C-1** (TAX-3 ②) | 발행 화면 진입 `new`가 차단되지 않는 문제 — `new`·`create` 공용 before_action 가드로 해소. 기능 게이트(`require_tax_invoice_feature` — 꺼짐이면 대시보드, 그대로) 다음에 대상 청구 로드(미마감 → 목록·기존 동작 이동) → `issue_guard_message` 판정(자격 없음·설정 미완료·거래처 사업자번호 없음·기발행)으로 막히면 **청구서 상세(`app_invoice_path`)로 리다이렉트**. 기존 가드를 같은 구조로 해소(Reviewer 권장 채택) — `create` 본문 7줄(10줄 기준 해소). `new`로 되돌리는 경로는 결제 버튼이 남은 막다른 길·무한 리다이렉트라 금지 | `App::TaxInvoicesController` — `load_issue_invoice`·`guard_issue_entry` 신설, `redirect_guard_message` 대상을 청구서 상세로 변경, `redirect_unpaid_invoice` 삭제, `new`는 빈 본문(`def new; end`) |
| **C-2** (TAX-3·4 ④) | 미결제(pending) 주문의 상세 화면이 게이트 밖 결제 진입점인 문제 — 주문이 pending이고 (a) 기능 꺼짐 (b) 사용자 부적격이면 컨트롤러가 차단 안내를 `@tax_invoice_blocked_notice`로 공급하고, 뷰가 포트원 체크아웃 섹션(Stimulus data 포함) **대신 안내 카드**를 그린다(결제가 시작되지 않게). 조회 자체는 200 유지. 꺼짐이 우선, 부적격이면 User 단일 출처 문구. paid 주문의 `show`·`cancel`은 그대로 허용(TAX-4 ④), 청구서로 돌아가는 링크 유지 | `App::TaxInvoicesController#show` · `app/views/app/tax_invoices/show.html.erb`(pending 분기 조건화) |
| **W-1** (TAX-4 ②) | 패널 판정 우선순위 재배열 — 기존 발행 기록 > **paid_pending(결제 완료·발행 기록 없음)** > 꺼짐 > 자격 없음 > settings_missing > client_missing > ready. 돈을 낸 사용자가 "발행 주문 확인" 링크를 잃지 않게(paid_pending 카드에는 발행 버튼이 없어 게이트 약화 없음) | `App::InvoicesController#set_tax_invoice_context` |
| **W-2** (TAX-4) | 두 컨트롤러에 복제된 `require_tax_invoice_feature`를 **컨트롤러 concern으로 추출**(RemindersContext 선례). C-2의 pending 주문 차단 판정(`tax_invoice_payment_block_notice`)도 같은 concern에 둠. "전자세금계산서 발행은 현재 준비 중입니다." 리터럴 3곳 → **`TaxInvoice::FEATURE_DISABLED_NOTICE`** 단일 출처(패널 보조 문장 "준비가 되면 이 화면에서 발행할 수 있습니다."는 뷰에 유지) | **신설** `app/controllers/concerns/tax_invoice_gate.rb` · `app/models/tax_invoice.rb`(상수) · 패널·두 컨트롤러는 include로 전환 |
| **W-3** (TAX-3) | 발행 설정 화면이 부적격 사용자를 인증서 등록으로 이끄는 문제 — ① 저장 성공 플래시를 자격 조건화(부적격은 "다음으로 공동인증서를 등록해 주세요" 미출력, "사업자 정보가 저장되었습니다." + 발급 불가 안내) ② 2단계 안내·버튼을 `@tax_type_ineligible`로 숨기고 발급 불가 안내(amber note 박스 — 기존 톤)를 대신 표시 ③ 과세 유형 도움말을 "사업자 유형에 따라 전자세금계산서 발급 가능 여부가 결정됩니다."로 교체 | `App::TaxInvoiceSettingsController#saved_notice` 신설 · `app/views/app/tax_invoice_settings/show.html.erb` |
| **W-4** (TAX-3·LP-12) | 안내 문구를 **서비스 기준**으로 교체(법적 단정 회피) — 간이과세: "받을돈에서는 간이과세자의 전자세금계산서 발급을 지원하지 않습니다. …매출 규모에 따라 세금계산서 발급이 필요할 수 있으니 세무사에게 확인해 주세요." / 면세사업자: "받을돈에서는 면세사업자의 전자세금계산서 발급을 지원하지 않습니다. …". 문구 단일 출처 유지(패널·플래시·설정 화면·서비스 예외), "세무 자문 아님" 고지는 변경 없음 | `User#tax_invoice_ineligibility_notice` |
| **W-5** (문서) | 이 문서의 정정 2건 — ① TAX-3 표 ② 행("issue_guard_message new·create 공용"은 사실과 달랐다 — `create` 전용) ② 리스크 2에 pending 주문 `show`의 결제 진입점 누락 — 와 본 절 신설 | `_workspace/03_implementation.md` |
| 경과 관찰 (채택) | ① `IssueService::TAX_TYPE_BY_USER`를 `"general"`만 남김 — 가드를 건너뛰어도 `fetch` 실패(KeyError)로 발행 레코드 미생성 ② `User` enum 주석("간이과세→영세(2)·면세→면세(3) 매핑")을 실제와 일치하게 정정 ③ `issue_service.rb` 오타 "검증 사알"→"검증 사항" | `app/services/tax_invoices/issue_service.rb` · `app/models/user.rb` |

범위 밖(이번에 변경 없음): 과세 유형 기본값(일반과세), 법적 예외(§64조의2) 지원, pending 주문 자동
만료·실패 처리 로직, 랜딩 문구, 결제·바로빌 호출·과금 로직. 소유권 제한 3파일(`Gemfile.lock` ·
`test/application_system_test_case.rb` · `test/test_helpers/capybara_chrome_compat.rb`)은 여전히
미접촉이다.
