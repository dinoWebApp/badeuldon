# 01_plan — 비운영 환경의 포트원 테스트 채널 키 사용 (2026-11-25, 일반 모드·Standard)

## 배경·목표

**사용자 요청(2026-11-25)**: credentials에 `portone.channel_key_billing_test`·`portone.channel_key_normal_test`를
추가했다. **로컬(development)과 테스트 환경에서는 이 테스트 채널 키로 결제 처리가 되게** 해달라.

**현 상태(코드 확인)**:
- 채널 키는 4곳에서 `Rails.application.credentials.dig(:portone, :channel_key_…)`로 **직접** 꺼낸다 — 환경 구분이 없어
  로컬에서도 운영 라이브 채널 키가 쓰인다(그래서 지금까지 "로컬에서 결제 버튼 금지" 운영 규칙으로 막아 왔다).
  1. `App::BillingsController#show` — `channel_key_normal`(수금 패스 결제창)·`channel_key_billing`(카드 등록)
  2. `App::LegalDocumentsController#set_portone_context` — `channel_key_normal`
  3. `App::TaxInvoicesController#set_portone_context` — `channel_key_normal`
  4. `Subscriptions::UpgradeService#portone_channel_key_billing` — 빌링키 발급·정기결제 차감(첫 결제·자동 갱신·재시도)
- 프런트엔드는 서버가 뷰에 심은 `data-portone-*-channel-key-value`를 PortOne SDK(`requestPayment`·
  `requestIssueBillingKey`)에 그대로 넘긴다. JS는 고칠 필요가 없다.
- 사용자가 추가한 키 확인(2026-11-25 11:18, 값 미열람): `:portone`에 키 6개 — 기존 4개 + 테스트 2개(길이 48,
  라이브 키와 다른 값, 빌링·일반 테스트 키도 서로 다름). `config/credentials.yml.enc`는 미커밋 상태.
- 환경별 분기 선례: `BaroBill::ClientService#release_mode?`(`Rails.env.production?`)·클라이언트 3종의 test 가드.
- 웹훅(`Webhooks::PortOneController`)은 모르는 paymentId를 흡수(200) → 테스트 채널 결제 이벤트가 운영 웹훅으로
  가도 무해. 단건 결제 확정은 콜백(`/app/orders/callback`)+서버 재조회라 채널 키가 필요 없다.
- 기존 테스트는 채널 키를 서비스에 주입(`channel_key:`)해 돌아서 영향 없음.

## 규모·파이프라인

- **Standard** — 0→1→✋→2→3→4→5→(6)→7→8→9. 기존 로직 수정(환경별 키 선택 1곳 신설 + 호출처 4곳 교체).
  마이그레이션·라우트 변경 없음.
- 호출 프로필(일반): `badeuldon-developer` → `badeuldon-reviewer` → `badeuldon-tester`.

## 관련 Rule ID

| Rule ID | 내용 | 이번 작업 |
|:---|:---|:---|
| PLAN-5 | 포트원(KG이니시스 채널) 결제 — 빌링키 정기결제·단건·웹훅 | "비운영 환경은 테스트 채널 키, 운영만 라이브 채널 키"를 구현 확정으로 추가 |
| PLAN-2·PLAN-4·PLAN-7·TAX-1 | 결제를 쓰는 상품(Plus·수금 패스·내용증명·세금계산서) | 동작 변경 없음 — 채널 키 공급 경로만 바뀜 |

새 Rule ID는 만들지 않는다(PLAN-5의 환경 운영 규칙).

## 설계 (Developer 지시 기준)

### 1. 채널 키 선택기 `PortOne::ChannelKey` (신설, `app/services/port_one/channel_key.rb`)

한 곳에서 환경별 키를 고른다. 인터페이스:

- `PortOne::ChannelKey.billing` / `PortOne::ChannelKey.normal` — 라이브 채널 키 또는 테스트 채널 키를 반환.
- ~~`PortOne::ChannelKey.fetch(kind, env: Rails.env, credentials: …)`~~ → 최종 API(리뷰 W-3 반영): `PortOne::ChannelKey.fetch(kind, credentials: Rails.application.credentials, live: live_channel?)` — `live_channel?`는 `config.x.portone_live_channel == true`.
  - `env.to_s == "production"`이면 `channel_key_#{kind}`, 아니면 `channel_key_#{kind}_test`.
  - `kind`는 `:billing`·`:normal` 두 가지. 그 외는 `ArgumentError`.
  - 환경·credentials를 인자로 받는 이유: 테스트에서 실제 credentials(로컬은 마스터 키가 있어 값이 있음, CI는 없음)와
    관계없이 값을 고정하기 위해서다.
- **fail-closed**: 비운영 환경에서 테스트 키가 없으면 `nil`을 돌려준다. **라이브 키로 대체하지 않는다.**

### 2. 호출처 4곳 교체

- `App::BillingsController#show`: `@portone_channel_key_normal = PortOne::ChannelKey.normal`,
  `@portone_channel_key_billing = PortOne::ChannelKey.billing`
- `App::LegalDocumentsController#set_portone_context`: normal
- `App::TaxInvoicesController#set_portone_context`: normal
- `Subscriptions::UpgradeService#portone_channel_key_billing`: `@channel_key || PortOne::ChannelKey.billing`
  (주입값 우선은 그대로 — 기존 테스트 밀봉 유지). 주석의 낡은 문구("INIBillTst 정기결제 테스트 채널" 등)를 정정.

### 3. 채널 키 없이 API를 부르지 않는 가드

`PortOne::ClientService#issue_billing_key`·`#charge_billing_key`: `channel_key`가 blank면 API를 호출하지 않고
`ArgumentError`(메시지에 "포트원 채널 키 미등록" 포함)로 실패한다. 키가 없는 상태에서 빌링키 발급·차감이
포트원으로 나가는 일을 막는다(fail-closed).

### 4. 뷰 문구 정정

`app/views/app/billings/show.html.erb`의 "결제 채널이 설정되지 않았습니다. 포트원 **테스트 키**를 credentials(…)에
등록하면 …" → 환경과 무관한 문구로("포트원 채널 키를 credentials(:portone)에 등록하면 카드 등록이 활성화됩니다").
키가 없을 때의 분기(`present?`)는 그대로.

### 5. 변경하지 않는 것

- JS(`portone_billing_controller.js`·`portone_payment_controller.js`)·SDK 로드 — 서버가 심어 주는 값만 쓰므로 무변경.
- ~~`config/deploy.yml`·운영 credentials 값 — 운영은 라이브 키를 그대로 쓴다(분기 결과가 동일).~~ → 정정: credentials의 운영 값 자체가 사용자 편집으로 바뀌었다(아래 "결정·정정" 참조). `config/deploy.yml`은 무변경.
- 라우트·마이그레이션 없음.

## 변경 예상 파일

| 영역 | 파일 | 내용 |
|:---|:---|:---|
| Service | `app/services/port_one/channel_key.rb` (신설) | 환경별 채널 키 선택기 |
| Service | `app/services/port_one/client_service.rb` | 채널 키 blank 가드 |
| Controller | `app/controllers/app/billings_controller.rb` | 선택기 사용 |
| Controller | `app/controllers/app/legal_documents_controller.rb` | 선택기 사용 |
| Controller | `app/controllers/app/tax_invoices_controller.rb` | 선택기 사용 |
| Service | `app/services/subscriptions/upgrade_service.rb` | 선택기 사용·주석 정정 |
| View | `app/views/app/billings/show.html.erb` | 미설정 문구 정정 |
| Test | `test/services/port_one/channel_key_test.rb` (신설)·`client_service_test.rb`·컨트롤러 테스트 3종·`upgrade_service_test.rb` | Tester |
| Docs | `PRD.md`(PLAN-5 구현 확정·v0.48)·`AGENTS.md`(운영 노트) | Phase 2·9 |

## 에이전트 지시 요약

- **Developer**: 위 설계대로 구현. 선택기 테스트는 `live:`·`credentials:` 인자로 고정해 **로컬(마스터 키 있음)과
  CI(마스터 키 없음) 모두에서 같은 결과**가 나오게 한다. 03 보고서에 콜사이트 4곳 매핑 기록.
- **Reviewer**: ① 운영 경로 결과가 바뀌지 않는가(라이브 키) ② 비운영에서 라이브 키로 새는 경로가 남지 않았는가
  (직접 `credentials.dig(:portone, :channel_key_…)` 참조 잔존 여부) ③ fail-closed(테스트 키 부재 시 nil·API 미호출)
  ④ 테스트 밀봉 ⑤ 의존 방향 규약.
- **Tester**: 선택기 정상(`live: true`→라이브 키, `live: false`→테스트 키·플래그 미정의 환경은 `live_channel?` false)·예외(비운영인데 테스트 키 없음 → nil, 라이브 키가
  있어도 대체하지 않음·운영인데 라이브 키 없음 → nil·잘못된 kind) / 클라이언트 가드(API 미호출·전용 예외) / 잡 처리(전용 예외만 잡아 계속 진행) / 컨트롤러 3종의
  데이터 속성에 선택기 값이 심어지는지(선택기 stub)·키 없을 때 결제 버튼 대신 안내 / `UpgradeService` 기본값이 선택기를 타는지(주입 없을 때) /
  **결제 확정 검증**(금액 불일치·채널 종류 불일치·필드 누락 → 확정하지 않음·승인 요청에 totalAmount·isTest 전달) / 전체 회귀. 포트원 실호출 없음(TEST_GUARD·대역).

## 결정·정정 (2026-11-25 리뷰 반영)

- **운영 스토어 전환은 의도된 것임(사용자 확인)** — 리스크 4의 "운영 동작 변화는 없다"는 틀렸다. 작업 트리의 credentials는 운영 `store_id`·라이브 채널 키 값까지 바꿨고(기존 값은 `*_test`로 이동), 이 파일을 배포하면 운영 결제가 새 스토어로 나간다. 운영 DB에 옛 주문·빌링키는 0건, `api_secret`은 새 스토어에서 유효(직접 조회). 배포 전 확인: 새 스토어 웹훅 URL. 커밋은 credentials를 코드와 분리한다.
- **테스트 채널 2개는 새 스토어의 채널임(사용자 확인)** — 스토어 ID는 환경 공통, 채널 키만 환경별(설계 그대로). 단 `_test` 값이 이전 운영 채널 키와 같아, 로컬 결제창이 뜨는지는 브라우저로 확인한다.
- **리뷰 W-1**: 단건 결제 3곳(수금 패스·내용증명·세금계산서)도 채널 키가 없으면 결제 버튼 대신 안내 — PRD 문단과 코드를 맞춘다.
- **리뷰 W-2**: 채널 키 없음은 `ArgumentError` 대신 전용 예외(`PortOne::ClientService::MissingChannelKey`). 갱신 잡은 루프 안에서 그 예외만 잡아 그 구독을 건너뛰고 계속, 재시도 잡은 잡아서 로그로 남긴다.
- **리뷰 W-3**: 환경 이름 직접 비교 대신 규약 §9.4대로 환경 설정 플래그 `config.x.portone_live_channel`(`production.rb`만 true, 미정의 환경은 테스트 채널)를 쓴다. 동작은 같다.
- **리뷰 W-4**: "실제 결제 없음"은 브라우저 확인 전 단정하지 않는다(AGENTS.md 운영 노트 정정).
- **재리뷰 R-1(BLOCKER)·R-2(CRITICAL) — 결제 확정 검증 추가(기존 공백)**: 포트원 공식 OpenAPI v2(1.16.0) 원문 확인 — `ConfirmPaymentBody.totalAmount`·`isTest`는 "검증용 파라미터로 … 일치하지 않을 경우 오류가 반환됩니다. 값 전달을 권장합니다", `PaidPayment.channel.type`은 `LIVE`·`TEST`(required), `amount.paid`는 required. 기존 코드는 승인 요청에 둘을 보내지 않고 확정점(`Orders::FulfillPassService`)에서 상태만 봤다 → 라이브 결제가 시작되면 낮은 금액·테스트 채널 결제가 정가 상품으로 확정될 수 있다. 수정: ① `confirm_payment`에 `total_amount`·`is_test` 전달 ② 신설 `PortOne::PaymentVerifier.verify!(payment, order_amount:, live:)` — `amount.paid == 주문 금액`, `channel.type == (live ? "LIVE" : "TEST")`, 아니면 `VerificationError`(fail-closed) ③ `FulfillPassService`가 pending 주문을 paid로 바꾸기 직전에 검증. **정정(오케스트레이터가 스펙을 다시 확인해 발견)**: 승인 요청의 200 응답은 공식 `ConfirmedPaymentSummary`(`pgTxId`·`paidAt`만)라 금액·채널이 없다 → 콜백 경로는 승인 성공 뒤 **반드시 재조회**(`get_payment`)한 결제 건으로 검증한다(승인 응답으로 검증하면 정상 결제가 전부 실패 처리된다). 승인은 됐는데 재조회가 실패하면 실패 확정하지 않고 pending 유지로 웹훅 회복을 연다 ④ 콜백 경로는 검증 실패 시 주문을 실패 처리(사유 메타데이터·로그) 후 `PurchaseError`, 웹훅 경로는 확정하지 않고 주문을 실패 처리 후 200 ⑤ 대역(`FakePortOneClient`)과 기존 테스트의 가짜 응답에 금액·채널 반영. Plus 갱신(빌링키 차감)은 서버가 금액·채널을 지정하므로 대상이 아니다.

## 리스크·모호점

1. **빌링키는 채널에 묶인다** — 라이브 채널로 발급된 빌링키는 테스트 채널에서 결제되지 않고 그 반대도 마찬가지다.
   로컬 DB에 라이브 채널로 카드 등록한 구독이 남아 있으면 로컬 자동 갱신이 실패 처리된다 → 로컬에서는 카드를 새로
   등록해야 한다. 운영 DB는 영향 없음.
2. **테스트 채널의 성격은 사용자가 포트원 콘솔에서 등록한 종류에 따른다**(KG이니시스 테스트 채널이면 테스트 카드만
   결제됨). 실제 결제창이 뜨는지는 로컬 브라우저에서 확인이 필요하다(Phase 8은 서버 값·부팅만 확인).
3. **테스트 채널 결제도 운영 웹훅 주소로 이벤트가 갈 수 있다** — 운영 웹훅은 모르는 결제 ID를 200으로 흡수하므로
   무해(코드 확인). 로컬은 공개 URL이 없어 웹훅을 못 받으므로 결제 확정은 콜백 경로로만 된다(기존과 동일).
4. ~~credentials.yml.enc 변경은 사용자 편집분 — 이 작업과 함께 커밋해야 운영 이미지에도 포함된다. 운영은 라이브 키를 그대로 쓰므로 운영 동작 변화는 없다.~~ → 정정(리뷰 B-1): credentials의 운영 스토어·라이브 채널 키 값이 바뀌었고 이는 사용자가 의도한 운영 스토어 전환이다(배포 시 운영 결제가 새 스토어로 나감). 커밋은 코드와 **별도**로 분리하고, **결제 확정 검증(R-1·R-2) 반영 전에는 커밋·배포하지 않는다**.
5. **"테스트 환경"에서의 실제 호출** — 자동 테스트는 대역과 TEST_GUARD로 실호출이 차단돼 있어 테스트 채널 키가
   실제로 쓰이지는 않는다(선택기 값만 검증). 실제 결제창 확인은 로컬(development)에서 한다.
