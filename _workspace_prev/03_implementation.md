# 03_implementation — 비운영 환경의 포트원 테스트 채널 키 사용 (2026-11-25, Developer)

승인된 `_workspace/01_plan.md` 설계를 그대로 구현했다. 마이그레이션·라우트 변경 없음.

## 변경 파일 목록

| 구분 | 파일 | 내용 |
|:---|:---|:---|
| 신설 | `app/services/port_one/channel_key.rb` | 채널 키 환경 선택기(단일 진입점) |
| 수정 | `app/controllers/app/billings_controller.rb` | show에서 선택기 사용(normal·billing) |
| 수정 | `app/controllers/app/legal_documents_controller.rb` | set_portone_context에서 선택기 사용(normal) |
| 수정 | `app/controllers/app/tax_invoices_controller.rb` | set_portone_context에서 선택기 사용(normal) |
| 수정 | `app/services/subscriptions/upgrade_service.rb` | 기본값을 선택기로 교체·주석 정정(INIBillTst 문구 삭제) |
| 수정 | `app/services/port_one/client_service.rb` | 채널 키 blank 가드(발급·차감) |
| 수정 | `app/views/app/billings/show.html.erb` | 미설정 문구 정정(환경 무관 문구로) |

기존 테스트 수정: **0건** — 기존 테스트는 채널 키를 서비스에 주입(`channel_key:`)하거나
데이터 속성 존재만 단언해서 이번 변경의 영향이 없었다(아래 "깨지는 기존 테스트" 절 참조).

## 설계 항목별 구현 위치

### 1. 채널 키 선택기 `PortOne::ChannelKey` (신설)
- `app/services/port_one/channel_key.rb` 전체.
  - `PortOne::ChannelKey.billing` / `.normal` — :16 / :21 (각각 `fetch` 위임).
  - `PortOne::ChannelKey.fetch(kind, env: Rails.env, credentials: Rails.application.credentials)` — :25
    - `kind` 정규화·검증 — :26~27 (`to_s.to_sym`로 nil·문자열·심볼 안전 처리, KINDS 밖이면 `ArgumentError`).
    - 환경 분기 — :29~30. `env.to_s == "production"`이면 `channel_key_#{kind}`, 아니면 `channel_key_#{kind}_test`.
    - credentials 키는 Rails 규약대로 심볼로 조회(`credentials.dig(:portone, :"channel_key_#{kind}#{suffix}")`).
- fail-closed — 비운영에서 테스트 키 부재 시 `dig`가 nil을 반환. 라이브 키 대체 경로 없음(클래스 주석 :5~7).
- Zeitwerk: `app/services/port_one/channel_key.rb` → `PortOne::ChannelKey` 확인(zeitwerk:check 통과).

### 2. 호출처 4곳 교체 (직접 참조 제거)
| 호출처 | 위치 | 변경 |
|:---|:---|:---|
| `App::BillingsController#show` | `app/controllers/app/billings_controller.rb:15~16` | `@portone_channel_key_normal = PortOne::ChannelKey.normal`, `@portone_channel_key_billing = PortOne::ChannelKey.billing` |
| `App::LegalDocumentsController#set_portone_context` | `app/controllers/app/legal_documents_controller.rb:122` | `PortOne::ChannelKey.normal` |
| `App::TaxInvoicesController#set_portone_context` | `app/controllers/app/tax_invoices_controller.rb:130` | `PortOne::ChannelKey.normal` |
| `Subscriptions::UpgradeService#portone_channel_key_billing` | `app/services/subscriptions/upgrade_service.rb:249~251` | `@channel_key \|\| PortOne::ChannelKey.billing` — 주입값 우선 유지(기존 테스트 밀봉). 주석의 "INIBillTst(정기결제 테스트 채널)" 낡은 서술을 환경 선택기 설명으로 정정(:247~248) |

- `store_id`는 환경과 무관해 기존 `credentials.dig(:portone, :store_id)` 그대로 유지.

### 3. 채널 키 없이 API를 부르지 않는 가드
- `app/services/port_one/client_service.rb`:
  - `issue_billing_key` — :33 `ensure_channel_key!(channel_key)`를 `request` 호출 전에 삽입.
  - `charge_billing_key` — :44 동일.
  - `ensure_channel_key!` — :73~76 (private). blank면 `ArgumentError`("포트원 채널 키가 등록되지 않았습니다 — credentials(:portone)에 환경에 맞는 채널 키를 등록해 주세요").

### 4. 뷰 문구 정정
- `app/views/app/billings/show.html.erb:135` — "결제 채널이 설정되지 않았습니다. 포트원 채널 키를 credentials(:portone)에 등록하면 카드 등록이 활성화됩니다."로 교체. 분기(`present?`)·다른 화면 요소 무변경.

### 5. 변경 금지 항목 준수
- JS(`app/javascript/controllers/portone_*.js`)·SDK 로드 — 무변경.
- `config/deploy.yml` — 무변경. credentials 파일 — Developer 무변경이나 워크트리의 `config/credentials.yml.enc`
  수정분(사전 사용자 편집)은 테스트 키 2개 추가가 아니라 **운영 `store_id`·라이브 채널 키 값까지 새 값으로 바꾼
  운영 스토어 전환**이다(사용자 의도 확인 — 배포 시 운영 결제가 새 스토어로 나감. 운영 DB에 옛 주문·빌링키 0건,
  `api_secret`은 새 스토어에서 유효 — 오케스트레이터 직접 조회 확인. 1차 보고 당시의 "운영 동작 변화 없음" 서술은
  이것으로 정정 — 상세는 §8).
- 라우트·마이그레이션 없음. `PRD.md`·`AGENTS.md`·`LAUNCH_TEST_SCENARIOS.md`·`ALIMTALK_TEMPLATES.md`·`.zcode/progress.json`·`_workspace/01_plan.md`·`02_prd_update.md` — 무변경(사전 Phase 편집분 제외, Developer는 건드리지 않음).

## 직접 참조 제거 확인 (`grep -rn "channel_key" app`)

`grep -rn "channel_key" app` 결과에서 `Rails.application.credentials.dig(:portone, :channel_key_…)` 형태의
직접 참조는 **0건**이 됐다. 남은 `channel_key` 매치는 전부 다음 중 하나다:

1. 선택기 자체 — `app/services/port_one/channel_key.rb:30` (단일 진입점 내부 — 유일한 credentials 읽기).
2. 선택기 호출 — `PortOne::ChannelKey.normal`/`.billing` 5행(컨트롤러 3파일·upgrade_service 1행+주석).
3. 키워드 인자·로컬변수 전달 — `client_service.rb`(발급·차감의 `channel_key:` 파라미터·본문 키 `channelKey`)와
   `upgrade_service.rb`(주입 인자·호출부 전달) — credentials를 읽지 않는 통로.
4. 주석 — `client_service.rb:31` 등 설명 문언.

## 깨지는 기존 테스트 점검 (수정 0건의 근거)

- `test/services/port_one/client_service_test.rb` — 모든 호출이 `channel_key:`를 명시 주입("ch_billing")해
  가드 통과. TEST_GUARD 테스트는 `get_payment`만 사용해 무관.
- `test/services/subscriptions/upgrade_service_test.rb`·`upgrade_service_coupon_test.rb`·`dunning_retry_test.rb`·
  `test/services/sales/attach_first_charge_coupon_service_test.rb` — `channel_key: "test-channel-billing"` 주입
  (주입값 우선 유지로 그대로 통과).
- `test/test_helpers/fake_portone_client.rb` — `channel_key:`를 필수 키워드로 기록하는 대역 — 무관.
- 컨트롤러 테스트 3종(billings·legal_documents·tax_invoices) — `data-controller=portone-payment` 등
  데이터 속성 존재만 단언, 채널 키 값·구 문구("포트원 테스트 키")를 단언하는 테스트 없음.

## 실행한 검증

| 명령 | 결과 |
|:---|:---|
| `mise exec -- bin/rails zeitwerk:check` | 통과 ("all is good!") |
| `mise exec -- bin/rubocop` | 425 files inspected, **no offenses** |
| `mise exec -- bin/rails test test/services/port_one/ test/services/subscriptions/ test/controllers/app/billings_controller_test.rb test/controllers/app/legal_documents_controller_test.rb test/controllers/app/tax_invoices_controller_test.rb test/controllers/webhooks/` | **116 runs, 682 assertions, 0 failures, 0 errors, 0 skips** |
| `mise exec -- bin/rails test` (전체) | **1,582 runs, 9,958 assertions, 0 failures, 0 errors, 0 skips** |
| `bin/rails runner` 스모크(값 미출력·존재만) | development: normal·billing 모두 present(48자 — 사용자 등록 테스트 키)·`fetch(:billing, env: "production")`: present(라이브 키)·`fetch(nil)`: ArgumentError |

## 남은 리스크

1. **빌링키 채널 종속** — 로컬 DB에 라이브 채널로 발급된 빌링키가 남은 구독은 테스트 채널 차감이 실패한다.
   로컬에서 카드 재등록 필요. 운영 DB는 영향 없음(운영 분기는 불변이나 credentials 값은 §8의 운영 스토어
   전환으로 교체 — 운영 DB에 옛 빌링키 0건이라 실무 영향 없음).
2. **credentials.yml.enc 커밋** — 사용자가 편집한 portone 블록(테스트 키 2개 + 운영 스토어 전환)이 미커밋 상태다.
   코드와 **별도 커밋**으로 함께 배포해야(01_plan 결정·정정) ~~CI·타임 머신 환경에서도 테스트 키가 보인다~~
   → 정정(재리뷰 R-3): CI는 마스터 키를 주입하지 않아(`.github/workflows/ci.yml`) 어느 경우도 credentials
   키가 보이지 않는다. 타임 머신(로컬) 환경에서만 키가 보인다(단,
   선택기·가드는 키 부재 시 nil·전용 예외로 fail-closed라 CI는 키가 없어도 녹색이다 — Tester 테스트는
   `live:`·`credentials:` 인자로 고정).
3. **테스트 채널의 실제 결제 동작** — 포트원 콘솔에 등록된 채널 종류(KG이니시스 테스트 여부)에 따라 결제 가능
   카드가 다르다. 실제 결제창 확인은 로컬 브라우저 수동 확인(Phase 8 범위 밖).
4. **테스트 채널 웹훅** — 테스트 채널 결제 이벤트가 운영 웹훅 URL로 갈 수 있으나 웹훅은 미지 paymentId를
   200 흡수(코드 확인 완료)해 무해. 로컬은 공개 URL 부재로 콜백 경로만(기존과 동일).
   → 정정(재리뷰 R-2·R-3): 이 서술은 **웹훅 URL이 탭별 설정**이라는 조건이 빠져 있다 — 포트원 콘솔의
   웹훅 URL은 V2 실연동 탭과 V2 테스트 탭에서 각각 설정되므로, V2 테스트 탭의 웹훅 URL을 운영 주소로
   두지 않으면 테스트 채널 이벤트는 운영 웹훅에 도달하지 않는다(운영 노트 확인 대상).

## 8. 리뷰 반영 (W-1~W-3 — 2026-11-25)

`05_review.md`의 지정 지적 3건(W-1·W-2·W-3)만 최소 범위로 반영했다. B-1은 사용자가 운영 스토어 전환을
의도라고 확인해 해소(코드 변경 없음), W-4는 오케스트레이터가 문서에서 정정했다. 리뷰와 무관한 코드는
변경하지 않았다.

### W-3 — 환경 판정을 규약 §9.4대로 설정 플래그로

| 파일 | 위치 | 변경 |
|:---|:---|:---|
| `config/environments/production.rb` | :98~101 | `config.x.portone_live_channel = true` 신설(주석 — PLAN-5·§9.4. 다른 환경 설정 파일에는 정의하지 않음 — 미정의 환경은 테스트 채널) |
| `app/services/port_one/channel_key.rb` | :16~21 | `PortOne::ChannelKey.live_channel?` 신설 — `config.x.portone_live_channel == true`, nil·그 외 값은 false(테스트 채널 — fail-closed) |
| `app/services/port_one/channel_key.rb` | :33~38 | `fetch`의 `env:` 인자를 `live:`(true/false)로 교체, `suffix = live ? "" : "_test"`, 클래스 주석을 플래그 방식에 맞게 갱신 |

동작은 동일하다(운영만 라이브, 그 외 테스트 채널, 미정의 환경은 테스트 채널). `.billing`·`.normal`·
`fetch`의 kind 검증·fail-closed는 무변경. 호출처 4곳(`.billing`·`.normal`)은 인자를 안 넘겨 변경 없음.

### W-2 — 채널 키 없음 전용 예외와 잡 처리

| 파일 | 위치 | 변경 |
|:---|:---|:---|
| `app/services/port_one/client_service.rb` | :15~18 | `PortOne::ClientService::MissingChannelKey < StandardError` 신설(규약 §3.5-5 — `Subscriptions::UpgradeService::UpgradeError < StandardError` 선례) |
| `app/services/port_one/client_service.rb` | :78~82 (§9 반영 후 :82~85) | `ensure_channel_key!`가 `ArgumentError` 대신 `MissingChannelKey`(메시지 동일) |
| `app/jobs/subscription_renewal_job.rb` | :16~19 | `find_each` 루프 안에 `rescue PortOne::ClientService::MissingChannelKey` 추가 — 그 구독만 `Rails.logger.error("[SubscriptionRenewalJob] user=…")` 후 다음 구독 계속(해지 후 만료 강등 포함). 기존 `rescue UpgradeError` 유지 — 전용 예외만 잡는다 |
| `app/jobs/subscriptions/dunning_retry_job.rb` | :34~37 | 같은 전용 예외를 잡아 `Rails.logger.error("[Subscriptions::DunningRetryJob] subscription=…")`만 남기고 종료 — dunning 단계·상태 변경 없음(설정 복구 후 수동 재실행 대상). 기존 `rescue UpgradeError` 유지 |

카드 등록 콜백 컨트롤러 등 그 외 경로는 예외를 삼키지 않는다(설정 오류는 그대로 드러난다 — 무변경).
`Rails.error`가 아닌 `Rails.logger`를 쓴 이유 — 프로젝트에 `Rails.error` 사용 예가 없어서다.

### W-1 — 단건 결제 화면 3곳도 채널 키 없음을 안내

| 파일 | 위치 | 변경 |
|:---|:---|:---|
| `app/views/app/billings/_checkout.html.erb` | :25~29 | "결제하기" 버튼 조건 앞에 `@portone_channel_key_normal.blank?` 분기 신설 — 키 없으면 요금제 페이지(`billings/show.html.erb:134~136`)와 같은 톤·색(amber 배경·stone 글자·`role="status"`)의 "결제 채널이 설정되지 않았습니다. 포트원 채널 키를 credentials(:portone)에 등록하면 결제가 활성화됩니다." 안내 |
| `app/views/app/legal_documents/show.html.erb` | :77~81 | 동일 |
| `app/views/app/tax_invoices/show.html.erb` | :110~114 | 동일(차단 안내 분기 내부) |

바깥의 `data-controller="portone-payment"` 블록은 **그대로 유지**했다 — 기존 컨트롤러 테스트
(`test/controllers/app/billings_controller_test.rb:101~117`)가 이 블록의 존재를 단언하고, 버튼만
분기하면 로컬(credentials에 키 있음)과 CI(키 없음)에서도 기존 테스트 결과가 같다.

### 기존 테스트 수정 — 0건

- 가드 예외 교체: nil 키로 가드에 닿는 기존 테스트가 0건(리뷰 §2-5 확인)이라 단언 교체 대상이 없다.
- 잡 rescue 추가: 예외가 발생하지 않는 경로의 동작은 무변경(`test/services/subscriptions/dunning_retry_test.rb:142·166`의
  `SubscriptionRenewalJob.perform_now` 포함).
- 뷰 분기: "결제하기" 버튼을 긍정 단언하는 기존 테스트가 없다. 기존 단언은 블록 존재·데이터 속성·차단 경로의
  `assert_no_match(/결제하기/)`(`tax_invoice_gate_test.rb:175` 등 — 위젯 미렌더 경로라 무관)뿐이라
  키 유무 환경 모두에서 결과가 같다.

### 운영 동작 서술 정정(리뷰 B-1 해소 반영)

§5의 "credentials 파일 — 무변경(사전 사용자 편집)" 서술을 위 표 이전에 정정했다. 1차 보고의 "운영은 동일
라이브 키 분기"(남은 리스크 1)도 credentials **값** 수준에서는 성립하지 않는다 — 작업 트리의 credentials는
운영 `store_id`·라이브 채널 키 값도 새 값으로 바뀌었고 이는 사용자가 의도한 운영 스토어 전환이다(배포 시
운영 결제가 새 스토어로 나감 — 운영 DB에 옛 주문·빌링키 0건, `api_secret`은 새 스토어에서 유효를
오케스트레이터가 직접 조회로 확인). 커밋은 credentials를 코드와 별도로 분리한다(01_plan 결정·정정).

### 리뷰 반영 후 검증

| 명령 | 결과 |
|:---|:---|
| `mise exec -- bin/rails zeitwerk:check` | 통과 ("all is good!") |
| `mise exec -- bin/rubocop` | 425 files inspected, no offenses |
| 범위 테스트(`test/services/port_one/`·`test/services/subscriptions/`·컨트롤러 3종·`tax_invoice_gate_test`·`tax_invoice_eligibility_test`) | 131 runs, 812 assertions, 0 failures, 0 errors, 0 skips |
| `bin/rails test test/jobs/` | 34 runs, 153 assertions, 0 failures, 0 errors, 0 skips |
| `mise exec -- bin/rails test` (전체) | 1,582 runs, 9,958 assertions, 0 failures, 0 errors, 0 skips |
| `bin/rails runner` 스모크(development, 값 미출력) | `live_channel?` = false(플래그 미정의 → 테스트 채널)·`fetch(:billing, live: false)` present·`fetch(:billing, live: true)` present — 플래그 동작·양쪽 접미사 분기 확인 |

## 9. 재리뷰 반영 (R-1·R-2 — 결제 확정 검증, 2026-11-25)

재리뷰의 **R-1(BLOCKER — 결제 금액 서버 검증 부재)·R-2(CRITICAL — 테스트 채널 결제 수용)**를 반영했다.
리뷰 지적 두 공백에 대한 최소 구현이며, R-3(문서 정정)도 이 파일 안에서 3건 정정했다(§8 표의 `:78~85` 행·
"남은 리스크" 2·4번). Plus 갱신(빌링키 차감 `Subscriptions::UpgradeService`)과 환불(`Orders::RefundService`
— 이미 `amount.paid`를 비교)은 리뷰가 검증 대상에서 제외해 변경하지 않았다. 신규 시나리오 테스트는 Tester
담당(재리뷰 §7-5)이라 이번 범위 밖 — 기존 테스트는 깨진 것만 최소 수정했다.

### 검증 규칙과 근거

`PortOne::PaymentVerifier.verify!(payment, order_amount:, live: PortOne::ChannelKey.live_channel?)` —
통과하면 payment를 그대로 반환, 실패하면 `VerificationError(reason, detail)`를 던진다(fail-closed).
payment가 nil이면(응답 부재) 금액 검사에서 실패로 떨어진다(예외 아님).

| 검사 | 규칙 | 근거(포트원 공식 OpenAPI v2 1.16.0) |
|:---|:---|:---|
| ① 금액 | `payment.dig(:amount, :paid)`가 `order_amount.to_i`와 같은 Numeric — JSON 정수·`4000.0` 형태 모두 통과. nil·비숫자·불일치는 실패(0원 주문은 없어 누락=실패) | `PaidPayment.amount` = `PaymentAmount` — `paid`("실제 결제금액") required |
| ② 채널 | `payment.dig(:channel, :type)` == (`live` ? `"LIVE"` : `"TEST"`). 누락·그 외 값은 실패 | `PaidPayment.channel` = `SelectedChannel` — `type`(`LIVE`·`TEST` enum) required |

승인 요청도 함께 보강했다 — `confirm_payment` 본문에 `totalAmount`(주문 원값)·`isTest`(환경 기대값 — 운영
false·그 외 true)를 보낸다. 근거: `ConfirmPaymentBody.totalAmount`·`isTest` — "검증용 파라미터로, 결제 건
총 금액·테스트 여부와 일치하지 않을 경우 오류가 반환됩니다. 값 전달을 권장합니다". 단, 파라미터 전달만으로는
부족하다(포트원이 값을 대조할 뿐, 확정점이 응답을 검증하지 않으면 리뷰 R-1 ②·③ 공백이 남는다) — 그래서
확정점 2차 검증(`FulfillPassService`)을 함께 뒀다. 클라이언트는 응답을 `symbolize_names: true`로 파싱하므로
검증기는 심볼 키를 읽는다.

### 변경 파일·위치

**줄 번호는 1차 구현(3차 수정 이전) 시점 기준** — 현재 위치는 §10 표를 따른다(재리뷰 2회차 R2-6(b) 표시).

| 파일 | 위치 | 변경 |
|:---|:---|:---|
| `app/services/port_one/client_service.rb` | :27~36 | `confirm_payment`에 `total_amount:`·`is_test:` 필수 인자 추가, 본문에 `totalAmount`·`isTest` 전송. 주석 정정 — "포트원이 결제 요청 당시 금액과 일치함을 검증" → "포트원 검증용 파라미터 + 서버 쪽 2차 검증은 `PortOne::PaymentVerifier`(확정점 `FulfillPassService`)" |
| `app/services/port_one/payment_verifier.rb` | 신설(79줄) | 검증기. 클래스 주석에 근거·why(fail-closed — 금액 변조·테스트 채널 결제가 정가 상품으로 이어지는 것 차단)·사용처(단건 결제 유일 확정점 `FulfillPassService`) 기술. `VerificationError < StandardError`(규약 §3.5-5 — `MissingChannelKey` 선례)는 `reason`(`:amount_mismatch`·`:channel_mismatch`)·`detail`(결정된 값·기대값)을 운반, 메시지는 "결제 확정 검증 실패(금액 불일치): paid=… expected=…" 형태로 로그에 바로 쓰게 설계 |
| `app/services/orders/fulfill_pass_service.rb` | :16~23 | `with_lock`의 `next unless pending?` 바로 뒤(상태 변경 전) `PortOne::PaymentVerifier.verify!(@response, order_amount: @order.amount)`. 멱등 no-op(이미 확정된 주문) 경로는 검증하지 않는다. 실패 시 아무것도 바꾸지 않고 예외를 그대로 올린다(트랜잭션 롤백 — 발급·발행 없음) |
| `app/services/orders/purchase_service.rb` | :50~55·:73~80·:84~97·:143~159 | `approve!`가 `total_amount:`·`is_test: !PortOne::ChannelKey.live_channel?` 전달(:73~80). `call`에 `rescue VerificationError` 절(:50~55) — `record_verification_failure!(e)` 후 `raise PurchaseError, verification_message`. `recover_from_recheck!`는 기존 rescue 목록(`PortOne::ApiError, PendingApprovalError`)을 유지하고 **별도 절**(:91~96)로 검증 실패 처리 — false로 삼키지 않는다(그 `PurchaseError`는 `call`의 `rescue PortOne::ApiError` 절 안에서 던져져 컨트롤러의 `PurchaseError` rescue로 전달된다). `record_verification_failure!`(:143~155)·`verification_message`(:157~159) 신설. 파일 머리 주석의 "(포트원이 검증)" 서술을 검증용 파라미터+2차 검증으로 정정 |
| `app/controllers/webhooks/portone_controller.rb` | :61~65·:79~110 | `sync_payment_status`에 `rescue VerificationError`(:61~65) — 확정하지 않고 `record_verification_failure!(order, e)`(private :101~110)로 주문 실패 기록. `create`의 항상 200 응답 유지(재시도 무의미 — 포트원 규격). `apply_status`의 Plus 갱신 분기(`settle_renewal`)는 무변경(빌링키 차감은 검증 대상 아님 — 주석으로 명시) |
| `app/services/port_one/channel_key.rb` | :16~22 | `live_channel?` 주석 정정 — "nil이나 그 외 값" → "nil·미정의(Rails 8.1 `config.x`는 정의되지 않은 키에 빈 `OrderedOptions`를 돌려준다 — 참으로 평가)·그 외 값". **`== true` 비교는 유지**(truthy 검사로 바꾸면 미정의 환경까지 라이브가 된다 — O-2) |

### 실패 시 동작(경로별)

| 경로 | 검증 위치 | 실패 시 동작 | 회원에게 보이는 것 |
|:---|:---|:---|:---|
| 콜백(수동 승인·즉시 승인 공통 — `PurchaseService`) | `FulfillPassService` 확정점(`with_lock` 내) | 주문 failed 확정 — `pg_payment_id` 스냅샷 + metadata 병합(`code: "PAYMENT_VERIFICATION_FAILED"`, `message`, `verification: { reason, detail }` — `invoice_id` 등 기존 키 보존, B-1 병합 선례) + `Rails.logger.error("[PaymentVerifier] order=… …")` → `PurchaseError` 전달 → 컨트롤러가 303 리다이렉트 alert | "결제 확인에 실패했습니다. 고객지원(문의)으로 연락해 주세요." (금액·채널 등 내부 값 미노출) |
| 웹훅(`Webhooks::PortOneController`) | 같은 확정점(`settle_paid` → `FulfillPassService`) | 확정 없이 pending 주문을 failed로 기록(같은 metadata 병합 — `pg_payment_id`는 이미 스냅샷 보존 중) + `Rails.logger.error("[PaymentVerifier][webhook] order=… …")`. 응답은 그대로 200 | 없음(서버 간 호출) |

모호 실패(타임아웃)와 달리 검증 실패는 **결정적 불일치**라 pending 유지·웹훅 회복 대상이 아니다 — 웹훅도
같은 검증으로 거절하므로 회복이 없고, pending으로 두면 사용자만 대기 화면에 갇힌다(지시서 판단 그대로).

### 발행 경로의 전제 확인(변경 없음)

`Orders::FulfillTaxInvoiceService`(발행)는 **paid 주문만 대상**임을 코드로 확인했다 — 앱 코드의 유일 호출처는
`FulfillPassService#fulfill_tax_invoice`(확정 트랜잭션 밖)뿐이고, 그 호출은 `newly_paid`(검증 통과 후의
pending→paid 전환)에만 일어난다. 발행 서비스 자체의 `next unless @order.reload.pending?` 재판정도 그대로다.
검증 실패 시 paid 전환이 없으므로 발행(바로빌 SOAP·실비)은 절대 호출되지 않는다 — 이 서비스는 변경하지 않았다.

### 고친 기존 테스트 — 10파일 19곳(단언의 의미는 유지)

| 파일 | 곳 | 수정 내용 |
|:---|:---|:---|
| `test/services/port_one/client_service_test.rb` | 3 | confirm 3호출(성공·404 실패·타임아웃)에 `total_amount: 4_000, is_test: true` 인자 추가 — 성공 테스트 본문 단언에 `"totalAmount" => 4_000, "isTest" => true` 반영 |
| `test/services/orders/purchase_service_test.rb` | 4 | 승인 요청 인자 단언에 `total_amount: 4_000, is_test: true` 추가 · paid 메타데이터 단언에 대역이 보강한 `amount`·`channel` 반영(→ 9-2에서 정정 — 보강 폐기, 승인 뒤 재조회 응답 기준으로) · 즉시 승인·모호 실패 재확인의 get_payment 응답을 `paid_payment` 헬퍼로 |
| `test/controllers/app/orders_controller_test.rb` | 1 | 즉시 승인 채널 콜백의 get_payment 응답을 헬퍼로 |
| `test/controllers/app/tax_invoice_callback_test.rb` | 1 | `confirm_via_callback`은 실제로 paymentToken 없는 콜백(조회 확정)이라 get_payment 응답을 헬퍼로 교체(기존 confirm_payment 주입은 사용되지 않던 값이었다) |
| `test/controllers/app/legal_documents_controller_test.rb` | 2 | B-1 회귀(웹훅 확정)·`confirm_paid!` 헬퍼의 get_payment 응답을 헬퍼로(`amount: Order::LEGAL_DOC_PRICE`) |
| `test/controllers/webhooks/portone_controller_test.rb` | 2 | 패스 확정·재시도 멱등의 get_payment 응답을 헬퍼로(Plus 갱신·위조 재조회·취소·실패 경로는 무변경 — 검증 대상 아님 또는 id 불일치 선행) |
| `test/controllers/webhooks/tax_invoice_settle_test.rb` | 1 | `post_paid_event`의 get_payment 응답을 헬퍼로(`amount: TaxInvoice::ISSUE_FEE`) |
| `test/models/order_item_type_test.rb` | 3 | `FulfillPassService` 직접 호출 3곳의 response를 헬퍼로(헬퍼용 require 추가) |
| `test/system/app_legal_document_pdf_test.rb` | 1 | `FulfillPassService` 직접 호출의 response를 헬퍼로 |
| `test/f_plan_review_fix_test.rb` | 1 | 타임아웃 후 재확인 PAID 합류의 get_payment 응답을 헬퍼로 |

`FakePortOneClient` 대역(:7~13·:24~27·:62~74) — `confirm_payment`가 새 인자를 기록하고, 승인 응답이 해시이면서
`amount`·`channel`이 없으면 호출 인자로 자동 보강(`amount: { paid: total_amount }`,
`channel: { type: is_test ? "TEST" : "LIVE" }` — 테스트가 명시하면 그 값 우선, 변조 시나리오용). 조회 응답은
호출 인자에 금액이 없어 자동 보강이 불가능하므로 `FakePortOneClient.paid_payment(id:, amount:, live: false)`
조립 헬퍼를 신설했다(기본 TEST — test 환경의 `live_channel?` false와 동일한 근거, credentials 비의존).
**[9-2에서 폐기]** 이 자동 보강은 실제 스펙에 없는 가정(승인 응답에 금액·채널이 있다)을 테스트에 심어
콜백 경로의 결함을 가렸다 — 9-2에서 삭제했고, 승인 응답은 스펙대로 pgTxId·paidAt만 돌려준다.

### 검증 수치

| 명령 | 결과 |
|:---|:---|
| `mise exec -- bin/rails test` (전체) | 1,582 runs, 9,958 assertions, 0 failures, 0 errors, 0 skips |
| `mise exec -- bin/rails test:system test/system/app_legal_document_pdf_test.rb` | 14 runs, 132 assertions, 0 failures, 0 errors, 0 skips |
| `mise exec -- bin/rubocop` | 426 files inspected, no offenses |
| `mise exec -- bin/rails zeitwerk:check` | all is good |

범위 선실행(전체 1회 이전) — `test/services/port_one/`+`test/services/orders/`+`order_item_type_test`+
`f_plan_review_fix_test`(74 runs, 0 failures)·웹훅·콜백 컨트롤러 4파일(42 runs, 0 failures).

### 남은 리스크

1. **[추정] 실결제 응답 필드의 실측 미완료** — 첫 실결제 1건으로 승인·재조회 응답의 `amount.paid`·
   `channel.type` 실측 값을 기록해 검증기 기대값의 근거를 확정한다(재리뷰 §8-3과 동일). KRW 단건이라
   `paid`는 정수가 예상되지만 소수 형태(`4000.0`)도 Numeric 비교로 통과시킨다.
2. **검증 실패 주문의 결제 실체** — failed로 확정된 주문의 결제는 포트원에 실제로 성립했을 수 있다(소액·
   테스트 채널 결제). 환불은 정책상 콘솔 수동 절차(PLAN-6)이므로 ADMIN-4 실패 주문 모니터링에서
   `code: "PAYMENT_VERIFICATION_FAILED"` metadata로 CS 추적한다. 리뷰 제안의 "관리자 알림"은 이번 범위 밖.
3. **웹훅 흡수 뒤 수동 회복** — 검증 실패 웹훅은 200으로 흡수되어 포트원 재시도가 없고, failed 주문은
   웹훅 회복 경로에서 벗어난다. 정상 결제였음이 나중에 확인되면 CS 수동 재발급이 필요하다(fail-closed의
   의도된 비용).
4. **PurchaseError 계약 의존** — 재조회 합류 경로의 검증 실패는 `call`의 `rescue PortOne::ApiError` 절 안에서
   `PurchaseError`로 바뀌어 전달된다. 새 호출처가 생기면 `PurchaseError`를 잡아야 한다(기존 계약과 동일).

### 9-1 방어 코드 보강 (2026-11-25)

`verify_amount!`·`verify_channel!`의 중첩 읽기를 `payment.dig(:amount, :paid)` 형태에서
`amount = payment[:amount]; paid = amount.is_a?(Hash) ? amount[:paid] : nil`로 바꿨다 —
`amount`·`channel`이 Hash 외 형태(문자열·배열·숫자)면 `Hash#dig`의 종류 없는 `TypeError`가 아니라
`VerificationError`로 떨어진다(웹훅 500→재시도 흡수, fail-closed). 문자열 키 해시는 관대하게 받지 않고
검증 실패로 유지하며(심볼 키만 인정), `EXPECTED_CHANNEL_TYPES.fetch(live)`를 `fetch(live == true)`로
바꿔 nil 등 비정상 live 값도 테스트 채널(false) 쪽으로 해석한다 — 라이브로 해석하는 경로를 남기지 않는다.
`payment_verifier.rb`만 수정(주석 갱신 포함), 테스트는 Tester 단계에서 추가한다.

### 9-2 콜백 경로 정정 — 승인 뒤 재조회 검증(2026-11-25)

오케스트레이터가 포트원 공식 OpenAPI v2 1.16.0 원문을 재확인해 지적한 사실을 반영했다 — §9의 1차 구현은
**콜백(paymentToken) 경로에서 승인 응답을 검증 대상으로 삼았고, 운영에서는 정상 결제까지 전부 검증 실패 →
주문 failed 처리될 결함**이었다.

**스펙 사실** — 승인 요청 `POST /payments/{paymentId}/confirm`의 200 응답은 `ConfirmedPaymentSummary`로
**`pgTxId`·`paidAt` 두 필드뿐**이다. `status`·`amount`·`channel`은 없다. 금액·채널이 담긴 전체 결제
객체(`PaidPayment` — `amount.paid`·`channel.type` required)는 `GET /payments/{paymentId}`(재조회)의
응답뿐이다. 즉 "승인 응답의 실제 결제금액·채널을 2차 검증"이라던 §9의 콜백 경로 서술은 검증에 쓸 필드가
응답에 없어 성립하지 않는다(웹훅·즉시 승인·모호 실패 회복 경로는 처음부터 재조회 결과를 검증해 정상).

**왜 1차 구현이 틀렸는지** — 테스트 대역 `FakePortOneClient`가 승인 응답에 `amount`·`channel`을 자동
보강(`with_verification_fields` — 호출 인자로 채움)해 주고 있었다. 스펙과 다른 이 가정이 기존 테스트를
전부 통과시켜 결함을 가렸다. 실호출 시에는 `verify_amount!`가 `paid=nil` → 즉시 `VerificationError` →
`record_verification_failure!`로 정상 결제가 failed가 된다.

**수정 내용** — `app/services/orders/purchase_service.rb`:

| 위치 | 변경 |
|:---|:---|
| `approve!`(:96~103) | paymentToken 경로를 `confirm_payment!` → `recheck_after_confirm!` 2단계로. 확정 응답(`@portone_response`)은 **재조회한 전체 결제 건** — 승인 응답은 검증에 쓰지 않고 버린다 |
| `confirm_payment!`(:108~112) | 승인 요청 분리 — 이 줄의 `ApiError`는 여기서 잡지 않고 `call`의 `rescue PortOne::ApiError`(모호 실패 재확인·ALREADY_PAID 회복·명확한 거부만 failed)로 그대로 흘려보낸다(두 단계 예외 처리 분리) |
| `recheck_after_confirm!`(:117~121) | 승인 성공 뒤의 재조회 실패(ApiError·PAID 아님)는 결제가 이미 성립했을 수 있으므로 failed 확정 금지 — `PendingApprovalError`(조회 실패 원문 동반)로 바꿔 올린다 |
| `PendingApprovalError`(:40~47) | `api_error` 속성 추가 — `rescue PendingApprovalError`(:64~70)가 `keep_pending_for_webhook_recovery!(e.api_error)`(ApiError면 원문을 metadata에 보존, 아니면 nil — 기존 회복 패턴 그대로) 후 `PurchaseError(recovery_message)` |
| 파일 머리·메서드 주석 | "승인 응답(ConfirmedPaymentSummary — pgTxId·paidAt만)에는 금액·채널이 없어 승인 뒤 재조회한 결제 건으로 검증한다", "승인 성공 뒤 재조회 실패는 pending 유지"로 정정 |

`FulfillPassService`·`PortOne::PaymentVerifier`·`Webhooks::PortOneController`는 **변경 0** — 확정점은
받은 응답을 검증할 뿐이고, 이제 그 응답이 항상 재조회 결과가 되므로 하위 계층 수정이 불필요함을 확인했다.
`test/test_helpers/fake_portone_client.rb` — 자동 보강(`with_verification_fields`) 삭제, 승인 응답은
스펙 기본값(pgTxId·paidAt만) 유지, 헤더에 "콜백 경로 테스트는 `get_payment:`에 `paid_payment`로 전체
결제 건을 지정" 명시, 호출 인자 기록(total_amount·is_test)은 유지.

**고친 기존 테스트 — 3파일 6곳(단언의 의미는 유지 — 승인 뒤 재조회 1회가 생긴 것만 반영)**

| 파일 | 곳 | 수정 내용 |
|:---|:---|:---|
| `test/services/orders/purchase_service_test.rb` | 4 | ① 승인 확정(PLAN-4)·② 승인 요청 인자·③ SEC 멱등 재승인·④ legal_doc B-1 병합 — 승인 뒤 재조회가 일어나므로 `get_payment: paid_payment(...)` 지정(①은 지정 없이 기본 get_payment가 검증 실패로 떨어짐). ①·④의 confirm_payment 주입은 스펙 형태로 불필요해 제거, metadata 스냅샷 주석을 "재조회한 전체 결제 건"으로 정정, ①에 `assert_equal 1, fake.calls[:get_payment].size` 추가 |
| `test/controllers/app/orders_controller_test.rb` | 1 | paymentToken 콜백(PLAN-4) — `get_payment: paid_payment` 지정 + 재조회 1회 단언 추가 |
| `test/services/orders/purchase_service_concurrency_test.rb` | 1 | 실스레드 경합 — 대역에 `get_payment: paid_payment` 지정(지정 없으면 승리 스레드가 재조회 응답 부재로 검증 실패) |

f_plan_review_fix_test·legal_documents·tax_invoice_callback·app_legal_document_pdf 등 나머지
`confirm_payment` 언급 테스트는 승인 요청이 예외(raise_on)이거나 paymentToken 없는 조회 확정 경로라
무변경이었음을 전수 확인(grep 기반).

**추가한 회귀 테스트 2건**(`test/services/orders/purchase_service_test.rb` — 이번 결함의 핵심 회귀)

1. "승인 응답(pgTxId·paidAt만)은 검증에 쓰지 않고 재조회한 결제 건으로 정상 확정한다" — 승인 응답은
   대역 기본값(실제 스펙 형태), 재조회 응답은 `paid_payment`. 정상 확정(paid·발급 1회) + 승인 1회·
   재조회 1회 단언 + metadata 스냅샷이 재조회 결과임을 단언. "승인 응답만으로 검증해 정상 결제가 실패
   처리되던 결함"의 회귀.
2. "승인은 성공하고 재조회가 실패하면 failed가 아닌 pending 유지로 웹훅 회복을 연다" — `get_payment`
   raise_on TIMEOUT(ApiError·모호 실패 코드). 주문 pending 유지·`pg_payment_id` 보존·
   `pending_recovery` metadata·재조회 실패 원문(`code: "TIMEOUT"`) metadata 보존·발급 없음·
   승인 1회·재조회 1회(재시도 없음) 단언.

**검증 수치**

| 명령 | 결과 |
|:---|:---|
| `mise exec -- bin/rails test` (전체) | 1,584 runs, 9,980 assertions, 0 failures, 0 errors, 0 skips(+2 — 회귀 테스트) |
| `mise exec -- bin/rubocop` | 426 files inspected, no offenses |
| `mise exec -- bin/rails zeitwerk:check` | all is good |

범위 선실행(전체 1회 이전) — purchase_service·concurrency·orders_controller·f_plan_review_fix·
port_one client_service(44 runs, 271 assertions, 0 failures).

**남은 리스크(기존 항목 유지)** — §9 "남은 리스크" 1번(실결제 응답 실측)은 이 정정으로 더욱 중요해졌다:
첫 실결제 1건으로 승인 응답이 정말 pgTxId·paidAt만인지·재조회 응답의 `amount.paid`·`channel.type` 실측값을
기록해 검증기 기대값의 근거를 확정한다.

## 10. 재리뷰 2회차 반영 (R2-1·R2-2·R2-4·R2-5·R2-6 — 2026-11-25)

재리뷰 2회차(BLOCKER 1 · WARNING 5)의 코드 대상 5건을 반영했다. **R2-3(검증 실패 주문의 환불·재발급
회복 수단)은 운영 절차 과제라 코드 변경 없음** — 오케스트레이터가 런북·AGENTS 노트로 반영(본 파일 범위 밖).
R2-6(c)의 이력 문서 2곳(`_workspace_prev_fplan/05_review.md:51`·`LAUNCH_TEST_SCENARIOS.md:48`)은 각각
변경 금지 대상·사용자 문서라 건드리지 않았다(오케스트레이터 보고 대상). §9·§9-2 표의 줄 번호는 당시
시점 기준이므로 현재 위치는 이 절의 표를 따른다.

### R2-1 (BLOCKER) — 웹훅 상태 동기화가 검증 실패 주문을 paid로 되돌리는 우회 차단

`Webhooks::PortOneController#apply_status`에서 범용 상태 동기화(`order.update!`) 앞에
`return if status == "paid"`를 뒀다 — **paid 전환은 pending 주문의 확정 경로(`settle_paid` →
`FulfillPassService` 검증)로만 일어난다.** 검증 실패로 `failed`가 된 주문(포트원에서는 실제 PAID —
소액·테스트 채널 결제)에 뒤늦은 `Transaction.Paid` 이벤트가 와도 재조회가 PAID라 검증 없이 paid로
뒤집히지 않는다(내용증명 정식 PDF 유출 차단). pending→실패·취소, paid→cancelled 동기화는 그대로 유지된다.

| 파일 | 위치(현재) | 변경 |
|:---|:---|:---|
| `app/controllers/webhooks/portone_controller.rb` | :74~93 | `apply_status`에 paid 전환 가드(:86) 추가. 메서드 주석 갱신 — "paid 전환은 pending 주문의 확정 경로로만"·"검증 실패·실패 주문이 뒤늦은 Paid 이벤트로 되돌려지는 우회 차단(재리뷰 2회차 R2-1)" |

**회귀 테스트 1건 추가**(`test/controllers/webhooks/portone_controller_test.rb:50~77`) — 검증 실패로
failed가 된 주문(`status: :failed`·`metadata.code = PAYMENT_VERIFICATION_FAILED`·`verification.reason/detail`)
에 `Transaction.Paid` 이벤트 + 재조회 대역이 올바른 전체 결제 건(`paid_payment(id:, amount: 주문 금액)`)을
돌려줘도 → **failed 유지 · `paid_at` nil · 수금 패스 발급 없음 · 검증 실패 metadata 보존 ·
`updated_at` 불변(범용 `update!` 미실행의 프록시 단언)**. 기존 테스트 중 failed→paid 동기화를 단언하던
것은 0건(재리뷰 2회차 §2 근거와 동일) — 수정 0건. pending 정상 경로(검증 통과→paid)는 기존 테스트가
그대로 통과해 회귀 없음을 확인.

### R2-5 — 검증 실패 기록의 중복 제거(`Order#mark_verification_failed!` 단일 구현)

컨트롤러·서비스에 중복되던 13줄의 잠금·쓰기(`record_verification_failure!`)를 모델 메서드 한 곳으로
모았다(`mark_refunded!` 선례). 웹훅 사본이 `pg_payment_id`를 기록하지 않던 어긋남(R2-5 지적)도 함께 해소 —
양 경로 모두 결제 ID 스냅샷을 남긴다. 로그 태그도 `[PaymentVerifier]`로 통일되었다(구 웹훅 사본의
`[PaymentVerifier][webhook]` 폐기). `PortOne::PaymentVerifier::VerificationError`(`reason`·`detail`)는 무변경.

| 파일 | 위치(현재) | 변경 |
|:---|:---|:---|
| `app/models/order.rb` | :54~91 | 신설 — `VERIFICATION_FAILED_CODE`(:56)·`VERIFICATION_FAILED_MESSAGE`(:57) 상수, `verification_failed?` 판정(:61~63 — failed 상태 AND `metadata["code"]` 일치), `mark_verification_failed!(reason:, detail:)`(:70~91 — `with_lock` 안에서 `reload` 뒤 pending일 때만 `failed` 확정·`pg_payment_id` 스냅샷·metadata 병합(`invoice_id` 등 기존 키 보존 — B-1 선례)·적용 여부 반환·적용 시 `Rails.logger.error("[PaymentVerifier] order=… 결제 확정 검증 실패(reason): detail")`. 이미 확정·실패된 주문은 무변경(멱등). 스키마 변경 없음 |
| `app/services/orders/purchase_service.rb` | :71~76·:131~137 | `rescue VerificationError` 2곳이 `@order.mark_verification_failed!(reason:, detail:)`를 호출. 중복 구현 `record_verification_failure!` 삭제(구 :187~199). `verification_message`는 유지 |
| `app/controllers/webhooks/portone_controller.rb` | :60~67 | `rescue VerificationError`가 모델 메서드를 호출(:66). 중복 구현 `record_verification_failure!` 삭제(구 :101~113). `create` 6줄·응답 200 유지 |

### R2-4 — 통화(KRW) 확인(승인 요청 전달 + 재조회 결제 건 검증)

공식 스펙(오케스트레이터 확인) 기준 — 승인 요청 `ConfirmPaymentBody.currency`(값 전달 권장), 재조회
`PaidPayment.currency`(required, enum에 KRW 포함). 양쪽에 모두 대응한다.

| 파일 | 위치(현재) | 변경 |
|:---|:---|:---|
| `app/services/port_one/client_service.rb` | :27~38 | `confirm_payment`에 `currency:` 인자 추가, 본문에 `currency` 전송. 주석 갱신 — "totalAmount·isTest·currency는 포트원 검증용 파라미터(ConfirmPaymentBody — 값 전달 권장)"·"승인 응답에는 검증에 쓸 필드가 없어 2차 검증은 재조회한 결제 건으로(R-1·R-2·R2-4)" |
| `app/services/orders/purchase_service.rb` | :105~114 | `confirm_payment!`가 `currency: "KRW"`를 전달(KRW 단건 고정). 주석 갱신 |
| `app/services/port_one/payment_verifier.rb` | :1~14·:29~32·:44~46·:96~102 | 세 번째 검증 `verify_currency!` 신설 — `payment[:currency]`가 `"KRW"`와 같은지(누락·그 외 통화는 실패). `EXPECTED_CURRENCY = "KRW"` 상수, `REASON_LABELS`에 `currency_mismatch: "통화 불일치"` 추가, 검증 순서는 금액→채널→통화. 클래스 주석 정정 — 검증 입력은 재조회 결과·승인 응답은 pgTxId·paidAt만(R2-6 병행) |
| `test/test_helpers/fake_portone_client.rb` | :12~20·:39~42 | `paid_payment(id:, amount:, live: false, currency: "KRW")` — `currency` 필드 추가(기본 KRW). `confirm_payment`가 `currency:` 인자를 기록 |

### R2-2 — 검증 실패 주문의 회원 안내(재결제 유도 금지)

검증 실패 주문은 "다시 시도/새로 주문"을 보이면 안 된다(잘못 걸러진 정상 결제라면 이중 결제). 두 주문 상세
화면 모두 검증 실패 판정을 `payment_failed` 파라미터보다 우선하고, 재시도 버튼 대신 문의 안내(`new_app_ticket_path`
— 기존 문의 경로 확인 후 사용)를 보인다. 문구는 서비스 내부 값(금액·채널·reason)을 노출하지 않는다.
디자인은 기존 톤(스톤 카드·주황 배지 — 환불 안내 섹션 선례)을 따른다.

| 파일 | 위치(현재) | 변경 |
|:---|:---|:---|
| `app/controllers/app/legal_documents_controller.rb` | :58~62·:85~98 | `show`의 flash 분기를 private `set_payment_failure_alert`로 추출 — `verification_failed?`면 "결제 확인에 실패했습니다. 고객지원(문의)으로 연락해 주세요.", 아니면 기존 `payment_failed=1` 문구 유지(검증 실패 우선). 액션 4줄 유지 |
| `app/views/app/legal_documents/show.html.erb` | :105~120 | 실패 분기 안에 `verification_failed?` 하위 분기 신설 — 재주문 버튼 숨김·"확인 필요" 주황 배지·"다시 결제하지 말아 주세요" 안내·"고객지원에 문의" 링크(`new_app_ticket_path`) |
| `app/controllers/app/tax_invoices_controller.rb` | :40~47·:67~78 | 같은 패턴 적용(실패 분기 존재 확인 후) — `set_payment_failure_alert` private 헬퍼. 액션 7줄 유지 |
| `app/views/app/tax_invoices/show.html.erb` | :130~152 | 같은 하위 분기 — "다시 발행 요청" 버튼 숨김·문의 안내 |

### R2-6 — "승인 응답으로 검증" 주석 정정

`grep -rn "승인 응답" app` 전수 확인 — 검증 대상을 승인 응답으로 읽히게 하는 서술 3곳만 정정하고,
이미 정확한 서술(purchase_service.rb 헤더·`approve!`·client_service `get_payment` 주석 등)은 유지했다.

| 파일 | 위치(현재) | 정정 내용 |
|:---|:---|:---|
| `app/services/port_one/payment_verifier.rb` | :1~6 | "포트원 승인(confirm)·재조회(get_payment) 응답을 주문과 대조" → "포트원에서 재조회(get_payment)한 전체 결제 건을 주문과 대조. 승인 응답(ConfirmedPaymentSummary)에는 pgTxId·paidAt만 있어 검증 대상이 아니다 — 검증 입력은 항상 재조회 결과다" |
| `app/services/orders/fulfill_pass_service.rb` | :20~23 | "승인·재조회 응답의 실제 결제금액과 채널 종류" → "재조회한 결제 건(승인 응답은 pgTxId·paidAt만이라 검증 대상 아니다)의 실제 결제금액·채널 종류·통화" |
| `app/services/port_one/client_service.rb` | :28~33 | "응답의 실제 결제금액·채널 종류에 대한 2차 검증"의 모호한 주어 → "승인 응답(ConfirmedPaymentSummary — pgTxId·paidAt만)에는 검증에 쓸 필드가 없으므로 … 재조회한 결제 건으로" (R2-4 주석 갱신과 병행) |

문서 보강 — §9 "변경 파일·위치" 표 머리에 "줄 번호는 1차 구현 시점 기준(현재 위치는 §10 표 참조)" 표시를
추가했다(R2-6(b)).

### 고친 기존 테스트 — 2파일 6곳(currency 반영·단언의 의미는 유지)

| 파일 | 곳 | 수정 내용 |
|:---|:---|:---|
| `test/services/port_one/client_service_test.rb` | 3 | confirm 3호출(성공·404 실패·타임아웃)에 `currency: "KRW"` 인자 추가. 성공 테스트 본문 단언에 `"currency" => "KRW"` 반영(주석도 R2-4로 갱신) |
| `test/services/orders/purchase_service_test.rb` | 3 | 승인 요청 인자 단언에 `currency: "KRW"` 추가(테스트명도 "검증값(금액·테스트 여부·통화)"로 확장)·metadata 스냅샷 단언 2곳에 대역이 추가한 `"currency" => "KRW"` 반영 |

그 밖의 결제 관련 테스트(tax_invoice_settle·tax_invoice_callback·orders_controller·legal_documents
controller·order_item_type·app_legal_document_pdf·f_plan_review_fix·purchase_service_concurrency)는
`paid_payment` 헬퍼 경유라 currency가 자동 포함돼 무변경으로 통과함을 전수 확인했다. 원시 해시를 쓰는 곳은
검증기에 도달하지 않는 것도 확인(타 결제 id 조기 반환·READY 회복·CANCELLED 동기화·settle_renewal 무검증).

### 추가한 테스트 — 2파일 6건

| 파일 | 건 | 내용 |
|:---|:---|:---|
| `test/controllers/webhooks/portone_controller_test.rb` | 1 | R2-1 회귀 — "검증 실패로 failed가 된 주문은 뒤늦은 Transaction.Paid로도 paid로 되돌려지지 않는다"(위 표 참조) |
| `test/services/port_one/payment_verifier_test.rb` | 5 | 신설 — R2-4 통화 검증 중점: KRW·금액·채널 일치 통과(payment 그대로 반환)·USD 불일치 `:currency_mismatch`(reason·detail·메시지 라벨 "통화 불일치")·통화 누락 실패(fail-closed)·검증 순서(금액→채널→통화 — 앞선 불일치 우선)·`paid_payment` 대역 계약(기본 KRW 포함·검증 통과). 금액·채널 전수 행렬은 Tester 단계(재리뷰 2회차 §7-2) |

### 검증 수치

| 명령 | 결과 |
|:---|:---|
| `mise exec -- bin/rails test` (전체) | 1,590 runs, 10,003 assertions, 0 failures, 0 errors, 0 skips(+6 — 신규 테스트) |
| `mise exec -- bin/rails test:system` | 14 runs, 132 assertions, 0 failures, 0 errors, 0 skips |
| `mise exec -- bin/rubocop` | 427 files inspected, no offenses |
| `mise exec -- bin/rails zeitwerk:check` | all is good |
| `mise exec -- bin/brakeman --no-pager -q` | Errors 0, Security Warnings 0 |

범위 선실행(전체 1회 이전) — port_one 2파일·purchase_service·웹훅 컨트롤러(45 runs, 224 assertions,
0 failures)·legal_documents·orders·tax_invoice_callback·tax_invoice_settle·order_item_type·
f_plan_review_fix·order·orders 서비스 전체(100 runs, 656 assertions, 0 failures).

### 남은 리스크

1. **R2-3(운영 절차)** — 검증 실패 주문의 환불·재발급은 앱 밖 절차(포트원 콘솔 수동 환불 + 콘솔 작업)다.
   오케스트레이터가 런북 반영(이번에 문서화됨) — 첫 실결제 전 처리 절차 확정 필요(재리뷰 2회차 §8-3).
2. **§9 "남은 리스크" 1번(실결제 응답 실측) 유지** — 이번에 `currency` 검증이 추가돼 첫 실결제 기록
   필드에 `currency`도 포함해 확인한다(재리뷰 2회차 §6-1과 동일 절차).
3. **O-4(발행 서비스의 미검증 전이)·O-3(settle_renewal 무검증)** — 변경 금지 대상이라 유지. 웹훅
   `apply_status` 가드(R2-1)로 pending 아닌 주문의 검증 없는 paid 전환 경로는 하나 더 줄었다.


## 11. 마감 리뷰 반영 (F-1~F-4 — 2026-11-25)

마감 리뷰(APPROVED — WARNING 4) 중 배포 전 권장 2건(F-1·F-2)과 같은 자리 정리 2건(F-3·F-4)을 최소 범위로 반영했다. 결제 확정 경로(PurchaseService·FulfillPassService·웹훅·PaymentVerifier·Plus 갱신·환불)는 건드리지 않았다.

### 변경 내용

**F-1 — 재주문 차단을 주문 생성 경로까지 확장** (상세 화면의 버튼 숨김만으로는 목록·청구서 상세·요금제 진입이 새 주문을 만들었다)

| 파일:라인 | 내용 |
|:---|:---|
| `app/models/order.rb:126-138` | `Order.verification_failed_for(user, item_type: nil, invoice_id: nil)` 신설 — 회원·품목·청구로 범위를 좁힌 뒤 루비에서 `verification_failed?` 재판정(회원별 failed 주문은 소수 — JSON 질의 불요). 주석에 운영 해제 조건 기록: `verification_failed?`는 `failed?`를 요구하므로 운영자가 runner로 상태를 다른 값(예: cancelled)으로 바꾸면 차단이 풀린다(관리자 화면 범위 밖) |
| `app/controllers/app/legal_documents_controller.rb:36-37`·`:109-112` | create 가드(paid 가드·pending 재사용보다 **앞**) — 같은 청구의 검증 실패 주문이 있으면 그 주문 상세로 리다이렉트 + `Order::VERIFICATION_FAILED_REORDER_NOTICE`. create 본문 액션 축약(10줄 내): `redirect_new_legal_target`·`redirect_paid_legal_order`·`issue_legal_order`로 분리(기존 동작 유지) |
| `app/controllers/app/tax_invoices_controller.rb:31-32`·`:137-141` | create 가드(paid 가드보다 앞 — pending 재사용으로 결제창을 다시 열게 두지 않는다) + `redirect_verification_failed_order` 헬퍼 |
| `app/controllers/app/orders_controller.rb:11-12`·`:42-45` | 수금 패스: `item_type: :pass`의 해결되지 않은 검증 실패 주문이 있으면 주문 생성·결제창 진입 없이 요금제(app_billing_path)로 리다이렉트 + 동일 안내(`redirect_pass_verification_failed`). plus_monthly 갱신 주문은 웹훅 settle_renewal이 검증 대상이 아니어서 검증 실패 표식이 생길 수 없어 `item_type: :pass` 스코핑이 정확하다 |

안내 문구는 `Order::VERIFICATION_FAILED_REORDER_NOTICE`("결제 확인에 실패한 주문이 있습니다. 고객지원(문의)으로 연락해 주세요.") 상수 1개로 3곳 공용. 뷰의 진입 링크(목록 "양식 발급"·청구서 상세 패널 "전자세금계산서 발행")는 지시대로 바꾸지 않았다(컨트롤러 가드가 잡는다 — 링크 숨김은 후속).

**F-2 — 검증 실패 안내를 사실대로** ("확인 중" 함축 제거 — 자동 확인·관리자 알림은 없음)

| 파일:라인 | 내용 |
|:---|:---|
| `app/models/order.rb:62-64` | `VERIFICATION_FAILED_USER_NOTICE` = "결제 확인에 실패했습니다. 다시 결제하지 말고 고객지원(문의)으로 연락해 주세요." (flash 단일 출처) |
| `app/controllers/app/legal_documents_controller.rb:84`·`app/controllers/app/tax_invoices_controller.rb:80` | `set_payment_failure_alert` 검증 실패 분기가 위 상수 사용 |
| `app/views/app/legal_documents/show.html.erb:115`·`app/views/app/tax_invoices/show.html.erb:141` | 본문을 "다시 결제하지 말고 고객지원(문의)으로 연락해 주세요."로 교체(제목·배지·문의 링크·색·타이포 유지) |

**F-3 — pending 회복 대기 주문의 착지 안내** (승인 됐거나 될 수 있는데 `?payment_failed=1` 착지 시 "다시 시도"로 덮어써지던 문제)

| 파일:라인 | 내용 |
|:---|:---|
| `app/models/order.rb:75-83` | `Order#pending_recovery_waiting?` 신설 — `pending?` + `metadata["pending_recovery"]`(PurchaseService#keep_pending_for_webhook_recovery! 표식) |
| `app/models/order.rb:69-71` | `PENDING_RECOVERY_NOTICE` = "결제 확인이 지연되고 있습니다. 승인 결과는 잠시 후 자동으로 반영됩니다." (PurchaseService#recovery_message와 같은 취지 — 서비스는 변경 금지 경로라 공유하지 않음) |
| 두 컨트롤러 `set_payment_failure_alert` (legal :83-87 / tax :79-83) | 우선순위: ① 검증 실패 → ② pending 회복 대기 → ③ 기존 payment_failed 재시도 안내 |

**F-4 — 통화 누락 보강**

| 파일:라인 | 내용 |
|:---|:---|
| `app/models/order.rb:57-58` | `VERIFICATION_FAILED_MESSAGE` → "결제 금액·결제 채널·결제 통화가 주문과 일치하지 않습니다"(metadata 기록용 — 신규 실패부터 반영). `:53-55` 주석은 이미 통화를 포함해 보강 불요. AGENTS·purchase_service·fulfill_pass_service 주석은 변경 금지 대상이라 제외(리뷰 F-4의 해당 항목) |

### 테스트 (신규 8건 — 기존 2건 문구 단언 갱신)

| 파일:라인 | 테스트 |
|:---|:---|
| `test/controllers/app/legal_documents_controller_test.rb:103`·`:117`·`:130`·`:339` | F-1 create 차단(주문 수 불변·해당 주문 리다이렉트·안내) / pending 공존 시 pending 재사용·결제창 금지 / 검증 실패 없으면 pending 재사용 회귀 / F-3 pending 회복 착지 안내 |
| `test/controllers/app/tax_invoices_controller_test.rb:371`·`:387` | F-1 create 차단(pending 공존 포함) / F-3 pending 회복 착지 안내 |
| `test/controllers/app/orders_controller_test.rb:47`·`:63` | F-1 패스 구매 차단(주문 생성 없음·요금제 리다이렉트·안내) / cancelled 전환(운영 해제 조건) 뒤 재구매 허용 |
| 문구 갱신 | legal :266·`:281`·`:296` / tax :339·`:352`·`:362` — 새 문구 단언 + "확인하고 있으니"(자동 확인 함축) 부정 단언 추가 |

### 검증

| 명령 | 결과 |
|:---|:---|
| `mise exec -- bin/rails test` (전체) | **1,664 runs, 10,553 assertions, 0 failures, 0 errors, 0 skips** (+8 — 신규 테스트) |
| `mise exec -- bin/rubocop` | 430 files inspected, no offenses |
| `mise exec -- bin/rails zeitwerk:check` | all is good |
| `mise exec -- bin/brakeman --no-pager -q` | No warnings found |

### 운영 해제 조건 (요약)

검증 실패 주문의 재주문 차단은 `status = failed` + `metadata.code = PAYMENT_VERIFICATION_FAILED`에 묶여 있다. 운영자가 포트원 콘솔 환불 등으로 정리한 뒤 `bin/rails runner`로 해당 주문 상태를 `cancelled` 등 다른 값으로 바꾸면(`Order#verification_failed?`가 거짓이 됨) 회원은 다시 구매할 수 있다. 관리자 화면은 범위 밖(후속).
