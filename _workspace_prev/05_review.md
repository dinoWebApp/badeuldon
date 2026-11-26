status: CHANGES_REQUESTED

# 05_review — 비운영 환경의 포트원 테스트 채널 키 사용 (2026-11-25, Reviewer)

**BLOCKER 1 · CRITICAL 0 · WARNING 4**

코드 변경(신설 선택기 + 호출처 4곳 교체 + 클라이언트 가드)은 승인된 설계대로이고, 운영 경로(키 이름)·fail-closed·테스트 밀봉은 실행으로 확인했다.
BLOCKER는 코드에 있지 않다. 함께 커밋될 예정인 **미커밋 `config/credentials.yml.enc`**가 운영 스토어·채널 키 값을 바꾸고 있어서, 커밋·배포 전에 사용자 판정이 필요하다.

---

## 1. 이슈 표

| ID | 심각도 | 위치 | 문제 | 영향 | 제안 수정 |
|:---|:---|:---|:---|:---|:---|
| B-1 | **BLOCKER** (사용자 판정 필요) | `config/credentials.yml.enc`(미커밋, 수정 2026-11-25 11:18) · `_workspace/01_plan.md:115-116`(리스크 4) · `_workspace/03_implementation.md:53, 92-94` · `PRD.md:214` · `AGENTS.md:211` | 작업트리 credentials의 `portone` 블록은 "테스트 키 2개 추가"가 아니다. HEAD(`04c48e1`, `origin/main`과 동일)와 복호화해 비교한 결과(값 미출력): (1) `store_id`·`channel_key_billing`·`channel_key_normal` 세 값이 모두 바뀌었다(`api_secret`만 동일). (2) 새 키 `channel_key_billing_test`는 HEAD의 `channel_key_billing`과, `channel_key_normal_test`는 HEAD의 `channel_key_normal`과 각각 같은 값이다. 즉 기존 키를 `_test`로 옮기고 기존 이름에 새 값을 넣었으며 `store_id`도 교체했다. (3) 기존 4개 키는 `5c28d8e`(2026-10-15) 이후 어느 커밋에서도 바뀌지 않았다. | 이 파일을 코드와 함께 커밋·배포하면(01_plan 리스크 4가 그렇게 하라고 한다) **운영 결제가 다른 스토어·다른 채널 키로 나간다.** "운영 경로 결과 불변"(리스크 4 "운영 동작 변화는 없다", 03 §5, 이번 리뷰의 전제 "지금까지대로 라이브 채널 키")이 값 수준에서 성립하지 않는다. 의도인지는 코드 리뷰로 판정할 수 없다. | ① 커밋·배포 전에 사용자에게 "운영 스토어·채널 키 교체가 의도인가" 확인. ② 의도라면 01_plan 리스크 4·03 §5·PRD PLAN-5 문단·AGENTS 운영 노트에 "이 커밋으로 운영 스토어·채널이 새 값으로 바뀐다"를 명시하고, credentials 전환을 코드 변경과 **별도 커밋**으로 분리한다(롤백 단위 분리). ③ 의도가 아니면 base 이름과 `store_id`를 HEAD 값으로 복원한다. ④ 어느 쪽이든 "운영 변화 없음" 서술은 정정한다. |
| W-1 | WARNING | `app/views/app/billings/_checkout.html.erb:5-7, 25` · `app/views/app/legal_documents/show.html.erb:60-62, 77` · `app/views/app/tax_invoices/show.html.erb:93-95, 110` · `PRD.md:214` · `AGENTS.md:211` | PRD PLAN-5 문단과 AGENTS 노트는 "테스트 키가 없으면 결제창·카드 등록은 비활성 안내"라고 쓰지만, 분기하는 곳은 카드 등록(`billings/show.html.erb:106-137`)뿐이다. 단건 결제 3곳(수금 패스·내용증명·세금계산서)은 채널 키 없이도 `data-controller="portone-payment"` 블록과 "결제하기" 버튼을 그대로 렌더한다(버튼 조건은 연락처 유무만: `_checkout:25`, `legal:77`, `tax:110`). 클릭하면 `PortOne.requestPayment({ channelKey: "" })`가 호출된다. 주문 생성도 막지 않는다. | 돈·보안 영향은 없다. 빈 채널 키로는 어느 채널로도 결제가 만들어질 수 없다[추정: 포트원 SDK가 오류로 거절한다. 실호출 금지라 확인하지 않았다]. 다만 단일 소스인 PRD 서술과 코드가 다르고, 키 없는 환경에서는 사용자가 "결제하기"를 눌러야 실패를 알게 된다. | 둘 중 하나. (a) 3곳 버튼 분기에 `@portone_channel_key_normal.present?`를 추가하고 요금제 페이지와 같은 "결제 채널이 설정되지 않았습니다" 안내를 낸다(세금계산서는 `@tax_invoice_blocked_notice` 경로 재사용 가능). (b) 코드는 두고 PRD·AGENTS를 "카드 등록은 비활성 안내, 단건 결제창은 채널 키 없이 SDK가 거절"로 정정한다. |
| W-2 | WARNING | `app/jobs/subscription_renewal_job.rb:10-17` · `app/jobs/subscriptions/dunning_retry_job.rb:29-34` · `app/services/port_one/client_service.rb:73-77` | 가드의 `ArgumentError`는 `UpgradeService`의 `rescue PortOne::ApiError`(`upgrade_service.rb:163, 192`)와 두 잡의 `rescue UpgradeError`에 모두 걸리지 않고 잡 밖으로 나간다. (1) `SubscriptionRenewalJob`은 `find_each` 루프가 그 지점에서 끊겨 뒤순번 due 구독의 처리(해지 후 만료 강등 포함)가 그 날 건너뛴다. 키가 없는 동안 매일 같은 지점에서 멈춘다. (2) `DunningRetryJob`은 실패로 끝나고 재예약이 없어, 구독이 `dunning_active?`이고 `next_retry_at`이 과거인 채로 멈춘다(결제 없이 Plus 유지, 설정을 복구해도 자동 재개 없음). (3) 오류 알림 구독자가 없어 실패는 Solid Queue 실패 기록과 로그에만 남는다. | 데이터 오염은 없다. `with_lock`이 트랜잭션으로 감싸므로(`activerecord/locking/pessimistic.rb:97-103`) 선기록한 pending 주문은 롤백되고, `record_charge_failure!`·`advance_dunning!`은 호출되지 않아 실패 주문·dunning 단계가 생기지 않는다(코드 독해로 확인, 실행 재현은 안 함). `retry_on`이 둘 다 없어 재시도 폭증도 없다. 운영은 키가 있어 이 상태에 들어가지 않는다(설정이 깨졌을 때만). | `ArgumentError` 대신 전용 예외(예: `PortOne::ClientService::MissingChannelKey < StandardError`, 규약 §3.5-5)를 던진다. 갱신 잡은 루프 안에서 그 예외만 잡아 `Rails.error.report` 뒤 다음 구독으로 넘어가게 하고, 재시도 잡은 같은 예외를 잡아 로그·보고한다. 코드 버그인 `ArgumentError`까지 삼키지 않도록 범용 클래스로 잡지 않는다. |
| W-3 | WARNING (확인 요청) | `app/services/port_one/channel_key.rb:25, 29` | ARCHITECTURE_CONVENTION §9.4는 "환경별 분기는 `Rails.env` 직접 비교보다 환경 설정 파일과 `config.xxx` 플래그로"라고 한다. 선택기는 주입받은 `env`(기본 `Rails.env`)를 `"production"`과 직접 비교한다. 승인된 설계(01_plan §1) 그대로이고 `BaroBill::ClientService#release_mode?`(`Rails.env.production?`) 선례가 있다. | 위반으로 보기는 어렵다. 결제 채널 선택은 환경 이름에 묶는 쪽이 플래그 오설정(비운영에서 라이브 플래그를 켬)보다 안전하고, `env:` 주입으로 테스트가 고정된다. 다만 규약 문자와 달라서 명시적으로 다룰 필요는 있다. | 규약 §9.4에 "결제 채널처럼 실패 비용이 큰 분기는 환경 이름 직접 비교를 허용(BaroBill·PortOne 선례)" 예외를 추가하거나, 규약대로 `config.x` 플래그로 바꾼다. 선택은 오케스트레이터와 사용자 판정. |
| W-4 | WARNING | `AGENTS.md:211` | 운영 노트가 "로컬에서 결제창·카드 등록을 실제로 띄워 확인할 수 있다(실제 결제 없음)"라고 단정한다. 테스트 채널에서 실제 결제가 안 되는지는 포트원 콘솔의 채널 등록 상태에 달려 있다(01_plan 리스크 2, 03 남은 리스크 3이 스스로 "확인 필요"라고 적은 항목)이고, 지금까지 확인된 적이 없다. B-1의 `_test` 키와 스토어 소속 문제가 겹치면 로컬 결제창이 아예 뜨지 않을 수 있다. | 문서만. 사용자가 로컬에서 결제 버튼을 눌러도 된다고 잘못 알 수 있다. | "(실제 결제 없음)"을 "테스트 채널로 등록된 경우에 한한다. 로컬 브라우저로 확인하기 전까지는 단정하지 않는다"로 바꾼다. `LAUNCH_TEST_SCENARIOS.md` §2.1의 "로컬에서 결제하기 버튼은 누르지 않는다"는 확인 뒤에 단다. |

### B-1 상세

배포 전에 확인해야 하고 리뷰에서는 확인할 수 없는 것:

- a) 바뀌지 않은 `api_secret`이 바뀐 `store_id`에서 유효한지.
- b) `_test` 채널 키가 현재 `store_id` 스토어에 속하는지. 옛 스토어에서 발급된 키라면 비운영 환경의 결제·빌링키 발급이 스토어-채널 불일치로 실패한다(이 작업의 목적과 어긋남).
- c) 새 스토어의 웹훅 URL(`POST /webhooks/portone`) 설정.
- d) 운영 DB에 옛 스토어로 발급된 빌링키·주문이 있으면 차감·조회·환불이 안 된다(코드는 `store_id`를 하나만 쓴다).

맥락(사용자의 미추적 문서 `LAUNCH_TEST_SCENARIOS.md`): §1 #4 "실제 결제와 환불이 한 번도 운영에서 실행된 적이 없다", §2.1 "로컬도 결제 키는 운영과 같다. 실제 결제가 된다"(변경 전 서술이고, 지금 `_test`로 이름 붙은 값이 그 "운영 키"다). 즉 지금까지 운영은 실결제가 아니었을 가능성이 높고, 이 credentials가 실결제 전환 스위치일 수 있다. 그렇다면 더욱 조용히 묻어 가면 안 된다.

"현재 운영은 HEAD 값을 쓴다"는 것은 Kamal이 git 커밋본으로 이미지를 빌드한다는 점(AGENTS.md "배포 전 커밋 필수")에 근거한 추정이다. 운영 서버에는 접근하지 않았다.

---

## 2. 중점 항목 판정

### 1. 운영 경로 불변 — 코드 수준 확인함, 값 수준 성립하지 않음(B-1)
- `channel_key.rb:29-30`: `env.to_s == "production"`이면 접미사가 빈 문자열이라 `:"channel_key_billing"`·`:"channel_key_normal"`을 읽는다. 기존 코드의 `credentials.dig(:portone, :channel_key_…)`와 같은 키 이름, 같은 `Rails.application.credentials` 객체다. 실행 확인: `fetch(:billing, env: "production")`이 기존 값을 그대로 돌려준다(true, normal도 true).
- 환경 판정: `Rails.env`의 클래스는 `ActiveSupport::EnvironmentInquirer`(StringInquirer 계열)이고 `to_s == "production"`은 true. `StringInquirer.new("production")`, 심볼, 문자열 모두 같은 결과. `Dockerfile:25`가 `RAILS_ENV="production"`이고 `config/environments/`는 development·production·test 3개뿐이다.
- 값 수준: 작업트리 credentials가 `store_id`와 채널 키 2개의 값을 바꿨다(B-1).

### 2. 라이브 키 유출 경로 — 확인함, 잔존 없음
- `grep -rn "channel_key\|channelKey\|channel-key" app config lib`: credentials를 읽는 곳은 `channel_key.rb:30`뿐이다. `dig(:portone` 전체는 `store_id` 3곳(컨트롤러), `api_secret`·`store_id`(ClientService 초기자), `channel_key.rb:30`이다.
- ENV·상수 경로 없음. `db/schema.rb`에 채널 키 컬럼 없음. `Order.metadata` 스냅샷을 채널 키 공급으로 읽는 코드 없음. JS의 `channelKey: String`에 기본값 없음(`portone_billing_controller.js:17`, `portone_payment_controller.js:17`). 뷰·헬퍼·초기자의 credentials 직접 읽기 없음(채널 키).
- 저장소 724개 파일 평문 스캔(`api_secret`과 라이브 채널 키 2개): 0건. `config/master.key`는 추적되지 않는다. 테스트의 키 값은 `"test-channel-billing"`·`"ch_billing"` 가짜값이다.
- 우회구 하나: `UpgradeService#portone_channel_key_billing`(`upgrade_service.rb:250`)의 `@channel_key ||`는 선택기를 건너뛴다. 앱 코드에서 `channel_key:`를 넘기는 호출처는 0건이다(테스트 전용). 승인된 설계라 이슈로 세지 않았다.

### 3. fail-closed — 서버는 확인함, 프런트엔드 단건 결제는 미흡(W-1)
- ① 뷰: 카드 등록은 `billings/show.html.erb:106`(키와 연락처), `:127`(키만), `:133-136`(else, "결제 채널이 설정되지 않았습니다")로 버튼을 막는다. 단건 결제 3곳은 분기가 없다.
- ② `UpgradeService`: 발급(`upgrade_service.rb:157-161`)과 차감(`:179-183`)이 `ClientService#issue_billing_key:33`, `#charge_billing_key:44`의 `ensure_channel_key!`에서 `request` 앞에 실패한다. 실행 확인: `request`를 재정의한 Probe 클래스로 nil·`""`·`"   "` 모두 ArgumentError이고 request에 닿지 않았다.
- ③ 삼킴·우회: 없다. `rescue_from` 0건, 예외 클래스 없는 `rescue` 0건. 경로 위의 rescue는 `PortOne::ApiError`(서비스 2곳)와 `UpgradeError`(컨트롤러 1곳, 잡 2곳)뿐이다. `rescue StandardError` 10곳은 전부 채널 키 경로 밖이다.

### 4. 예외 전파 — 데이터 오염 없음, 잡의 실패 방식은 개선 여지(W-2)
- ① 카드 등록 콜백 `App::SubscriptionsController#update:23-31`: `ArgumentError`는 500. 수용 가능하다. 설정 오류이고 상태 변경이 없다(`activate!`는 인자 평가에서 실패해 호출되지 않는다). 키가 없으면 UI에 버튼 자체가 없어 위조 `issue_token` 요청만 500에 닿는다.
- ② 잡: `retry_on`이 둘 다 없어 재시도 폭증이 없다. 구독 상태를 바꾸지 않는다(트랜잭션 롤백, `record_charge_failure!` 미호출). 부작용은 W-2.

### 5. 테스트 밀봉·환경 의존 — 확인함, 기존 테스트에 로컬/CI 편차 없음
- 컨트롤러 테스트 3종은 채널 키 값을 단언하지 않는다. `billings_controller_test.rb:101-103`은 data-controller 존재와 payment-id·amount만, `tax_invoice_gate_test.rb:174-176`은 안내 문구와 위젯 미렌더만 본다.
- 실제 `ClientService`의 가드에 nil 키로 닿는 기존 테스트는 0건이다. 컨트롤러 테스트는 `with_portone_client`로 `ClientService.new`를 FakePortOneClient로 통째로 바꾸고, 서비스 테스트는 `channel_key:`를 주입하고, 잡을 직접 실행하는 테스트(`dunning_retry_test.rb:65, 91, 123, 142, 166, 190`, `refund_service_test.rb:204`)는 대역을 쓰거나 no-op 경로다.
- 뷰의 존재 여부 분기도 바뀌지 않았다. 이 Mac은 변경 전(라이브 키)과 후(테스트 키) 모두 present, CI는 마스터 키가 없어(`.github/workflows/ci.yml:95, 123`) 전후 모두 nil이다.
- 선택기와 가드를 검증하는 테스트는 아직 없다(`test/services/port_one/channel_key_test.rb` 미존재, Tester 단계). 시스템 테스트 중 카드 등록·결제 버튼을 누르는 것은 없다.

### 6. `fetch` 구현 — 확인함
- `kind.to_s.to_sym`: nil은 `:""`가 되어 거절된다. 실행 확인 결과 `:billing`과 `"billing"`은 같은 값을 돌려주고, nil·`""`·`"BILLING"`·`" billing"`·`"billing_test"`·정수·배열은 모두 ArgumentError다.
- credentials 키 타입은 심볼이다. Rails 8.1.4.1의 `EncryptedConfiguration#config`가 `deep_transform_keys(&:to_sym)`로 심볼화하고(`encrypted_configuration.rb:85-87`) 실제 키 클래스도 Symbol이다. 심볼 조회가 맞다. 참고로 문자열 키 일반 Hash를 `credentials:`로 넘기면 nil이 된다. 새 테스트가 credentials를 직접 만들 때는 심볼 키를 써야 한다.
- 기본 인자는 호출 시점에 평가된다(루비 기본 인자). `credentials: nil`을 명시하면 `nil.dig`로 NoMethodError가 나지만 기본값은 절대 nil이 아니다(첫 검증 실행에서 제 스크립트가 이 값으로 중단됐다. 선택기 결함은 아니다).

### 7. 가드 범위 — 확인함
- `channel_key:`를 받는 public 메서드는 `issue_billing_key`와 `charge_billing_key` 2개뿐이다(실행 확인). `confirm_payment`는 위젯에서 이미 만들어진 결제의 확정이고 `get_payment`·`cancel_payment`·웹훅 재조회는 채널 키가 필요 없다. 결제를 새로 만드는 경로는 전부 채널 키를 거친다(서버 2곳은 가드, 프런트엔드 4곳 중 3곳은 빈 키로 버튼이 활성: W-1).

### 8. 아키텍처 — 위반 없음, 관찰 1건
- 의존 방향: 컨트롤러가 선택기를 부르는 것은 허용되고, `Subscriptions::UpgradeService`가 `PortOne::ChannelKey.billing`만 쓰는 것은 타 도메인 공개 진입점이다(§4.3). 선택기는 params·Current를 쓰지 않는다(§4.2). 뷰는 `@portone_channel_key_*`만 쓴다. Job은 Service만 부른다.
- 위치·네이밍: `app/services/port_one/channel_key.rb`가 `PortOne::ChannelKey`다. `*Service`·`#call` 꼴은 아니지만(§3.5) §4.3의 "공개 진입점(단일 모듈 메서드)"에 해당하고 같은 디렉터리의 `PortOne::ApiError` 선례가 있다. 적합하다.
- 관찰(이번 변경과 무관): `App::BillingsController#show` 본문이 18줄(주석 제외 13문장)로 10줄을 넘는다. 변경 전에도 17줄이었고 이번에는 주석 1줄만 늘었다. 나중에 `set_portone_context` before_action으로 뽑으면 다른 컨트롤러 2개와 같아진다.
- §9.4 환경 분기 방식은 W-3.

### 9. 문서·주석 정합 — 부분 정합
- 맞는 것: `03_implementation.md`의 줄 번호 전부, "직접 참조 0건", 테스트 수치(1,582건·9,958 단언·0실패, rubocop 425파일 0건, zeitwerk 통과). `client_service.rb:70-72` 주석과 뷰 문구(`show.html.erb:135`)는 코드와 맞다.
- 틀린 것: "운영 동작 변화 없음"(01_plan 리스크 4, 03 §5와 남은 리스크 2)은 B-1. "결제창 비활성 안내"(`PRD.md:214`, `AGENTS.md:211`)는 W-1. "(실제 결제 없음)"(`AGENTS.md:211`)는 W-4. `channel_key.rb:3-4`와 PRD 문단의 "지금까지 로컬에서도 라이브 채널 키가 쓰였다"는 B-1과 맞지 않는다(지금까지의 값이 사용자가 `_test`로 이름 붙은 값이다).

---

## 3. Rule ID 준수 매핑

| Rule ID | 판정 | 근거 |
|:---|:---|:---|
| PLAN-5 채널 키 환경 분리 | 코드는 준수, 운영 값 변경은 미확정 | 단일 진입점, 비운영은 `_test` 키, 라이브 대체 없음. 값 수준은 B-1 |
| PLAN-5 dunning(결제 실패 재시도) | 준수 | 키 부재는 `record_charge_failure!`를 거치지 않아 실패 주문·단계 진행이 없다(카드 거절과 구분됨) |
| PLAN-4·LEGAL-2·TAX-1(단건 결제) | 동작 불변 | 승인·조회·취소 경로는 무변경, 채널 키 공급만 바뀜 |
| SEC-5(멱등) | 준수 | 키 부재 시 선기록 pending 주문이 롤백된다. 포트원 멱등 키 로직 무변경 |
| ADMIN-4(실패 주문·매출) | 준수 | 설정 오류가 실패 주문으로 남지 않아 ADMIN-4·ADMIN-5 집계가 오염되지 않는다 |

---

## 4. 확인한 것 / 확인하지 못한 것

### 확인한 것 (코드·실행)
- 운영 분기가 기존 credentials 키 이름·값을 그대로 읽는다. 환경 판정이 `EnvironmentInquirer`에서 동작한다.
- development·test·staging과 "Production"·"prod"처럼 대소문자가 다른 값은 모두 테스트 키로 가고 라이브 키를 돌려주지 않는다.
- 키가 없으면 nil이다(빈 credentials, 라이브 키만 있고 비운영, 테스트 키만 있고 운영). 가드는 nil·빈 문자열·공백에서 API 호출 전에 실패한다.
- credentials 키 타입은 심볼이고, kind 정규화는 의도대로 동작한다.
- 코드베이스에 라이브 채널 키를 직접 읽거나 하드코딩한 곳이 없고, 저장소에 평문 시크릿이 없다.
- 작업트리 credentials의 `store_id`·채널 키 2개 값이 HEAD와 다르고, 새 `_test` 키가 HEAD의 기존 키와 같다.
- 기존 테스트에 로컬/CI 편차를 만드는 경로가 없다. 전체 테스트와 시스템 테스트가 통과한다.
- 채널 키 경로에 `ArgumentError`를 삼키는 광역 rescue가 없고, 두 잡에 `retry_on`이 없다.

### 확인하지 못한 것
- 바뀐 `store_id`와 채널 키 4개의 실제 성격(라이브인지, 어느 스토어에 속하는지, `api_secret` 권한, 웹훅 설정, KG이니시스 라이브 채널 상태). 포트원 콘솔과 실제 호출이 필요하고 실호출은 금지다. B-1의 a~c는 전부 여기에 속한다.
- 운영 DB에 옛 스토어로 발급된 빌링키·주문이 있는지. 운영 서버에 접근하지 않았다.
- 포트원 SDK가 빈 `channelKey`로 호출됐을 때의 동작(W-1의 "돈 영향 없음"은 추정이다).
- 잡 경로의 롤백은 코드 독해로만 확인했다(임시 테스트 금지).
- 로컬 브라우저에서 테스트 채널 결제창이 뜨는지.
- GitHub Actions CI의 실제 실행. CI 조건(credentials 비어 있음)을 로컬에서 재현하지는 않았고, 정적 조사로 환경 의존 테스트가 없음을 확인했다.

---

## 5. 실행한 명령과 결과

| 명령 | 결과 |
|:---|:---|
| `mise exec -- bin/rails test` | 1,582 runs, 9,958 assertions, 0 failures, 0 errors, 0 skips |
| `mise exec -- bin/rails test:system` | 14 runs, 131 assertions, 0 failures, 0 errors, 0 skips |
| `mise exec -- bin/rubocop` | 425 files inspected, no offenses |
| `mise exec -- bin/rails zeitwerk:check` | all is good |
| `mise exec -- bin/brakeman --no-pager -q` | Errors 0, Security Warnings 0 |
| `mise exec -- bin/rails runner -`(development, credentials만 읽고 네트워크 없음, 값 미출력) 4회 | 아래 표 |

| 검증 | 결과 |
|:---|:---|
| portone 블록 | 키 6개, 키 클래스 Symbol, 채널 키 4개 모두 present(길이 48) |
| 운영 분기 동일성 | `fetch(billing, env: "production")`이 기존 키 값과 동일(true, normal도 true). StringInquirer·EnvironmentInquirer 동일 |
| 비운영 분기 | development·test·staging·Production·prod 모두 테스트 키, 라이브 false |
| fail-closed | 빈 credentials에서 nil, 라이브만 있고 비운영에서 nil, 테스트만 있고 운영에서 nil |
| kind 16종 | `:billing`·`"billing"`·`:normal`·`"normal"`만 통과, 나머지 12종 ArgumentError |
| 가드(Probe, `request` 재정의) | nil·`""`·`"   "`는 ArgumentError이고 request 미도달. `channel_key:`를 받는 public 메서드 2개 |
| credentials HEAD 대비 | portone 값 변경 3개(`store_id`·`channel_key_billing`·`channel_key_normal`), 추가 2개, `api_secret` 동일, portone 외 5개 항목 동일 |
| 값 동일성 | HEAD `channel_key_billing` == 작업트리 `channel_key_billing_test`, HEAD `channel_key_normal` == 작업트리 `channel_key_normal_test` |
| 커밋 이력 | portone 4개 키는 `5c28d8e`(2026-10-15) 이후 변경 0회. local main == origin/main |
| 평문 스캔 | 724개 파일 중 0건 |

- 검증 중 오류 1회: 첫 runner에서 `credentials: nil`을 넘겨 NoMethodError로 중단됐다(제 스크립트 문제). 고쳐서 재실행했다.
- 작업트리 무변경: 검증 전후 `git status --short` 27항목, 해시 동일. 임시 테스트 파일 없음. HEAD 커밋본 비교에 쓴 임시 디렉터리는 자동 삭제됨.

---

## 6. Tester 중점 테스트 제안

1. **선택기**(`test/services/port_one/channel_key_test.rb`): 운영이면 base 키, development·test·staging이면 `_test` 키. 비운영인데 테스트 키가 없으면 라이브 키가 있어도 nil. 운영인데 라이브 키가 없으면 nil. kind는 문자열·심볼 동등, nil·`""`·`"BILLING"`·`"billing_test"`·정수는 ArgumentError. `env:`에 `ActiveSupport::EnvironmentInquirer.new("production")`도 통과. 반드시 `env:`·`credentials:`를 주입할 것(심볼 키 Hash).
2. **클라이언트 가드**(`client_service_test.rb`): `issue_billing_key`·`charge_billing_key`에 nil·`""`·`"   "`를 넣으면 ArgumentError이고 `FakePortOneTransport.requests`가 비어 있다(가드 추가로 생긴 경로라 기존 테스트에 없다).
3. **컨트롤러 3종**: `PortOne::ChannelKey`를 고정값으로 바꿔 `billings#show`(카드 등록 위젯·체크아웃), `legal_documents#show`, `tax_invoices#show`의 `data-*-channel-key-value`가 그 값인지 확인. 빌링 키가 nil이면 "결제 채널이 설정되지 않았습니다"가 나고 `portone-billing` 컨트롤러 요소가 없는지 확인.
4. **`UpgradeService` 기본 경로**: `channel_key:`를 주입하지 않고 선택기를 고정값으로 바꿔 `fake.calls[:issue_billing_key]`·`[:charge_billing_key]`의 `channel_key`가 선택기 값인지 확인(주입값이 우선하는 기존 테스트와 함께).
5. **예외 전파**: 키가 nil일 때 `action: :renew`·`:retry_charge`가 `UpgradeError`가 아니라 가드 예외로 끝나는지, 구독 상태·dunning 단계·주문 수가 변하지 않는지(롤백). `SubscriptionRenewalJob`은 W-2 수정 뒤에는 뒤순번 구독이 계속 처리되는지까지.
6. **단건 결제 뷰**(W-1 결정에 따라): normal 키가 nil일 때 버튼이 막히는지, 아니면 현재 동작이 유지되는지를 고정.
7. **CI 동등성**: 새 테스트 전부가 credentials가 비어 있는 조건에서도 같은 결과인지(로컬 credentials 값을 절대 기대값으로 쓰지 않는다).
8. 전체 회귀는 Developer가 이미 돌렸고 이번 리뷰에서도 재현했다(1,582건, 시스템 14건).

---

## 7. 운영상 주의

1. **커밋·배포 게이트(B-1)**: 사용자가 운영 스토어·채널 키 교체를 확인하기 전까지는 `config/credentials.yml.enc`를 커밋·배포하지 않는다. 코드만 먼저 배포하는 것은 안전하다(운영은 base 키를 그대로 읽는다).
2. **credentials는 코드와 별도 커밋**: 결제 채널 전환은 코드 롤백으로 되돌릴 수 없다.
3. **커밋 범위**: 작업트리에 이번 작업 밖의 미커밋 변경이 섞여 있다(`ALIMTALK_TEMPLATES.md`, `_workspace_prev/*`, 미추적 `LAUNCH_TEST_SCENARIOS.md`). B-1 해소와 무관하게 커밋을 나눈다.
4. **격리 범위**: 채널 키 분리가 나누는 것은 결제 생성 경로뿐이다. `api_secret`·`store_id`는 환경 공통이라 비운영에서도 `get_payment`·`cancel_payment`는 같은 스토어 API에 닿는다.
5. **키 부재 상태 복구(W-2)**: credentials를 복원한 뒤 멈춘 dunning 구독은 `Subscriptions::DunningRetryJob.perform_later(id)`로 수동 재실행해야 한다.
6. **로컬 DB 빌링키**: 로컬에 남은 빌링키가 `_test` 채널·현재 `store_id`와 맞지 않으면 다시 등록해야 한다(01_plan 리스크 1).

---

## 재리뷰 (2026-11-25 — B-1·W-1~W-4 반영 확인)

status: CHANGES_REQUESTED

**BLOCKER 1 · CRITICAL 1 · WARNING 1** · 관찰 3(이슈로 세지 않음)

재리뷰 대상 변경분(`PortOne::ChannelKey` 플래그 전환·`MissingChannelKey`·잡 rescue·단건 결제 3곳 분기·문서)은 B-1·W-1~W-4를 모두 반영했고, 변경분 안에서 코드 결함은 찾지 못했다. **CHANGES_REQUESTED는 변경분 결함 때문이 아니다.** 중점 5(간접 경로)를 추적하던 중에 결제 확정 경로에 서버 측 검증(금액·테스트 채널 여부)이 없다는 기존 공백을 확인했다(R-1·R-2). B-1 해소로 운영이 처음 라이브 채널을 쓰게 되면 이 공백이 유효해진다.

**R-1·R-2를 반영하기 전까지 `config/credentials.yml.enc`(운영 스토어 전환)은 커밋·배포하지 않는다.** 코드 변경분만 먼저 커밋하는 것은 안전하다(운영은 지금 credentials 값을 그대로 읽는다).

---

### 1. 항목별 반영 판정

| 항목 | 판정 | 근거 위치 |
|:---|:---|:---|
| B-1 | **해소됨**(사용자 판정 + 문서 정정). 잔존 R-3 | `AGENTS.md:212` 노트 — 운영 스토어 전환이 의도, 배포 시 운영 결제가 새 스토어로 나감, `api_secret` 유효 확인, ②③ 미확인, 별도 커밋. `_workspace/01_plan.md:108-109`, `_workspace/03_implementation.md:53-57, 156-162`. 코드·뷰·config 주석에 "운영 변화 없음"류 서술 0건 |
| W-1 | **해소됨** | `_checkout.html.erb:25-41` · `legal_documents/show.html.erb:77-93` · `tax_invoices/show.html.erb:110-124` — 키 없음 → 안내 / 키·연락처 있음 → 버튼 / 키만 있음 → 연락처 안내. 바깥 `data-controller="portone-payment"` 블록 유지 |
| W-2 | **해소됨** | `client_service.rb:15-18, 78-82`(`MissingChannelKey < StandardError`) · `subscription_renewal_job.rb:16-19` · `dunning_retry_job.rb:34-37` — 두 잡 모두 그 예외만 잡는다 |
| W-3 | **해소됨** | `config/environments/production.rb:98-101`(플래그의 유일한 정의) · `channel_key.rb:19-21, 33-39`(`== true`, `live:` 인자) |
| W-4 | **해소됨** | `AGENTS.md:212` — "브라우저로 확인하기 전까지는 단정하지 않는다", "테스트 채널에서 실제 결제가 일어나지 않는지도 … 단정하지 않는다". 변경 기록 `02_prd_update.md:18`에는 옛 문구가 남는다(R-3) |

---

### 2. 새로 발견한 이슈

| ID | 심각도 | 위치 | 문제 | 영향 | 제안 수정 |
|:---|:---|:---|:---|:---|:---|
| R-1 | **BLOCKER** (라이브 전환 전 필수 — 기존 코드 공백) | `app/services/port_one/client_service.rb:27-33`(`confirm_payment`가 `storeId`·`paymentToken`만 전송) · `app/services/orders/purchase_service.rb:65-71, 77-90` · `app/services/orders/fulfill_pass_service.rb:13-32` · `app/controllers/webhooks/portone_controller.rb:53-60, 71-90` · `_workspace_prev_fplan/05_review.md:51` | **결제 금액을 서버가 검증하지 않는다.** ① 승인 요청에 `totalAmount`가 없다 — 공식 OpenAPI v2(1.16.0) `ConfirmPaymentBody.totalAmount`: "검증용 파라미터로, 결제 건 총 금액과 일치하지 않을 경우 오류가 반환됩니다. 값 전달을 권장합니다." ② 재조회(`recheck_payment!`·웹훅)는 결제 상태(웹훅은 결제 ID 일치도)만 본다 — 응답의 `amount.paid`(공식 `PaymentAmount` required "실제 결제금액")를 `order.amount`와 비교하는 곳이 없다. ③ `FulfillPassService`는 바로 paid 전환·발급한다. 공식 가이드 "인증 결제 연동하기 §4"는 **결제 검증 필수**다("결제 금액 등 정보가 고객의 브라우저 측에서 처리되므로, 의도한 결제 내용이 맞는지 꼭 확인하여야 위변조를 막을 수 있습니다") — 예시도 금액을 먼저 비교한다. 과거 F-PLAN 리뷰의 "금액 변조 방어됨"과 `client_service.rb:27-29` 주석은 "포트원 confirm이 금액을 검증한다"는 가정인데, `totalAmount`를 넘길 때만 검증하므로 성립하지 않는다. | 로그인 사용자가 자기 대기 주문의 `paymentId`(주문번호로 화면 노출)로 포트원 SDK를 직접 호출해 낮은 금액을 넣어 결제하면, 서버는 PAID면 정가 주문을 paid로 확정하고 발급물을 준다 — 수금 패스 4,000원·내용증명 5,000원·세금계산서 300원(발행은 바로빌 실비 발생). 타인 주문 침해는 아니다(소유권 격리는 그대로). Plus 갱신은 서버가 금액을 지정하는 빌링키 차감이라 영향 없다. 환불 경로(`refund_service.rb:158-163`)는 이미 `amount.paid`를 비교하고 있어 구매 확정 경로만 빠져 있다. 지금(테스트 채널)은 실금액이 없어 노출이 없고 **라이브 채널 전환 순간 유효해진다**. [추정] 소액 결제가 실제 PAID로 확정되는지는 재현하지 않았다(실호출 금지). 근거는 코드 3경로와 공식 스펙·가이드 원문이다. | ① `confirm_payment`에 `totalAmount`(주문 금액)를 전달한다. ② 재조회 경로(`recheck_payment!`·`recover_from_recheck!`)와 웹훅 `settle_paid` 앞에 공용 검증을 둔다 — `payment.dig(:amount, :paid)`가 `order.amount`와 같고 취소분이 0인지. 불일치면 paid 전환 금지·주문 failed(또는 보류)·관리자 알림. `redirectUrl` 방식(모바일 기본)은 `paymentToken`이 없어 재조회 경로로만 확정되므로 ②가 실질적 방어다. ③ `settle_renewal`(`upgrade_service.rb:129-151`)에도 같은 검증기를 적용한다. ④ `_workspace_prev_fplan/05_review.md:51`의 "방어됨"과 `client_service.rb:27-29` 주석을 정정한다. |
| R-2 | **CRITICAL** (전제 확인 요청 — 라이브 전환 전 필수) | R-1과 같은 경로 · `app/services/port_one/channel_key.rb:19-39`(분리 범위는 결제 **생성** 경로) · `config/credentials.yml.enc`(스토어 ID·API 시크릿은 환경 공통) | **운영이 테스트 채널 결제를 paid로 받아들일 수 있다.** 이 변경으로 운영은 라이브 채널, 비운영은 `_test` 채널을 쓰는데 스토어는 하나다(사용자 확인: 테스트 채널 2개는 새 스토어의 채널). 확정 경로는 결제가 어느 채널로 만들어졌는지 보지 않는다. 공식 스펙 `ConfirmPaymentBody.isTest`: "검증용 파라미터로, 결제 건 테스트 여부와 일치하지 않을 경우 오류가 반환됩니다. 값 전달을 권장합니다"(미전달). 재조회 응답 `PaidPayment.channel.type`은 `LIVE`·`TEST`(required)인데 코드가 읽지 않는다. 포트원 콘솔 가이드는 테스트 결제를 "테스트 채널로 시도된 결제 거래 건"으로 정의하고, 테스트 채널은 같은 스토어의 결제 연동 페이지에 추가한다. | [추정 — 전제 2개] ㉠ `_test` 채널이 실제 금액이 결제되지 않는 테스트 채널일 것(설계·PRD의 전제). ㉡ 테스트 채널 키를 알면 운영 스토어에서 그 채널로 결제할 수 있을 것. 둘이 성립하면 로그인 사용자가 **0원으로** 수금 패스·내용증명 PDF·세금계산서 발행을 받는다(R-1과 같은 수법, 채널만 다름). 채널 키는 비밀이 아니다 — 이전 운영 채널 키와 같은 값(1차 리뷰 B-1 확인)이고 비운영 화면의 HTML에 노출된다. Plus 구독은 빌링키 발급이 서버 경로라 막힌다. 웹훅 경로도 같다(콘솔의 V2 테스트 웹훅 URL이 운영 주소면 콜백 없이도 확정된다). | ① `confirm_payment`에 `isTest: !PortOne::ChannelKey.live_channel?`를 전달한다 — 운영은 테스트 결제를 거절하고 비운영은 라이브 결제를 거절한다(양방향 격리). ② 재조회·웹훅에서 `payment.dig(:channel, :type)`이 기대값(`live_channel?`면 `"LIVE"`, 아니면 `"TEST"`)과 다르면 paid 전환 금지·보류. ③ `AGENTS.md:212` 노트 ②를 "포트원 콘솔 **V2 실연동** 탭 웹훅 URL에 운영 주소를 등록하고, **V2 테스트** 탭은 운영 주소로 두지 않는다"로 보강한다(콘솔 가이드 — 웹훅 URL은 두 탭에서 각각 설정). ④ 사용자 확인: 포트원 콘솔에서 `_test` 채널 2개의 환경이 '테스트'로 표시되는지. |
| R-3 | WARNING (문서) | `_workspace/01_plan.md:77`("운영은 라이브 키를 그대로 쓴다") · `:124-125`(리스크 4 — "이 작업과 함께 커밋해야 … 운영 동작 변화는 없다") · `:96`(Tester 지시가 `env:` 인자를 지시 — 현재 API는 `live:`) · `_workspace/02_prd_update.md:18`("(실제 결제 없음)") · `_workspace/03_implementation.md:98, 103-104, 128` · `LAUNCH_TEST_SCENARIOS.md:48, 867`(미추적 사용자 문서) | 01_plan의 낡은 두 서술이 같은 파일의 결정·정정(`:108`, `:112-113`)과 모순된 채 남아 있다(한쪽은 "코드와 함께 커밋", 다른 쪽은 "별도 커밋"). 03 `:98`의 "CI … 테스트 키가 보인다"는 사실과 다르다 — CI는 마스터 키를 주입하지 않아(`.github/workflows/ci.yml:95, 123`) 어느 경우도 키가 보이지 않는다. 03 `:103-104`·01_plan `:122-123`의 "테스트 채널 결제도 운영 웹훅 주소로 갈 수 있다"는 웹훅 URL이 탭별 설정이라는 조건이 빠져 있다. 03 `:128`은 `:78~85`인데 실제는 `:78-82`다. LAUNCH `:48`의 "로컬도 결제 키는 운영과 같다"는 이 변경 뒤 틀리다(로컬은 `_test` 키). | 단일 소스(PRD·AGENTS)는 정확하고 작업 문서만 해당되므로 실행 영향은 없다. 다만 Tester가 01_plan `:96`만 읽으면 없는 인자를 쓰고, 운영 담당이 리스크 4만 읽으면 credentials를 코드와 묶어 커밋할 수 있다. | 해당 줄에 정정 표시(삭제선 또는 "→ 결정·정정 참조"). `LAUNCH_TEST_SCENARIOS.md`는 사용자 문서라 에이전트가 수정하지 않고 사용자에게 알린다("로컬에서 결제 버튼은 누르지 않는다"는 `_test` 채널의 실결제 여부를 확인할 때까지 유효). |

**관찰(이슈로 세지 않음)**

- **O-1 단건 결제 안내 문구**: 3곳 모두 "결제 채널이 설정되지 않았습니다. 포트원 채널 키를 credentials(:portone)에 등록하면 결제가 활성화됩니다." — 기존 요금제 카드 등록 안내(`billings/show.html.erb:133-137`)와 첫 문장·구조·색·`role="status"`가 같아 선례 대비 개발 용어가 과하지 않고 4곳이 일관된다. 다만 회원이 볼 수 있는 문구로는 `credentials(:portone)`이 회원이 할 수 있는 행동이 아니다(같은 코드베이스의 다른 준비 중 안내는 "… 현재 준비 중입니다" 형태 — `TaxInvoice::FEATURE_DISABLED_NOTICE`). 운영에서 이 상태는 credentials 누락(배포 장애)일 뿐이라 권고만 남긴다 — 회원 문구는 "결제 서비스를 일시적으로 이용할 수 없습니다. 고객지원(문의)으로 연락해 주세요"로 두고 기술 안내는 로그로 옮기는 편이 회원에게 낫다. 판정: 기준 준수.
- **O-2 `config.x`의 미정의 값은 nil이 아니다**: Rails 8.1의 `config.x`는 `Configuration::Custom`인데, 정의되지 않은 키를 읽으면 빈 `OrderedOptions`(truthy)를 만들어 돌려준다(`railties-8.1.4.1/lib/rails/application/configuration.rb:71, 620-631`). 실행 확인 — development에서 플래그 값의 클래스가 `OrderedOptions`이고 `live_channel?`는 false다. `== true` 비교 덕분에 fail-closed가 유지된다. 이 비교를 truthy 검사로 바꾸면 모든 환경이 라이브가 되므로 `== true`를 지키고, `channel_key.rb:17`·03·AGENTS의 "nil" 서술은 "nil·미정의·그 외 값"으로 맞춘다.
- **O-3 시스템 테스트 첫 실행 1건 실패**: `AppLegalDocumentPdfTest`의 로그인 단계("로그인되었습니다." 미검출 — 변경 뷰에 도달하기 전). 재실행 3회와 단일 파일 실행에서 모두 통과해 재현되지 않았다. 변경분과 무관하다.

---

### 3. 중점 항목 판정

**1. W-3 반영 — 통과**

- 플래그 정의: 저장소 전체에서 `config.x.portone_live_channel = true`는 `config/environments/production.rb:101` 한 곳이다(`Rails.application.configure` 블록 안, `ruby -c` 통과). `development.rb`·`test.rb`·`application.rb`·`config/initializers/*`·`config/deploy.yml`에 정의가 없고 ENV 우회 경로도 없다(`tax_invoice_enabled`와 달리 ENV를 읽지 않는다).
- fail-closed(실행 확인, development): `true`만 live. `false`·`nil`·`"true"`·`1`·`:true`·`"1"`·`[]`·미정의 값은 모두 `live_channel? == false`이고 `.billing`이 `_test` 키를 돌려준다.
- 기본 인자의 호출 시점 평가(실행 확인): 플래그를 true로 바꾸면 다음 호출에서 base 키, nil로 되돌리면 `_test` 키. `Rails.application.credentials`를 가짜 Hash로 임시 교체하면 다음 호출에 반영된다(심볼 키). 테스트가 `config.x`·credentials를 바꾸면 반영된다.
- 운영 경로 불변: `fetch(:billing, live: true)`·`fetch(:normal, live: true)`가 `credentials.dig(:portone, :channel_key_billing)`·`:channel_key_normal`과 같은 값을 돌려주고 키 이름은 기존 코드와 같다. `RAILS_ENV=production` 부팅은 실행하지 않았다(부작용 회피) — 101행 정적 확인과 development 플래그 토글로 갈음한다.
- 주의는 O-2 하나다.

**2. W-2 반영 — 통과**

- ① `MissingChannelKey < StandardError`(`client_service.rb:18`)이고 가드는 `ArgumentError` 대신 이것을 던진다(`:81`). 실행 확인: nil·`""`·`"   "` 모두 `PortOne::ClientService::MissingChannelKey`이고 `request`에 닿지 않는다.
- ② 두 잡의 rescue는 `UpgradeError`(기존)와 `MissingChannelKey`(신규)뿐이다. 계층 확인: `MissingChannelKey`는 `ApiError`·`UpgradeError`·`ArgumentError` 어느 쪽도 아니다(모두 `StandardError` 직계).
- ③ 갱신 잡 루프: rescue가 `find_each` 블록 안에 있어 그 반복의 예외만 흡수하고 다음 구독으로 넘어간다. 해지 후 만료 강등(`expire!`)은 클라이언트 호출이 없어 키 없음과 무관하게 처리된다.
- ④ 상태 변경 없음(코드 추적): `with_lock`은 `transaction do lock!; yield end`다(`activerecord-8.1.4.1/lib/active_record/locking/pessimistic.rb:97-104`). `charge_and_extend!`(`upgrade_service.rb:174-194`)에서 `prepare_renewal_order!`(`:235-245`, pending 주문 `create!`·`update!`) 뒤 `@client.charge_billing_key`의 가드가 던지면 `rescue PortOne::ApiError`(`:192`)에 걸리지 않고 블록 밖으로 나가 트랜잭션이 롤백된다. 잡이 바깥 트랜잭션을 열지 않아 롤백이 실제로 일어난다. `record_charge_failure!`·`advance_dunning!`는 호출되지 않아 구독 상태·`dunning_stage`·`next_retry_at`·주문 수가 그대로다. `Order`에는 콜백이 없다.
- ⑤ 구문: 변경 ruby 5개 파일 `ruby -c` 통과, rubocop 0건, zeitwerk 통과.
- ⑥ 다른 경로: `rescue_from` 0건. `App::SubscriptionsController#update`(`:23-31`)는 `UpgradeError`만 잡아 `MissingChannelKey`는 500으로 드러난다(`activate!`는 인자 평가에서 실패해 호출되지 않는다). 이 예외를 잡는 곳은 두 잡이 전부다.
- 운영 참고: 재시도 잡은 예외를 로그로 남기고 정상 종료하므로 Solid Queue 실패 집계에는 잡히지 않는다. `Rails.error.report` 대신 `Rails.logger.error`를 쓴 03 §8의 이유(프로젝트에 사용 예 없음)는 사실이다(`Rails.error` 0건). 키 복구 뒤 dunning 구독은 수동 재실행이 필요하다(1차 리뷰 §7-5와 같다).

**3. W-1 반영 — 통과**

- 분기 순서가 3곳에서 같다(키 없음 → 안내 / 키·연락처 있음 → 결제 버튼 / 키만 있음 → 연락처 안내).
- 기존 테스트(정적 판정): `billings_controller_test.rb:101-103`은 블록 존재·payment-id·amount만 단언해 키가 있는 로컬과 없는 CI가 같다. `tax_invoice_gate_test.rb:175-176`·`tax_invoice_eligibility_test.rb:145-146, 222`은 위젯 미렌더 경로의 부정 단언이다. "결제하기"를 긍정 단언하는 테스트 0건, 결제 버튼을 누르는 시스템 테스트 0건, 테스트 파일 변경 0건.
- 키 없음 상태: 버튼(`data-action="portone-payment#pay"`)이 렌더되지 않고 `portone-payment` 컨트롤러에는 `pay()` 액션뿐이라 SDK 호출 경로가 남지 않는다(`channelKey`가 빈 data 속성은 남지만 무해). 주문 생성은 막지 않는다(1차 리뷰 W-1의 선택 (a) 범위 그대로).
- 문구·디자인: 3곳이 같은 클래스(`mt-4 rounded-xl bg-amber-50 p-3 text-sm font-semibold text-stone-700`)·`role="status"`·같은 문구다. 인접한 "연락처" 안내와 같은 간격·모서리다. 금지 표현(LP-12)에 해당하지 않고 대비가 충분하며 비대화형이라 터치 타깃 해당이 없다. 문구 자체는 O-1.

**4. B-1 해소의 문서 반영 — 정합, 잔존 R-3**

- AGENTS 노트 두 항목·01_plan 결정·정정·03 §5/§8은 다음 사실과 맞다: 운영 스토어 전환은 의도, 이 credentials를 배포하면 운영 결제가 새 스토어로 나감, `api_secret`은 새 스토어에서 유효(직접 조회), 배포 전 확인 ②③은 미확인, credentials는 코드와 별도 커밋.
- "운영 변화 없음"류 서술: 코드 주석·뷰·config에 0건. 문서에서는 `_workspace/01_plan.md:77, 124-125`와 `_workspace/02_prd_update.md:18`에 남아 있다(R-3). PRD PLAN-5 문단(`PRD.md:214`)은 결제창·카드 등록 비활성 안내(3곳 분기로 참이 됐다)·API 미호출·단일 진입점·라이브 대체 금지를 서술하고 있어 구현과 모순되지 않는다.
- B-1 해소의 파생 검토에서 R-1·R-2를 확인했다. 문서 반영 자체는 정합이지만, 라이브 전환은 R-1·R-2 반영이 전제된다.

**5. 그 외 회귀 — 변경분이 만든 회귀 없음. 간접 경로에서 결제 확정 검증 공백 확인(R-1·R-2)**

- 변경 외 동작: `git diff HEAD` 기준 선택기 교체 4곳·가드·뷰 분기·잡 rescue·플래그뿐이다. `UpgradeService`는 선택기 1줄과 주석만 바뀌었다.
- 라이브 키가 비운영으로 새는 경로: 없음. 채널 키를 credentials에서 읽는 곳은 `channel_key.rb:38` 한 곳이고 `_test` 접미사는 live일 때만 빠진다. ENV·상수·`Order.metadata` 경유 공급 0건.
- 운영이 테스트 키를 "쓰는"(결제를 만드는) 경로: 없음 — 운영 화면은 base 키만 심는다.
- 운영이 테스트 채널 결제를 "받아들이는"(확정하는) 경로: 있음 — R-2. 같은 자리에서 금액 미검증(R-1)도 확인했다.

---

### 4. Rule ID 준수 매핑

| Rule ID | 판정 | 근거 |
|:---|:---|:---|
| PLAN-5 채널 키 환경 분리 | 준수(생성 경로) | 단일 진입점·비운영 `_test`·라이브 대체 없음·`== true` fail-closed |
| PLAN-4·LEGAL-2·TAX-1(단건 결제 확정) | **미준수 — 서버 검증 없음(R-1·R-2)** | 포트원 "결제 검증 필수"·`totalAmount`·`isTest` 권장 파라미터 미전달, 재조회 금액·채널 미비교 |
| PLAN-5 dunning | 준수 | 키 부재는 실패 주문·단계 진행 없이 건너뛴다(카드 거절과 구분) |
| SEC-5(멱등) | 준수 | 키 부재 시 선기록 pending 주문이 롤백된다 |
| ADMIN-4(실패 주문·매출) | 준수 | 설정 오류가 실패 주문으로 남지 않는다 |

---

### 5. 실행한 명령과 결과

| 명령 | 결과 |
|:---|:---|
| `mise exec -- bin/rails test` | 1,582 runs, 9,958 assertions, 0 failures, 0 errors, 0 skips |
| `mise exec -- bin/rails test:system` | 1회차 14 runs, 119 assertions, **1 failures**(`AppLegalDocumentPdfTest` — 로그인 단계) → 재실행 3회 각 14 runs, 131 assertions, 0 failures. 단일 파일 단독 1 runs, 15 assertions, 0 failures(O-3) |
| `mise exec -- bin/rubocop` | 425 files inspected, no offenses |
| `mise exec -- bin/rails zeitwerk:check` | all is good |
| `mise exec -- bin/brakeman --no-pager -q` | Errors 0, Security Warnings 0 |
| `ruby -c`(변경 ruby 5개 파일) | 모두 Syntax OK |
| `mise exec -- bin/rails runner -`(development, 값 미출력, `request` 재정의) 1회 | 아래 표 |
| 포트원 공식 문서 원문 열람(OpenAPI v2 1.16.0 `src/schema/v2.openapi.json`, 인증 결제 연동하기, 콘솔 가이드) | PG API 호출 없음 |

| 검증 | 결과 |
|:---|:---|
| 플래그·환경 | development에서 플래그 미정의(클래스 `OrderedOptions`), `live_channel?` false |
| credentials 키 구성(이름만) | `:portone` 키 6개는 모두 심볼, 채널 키 4개는 모두 present(길이 48) — base와 `_test`는 쌍마다 다른 값 |
| 운영 키 이름 | `live: true`가 base 키와 동일(billing·normal), `live: false`가 `_test` 키와 동일 |
| 플래그 토글 8종 | 전부 기대값(true만 base, 나머지 `_test`) |
| credentials 호출 시점 평가 | 가짜 Hash 교체가 다음 호출에 반영 |
| fail-closed | 라이브만 있고 비운영 → nil, 테스트만 있고 운영 → nil, 빈 credentials → nil, 문자열 키 → nil |
| kind | `:billing`·`"billing"`·`:normal`·`"normal"`만 통과, 나머지 8종 ArgumentError |
| 가드(Probe) | nil·`""`·`"   "`는 `MissingChannelKey`, request 미도달 |
| 작업트리 | 검증 전후 `git status --short` 33항목 해시 동일, 임시 파일 없음 |

---

### 6. 확인한 것 / 확인하지 못한 것

**확인한 것**

- B-1·W-1~W-4의 코드·문서 반영(§1·§3). 운영은 base 키 이름을 그대로 읽고 비운영만 `_test`를 읽는다.
- 플래그가 `production.rb`에만 정의돼 있고 `== true`라 nil·문자열·미정의 값이 모두 테스트 채널로 떨어진다. 기본 인자는 호출 시점에 평가된다.
- 전용 예외가 두 잡에서만 잡히고, 키 없음 시 pending 주문은 롤백되며 구독 상태가 바뀌지 않는다(코드 추적 + Rails 소스).
- 단건 결제 3곳이 키 없음에 버튼을 막고, 기존 테스트가 키 유무와 무관하게 같은 결과를 낸다(정적 판정).
- 결제 확정 3경로(콜백 승인·재조회·웹훅)와 `FulfillPassService` 어디에도 금액·채널 비교가 없다. `confirm_payment`는 `totalAmount`·`isTest`를 보내지 않는다.
- 공식 스펙: `ConfirmPaymentBody`의 `totalAmount`·`isTest`는 검증용 파라미터(전달 권장), `PaidPayment`의 `amount.paid`·`channel.type`(`LIVE`·`TEST`)은 required. 공식 가이드는 서버 검증을 필수로 요구한다.
- 포트원 콘솔의 웹훅 URL은 V2 실연동·V2 테스트 탭에서 각각 설정한다.

**확인하지 못한 것**

- **R-1·R-2의 실제 재현** — 소액·테스트 채널 결제가 PAID로 확정되는지. 실호출 금지라 코드와 공식 스펙·가이드 원문으로만 판단했다.
- **R-2의 전제** — `_test` 채널 2개가 실금액 없이 결제되는 테스트 채널인지, 새 스토어의 채널 목록에 있는지, V2 테스트 웹훅 URL이 어디로 설정돼 있는지. 포트원 콘솔이 필요하다.
- 운영 부팅(`RAILS_ENV=production`)에서의 플래그 값 — 정적 확인으로 갈음했다.
- 운영 DB 주문 0건·빌링키 보유 구독 0건, `api_secret` 새 스토어 유효, 결제 시도 3건 실패 — 오케스트레이터·사용자 보고이며 운영 서버에 접근하지 않았다.
- 잡 경로의 롤백은 실행 재현이 아니라 코드 추적이다(임시 테스트 금지).
- GitHub Actions CI의 실제 실행, 로컬 브라우저의 테스트 채널 결제창.

---

### 7. Tester 중점 테스트 제안

1. **선택기**: `live:`·`credentials:`(심볼 키) 주입으로 운영·비운영·fail-closed·kind를 고정. `config.x.portone_live_channel`를 바꾸는 테스트는 `ensure`로 복원하고, "test 환경의 `live_channel?`는 false"를 고정한다(O-2).
2. **가드**: nil·`""`·공백 키가 `MissingChannelKey`이고 요청이 나가지 않는지.
3. **잡**: 키가 nil일 때 `SubscriptionRenewalJob`이 뒤순번 구독(해지 후 만료 강등)을 계속 처리하는지, `DunningRetryJob` 실행 뒤 상태·단계·`next_retry_at`·주문 수가 그대로인지.
4. **단건 결제 뷰**: normal 키가 nil이면 "결제하기"가 없고 안내가 나오는지, 키가 있고 연락처가 없으면 연락처 안내인지.
5. **결제 확정 검증(R-1·R-2 반영 뒤)**: 금액 불일치·채널 타입 불일치 결제가 콜백 승인·재조회·웹훅 3경로에서 paid로 확정되지 않는지, 정상 결제는 그대로 확정되는지.

---

### 8. 운영상 주의

1. **credentials는 보류**: R-1·R-2 반영 전까지 `config/credentials.yml.enc`를 커밋·배포하지 않는다. 라이브 채널이 켜지는 순간 미달 금액·테스트 채널 결제가 유효해진다.
2. **코드 변경분은 선행 가능**: 선택기·예외·뷰 분기는 운영 동작을 바꾸지 않는다.
3. **첫 실결제 확인**: 라이브 전환 뒤 첫 결제 1건으로 재조회 응답의 `amount.paid`·`channel.type` 실측 값을 기록한다(검증기의 기대값 근거).
4. **포트원 콘솔**: 웹훅 URL은 V2 실연동 탭에 운영 주소, V2 테스트 탭은 운영 주소로 두지 않는다.

---

## 재리뷰 2회차 (2026-11-25 — 결제 확정 검증 R-1·R-2 반영 확인)

status: CHANGES_REQUESTED

**BLOCKER 1 · WARNING 5** · 관찰 6(이슈로 세지 않음)

요약. 1차 구현의 결함(승인 응답으로 검증)은 3차 수정으로 바로잡혔고, 변경분 안에서 로직 오류·런타임 오류는 찾지 못했다. 정상 결제가 실패하거나 pending에 갇히는 경로(㉯)도 코드 추적 범위에서는 없다. **CHANGES_REQUESTED는 우회 경로 1건(R2-1) 때문이다.** 검증을 통과하지 못해 `failed`가 된 주문을 웹훅 컨트롤러의 상태 동기화가 검증 없이 `paid`로 되돌려, R-1·R-2의 목적이 내용증명에서 무너진다. 수정 범위는 `apply_status` 가드 1줄과 회귀 테스트다.

**R2-1 반영 전까지 `config/credentials.yml.enc`은 커밋·배포하지 않는다**(1차 재리뷰 §8-1과 같다).

### 1. 항목별 반영 판정

| 항목 | 판정 | 근거 위치 |
|:---|:---|:---|
| R-1 (BLOCKER) | **부분 해소 — 잔존 우회 R2-1** | 직접 경로는 해소됐다. 승인 요청이 `totalAmount`를 보낸다(`app/services/port_one/client_service.rb:33-37`). 확정점이 `amount.paid == 주문 금액`을 검증한다(`app/services/orders/fulfill_pass_service.rb:23`, `app/services/port_one/payment_verifier.rb:66-73`). 미해소: 검증 실패 주문이 웹훅으로 paid가 된다(`app/controllers/webhooks/portone_controller.rb:77-80`) |
| R-2 (CRITICAL) | **부분 해소 — 같은 우회 R2-1** | 직접 경로는 해소됐다. `isTest`를 환경값으로 보낸다(`app/services/orders/purchase_service.rb:108-112` — 운영 false). `channel.type`을 검증한다(`payment_verifier.rb:78-85`). 테스트 채널 결제도 R2-1 경로로 paid가 된다 |
| R-3 (WARNING) | **대부분 해소, 잔존 2건(R2-6)** | `_workspace/01_plan.md:77`·`:96`·`:125`, `_workspace/02_prd_update.md:18`, `_workspace/03_implementation.md:98`·`:103-109`·`:133` 정정 확인. 미정정: `_workspace_prev_fplan/05_review.md:51`, `LAUNCH_TEST_SCENARIOS.md:48` |

### 2. 새로 발견한 이슈

| ID | 심각도 | 위치 | 문제 | 영향 | 제안 수정 |
|:---|:---|:---|:---|:---|:---|
| R2-1 | **BLOCKER** (라이브 전환 전 필수 — R-1·R-2 잔존 우회) | `app/controllers/webhooks/portone_controller.rb:76-81`(`apply_status` 마지막 줄) · `:46-60` · `config/routes.rb:121` · `app/controllers/app/legal_documents_controller.rb:74-75` | **pending이 아닌 주문을 검증·확정 없이 paid로 바꾼다.** `apply_status`는 `order.pending? && status == "paid"`일 때만 `settle_paid`(검증 포함)를 타고, 그 밖은 `order.update!(status: status)`다. 주문이 `failed`이고 재조회 결과가 PAID이면 이 줄이 실행된다. 아래 경로 참조 | 변조·테스트 채널 결제로 내용증명 정식 PDF(5,000원 상품)를 받는다. 수금 패스는 발급이, 세금계산서는 발행이 따르지 않아 실익은 없지만 paid 기록이 남는다(`paid_at` nil, metadata에 `PAYMENT_VERIFICATION_FAILED` 그대로 → ADMIN-5 매출 집계 오염). 반대 방향으로는 잘못 걸러진 정상 결제가 발급 없이 '결제 완료'가 된다(수금 패스는 패스 없음, 세금계산서는 재주문 차단까지) | `apply_status`에서 pending 아닌 주문의 paid 전환을 막는다(아래 코드). 회귀 테스트 1건 |
| R2-2 | WARNING (안내 문구) | `app/controllers/app/legal_documents_controller.rb:60` · `app/controllers/app/orders_controller.rb:27-30, 37-46` · `app/views/app/legal_documents/show.html.erb:107-116` | 내용증명 주문의 콜백 실패 착지는 `?payment_failed=1`이라 `show`가 `flash.now[:alert]`로 "결제가 승인되지 않았습니다. 다시 시도해 주세요."를 덮어쓴다(실행 확인). 이 변경이 기대하는 `verification_message`·`recovery_message`는 보이지 않는다. failed 화면은 "새로 주문해 주세요"를 안내한다 | 결제가 실제로 성립했을 수 있는 상태(검증 실패, pending 회복 대기)에서 재결제가 유도된다. 03 §9 "회원에게 보이는 것" 열은 수금 패스·세금계산서에만 맞다 | `payment_failed=1`은 위젯 실패(`code`) 응답에만 쓰거나 `flash[:alert]`가 비었을 때만 기본 문구로 대체한다. 검증 실패 주문은 "새로 주문" 대신 문의 안내 |
| R2-3 | WARNING (운영 절차) | `app/services/orders/refund_service.rb:65-66` · `app/services/orders/fulfill_pass_service.rb:18` | 검증 실패 주문은 `failed`·`paid_at` nil이라 관리자 환불 실행의 사전 가드(결제 완료·취소 상태 + `paid_at`)에서 거부된다. 재발급 액션도 없다(pending 한정) | 정상 결제가 잘못 걸러진 경우(O-1) 앱 안에 회복 수단이 없다. 포트원 콘솔 수동 환불과 콘솔 작업만 가능하고 정산 기록이 남지 않는다 | 런북·AGENTS 노트에 처리 절차를 적는다(최소). 후속으로 failed→pending 되돌리기 또는 수동 발급 액션 |
| R2-4 | WARNING (방어 강화 — 낮음) | `app/services/port_one/client_service.rb:34-36` · `app/services/port_one/payment_verifier.rb:54-58` | `currency`를 승인 요청에 보내지 않고 검증기도 보지 않는다. 공식 `ConfirmPaymentBody.currency`도 "검증용 파라미터로 … 값 전달을 권장합니다"이고 `PaidPayment.currency`는 required다 | 낮음. 위젯이 "KRW"로 고정하지만 클라이언트 값이다. [추정] 통화를 바꿔 결제해도 금액 숫자만 맞으면 통과한다. KG이니시스 채널에서 KRW 외 통화가 결제되는지는 확인하지 못했다 | 본문에 `currency: "KRW"`, 검증기에 통화 비교 1줄 |
| R2-5 | WARNING (아키텍처) | `app/controllers/webhooks/portone_controller.rb:101-113` · `app/services/orders/purchase_service.rb:187-199` | 잠금·쓰기 13줄(`record_verification_failure!`)이 컨트롤러와 서비스에 중복되고, 이미 다르다. 웹훅 쪽은 `pg_payment_id`를 남기지 않는다(웹훅이 먼저 오면 nil — 03 §9 "이미 스냅샷 보존 중"은 그 경우 사실이 아니다) | 규약 §3.3-5·§3.5(트랜잭션 로직은 Service). 두 사본이 계속 어긋난다 | `Orders::RecordVerificationFailureService` 한 곳으로 모은다 |
| R2-6 | WARNING (문서·주석) | `app/services/orders/fulfill_pass_service.rb:20-21` · `app/services/port_one/payment_verifier.rb:1-2` · `app/services/port_one/client_service.rb:30-31` · `_workspace/03_implementation.md:206-222, 257-263` · `_workspace_prev_fplan/05_review.md:51` · `LAUNCH_TEST_SCENARIOS.md:48` | (a) 주석 3곳이 "승인(·재조회) 응답의 금액·채널"을 검증 대상이라고 적는다 — 승인 응답에는 없다. (b) 03 §9 표의 줄 번호(`:50~55`·`:73~80`·`:143~159`)·"79줄"·1차 수치는 3차 수정 뒤와 다르다(현재 `:71-76`·`:108-112`·`:187-199`, 87줄). §9-2 번호는 맞다. (c) R-1 제안 ④의 `_workspace_prev_fplan/05_review.md:51`("금액 변조 방어됨")과 `LAUNCH_TEST_SCENARIOS.md:48`("로컬도 결제 키는 운영과 같다")가 그대로다 | 실행 영향 없음. 뒤따르는 개발자가 승인 응답을 검증에 쓰는 실수를 반복할 수 있다 | 주석 3곳 정정, §9 표에 "1차 기준" 표시, 이력 문서 2곳에 정정 주석(LAUNCH 파일은 사용자 문서 — 사용자에게 알림) |

집계 제외: 검증 실패 경로(`VerificationError`·`PAYMENT_VERIFICATION_FAILED`)를 단언하는 테스트가 0건이다(`grep` — 대역 주석 2건뿐). 03 보고서대로 Tester 단계 범위라 결함으로 세지 않았다. **R2-1 수정과 함께 반드시 포함된다(§7-1).**

#### R2-1 경로

1. 사용자가 자기 주문(paymentId는 주문번호로 화면 노출)으로 소액 결제를 만들어 포트원에서 PAID로 만든다. R-1과 같은 전제이고 [추정] 실호출로 재현하지 않았다.
2. 주문이 `failed`가 된다. 콜백이 먼저면 검증 실패로 failed다(`purchase_service.rb:71-76`). 콜백 없이 위조 이벤트 1회를 보내도 된다 — pending이라 `settle_paid` → 검증 실패 → failed(`portone_controller.rb:61-65`).
3. `POST /webhooks/portone`에 `{"type":"Transaction.Paid","data":{"paymentId":…}}`를 보낸다. 라우트는 비인증 공개다(`routes.rb:121`). 포트원이 실제로 보내는 이벤트도 같다. 컨트롤러는 재조회만 믿는데 그 결제는 포트원에서 실제 PAID이고 `id`도 일치한다.
4. `apply_status`: `order.status == status` 거짓, `order.pending?` 거짓 → `order.update!(status: "paid")`. `settle_paid`를 거치지 않아 검증기가 호출되지 않는다.
5. 내용증명 주문이면 `download`가 `@order.paid?`만 보고 워터마크 없는 정식 PDF를 준다(`legal_documents_controller.rb:74-75`).

이 전이 자체는 기존 코드다. "포트원에서 실제 PAID인데 앱이 failed로 둔 주문"이 이번 변경으로 처음 생겨서 유효해졌다.

근거: 코드 추적이다. 같은 줄이 paid→cancelled 전이에서 실행되는 것은 기존 테스트가 확인한다(`test/controllers/webhooks/portone_controller_test.rb:90-100`). 실행 재현은 하지 않았다(임시 테스트 금지). 기존 테스트 중 failed→paid를 다루는 것은 0건이다.

제안 수정(`portone_controller.rb` `apply_status`):

```ruby
def apply_status(order, status, payment)
  return if order.status == status
  return settle_paid(order, payment) if order.pending? && status == "paid"

  # failed·cancelled 주문은 검증·확정 없이 paid로 뒤집지 않는다(재리뷰 2회차 R2-1)
  return if status == "paid"

  order.update!(status: status)
end
```

pending 주문의 paid 전환은 그대로 `settle_paid`를 타므로 Plus 갱신(`settle_renewal`)과 정상 웹훅 회복은 영향받지 않는다. failed 주문을 paid로 만들어야 하는 정상 시나리오는 없다 — 그 전이는 발급을 동반하지 않아 이미 망가진 상태다.

**관찰(이슈로 세지 않음)**

- **O-1 `amount.paid`와 카드사 할인**: 공식 `PaymentAmount.discount` 설명이 "카드사 할인금액, 포트원 프로모션 할인금액, 간편결제 할인금액…"이다. 할인이 붙은 정상 결제는 `paid < total`로 올 수 있고 검증은 실패시킨다(fail-closed, 의도). [추정] KG이니시스 상점에서 카드사 즉시할인이 기본 활성인지는 확인하지 못했다. 첫 실결제 때 `amount.discount`가 0인지 기록한다(§6).
- **O-2 잠금 유지 중 HTTP 호출**: `PurchaseService#call`의 `with_lock` 안에서 이제 confirm과 get_payment 2회를 부른다. SQLite 어댑터 기본값이 `:immediate`라(`activerecord-8.1.4.1/lib/active_record/connection_adapters/sqlite3_adapter.rb:162`) 쓰기 잠금이 그동안 유지되고 최악 60초×2다(기존 60초). 정상 시 수백 ms 추가다. 기존 설계라 지적으로 세지 않는다 — 후속으로 HTTP 호출을 잠금 밖으로 옮기고 잠금 안에서 pending을 재판정하면 된다.
- **O-3 `settle_renewal` 미검증**: `app/services/subscriptions/upgrade_service.rb:129-151`은 금액·채널을 검증하지 않는다(기존). pending plus_monthly 주문의 `pg_order_id`(UUID)는 앱 뷰에 노출되지 않아(`grep`) 위젯 결제로 연결하기 어렵다. 오케스트레이터가 검증 대상에서 제외했으므로 후속 방어만 권장한다.
- **O-4 `FulfillTaxInvoiceService`의 미검증 전이**: `app/services/orders/fulfill_tax_invoice_service.rb:15-23`에 검증 없는 pending→paid가 남아 있다. 앱 호출처는 `FulfillPassService` 1곳이고 항상 paid 뒤라 실행되지 않는다. AGENTS의 "단건 결제 확정은 `FulfillPassService` 한 곳"은 호출처 기준으로만 참이다.
- **O-5 ApiError 아닌 예외**: `client_service.rb:130-143`의 `parse`는 비JSON 오류 본문에서 `JSON::ParserError`를 던진다. 재조회 단계에서 잡지 않아 500으로 끝나지만 트랜잭션이 롤백돼 주문은 pending으로 안전하다(기존 동작).
- **O-6 운영 스모크는 실카드만 가능**: 운영은 `isTest: false`와 `LIVE` 기대값이라 테스트 채널 결제가 전부 거절된다. 설계대로지만 첫 실결제 확인 계획에 반영해야 한다.

### 3. 중점 항목 판정

**1. 검증 입력이 항상 재조회한 전체 결제 건인가 — 확인함, 문제 없음**

- `FulfillPassService.new(response: …)`의 앱 호출처는 3곳이다.
  - ① 콜백·paymentToken 있음: `approve!`(`purchase_service.rb:96-103`)가 `confirm_payment!` → `recheck_after_confirm!`을 부르고 승인 응답은 버린다. 확정 응답은 재조회 결과다(`:60-61`).
  - ② 콜백·paymentToken 없음: `recheck_payment!` 결과가 그대로 확정 응답이다.
  - ③ 모호 실패·ALREADY_PAID 회복: `recover_from_recheck!`(`:127-129`)가 `response: recheck_payment!`를 넘긴다.
  - ④ 웹훅: `settle_paid`(`portone_controller.rb:83-92`)가 `get_payment` 결과를 넘긴다.
- `recheck_payment!`(`:145-150`)는 `get_payment` 응답 중 PAID만 돌려준다. `confirm_payment`의 반환값을 검증에 넘기는 곳은 없다.
- 테스트의 직접 호출 4곳(`test/models/order_item_type_test.rb:46, 60, 73`, `test/system/app_legal_document_pdf_test.rb:45`)은 모두 `paid_payment`를 넘긴다. `FulfillPassService`의 기본값 `response: {}`은 검증 실패로 떨어진다(미전달이 곧 차단).

**2. 보안(㉮) — 직접 경로는 확인함. 우회 1건(R2-1)**

- `confirm_payment` 본문은 `totalAmount: @order.amount`(정수 — `Order` 검증이 `only_integer`·`greater_than 0`), `isTest: !PortOne::ChannelKey.live_channel?`(운영 false)다. `client_service_test.rb`가 본문을 단언한다.
- 검증기 실행 확인(development): 금액 20건·채널 10건·`live:` 비정상 값 5건. 낮은·높은·음수·소수 금액, 누락, 비숫자(`"4000"`·`true`), 비객체 응답(nil·String·Array·중첩이 String·Array·nil), 문자열 키가 전부 `amount_mismatch`다. LIVE/TEST 교차·누락·소문자·심볼·뒤 공백이 전부 `channel_mismatch`다. 통과는 정상 5건만이다. 예상 밖 예외(`TypeError` 등) 0건. `live:`가 nil·`"true"`·`1`이면 TEST로 해석된다. 금액 검사가 채널 검사보다 앞선다.
- 발급·발행: 검증은 `with_lock` 안, 상태 변경 앞에 있고(`fulfill_pass_service.rb:17-23`) 실패 시 예외가 그대로 올라 아무 쓰기도 없다. `fulfill_tax_invoice`는 검증 통과 뒤 전환(`newly_paid`)일 때만 호출된다(`:39`). `FulfillTaxInvoiceService`의 앱 호출처는 그 한 곳이다(O-4).
- 승인 단계의 불일치: 공식 `ConfirmPaymentError`에 `InformationMismatchError`가 있다. `AMBIGUOUS_CODES`(TIMEOUT·CONNECTION)도 `ALREADY_PAID`도 아니어서 `record_failure!`로 failed다(`purchase_service.rb:77-87`).
- paid로 쓰는 코드는 `FulfillPassService`·`FulfillTaxInvoiceService`·`UpgradeService` 2곳(`upgrade_service.rb:144, 186`)·웹훅 `apply_status`이다. 관리자 콘솔에는 paid 전환 액션이 없다(index·show·refund). **이 중 웹훅 `apply_status`만 검증을 거치지 않는다(R2-1).** `settle_renewal`은 O-3.

**3. 런칭 안전성(㉯) — 5경로 코드 추적은 문제없음. 안내 문구(R2-2)·회복 절차(R2-3)가 미흡**

| 경로 | 결과 | 근거 |
|:---|:---|:---|
| ① 승인 200 → 재조회 PAID → 검증 통과 | paid·발급 1회 | `purchase_service_test.rb:16, 46` 통과 |
| ② 승인 200 → 재조회 `ApiError` | pending + metadata(`code`·`message`·`pending_recovery`) + "지연" 안내 → 웹훅이 paid로 | `recheck_after_confirm!`(`:117-121`), `purchase_service_test.rb:171` 통과 |
| ③ 승인 200 → 재조회가 PAID 아님 | pending(②와 같은 분류, `api_error` nil) | `purchase_service.rb:147` |
| ④ 모호 실패·ALREADY_PAID 회복 | 재조회 PAID → 검증 통과 → paid. 재조회 실패 → pending. 검증 실패 → failed | `purchase_service_test.rb:133`, `f_plan_review_fix_test.rb:17, 41, 65` 통과 |
| ⑤ paymentToken 없음 | 재조회 PAID → 검증 → paid | `purchase_service_test.rb:79`, `orders_controller_test.rb:73` 통과 |

- 웹훅이 안 오면 pending은 영원히 남는다. pending 주문을 재조회하는 잡은 없고(`config/recurring.yml`·`app/jobs` 확인), 기존 모호 실패 설계와 같다. 달라진 점은 paymentToken 경로의 정상 확정이 이제 `get_payment` 성공에도 의존한다는 것이다. 운영 웹훅 URL 등록이 그만큼 중요해졌다.
- ③(재조회가 PAID 아님)과 ④의 검증 실패는 아직 테스트가 없다(§7-5, §7-9).
- 안내 문구: 수금 패스(`app_billing_path`)와 세금계산서는 컨트롤러의 alert가 그대로 보인다. 내용증명은 덮어써진다(R2-2).

**4. 실패 분류 — 확인함, 섞이지 않는다**

- 세 예외는 모두 `StandardError` 직계라 서로 포함되지 않는다(실행 확인). `rescue` 순서는 `PendingApprovalError` → `VerificationError` → `ApiError`다(`purchase_service.rb:64-87`).
- `recover_from_recheck!`가 던지는 `PurchaseError`는 `call`의 `rescue PortOne::ApiError` 절 안에서 나와 형제 절에 잡히지 않고 컨트롤러로 간다.
- `PendingApprovalError#api_error`: 재조회 TIMEOUT이면 metadata에 `code: "TIMEOUT"`과 원문이 남고(`purchase_service_test.rb:186`), PAID 아님은 `code: nil`·`pending_recovery: true`다(기존과 같다).
- `record_verification_failure!` 양쪽 모두 `with_lock` 안에서 `reload.pending?`를 다시 판정하고 기존 metadata를 병합한다(`invoice_id` 보존). 이미 확정된 주문은 건드리지 않는다.

**5. 웹훅 컨트롤러 — 지시된 3항목 확인함. `apply_status` 우회가 있다(R2-1)**

- `sync_payment_status`의 rescue는 `VerificationError`만 잡는다(`portone_controller.rb:61`). `get_payment`의 `ApiError`는 `create`까지 올라가 500이 되고 포트원이 재시도한다. 이를 직접 단언하는 테스트는 없다(§7-7).
- 검증 실패 뒤 `create`는 `head :ok`(200)다.
- Plus 갱신 분기(`:93-95`, `settle_renewal`)는 변경 0이고 pending plus_monthly 주문만 간다(`portone_controller_test.rb:65` 통과).

**6. 트랜잭션·잠금 — 확인함, 문제 없음**

- 검증은 `FulfillPassService#call`의 `with_lock` 첫 단계고 실패 시 블록이 예외로 끝나 롤백된다.
- `PurchaseService#call`의 rescue 3절은 메서드 수준이라 `with_lock`이 풀린 뒤 실행된다. 호출처 `App::OrdersController#callback`은 트랜잭션을 열지 않아 `keep_pending…`·`record_verification_failure!`의 쓰기는 롤백되지 않는다(`purchase_service_test.rb:171`의 metadata 단언이 이를 확인한다).
- 웹훅: `get_payment`는 잠금 밖, 검증은 `FulfillPassService`의 잠금 안, 실패 기록은 그 뒤 별도 잠금이다.
- O-2(잠금 유지 중 HTTP 호출)는 기존 설계다.

**7. 대역의 충실성 — 확인함, 문제 없음**

- 승인 응답 기본값은 `{ pgTxId:, paidAt: }`뿐이다(`test/test_helpers/fake_portone_client.rb:26`). `with_verification_fields`는 코드에 0건이다(03 문서의 이력 서술 2곳만 남음).
- 회귀 테스트(`purchase_service_test.rb:46`)는 논리상 그 결함을 잡는다. 승인 응답으로 검증하는 구현이면 대역 기본 응답에 금액이 없어 `VerificationError` → `PurchaseError`로 테스트가 깨진다. 단 이 보호는 대역이 승인 응답을 자동으로 채우지 않는다는 전제에 있으므로 §7-10을 권장한다.
- `paid_payment` 기본은 TEST이고 test 환경의 `live_channel?`는 false다(플래그는 `production.rb`에만 정의). 검증기와 `is_test` 계산은 credentials를 읽지 않아 로컬과 CI가 같다.

**8. 기존 테스트 수정의 타당성 — 확인함, 문제 없음**

- 13파일이고 `git diff HEAD --stat` 목록이 03 §9·§9-2 표와 일치한다.
- 헬퍼에 넣은 금액은 전부 그 주문의 금액이다(4,000·`LEGAL_DOC_PRICE`·`ISSUE_FEE`). 통과시키려고 값을 비틀어 넣은 곳은 없다.
- 승인 응답을 직접 주입하는 테스트는 0건이다(`confirm_payment: {` — 대역 기본값 정의 1곳뿐). `tax_invoice_callback_test.rb:28`의 "기존 confirm 주입은 사용되지 않던 값"은 사실이다(콜백이 `paymentId`만 보낸다).

**9. 문서 정합 — PRD·AGENTS·01_plan은 코드와 맞다. 잔존 R2-6**

- PRD PLAN-5(`PRD.md:214`)·AGENTS 노트(`AGENTS.md:212`)의 "재조회한 결제 건으로 검증", "승인 응답에는 금액·채널이 없다", "승인 뒤 재조회 실패는 pending"이 코드와 맞다. `_workspace/01_plan.md:114`도 맞다.
- 낡은 "승인 응답으로 검증" 서술은 코드 주석 3곳과 03 §9 표에 남아 있다(R2-6). `_workspace_prev_fplan/05_review.md:51`과 `LAUNCH_TEST_SCENARIOS.md:48`는 정정되지 않았다.
- 03 수치: §9-2의 1,584 runs·9,980 assertions가 이번 실행과 같다.

**10. 아키텍처·규약 — 의존 방향 위반 없음. 컨트롤러 중복(R2-5)**

- 검증기 위치와 네임스페이스는 1차 재리뷰에서 승인한 `PortOne::ChannelKey` 선례와 같다. `VerificationError`는 전용 예외다(§3.5-5). `FulfillPassService`·`PurchaseService`는 `PortOne` 래퍼의 공개 진입점만 쓴다(§4.3).
- 서비스가 `params`·`Current`를 읽지 않는다(`live_channel?`는 환경 설정 플래그만 읽는다). 뷰 변경 0건. 웹훅 `create` 본문은 6줄이다.
- `record_verification_failure!`가 컨트롤러에 잠금·쓰기로 남아 있다(R2-5).

### 4. Rule ID 준수 매핑

| Rule ID | 판정 | 근거 |
|:---|:---|:---|
| PLAN-5 결제 확정 검증 | **직접 경로 준수, 우회 미준수(R2-1)** | 승인 요청 `totalAmount`·`isTest` 전달, 확정점 금액·채널 검증. 웹훅 `apply_status`는 pending 아닌 주문을 검증 없이 paid로 바꾼다 |
| PLAN-4(수금 패스) | 준수 | 검증 통과 뒤에만 발급. 우회 경로로는 `PaymentPass`가 만들어지지 않는다 |
| LEGAL-2(내용증명) | **미준수(R2-1)** · 안내 미흡(R2-2) | `download`가 `paid?`만 보고 정식 PDF를 준다. 콜백 안내가 덮어써진다 |
| TAX-1(세금계산서) | 준수 | 발행은 `FulfillPassService` → `FulfillTaxInvoiceService` → `IssueService` 한 경로이고 검증 통과 뒤에만 호출된다 |
| SEC-5(멱등) | 준수 | pending 재판정·잠금 그대로. 검증 실패 기록도 `pending?`를 다시 판정한다 |
| PLAN-9·ADMIN-11(환불 콘솔) | 검증 실패 주문 미지원(R2-3) | 사전 가드가 paid·cancelled와 `paid_at`을 요구한다 |
| ADMIN-4(실패 주문) | 준수 | metadata의 `code`·`verification`이 관리자 주문 상세에 보인다(`app/views/admin/orders/show.html.erb:22`) |

### 5. 실행한 명령과 결과

| 명령 | 결과 |
|:---|:---|
| `mise exec -- bin/rails test` | 1,584 runs, 9,980 assertions, 0 failures, 0 errors, 0 skips |
| `mise exec -- bin/rails test:system` | 14 runs, 131 assertions, 0 failures, 0 errors, 0 skips(1회) |
| `mise exec -- bin/rubocop` | 426 files inspected, no offenses |
| `mise exec -- bin/rails zeitwerk:check` | all is good |
| `mise exec -- bin/brakeman --no-pager -q` | Errors 0, Security Warnings 0 |
| `bin/rails runner -`(development, 순수 객체만 — 키 값 미출력) 4회(2회는 내 스크립트 구문 오류로 재실행) | flash.now 덮어쓰기 확인 · 검증기 행렬 35건 + 기본값 2건 |
| 포트원 공식 OpenAPI v2(1.16.0) 원문 다운로드·파싱(2,175,359바이트, 저장소 밖 임시 디렉터리, `python3 -I`) | PG API 호출 0건. 임시 디렉터리는 삭제 |
| 작업트리 | 실행 전후 `git status --short` 해시 동일(49항목). 코드·문서 수정 0건(이 파일의 이 절만 추가) |

### 6. 확인한 것 / 확인하지 못한 것

**확인한 것**

- 공식 스펙(원문): `ConfirmPaymentBody`의 `paymentToken`(필수)·`totalAmount`·`isTest`·`currency`(세 개 모두 "검증용 파라미터 … 값 전달을 권장합니다"). `ConfirmedPaymentSummary`는 `pgTxId`·`paidAt`뿐이다. `GET /payments/{paymentId}` 200은 `Payment` 유니온(oneOf)이고 `PaidPayment`의 `amount`(`PaymentAmount` — `paid` required)·`channel`(`SelectedChannel` — `type`은 `LIVE`·`TEST` required)·`currency`가 required다. confirm 작업 설명은 "수동 승인으로 설정된 인증 결제에 대해"라 paymentToken 없는 경로에는 승인 요청이 없다(검증기만 방어).
- 검증기는 위 행렬에서 기대대로 동작하고 비객체 응답에서 예외 종류가 새지 않는다.
- 검증 입력 4경로가 모두 재조회 결과다. `confirm_payment` 호출처는 `PurchaseService` 1곳이다.
- 콜백·웹훅의 분류와 트랜잭션 경계(§3-4, §3-6). 전체 테스트·정적 분석 통과(§5).
- 내용증명 주문의 콜백 alert가 `flash.now`로 대체된다(실행 확인).
- SQLite 어댑터 기본 트랜잭션 모드가 `:immediate`다(설치된 gem 소스 `sqlite3_adapter.rb:162`).

**확인하지 못한 것**

- **실제 포트원 응답**. 승인 200 뒤 `get_payment`가 즉시 `PAID`를 돌려주는지, 라이브 채널의 `channel.type`이 `LIVE`인지, `amount.paid`가 주문 금액과 같고 `discount`가 0인지. 전부 스펙과 코드만으로 판단했다.
- **R2-1의 실행 재현**. 코드 추적이다(임시 테스트 금지). Tester가 §7-1로 먼저 재현한다.
- **R-1의 근본 전제**(클라이언트가 지정한 소액으로 PAID가 된다)도 1차 재리뷰와 같이 미재현이다.
- `isTest`·`totalAmount` 불일치 때 포트원이 돌려주는 오류 `type` 문자열. 분류에는 영향이 없다(`AMBIGUOUS_CODES`·`ALREADY_PAID` 어느 쪽도 아니면 failed).
- 운영 부팅(`RAILS_ENV=production`)의 플래그 값, 운영 웹훅 URL 등록 상태, 포트원 콘솔 설정.

**운영 첫 실결제 때 반드시 확인할 것**

1. 결제 1건으로 서버 로그에 승인 응답 본문(`pgTxId`·`paidAt`만인지)과 재조회 응답의 `status`·`amount.total`·`amount.paid`·`amount.discount`·`channel.type`·`currency`를 기록한다. 개인정보·키 값은 제외한다.
2. 주문이 paid가 되고 `paid_at`이 기록되며 발급(또는 PDF 다운로드)이 정확히 1회이다. 콜백 경로와 휴대폰(redirectUrl, paymentToken 없음) 경로를 각각 1건씩 본다.
3. 콜백이 pending으로 남긴 경우 웹훅으로 회복되는지(V2 실연동 탭 웹훅 URL이 운영 주소인지).
4. R2-1 수정 뒤: 소액 결제 1건이 failed + `metadata.code == "PAYMENT_VERIFICATION_FAILED"`로 남고, 그 뒤 `/webhooks/portone`에 같은 paymentId의 `Transaction.Paid`를 보내도 paid로 바뀌지 않는다.
5. 관리자 주문 상세에서 4번 주문을 식별할 수 있다.
6. 운영은 테스트 채널 결제가 전부 거절되므로(O-6) 위 확인은 실카드 실결제로 한다.

### 7. Tester 중점 테스트(아직 없는 시나리오)

1. **R2-1 회귀(최우선)**: pending 주문에 재조회 금액 불일치 `Transaction.Paid` → failed. 그 뒤 같은 paymentId로 재조회 PAID·id 일치 이벤트를 보내도 주문이 paid로 바뀌지 않고 패스가 없다. cancelled 주문도 `Transaction.Paid`로 paid로 돌아가지 않는다. 내용증명 주문은 정식 PDF 대신 워터마크 PDF다.
2. **검증기 단위**(`test/services/port_one/payment_verifier_test.rb` 신설): 금액(낮음·높음·음수·소수·누락·String·`true`·비Hash 중첩), 채널(LIVE/TEST 교차·누락·소문자·심볼), 비객체 응답(nil·String·Array), 문자열 키가 모두 `VerificationError`이고 `reason`·`detail`을 가진다. `live:` nil·`"true"`·`1`은 TEST.
3. 콜백 금액 불일치: `PurchaseError`("결제 확인에 실패")·failed·`pg_payment_id` 스냅샷·metadata(`code`·`verification.reason`)·패스 0·승인 1회·재조회 1회.
4. 콜백 채널 불일치(운영 기대값에서 TEST 결제): `PortOne::ChannelKey.live_channel?`를 stub해 `live: true`를 만들고 `is_test: false` 전달까지 단언한다.
5. 모호 실패·ALREADY_PAID 회복 경로에서 재조회 응답이 불일치 → failed(`PurchaseError`), pending이 아니다.
6. 웹훅 금액·채널 불일치: 200·failed·패스 0·`invoice_id` 보존. 같은 이벤트를 다시 보내도 무변경이다.
7. 웹훅 `get_payment`가 `ApiError`를 던지면 2xx가 아니어 재시도가 유지된다.
8. 콜백 선·웹훅 후와 웹훅 선·콜백 후 경합에서 검증 실패 기록이 정확히 1회다.
9. 승인 200 뒤 재조회가 PAID 아님(`PAY_PENDING`) → pending + `pending_recovery`.
10. 대역 계약: `FakePortOneClient.new`의 기본 승인 응답 키가 `[:pgTxId, :paidAt]`이다(자동 보강 재발 방지).
11. 세금계산서 주문의 검증 실패 → 바로빌 클라이언트 호출 0회.
12. 내용증명 주문 콜백의 검증 실패·pending 회복 안내 문구(R2-2 반영 뒤).

### 8. 운영상 주의

1. **credentials 보류 유지**: R2-1 반영 전까지 `config/credentials.yml.enc`을 커밋·배포하지 않는다. 변경분의 나머지는 운영 동작을 안전한 쪽으로만 바꾼다.
2. **재리뷰 범위**: R2-1 수정이 `apply_status` 가드 1줄과 테스트라면 다음 재리뷰는 그 diff와 §7-1 결과만 보면 된다. WARNING 5건은 수정 여부를 오케스트레이터가 정한다.
3. **검증 실패 주문 처리 절차**를 첫 실결제 전에 정한다(R2-3). 지금은 앱 안에 환불·재발급 수단이 없다.

## 마감 리뷰 (2026-11-25 — 재리뷰 2회차 R2-1~R2-6 반영·새 테스트)

status: APPROVED

**BLOCKER 0 · CRITICAL 0 · WARNING 4** · 관찰 9(이슈로 세지 않음)

요약. 재리뷰 2회차의 BLOCKER(R2-1)는 해소됐고 코드 대상 WARNING 4건(R2-2·R2-4·R2-5·R2-6)도 지적 범위 안에서 반영됐다. 새로 추가된 테스트 66건은 로컬과 CI에서 같은 결과를 내도록 고정돼 있고(코드 경계로 판정 — 아래 §6), 핵심 결함 4종을 각각 잡는 단언이 있다. 이번 변경분에서 런타임 오류·비즈니스 로직 오류·의존 방향 위반은 찾지 못했다. 전체 테스트·시스템 테스트·정적 분석 3종이 통과했다.

**`config/credentials.yml.enc` 커밋·배포 보류는 해제할 수 있다**(재리뷰 2회차 §8-1의 조건이 R2-1 해소였다). AGENTS 운영 노트의 배포 전 확인 사항(웹훅 URL 등)은 그대로 적용된다. WARNING 4건은 배포를 막는 수준이 아니며, F-2(문구 1줄)·F-1(재주문 가드)은 배포 전 반영을 권장한다.

범위. ① 마지막 수정분(R2-1·R2-2·R2-4·R2-5·R2-6) ② 새 테스트의 밀봉성·회귀 가치. 앞서 검증한 선택기·검증기 기본·콜백 재조회는 다시 리뷰하지 않았고, 마지막 수정이 그것들과 충돌하는지만 봤다(충돌 없음 — §3-10).

### 1. 항목별 반영 판정

| 항목 | 판정 | 근거 위치 |
|:---|:---|:---|
| R2-1 (BLOCKER) | **해소됨** | `app/controllers/webhooks/portone_controller.rb:81-89` — `apply_status`가 같은 상태면 무변경(`:82`), pending + paid일 때만 `settle_paid`(검증 포함, `:83`), 그 밖의 paid 전환은 `return`(`:86`). 범용 `update!`(`:88`)은 failed·cancelled 동기화에만 도달한다. 회귀 테스트 2건이 그 가드에 의존한다(§3-1) |
| R2-2 (WARNING) | **지적 범위는 해소 — 잔존 F-3·미차단 F-1** | `app/controllers/app/legal_documents_controller.rb:91-97` · `app/controllers/app/tax_invoices_controller.rb:71-77` — 검증 실패 판정이 `payment_failed`보다 앞. 뷰 `app/views/app/legal_documents/show.html.erb:105-119` · `app/views/app/tax_invoices/show.html.erb:131-145` — 재주문·재발행 버튼 없음, 문의 링크. 남은 것: pending 회복 대기 주문의 문구가 아직 덮어써진다(F-3), 상세 화면 밖에서는 재주문이 된다(F-1) |
| R2-4 (WARNING) | **해소됨** | `app/services/port_one/client_service.rb:34-39`(`currency:` 필수 인자·본문 전송) · `app/services/orders/purchase_service.rb:108-113`(`currency: "KRW"`) · `app/services/port_one/payment_verifier.rb:96-102`(`verify_currency!`), 순서는 `:60-65` 금액→채널→통화 |
| R2-5 (WARNING) | **해소됨** | `app/models/order.rb:70-88` `mark_verification_failed!` 단일 구현. 호출처 3곳 — `app/services/orders/purchase_service.rb:75`·`:136`, `app/controllers/webhooks/portone_controller.rb:66`. 웹훅 경로도 결제 ID 스냅샷을 남긴다(`order.rb:76`) |
| R2-6 (WARNING) | **해소됨** | `grep -rn "승인 응답" app` 5건 모두 정확한 서술. 낡은 서술 0건. 03 §10 표의 위치·수치가 코드·실행과 맞다. 통화 추가로 생긴 요약 누락은 F-4 |

R2-3(검증 실패 주문의 환불·재발급 회복 수단 — 운영 절차)은 코드 변경 대상이 아니었다. AGENTS 노트(`AGENTS.md:212`)에 처리 절차가 적혀 있다(포트원 콘솔 환불·CS 수동 재발급). 앱 안 회복 수단은 여전히 없다(후속 과제).

### 2. 새로 발견한 이슈

| ID | 심각도 | 위치 | 문제 | 영향 | 제안 수정 |
|:---|:---|:---|:---|:---|:---|
| F-1 | WARNING (보호 범위 — 배포 전 권장) | `app/controllers/app/legal_documents_controller.rb:30-54` · `app/controllers/app/tax_invoices_controller.rb:28-37` · `app/services/tax_invoices/create_order_service.rb:16-24` · `app/controllers/app/orders_controller.rb:8-14` · `app/views/app/legal_documents/index.html.erb:36` · `app/views/app/invoices/_tax_invoice_panel.html.erb:62` | 검증 실패 주문의 재결제 차단이 **주문 상세 화면에만** 있다. 주문 생성 3곳은 paid 주문만 가드하고 pending 주문만 재사용한다. 검증 실패로 failed가 된 주문이 있어도 새 pending 주문이 만들어진다. 목록의 "양식 발급"·청구서 상세 패널의 "전자세금계산서 발행" 링크는 그대로 살아 있다(청구가 미수인 한 항상 표시). 기존 `create` 설계의 공백이고, 이번 변경이 새로 만든 결함은 아니다. 테스트 `legal_documents_controller_test.rb:89`(C-2)는 paid 주문만 다룬다 | 잘못 걸러진 정상 결제(재리뷰 2회차 O-1 카드사 할인 등)를 한 회원이 상세 화면의 "다시 결제하지 말아 주세요"를 보지 않고 목록·청구서 상세·요금제에서 다시 결제하면 이중 결제가 된다(내용증명 5,000원·세금계산서 300원·수금 패스 4,000원). 상세 화면의 안내는 유도를 끊았지만 허용은 남아 있다 | `create` 3곳에서 같은 청구(수금 패스는 미결제 검증 실패 주문)의 `verification_failed?` 주문이 있으면 새 주문을 만들지 않고 그 주문 상세로 되돌린다(`find_paid_legal_order` 선례). 최소: 목록·패널에서 해당 청구 링크 옆에 "결제 확인 중" 안내 |
| F-2 | WARNING (안내 문구 — 배포 전 권장) | `app/views/app/legal_documents/show.html.erb:115` · `app/views/app/tax_invoices/show.html.erb:141` | "결제 상태를 확인하고 있으니 다시 결제하지 말아 주세요"는 서비스가 자동으로 확인 중이라고 읽힌다. 실제로는 검증 실패 주문을 관리자에게 알리거나 감시하는 코드가 없다(`grep` — 로그와 metadata만 남는다). 회원이 문의해야 CS가 움직인다 | 돈은 냈는데 상품을 못 받은 회원이 "확인 중"이라 믿고 문의하지 않으면 해결되지 않는다(P1 관계 보존). 바로 아래에 문의 링크가 있어 완화되지만, 문구가 행동 필요성을 흐린다 | 다음 행동을 문의로 명시한다 — 예: "확인이 필요한 결제입니다. 다시 결제하지 말고 고객지원(문의)으로 연락해 주세요." 또는 관리자 알림을 만들어 문구를 사실로 맞춘다 |
| F-3 | WARNING (R2-2 잔존 — 문구) | `app/controllers/app/legal_documents_controller.rb:94-95` · `app/controllers/app/orders_controller.rb:28-29`·`:37-40` | 내용증명 주문이 pending 회복 대기(승인 성공·재조회 실패)로 남으면 콜백은 `?payment_failed=1`로 돌아오고, `show`가 정확한 안내("결제 확인이 지연되고 있습니다…")를 "결제가 승인되지 않았습니다. 다시 시도해 주세요."로 덮어쓴다. 재리뷰 2회차 R2-2가 함께 짚은 경우인데 이번 반영은 검증 실패 분기만 우선하게 했다. 코드 추적(실행 재현 없음) | 낮음. 해당 주문은 pending이라 결제 버튼이 다시 보이고 "다시 시도" 안내가 붙는다. 포트원이 같은 paymentId의 재결제를 막을 것으로 [추정] — 확인하지 못했다 | `payment_failed=1`은 `flash.now[:alert]`가 비어 있을 때만 기본 문구로 쓰거나, `metadata["pending_recovery"]`면 재결제 안내 대신 회복 안내를 쓴다 |
| F-4 | WARNING (문서·주석 — 낮음) | `AGENTS.md:212` · `app/services/orders/purchase_service.rb:6-9`·`:92-95` · `app/services/orders/fulfill_pass_service.rb:5` · `app/models/order.rb:57` | 통화 검증(R2-4)이 추가된 뒤 요약 서술이 갱신되지 않았다. AGENTS 노트는 검증 항목을 "결제금액 == 주문 금액·채널 종류 == 환경 기대값"으로만 적고(노트 끝의 첫 실결제 확인 문장에는 `currency`가 있다), `VERIFICATION_FAILED_MESSAGE`는 "결제 금액 또는 결제 채널이"이다. PRD(`PRD.md:214`)는 통화까지 맞다 | 실행 영향 없음. 통화 불일치 주문을 관리자가 메시지만 보고 금액·채널 문제로 오해할 수 있다(`metadata.verification.reason`에는 `currency_mismatch`가 남는다) | 각 1곳에 통화를 추가 |

**관찰(이슈로 세지 않음)**

- **O-1 회귀 테스트 주석과 실제 경로**: `test/controllers/webhooks/portone_controller_test.rb:341-342`는 두 번째 이벤트를 "`mark_verification_failed!`가 이미 failed인 주문을 건드리지 않는다"고 적었지만, 실제로는 `apply_status`의 R2-1 가드(`portone_controller.rb:86`)가 먼저 흡수해 검증기·모델 메서드에 도달하지 않는다. 단언(무변경)은 유효하고 모델의 멱등은 `test/models/order_test.rb:151-178`이 고정한다.
- **O-2 대역 계약 테스트 부재**: `FakePortOneClient.new`의 기본 승인 응답 키가 `[:pgTxId, :paidAt]`임을 단언하는 테스트가 0건이다(재리뷰 2회차 §7-10). 콜백 회귀 테스트 2건의 보호는 대역이 승인 응답을 자동으로 채우지 않는다는 전제에 있다(`with_verification_fields`는 코드에 0건).
- **O-3 행렬 공백**: 음수·소수 불일치(`4000.5`)·`true`·심볼 통화(`:KRW`)·소문자·앞뒤 공백 변형은 명시적 테스트가 없다. 실행 확인 결과 전부 실패로 떨어진다(§5).
- **O-4 `pending_recovery` 잔존**: 모호 실패 뒤 재조회에서 검증에 실패한 주문은 `pending_recovery: true`가 metadata에 남는다(`app/models/order.rb:77-81`은 `code`·`message`만 덮어쓴다). 앱 코드가 이 키를 읽는 곳은 없다. 관리자 주문 상세에 함께 보인다.
- **O-5 플래그 복원 형태**: `test/services/port_one/channel_key_test.rb:78-89`는 미정의 키의 "원본"(빈 `OrderedOptions`)을 값으로 되돌려 복원 뒤 키가 명시적으로 저장된 상태가 된다. 값이 동등해 `== true` 판정은 불변이다.
- **O-6 `order_amount.to_i`**: `app/services/port_one/payment_verifier.rb:54`는 nil을 0으로 만들어 0원 결제가 통과한다. `Order` 검증(`greater_than 0`)상 호출처에서 불가능한 입력이다(실행 확인).
- **O-7 재리뷰 2회차 §7 중 미반영**: §7-7(웹훅 `get_payment` `ApiError` → 2xx 아님)·§7-8(콜백↔웹훅 경합에서 검증 실패 기록 1회)·§7-10(대역 계약)·§7-12(pending 회복 문구)·cancelled 주문 + `Transaction.Paid` 변형. 07 보고서가 범위 밖으로 남긴 것들이다(§8).
- **O-8 이력 문서**: `_workspace_prev_fplan/05_review.md:51`("금액 변조 방어됨 … 포트원 confirm이 금액 검증")은 낡은 서술 그대로다(R2-6(c) — 변경 금지 대상). `LAUNCH_TEST_SCENARIOS.md`는 정정돼 있다.
- **O-9 07 보고서 집계**: 그룹 표의 행 합은 67인데 요약은 66이다(B 그룹에 기존 테스트 1행이 섞여 있다). runs 증분(1,590→1,656)은 요약과 일치한다.

### 3. 중점 항목 판정

**1. R2-1 — 확인함. pending이 아닌 주문이 paid로 바뀌는 경로는 없다**

- Order의 상태를 paid로 바꾸는 줄은 5곳이다. `app/services/orders/fulfill_pass_service.rb:28`(검증 통과 뒤) · `app/services/orders/fulfill_tax_invoice_service.rb:20`(앱 호출처는 `fulfill_pass_service.rb:57` 한 곳이고 항상 paid 뒤라 `:17`의 pending 재판정에서 no-op) · `app/services/subscriptions/upgrade_service.rb:144`(`settle_renewal` — `:136`에서 pending 재판정)·`:186`(`charge_and_extend!` — 서버가 만든 plus_monthly 주문) · `portone_controller.rb:88`(가드 뒤라 paid가 올 수 없다). 웹훅 컨트롤러에서 paid를 대입하는 곳은 `ORDER_STATUS_BY_PORTONE`(`:27`) 매핑 하나뿐이다. 웹훅 라우트도 `config/routes.rb:121` 하나다.
- `settle_paid` 호출 조건(`:83`)의 `order.pending?`는 잠금 없는 읽기지만, 읽은 뒤 주문이 바뀌어도 `FulfillPassService`(`fulfill_pass_service.rb:18`)·`settle_renewal`(`upgrade_service.rb:136`)가 잠금 안에서 pending을 다시 판정한다.
- 기존 동기화는 그대로다(실행): pending→failed(`test/controllers/webhooks/portone_controller_test.rb:133-145`)·paid→cancelled(`:121-131`)·PartialCancelled(`:147-157`)·환불 실행 뒤 취소 이벤트(`:161-210`)·Plus 갱신 `settle_renewal`(`:96-119`)·pending→paid 검증 통과(`:13-49`).
- 회귀 테스트는 가드에 의존한다. `portone_controller_test.rb:55-80`·`:354-379`는 주문을 failed로 만들고 재조회는 정상 금액으로 돌려준 뒤 `failed?`(`:75`)·`paid_at` nil(`:76`)·패스 없음(`:78`)·`updated_at` 불변(`:79`)을 단언한다. `:86`을 지우면 `:88`의 `update!(status: "paid")`가 실행돼 이 단언들이 깨진다. 코드를 읽어 판정했다(가드를 지우고 실행하지는 않았다).
- 내용증명 `download`(`app/controllers/app/legal_documents_controller.rb:75-76`)는 `paid?`만 본다. 내용증명 주문이 paid가 되는 길은 검증 확정점 하나다(Plus 갱신 경로는 `plus_monthly?` 주문만 간다). `test/controllers/app/legal_documents_controller_test.rb:228-256`가 워터마크 PDF(정식 PDF와 바이트 다름)를 단언한다.

**2. R2-5 — 확인함. 잠금 안에서 pending일 때만 적용된다**

- `app/models/order.rb:70-88`: `with_lock` → `reload` → `next unless pending?` → `update!(status: :failed, pg_payment_id: pg_order_id, metadata: 병합)` → 적용 여부 반환·로그.
- `next`의 동작: 설치된 `activerecord-8.1.4.1/lib/active_record/locking/pessimistic.rb:97-103`은 `transaction(**opts) { lock!(lock); yield }`다. 블록 안 `next`는 예외가 아니라 `yield`의 정상 반환이라 트랜잭션은 **커밋**으로 끝나고 잠금이 풀린다(롤백은 예외·`break`·`return`·`throw`). 쓰기가 없어 커밋이어도 변경은 없다. 소스로 확인했다(DB 쓰기를 동반한 실행 재현은 하지 않았다).
- 무변경 경로: 이미 paid·이미 failed(일반 PG 거절)는 `false`를 돌려주고 사유를 덮어쓰지 않는다(`test/models/order_test.rb:151-178`). `pg_payment_id` 스냅샷·metadata 병합(`invoice_id` 보존)은 `order_test.rb:115-149`가 고정한다.
- 호출처 3곳의 이전 동작 유지: `purchase_service.rb:75`(failed 확정 뒤 `PurchaseError` — 컨트롤러가 303 리다이렉트 + alert)·`:136`(`call`의 `rescue PortOne::ApiError` 절 안에서 던져져 형제 rescue에 흡수되지 않고 컨트롤러로 간다)·`portone_controller.rb:66`(기록 뒤 200). 세 곳 모두 `with_lock` 블록 밖이라 기록은 롤백되지 않는다(`test/services/orders/purchase_service_test.rb:265-286`의 metadata 단언).
- 재리뷰 2회차 제안은 Service였으나 `mark_refunded!` 선례에 따라 모델 메서드로 모았다. 중복 제거·단일 구현 목적은 달성됐고 의존 방향 위반은 없다.

**3. R2-4 — 확인함**

- `confirm_payment`(`app/services/port_one/client_service.rb:34-39`)에 `currency:`가 필수 인자로 들어가고 본문에 실린다. 앱 호출처는 `purchase_service.rb:108-113` 한 곳이다. 본문 등식은 `test/services/port_one/client_service_test.rb:43-67`이, 서비스의 전달 값은 `test/services/orders/purchase_service_test.rb:68-80`·`:435-456`이 고정한다.
- `verify_currency!`(`payment_verifier.rb:96-102`)는 `payment[:currency] == "KRW"`. 실행 확인(development runner, 순수 객체): "USD"·nil·키 누락·`:KRW`·"krw"·" KRW"·"KRW "·""·`1`·`["KRW"]` 모두 `currency_mismatch`.
- 대역 `paid_payment`의 기본값 KRW(`test/test_helpers/fake_portone_client.rb:18-21`)는 스펙·앱(단건 KRW 고정)과 같은 값이라 낙관적이지 않다. 통화 누락 시나리오는 별도 테스트(`test/services/port_one/payment_verifier_test.rb:31-41`·`:150-166`)가 가드한다.
- 주의: 실제 재조회 응답에 `currency`가 없거나 "KRW"가 아니면 정상 결제가 전부 failed가 된다(§7-1).

**4. R2-2 + UI 품질 기준 — 확인함. 잔존 F-1·F-2·F-3**

- 우선순위: 두 컨트롤러 모두 `verification_failed?` 분기가 `payment_failed` 분기보다 앞이다(테스트 `legal_documents_controller_test.rb:273-283`·`tax_invoices_controller_test.rb:347-357`).
- 버튼: 검증 실패 하위 분기에는 "새 양식 발급"·"다시 발행 요청"이 없다(`legal_documents_controller_test.rb:258-271`·`tax_invoices_controller_test.rb:332-345`). 일반 실패 주문은 기존 버튼을 유지한다(회귀 테스트 각 1건).
- 문의 링크: `new_app_ticket_path`는 `config/routes.rb:70`의 `resources :tickets, only: [:index, :new, :create, :show]`로 존재한다.
- 내부 값 미노출: 뷰는 `@order.verification_failed?`만 읽는다. `metadata["message"]`·`verification.detail`을 회원 표면(`app/views/app`)에 출력하는 곳은 없다. 관리자 주문 상세(`app/views/admin/orders/show.html.erb:22`)만 `metadata.inspect`로 보인다. 콜백 alert도 내부 값이 없다(`purchase_service_test.rb:269-271`).
- 액션 길이·뷰: `show` 본문 2줄(내용증명)·7줄 중 주석 2줄(세금계산서). 뷰는 `@변수`와 경로 헬퍼만 쓰고 모델 클래스 메서드를 부르지 않는다.
- 색·타이포: 스톤 카드(`rounded-2xl border border-stone-200 bg-white p-5 shadow-sm`)와 주황 배지(`bg-orange-50 text-orange-600`)는 환불 완료 섹션과 같은 조합이고, 링크는 `min-h-11`이다. 기존 화면과 일관된다.
- 금지 표현: 해당 없음(발신·마케팅 문구가 아니다). 오해 소지 1건(F-2).
- 상세 화면 밖의 재주문 진입점은 막히지 않는다(F-1).

**5. R2-6 — 확인함**

- `grep -rn "승인 응답" app` 결과 5건(`client_service.rb:31`·`:62`, `purchase_service.rb:6`·`:94`, `fulfill_pass_service.rb:20`)은 모두 "승인 응답에는 `pgTxId`·`paidAt`만 있다"는 정확한 서술이다. 낡은 서술 패턴은 0건.
- 03 §10 표의 줄 번호·"액션 4줄·7줄 유지"·수치(1,590 runs)는 코드와 맞다. 미세한 차이: 회귀 테스트 위치가 `:50~77`(실제 `:51~80`), `mark_verification_failed!` 끝이 `:91`(실제 `:88`), 세금계산서 뷰 하위 분기 `:130~152`(실제 `:131~145`).

**6. 새 테스트의 밀봉성 — 확인함(코드 경계). CI 조건 재현 실행은 하지 않음**

- 헬퍼 `with_portone_channel_keys`(`test/test_helpers/portone_stubbing.rb:24-47`)는 교체 전 `Method` 객체를 저장하고 `ensure`에서 `define_singleton_method(이름, 원본)`으로 복원한다. 저장소를 `begin` 밖에서 초기화해 예외 경로에서도 복원된다. 중첩 호출은 바깥이 자기 시점의 메서드를 캡처하므로 올바르게 겹친다(`test/jobs/subscription_renewal_job_test.rb:82-84`). `live:`는 `live == true`로 정규화한다(원본과 같은 판정). 이 방식은 기존 `with_portone_client`(`:7-13`)와 같은 계약이다.
- `config.x.portone_live_channel`를 직접 교체하는 테스트는 하나다(`test/services/port_one/channel_key_test.rb:78-89`) — `ensure`에서 복원(O-5).
- 실제 credentials를 읽는 경로와 새 테스트의 관계. ① `ChannelKey.fetch` 기본 인자 — `fetch`에 가짜를 넘기거나(`channel_key_test.rb:20-70`) `.normal`·`.billing`을 교체한다. ② `ClientService#initialize` 기본 인자 — `client_service_test.rb:37`은 `api_secret: "test-secret", store_id: "store-test"`를 주입한다. 잡 테스트의 키 없음 시나리오(`subscription_renewal_job_test.rb:33-57`·`test/services/subscriptions/dunning_retry_test.rb:232-250`)는 기본 인자로 실제 값을 읽지만 가드가 HTTP 전에 예외를 던진다(`client_service.rb:55-56` → `:84-88`). 읽힌 값은 요청에 쓰이지 않는다. ③ `@portone_store_id`(컨트롤러 3곳) — 어떤 테스트도 store-id 속성을 단언하지 않는다.
- 다른 테스트로 새지 않는다: 비시스템 테스트는 프로세스 병렬(`Running 1656 tests in parallel using 8 processes`)이고 시스템 테스트는 단일 프로세스다. 교체는 블록 범위 + `ensure`다.
- 시스템 테스트와 서버 스레드: 싱글톤 메서드 교체는 같은 프로세스의 서버 스레드에 보인다(의도). `visit`이 응답을 기다린 뒤 블록이 끝나므로 복원 뒤에 오는 요청이 없다.
- TEST_GUARD 우회 없음: `Thread.current[:portone_http_stub]`를 켜는 곳은 `with_http_transport`(`portone_stubbing.rb:56`) 한 곳이고 같은 헬퍼가 `Net::HTTP.start`를 함께 교체한다(`:50-53`). 시스템 테스트는 "결제하기"를 클릭하지 않는다. 이번 실행에서 TEST_GUARD 메시지로 실패한 테스트는 0건이다.

**7. 새 테스트의 회귀 가치 — 확인함. 핵심 결함 4종을 각각 잡는다**

| 결함 | 잡는 테스트 | 단언 |
|:---|:---|:---|
| 정상 결제가 검증 실패로 처리되던 결함(승인 응답으로 검증) | `test/services/orders/purchase_service_test.rb:47-66`·`:16-40` | 대역의 승인 응답은 기본값(`pgTxId`·`paidAt`만). paid·패스 1건·승인 1회·재조회 1회(`assert_equal 1, fake.calls[:get_payment].size`)·metadata 스냅샷이 재조회 결과 |
| 검증 실패 주문이 웹훅으로 paid 되돌려지던 결함 | `test/controllers/webhooks/portone_controller_test.rb:55-80`·`:354-379` | `failed?`·`paid_at` nil·패스 없음·`updated_at` 불변 |
| 채널 키 없음이 라이브 키로 대체되던 결함 | `test/services/port_one/channel_key_test.rb:41-47`·`:49-60`, `test/services/port_one/client_service_test.rb:305-341` | 라이브 키가 있어도 nil, HTTP 요청 0건 |
| `== true`를 truthy로 바꾸면 전 환경 라이브 | `test/services/port_one/channel_key_test.rb:78-89`, `test/services/port_one/payment_verifier_test.rb:176-189` | `"true"`·`nil`·`1`·`false`는 테스트 채널 |

- 검증기 행렬은 `payment_verifier_test.rb` 20건(Developer 5 + Tester 15)이다. 금액(낮음·높음·nil·키 누락·문자열·비Hash·비객체), 채널(교차·누락·공백·소문자·심볼·비Hash), 통화(USD·nil·키 누락), 형태 이상 10종, 문자열 키, `live:` 비정상 값을 덮는다. 빠진 변형은 O-3(전부 실패로 떨어짐을 실행 확인).
- 그 밖의 보강: 콜백 금액·채널·통화 불일치(`purchase_service_test.rb:265-321`), 즉시 승인 채널(`:322-336`), 모호 실패·ALREADY_PAID 회복 경로의 검증 실패(`:338-372`), 승인 거절과의 구분(`:394-411`), 웹훅 금액·채널·통화 불일치(`portone_controller_test.rb:265-324`), 재수신 멱등(`:326-352`), 모델 4건(`order_test.rb:115-202`).

**8. 시스템 테스트 1건 — 확인함**

- `test/system/app_billing_channel_key_notice_test.rb:13-28`는 "결제하기"를 클릭하지 않는다(`assert_no_button "결제하기"`). 로그인·이동·렌더만 본다.
- 교체 복원은 `with_portone_channel_keys(normal: nil)`의 `ensure`이고 `visit` 뒤 블록이 끝난다.
- 선례: `fill_in`은 `ApplicationSystemTestCase#fill_in`(`test/application_system_test_case.rb`)이 값 검증형으로 덮어쓰므로 이 테스트도 자동으로 그 선례를 탄다. `log_in_as`(`click_button "로그인"` + `assert_text`)는 `test/system/app_invoice_form_scorecard_test.rb:34-40`와 같은 패턴이다. 클릭 드롭 대응 `dom_click_button`은 `button_to` 전용 선례라 로그인 폼에는 해당하지 않는다. 내 실행은 15/15 통과(1회).

**9. 문서 정합 — PRD·03 §10은 코드와 맞다. AGENTS 노트는 통화 누락(F-4)**

- PRD(`PRD.md:214`): "주문이 paid가 되는 길은 검증을 거친 확정 경로뿐 — 웹훅의 상태 동기화는 pending 주문의 확정 외에는 주문을 paid로 바꾸지 않는다", "통화가 KRW인지도 확인한다", "검증 실패 주문은 앱 안에서 환불·재발급할 수 없다" — 모두 코드와 맞다.
- AGENTS(`AGENTS.md:212`): 웹훅 가드·검증 실패 주문 식별값·첫 실결제 확인 항목은 코드와 맞다. 검증 항목 목록에 통화가 빠져 있다(F-4).
- PRD 문장 "paid가 되는 길은 검증을 거친 확정 경로뿐"은 바로 뒤 단서대로 단건 결제 기준이다. Plus 갱신(`upgrade_service.rb:144`·`:186`)과 `FulfillTaxInvoiceService:20`의 미검증 전이는 그대로다(재리뷰 2회차 O-3·O-4, 변경 금지 대상).
- 03 §10: 위치·수치 일치(§3-5). 수치 흐름 1,584 → 1,590(Developer) → 1,656(Tester)가 실행과 같다.

**10. 앞선 변경과의 충돌 — 없음**

- R2-5의 모델 메서드는 `VerificationError`의 `reason`·`detail`을 그대로 기록하고, 검증기·확정점·콜백 재조회 구조는 변경되지 않았다.
- R2-4의 `currency:` 필수 인자에 맞춰 `FakePortOneClient#confirm_payment`가 `currency:`를 받는다. 대역 쪽은 선택 인자라 앱 코드가 인자를 빠뜨려도 서비스 테스트는 통과하지만, 실제 클라이언트의 본문 등식(`client_service_test.rb:43-67`)과 서비스의 전달 값 단언이 그 차이를 막는다.

### 4. Rule ID 준수 매핑

| Rule ID | 판정 | 근거 |
|:---|:---|:---|
| PLAN-5 결제 확정 검증 | **준수** | 단건 결제의 paid 전환은 검증 확정점 하나. 웹훅은 pending 주문의 확정만 검증점을 탄다. 금액·채널·통화 검증, 승인 요청에 `totalAmount`·`isTest`·`currency` |
| PLAN-4 (수금 패스) | 준수 | 검증 통과 뒤에만 발급. 검증 실패 주문은 패스 0건 |
| LEGAL-2 (내용증명) | 준수 · 안내 미흡(F-1~F-3) | 정식 PDF는 검증을 거친 paid 주문만. 회원 안내는 상세 화면에서만 재결제를 차단한다 |
| TAX-1 (세금계산서) | 준수 | 발행은 검증 통과 뒤 `FulfillTaxInvoiceService` 한 경로 |
| SEC-5 (멱등) | 준수 | 검증 실패 기록은 잠금 안에서 pending을 다시 판정한다. 재수신 이벤트는 무변경 |
| ADMIN-4 (실패 주문) | 준수 · 감시 수단 없음(F-2) | `metadata.code`·`verification`은 관리자 주문 상세에 보인다. 자동 알림은 없다 |
| PLAN-9·ADMIN-11 (환불 콘솔) | 미지원(R2-3, 기존) | 검증 실패 주문은 사전 가드 대상이 아니다 — AGENTS 노트에 콘솔 수동 절차 |

### 5. 실행한 명령과 결과

| 명령 | 결과 |
|:---|:---|
| `mise exec -- bin/rails test` | 1,656 runs, 10,504 assertions, 0 failures, 0 errors, 0 skips(seed 57421, 8프로세스) |
| `mise exec -- bin/rails test:system` | 15 runs, 135 assertions, 0 failures, 0 errors, 0 skips(seed 46808, 1회) |
| `mise exec -- bin/rubocop` | 430 files inspected, no offenses |
| `mise exec -- bin/rails zeitwerk:check` | all is good |
| `mise exec -- bin/brakeman --no-pager -q` | Errors 0, Security Warnings 0 |
| `bin/rails runner -`(development, `PortOne::PaymentVerifier` 순수 객체만 — credentials·HTTP 접근 없음, 키 값 미출력) 2회 | 변형 50여 건 — 테스트에 없는 음수·0·소수·`true`/`false`·중첩 이상·심볼/소문자/공백 통화·대소문자 변형 채널·`live:` 10종. 예상 밖 예외 0건 |
| `grep`·소스 열람 | paid 대입 줄 전수, 웹훅 라우트, `승인 응답` 주석, `pending_recovery`·`verification` 소비자, `portone_http_stub` 설정처, `activerecord-8.1.4.1` `with_lock` 소스 |
| 작업트리 | 실행 전후 `git status --short` 해시 동일(`510978e8…87961d`). 코드·문서 수정 0건(이 파일의 이 절만 추가) |

### 6. 확인한 것 / 확인하지 못한 것

**확인한 것**

- R2-1~R2-6의 반영(§1·§3-1~5). paid로 바꾸는 줄 5곳과 그중 검증을 거치지 않는 곳이 주문 상태를 바꿀 수 있는 조건.
- `with_lock` 블록 안 `next`의 동작(설치된 Rails 소스).
- 검증기는 테스트에 없는 변형에서도 실패로 떨어지고 `live:`가 `true`일 때만 LIVE를 받는다(실행).
- 새 테스트의 교체·복원 구조와 실제 credentials를 읽는 경로의 분리(코드 경계). TEST_GUARD 우회 경로 없음.
- 전체 테스트·시스템 테스트·정적 분석 3종 통과(§5).

**확인하지 못한 것**

- **실제 포트원 응답**. 재조회 응답에 `currency`가 "KRW"로 오는지, `amount.paid`가 주문 금액과 같고 `amount.discount`가 0인지, `channel.type`이 `LIVE`인지, 승인 200 뒤 재조회가 즉시 `PAID`인지. 스펙과 코드만으로 판단했다. 통화 검증이 추가돼 실패 폭이 금액·채널과 같아졌다.
- **CI 조건(마스터 키 없음)에서의 실행**. 마스터 키 파일을 옮기는 재현은 하지 않았다(저장소 파일 조회·변경 최소화). 밀봉성은 코드 경계 판정이다.
- **R2-1 가드를 지운 상태의 실행**. 회귀 테스트의 실질성은 코드를 읽어 판정했다(코드 수정 금지).
- **F-3의 실행 재현**. pending 회복 주문의 문구 덮어쓰기는 코드 추적이다(1차 재리뷰에서 같은 줄의 덮어쓰기를 실행 확인한 선례).
- **시스템 테스트 반복 안정성**. 1회 실행(15/15). 07 보고서의 "전체 스위트 16회 중 2회 실패(기존 테스트 플레이크)"는 재현하지 않았다.
- 운영 부팅의 플래그 값, 웹훅 URL 등록 상태, 포트원 콘솔 설정.

### 7. 운영 첫 실결제 때 반드시 확인할 것

1. **결제 1건으로 응답을 기록한다**(운영자 실카드 — 운영은 테스트 채널 결제가 거절된다). 승인 응답이 `pgTxId`·`paidAt`뿐인지, 재조회 응답의 `status`·`amount.paid`·`amount.discount`·`channel.type`·**`currency`**. `currency`가 없거나 "KRW"가 아니면 그 결제는 failed가 된다 — 그 경우 결제를 더 진행하지 말고 검증기를 고친다. 개인정보·키 값은 제외한다.
2. 주문이 paid가 되고 `paid_at`이 기록되며 발급(또는 PDF 다운로드)이 정확히 1회이다. 콜백(paymentToken)과 휴대폰(redirectUrl, paymentToken 없음) 경로를 각각 1건씩 본다.
3. 콜백이 pending으로 남긴 경우 웹훅으로 회복되는지(V2 실연동 탭 웹훅 URL이 운영 주소인지).
4. 소액 결제 1건이 failed + `metadata.code == "PAYMENT_VERIFICATION_FAILED"`로 남고, 그 뒤 `/webhooks/portone`에 같은 paymentId의 `Transaction.Paid`를 보내도 paid로 바뀌지 않는다. 내용증명 주문이면 다운로드는 워터마크 PDF다.
5. 4번 주문이 관리자 주문 상세에서 식별되는지, 회원 상세 화면에 문의 안내만 보이는지(F-1~F-3 반영 여부에 따라 목록·청구서 상세의 재주문 링크도 함께 본다).
6. 검증 실패 주문의 처리 절차(포트원 콘솔 환불·CS 수동 재발급)를 담당자가 알고 있는지. 자동 알림은 없다.

### 8. Tester 중점 테스트(권장 — 이번 지시 범위 밖)

1. **대역 계약**: `FakePortOneClient.new`의 기본 승인 응답 키가 `[:pgTxId, :paidAt]`이다(자동 보강 재발 방지, O-2).
2. **웹훅 `get_payment` `ApiError`**: 응답이 2xx가 아니어 재시도가 유지된다(07 보고서가 남긴 항목).
3. **F-3 반영 뒤**: pending 회복 주문의 내용증명 `?payment_failed=1` 착지 문구.
4. **F-1 반영 뒤**: 검증 실패 주문이 있는 청구(내용증명·세금계산서)와 미결제 검증 실패 패스 주문이 있는 사용자가 `create`를 다시 요청하면 새 주문이 만들어지지 않는다.
5. cancelled 주문 + `Transaction.Paid` → paid로 돌아가지 않는다(R2-1 가드의 나머지 절반).
6. 행렬 공백: 음수·소수 불일치·`true`·`:KRW`(O-3).
7. 콜백↔웹훅 경합에서 검증 실패 기록이 정확히 1회.

### 9. 운영상 주의

1. **credentials 보류 해제**: R2-1이 해소됐고 BLOCKER·CRITICAL이 0건이므로 `config/credentials.yml.enc`을 코드 변경과 별도 커밋으로 분리해 배포할 수 있다(AGENTS "운영 포트원 스토어 전환" 노트의 배포 전 확인은 그대로).
2. **WARNING 4건의 처리는 오케스트레이터가 정한다.** F-2(문구 1줄)·F-1(`create` 가드)은 배포 전 반영을 권장한다. 둘 다 변경 범위가 작아 반영 뒤에는 그 diff와 테스트 1~2건만 확인하면 된다. F-3·F-4는 후속으로 미뤄도 결제 안전성에는 영향이 없다.
3. **첫 실결제 확인(§7)은 생략하지 않는다.** 검증기는 fail-closed라 스펙과 실제 응답이 다르면 정상 결제가 실패 처리된다. 금액·채널에 이어 통화까지 세 필드 모두 그 대상이다.
