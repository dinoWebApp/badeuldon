# 03_implementation — F-EMAIL 자체 메일 API 연동 (2026-11-20, 일반 모드 · Sequential · developer)

## 0. 결과 요약

- `bin/rubocop` 0 offenses(399 files) · `bin/rails zeitwerk:check` 통과 · runner 스모크 **26항목 전부 PASS · 실호출 0건**(전송 계층 stub·`perform` 오버라이드만 사용)
- 테스트 파일 미작성(Phase 7 Tester 대상) · git 커밋 없음(지시서 제약 준수) · PRD/AGENTS/OUTBOUND_MAIL_API.md/01_plan 미수정(PRD v0.43은 이미 오케스트레이터가 반영)
- 기존 메일러(`PasswordsMailer`·`AdminMailer`)와 `deliver_later` 호출부 4곳 **수정 0줄** — 배달 방식 교체만으로 전환

## 1. 변경 파일 전수

### 신규 (4)

| 파일 | 내용 |
|---|---|
| `app/services/outbound_mail/api_error.rb` | 오류 정규화 — `status`(HTTP)·`code`(OUTBOUND_MAIL_API.md §2 오류 표)·`message`. `RETRYABLE_CODES`(TIMEOUT·CONNECTION·RATE_LIMITED·LOCAL_MTA_ERROR·MAIL_SERVICE_UNAVAILABLE·MANUAL_REVIEW) + `retryable?` — 솔라피 래퍼와 동일 규약 |
| `app/services/outbound_mail/client_service.rb` | HTTP 래퍼 — credentials `outbound_mail: {base_url, token}` 기본값+주입(port_one 선례·Net::HTTP 방식)·`configured?`(token 부재=비구성)·`send_email(payload)`(payload의 `:idempotency_key`를 헤더로 승격·바디에서 제외·`compact`로 null 제거)·202 → `{id, message_id, status}` 스냅샷·타임아웃 10초·스킴별 SSL(로컬 검증 http 지원)·오류 표 code 매핑 |
| `app/services/outbound_mail/delivery_method.rb` | ActionMailer 커스텀 배달 방식 — `initialize(settings)`(settings에 `client:`·`from_email:`·`from_name:`·`reply_to:` 주입 가능 — 테스트 시 대체)·`deliver!(mail)`(multipart text+html·단일 파트 추출→payload 조립)·from/reply_to credentials 강제·Idempotency-Key 파생·credentials 부재 시 로그 폴백 |
| `config/initializers/outbound_mail.rb` | `ActionMailer::Base.add_delivery_method :outbound_mail_api, OutboundMail::DeliveryMethod` — **`after_initialize`로 등록**(Rails 8.1 `add_delivery_method`는 클래스 객체 자체를 저장하므로 상수 실재 필요 — app 코드는 초기자 시점에 자동 로딩 전이라 직접 참조하면 NameError 실측 → finisher 순서 확인 후 `after_initialize`(zeitwerk 세팅·eager_load 이후)로 미룸) |

### 수정 (2)

| 파일 | 내용 |
|---|---|
| `config/environments/production.rb` | ① `config.action_mailer.raise_delivery_errors = true` ② `config.action_mailer.delivery_method = :outbound_mail_api` ③ `default_url_options`를 `host: "example.com"` → **`host: "badeuldon.kr", protocol: "https"`** — 재설정 링크가 실제 도메인 https로 생성(기존 example.com이면 운영 재설정 링크가 파탄 — 지시서 4번 항목) |
| `app/mailers/application_mailer.rb` | `default from: mailer_from_header` — credentials `outbound_mail.from_email`·`from_name` → `"받을돈 <badeuldon@veloloop.kr>"` 형식 표시 발신자(실제 발신은 배달 방식이 재강제). 미구성 환경(개발·테스트)은 from nil — 배달 방식 로그 폴백이 흡수 |

### 미수정 (설계 목적 달성 확인)

- `app/mailers/passwords_mailer.rb`·`admin_mailer.rb`·컨트롤러 4곳(`passwords_controller`·`admin/{passwords,sessions}_controller`의 `deliver_later`) — **한 줄도 수정 없음**
- 개발·테스트 환경 설정 — 기존 유지(test=`:test` 배달 → 기존 메일러·컨트롤러 테스트 전부 무영향)

## 2. 설계 결정

### 2.1 Idempotency-Key — 지시서 메커니즘의 실측 기반 교체 [중요 편차]

지시서는 "mail.message_id 정제(bd. 접두)"를 규정했으나 **2026-11-20 실측으로 불가능이 확인**됐다:

1. `mail.message_id`는 **렌더 직후 nil**이다(mail 2.9.1 — `Mail::Message#deliver!`가 배달 방식을 호출한 뒤 Mail gem이 난수로 채움. gem 소스 확인: `deliver!` → `delivery_method.deliver!(self)` 시점에 message_id 미부여).
2. 난수라 재렌더마다 달라져 **잡 재시도 동일 키**라는 지시서의 명시 목적("잡 재시도 동일 직렬화=동일 키(자연 멱등)")를 원천적으로 만족할 수 없다.

**채택: 렌더 결과의 결정적 필드(수신자·제목·본문)의 SHA-256 파생 키**(`bd.` + hex 64자 = 67자 — API 규칙 8~128자·[A-Za-z0-9._-] 충족). 실측으로 멱등 범위를 확정했다:

| 메일 종류 | 재렌더 본문 | 멱등 동작 |
|---|---|---|
| AUTH-7.3 잠금 통보·AUTH-7.4 신규 IP | **결정적(실측)** — 정적 문구+수신자+IP | 재시도·재실행 모두 동일 키 → API 멱등 흡수(재발송 없음) — 완전 멱등 |
| AUTH-8·AUTH-7.6 재설정 링크 | **렌더마다 로테이션(실측)** — Rails `token_for`가 `expires_in` 타임스탬프를 서명 페이로드에 포함 | 재렌더 시 새 키 = 새 메일. 단 두 링크 모두 유효(token_for는 사용자 상태 기반 검증 — 무결성 손실 없음) |
| 어떤 경우든 | — | 같은 키 ↔ 같은 payload가 구조적으로 보장 → **409 IDEMPOTENCY_CONFLICT 불가능** |

보완 사실: `ActionMailer::MailDeliveryJob`은 **retry_on이 없다(실측)** — 현재 자동 재시도가 없어 재렌더 케이스는 자동 발생하지 않는다(Solid Queue 실패 기록·수동 재실행만). 잡 재시도를 도입할 때의 권장 후속: `ActionMailer::MailDeliveryJob` 서브클래스(`OutboundMail::DeliveryJob` — `around_perform`에서 `job.job_id`를 스레드 로컬로 전달)+`config.action_mailer.delivery_job` 지정으로 **잡 식별자 기반 키**로 승격 — job_id는 ActiveJob 재시도에 보존되어 완전 멱등이 된다. 이번 스코프(프레임워크 잡 커스터마이징 미포함) 밖이라 03에 기록만 남긴다.

### 2.2 from·reply_to 강제

API는 클라이언트별 사전 허용 발신 주소만 수용한다(SENDER_NOT_ALLOWED 403). 메일러·default from 지정과 무관하게 페이로드의 from/reply_to를 credentials로 교체한다(주석 명시). 단, **token은 있는데 from_email이 없는 운영 실수는 폴백이 아니라 fail-fast**(`MISSING_CREDENTIALS`) — 조용히 통과시키지 않는다. `configured?`는 base_url(문서 기본값 상존)·token 기준.

### 2.3 폴백(무중단 전환)

`client.configured? == false`(credentials outbound_mail.token 미등록) → 실호출 없이 `Rails.logger.info("[OUTBOUND_MAIL:fallback] …")` 1행(수신자·제목만 — 본문 미기록은 메일 서버 쪽 원칙 준용) 후 정상 종료. NOTI-3(NO_TEMPLATE skip)과 같은 선례 — 등록 전 기존 동작 유지. production `raise_delivery_errors = true`와의 조합이 안전한 이유: 미등록 시 예외가 아니라 정상 종료한다.

### 2.4 등록 시점

`add_delivery_method`는 클래스 객체를 저장(Rails 8.1 `delivery_methods.rb` 실측) → 초기자에서 app 상수 직접 참조 시 NameError(실측) → `after_initialize`(finisher `:setup_main_autoloader`·`:eager_load!` 이후 — finisher.rb 소스 확인)로 등록.

### 2.5 그 외

- 첨부 미지원(v1) — 재설정·보안 통보 메일에 불요. 추후 `attachments` 필드로 확장 가능(payload 조립 지점 한 곳).
- 202 응답은 `{success, data}` 래퍼에서 data의 식별자 3키만 스냅샷 반환. 202=Postfix 접수까지만 — 최종 배달 추적은 메일 서버 쪽(GET /api/v1/emails/:id·journalctl).
- 스모크에서 발견해 반영한 방어 1건: ClientService 송신 바디 `.compact` — nil 값(`html_body: null`)이 JSON null로 나가는 것을 차단(사양상 text/html 중 하나 이상 요건과 null 처리 불명확 — DeliveryMethod의 compact와 이중 방어).

## 3. [INFERENCE] — 실측 전 항목(첫 실발송 시 확정)

| # | 항목 | 근거·확정 방법 |
|---|---|---|
| I-1 | **오류 본문 형식** — 성공이 `{success, data}` 래퍼인데 오류는 `{code,message}` / `{error:{code,message}}` / `{data:{code,message}}` 어느 형태인지 문서 미명시 | 래퍼가 3형식을 순차 탐색하고 코드 없으면 `HTTP_<status>`, 메시지 없으면 원문 본문 보존. 첫 4xx 실응답으로 확정 |
| I-2 | **202 응답 data 상세** — `id`(=`mail_…` ULID?)·`message_id` 형식은 문서 예시뿐 | 스냅샷은 3키만 잘라 반환 — 키 존재만 보장하면 동작. 첫 실발송 응답 캡처로 확정 |
| I-3 | **null 필드 수용 여부** — 사양 예시는 `cc: []` 등 빈 배열이지만 null 미언급 | 래퍼가 null을 제거해 송신(2.5) — 실측 불요 가능성 높으나 첫 발송에서 확인 |
| I-4 | **RATE_LIMITED 재시도 호환** — 분 30/일 100 초과 시 429 본문 형식 | `retryable?`에 포함 — 실측 시 잡 재시도 설계(2.1 후속)와 함께 정리 |
| I-5 | **한글 Display Name 인코딩** — from_name "받을돈"의 RFC2047 인코딩은 Mail gem 표준 동작에 위임 | 첫 실발송 수신함에서 표시 확인 |

## 4. 사용자 운영 절차(게이트 확정 대상)

### 4.1 메일 서버(rake 2종 — OUTBOUND_MAIL_API.md §1 재사용)

```bash
# ① 발급 — 토큰은 이때 한 번만 출력(메일 서버 쪽 DB는 SHA-256 digest만 저장)
sudo /opt/company-mail/scripts/run-rake.sh 'mail:api_client:create[badeuldon]'

# ② 발신 주소 허용 — 권고: badeuldon@veloloop.kr(전용 alias. PRD v0.43 확정 발신 주소)
sudo /opt/company-mail/scripts/run-rake.sh 'mail:api_client:allow_sender[badeuldon,badeuldon@veloloop.kr]'
```

- `badeuldon@veloloop.kr` alias가 아직 없으면 메일 서버에 alias 신설이 먼저 필요(활성 메일 사용자 또는 alias만 allow_sender 가능 — API 문서 규칙). `contact@veloloop.kr`은 이미 허용돼 있을 가능성(문서 예시)이나 **서비스 전용 주소 원칙상 전용 alias 권장**(문서: "서비스마다 별도 클라이언트 발급·공용 토큰 금지" 정신 준용).
- 운영 한도: 분 30(클라이언트별)/일 100(전체 합산) — 재설정+관리자 통보 트래픽으로는 충분(01_plan 리스크 2 재확인).

### 4.2 credentials 등록(받을돈 서버 — `bin/rails credentials:edit`)

```yaml
outbound_mail:
  base_url: "https://mail-api.veloloop.kr"   # 생략 가능 — 래퍼 기본값 상수와 동일
  token: "<4.1에서 출력된 MAIL_API_TOKEN>"     # 필수 — 이것만 부재면 로그 폴백(무중단)
  from_email: "badeuldon@veloloop.kr"         # 필수 — allow_sender로 허용된 주소(없으면 fail-fast)
  from_name: "받을돈"                          # 선택 — 표시명(생략 시 주소만)
  reply_to: "contact@veloloop.kr"             # 선택 — 승인된 회사 주소만 허용
```

- 등록 순서 무중단: ① 위 credentials 등록 전에는 모든 메일이 `[OUTBOUND_MAIL:fallback]` 로그로 흡수(기존 동작 유지) ② 등록·재배포 후 실발송 전환 ③ 토큰 회전은 `mail:api_client:rotate[badeuldon]` → credentials 갱신
- 토큰은 URL·로그·채팅에 노출 금지(API 문서 운영 규칙 — master.key와 동일 보관 등급)

### 4.3 전환 확인

```bash
# fallback 로그가 더 이상 안 찍히는지 + 실발송 1건(개인 계정으로 비밀번호 재설정 요청)
bin/kamal logs | grep OUTBOUND_MAIL
# 메일 서버 쪽 접수·배달 추적
sudo /opt/company-mail/scripts/run-rake.sh runner \
  'puts MailApiMessage.order(created_at: :desc).limit(5).pluck(:id, :status, :error_code)'
```

## 5. 자가 검증 기록

| 게이트 | 결과 |
|---|---|
| `bin/rubocop` | 399 files inspected, **no offenses** |
| `bin/rails zeitwerk:check` | "Otherwise, all is good!" |
| runner 스모크(26단언) | **전부 PASS·exit 0·실호출 0** — ①payload 조립·키 규칙(bd.+hex64=67자·문자셋)·from/reply_to 강제·to/cc/bcc 매핑·첨부 미지원 ②재렌더 동일 키(정적 본문)·다른 메일 다른 키 ③폴백(실호출 없음·로그 태그·본문 미기록) ④ClientService(엔드포인트·Bearer·Idempotency-Key 헤더·바디에서 키 제외·null 제거·202 스냅샷·403→ApiError status/code/비재시도·규격 위반 키 fail-fast·configured?) ⑤전체 체인(PasswordsMailer → delivery_handler → :outbound_mail_api → payload)·production.rb 설정 반영 |
| 전체 테스트 실행 | **금지 준수 — 미실행**(Phase 7 Tester 대상) |

- 스모크 스크립트: `/tmp/outbound_mail_smoke.rb`(저장소 밖 — 커밋 대상 아님). 테스트 주입 시먼트: `config.action_mailer.outbound_mail_api_settings = { client: …, from_email: … }`로 전송 계층 stub·발신자 주입 가능(`initialize(settings)` 경유).

## 6. Tester·Reviewer 전달 사항

1. **테스트 시먼트**: DeliveryMethod 단위는 settings 주입(stub client·from_email)·ClientService 단위는 `perform` 오버라이드 또는 WebMock 없이 fake `Net::HTTP*` 응답(`.new("1.1", "403", "Forbidden")` 인자 순서 주의 — httpv·code·message. 첫 인자에 상태코드를 넣으면 `code`가 오염됨 — 스모크에서 실측한 함정).
2. **기존 테스트 무영향 확인 요망**: test 환경은 `:test` 배달 유지 → `passwords_mailer_test`·`passwords_controller_test`·`admin/sessions_controller_test`의 `assert_enqueued_email_with`·`ActionMailer::Base.deliveries` 단정은 그대로 통과해야 한다(렌더 결과 불변 — from만 credentials 의존이 되어 단정 대상 아님).
3. **문구 점검 결과**(지시서 4번): 메일러 뷰 4종(reset·locked_out·new_login·password_reset 각 text/html) 본문 존재 확인·한국어 안내 완비·링크 host는 production default_url_options 갱신으로 badeuldon.kr(https). AdminMailer 헤더 주석의 "이메일 서비스 미지정" 문구는 이제 과거 서술이지만 파일 수정 금지 대상이 아닌 **주석 1행**이라 판단 — 건드리지 않았다(Reviewer 판정 요청).
4. **작업 트리 잔존**: 이번 위임과 무관한 미커밋 변경이 이미 존재(solapi·phone_verifications AUTH-9 계열, tax_invoices notify_issued 등) — 건드리지 않았다. 커밋 시 분리 권장.

## 7. Rule ID 구현 매핑

| Rule ID | 구현 |
|---|---|
| AUTH-8 | U1 재설정 메일이 `:outbound_mail_api`로 실발송 전환(메일러·컨트롤러 무수정 — 배달 방식 교체)·링크 host badeuldon.kr(https) |
| AUTH-7.4 | 신규 IP 통보 메일 동일 경로 전환 — 정적 본문으로 완전 멱등 키 |
| AUTH-7.6 | 관리자 재설정 메일 동일 경로 전환 |
| EXT-1(이메일 행) | OUTBOUND_MAIL_API.md 사양 준수 래퍼 — Bearer·Idempotency-Key·202 접수 스냅샷·오류 code 매핑 |
| SEC-5 | Idempotency-Key 파생(결정적 렌더 해시 — 2.1 멱등 범위 실측 문서화·재시도 시 같은 키 재사용 경로 확보) |
| P4 | 폴백 로그 기록(수신자·제목만)·오류 시 원문 본문 보존(ApiError message) — 본문은 어느 경로로도 미기록 |

## Phase 6 수정(2026-11-20) — 05_review CHANGES_REQUESTED(C-1·W1~W6) 반영

### 0. 원칙·범위

- 리뷰 지적만 최소 수정 — 리뷰 외 변경 0건. 기존 deliver_later 호출부 4곳은 여전히 수정 없음.
- W-1(PRD AUTH-8 문구)은 코드 스코프 밖 — 오케스트레이터의 Phase 6 문서 갱신 대상으로 남긴다.

### 1. C-1 — 멱등 키를 잡 식별자 기반으로 전환(리뷰 권고 방향)

**키 파생 순서 변경**(`delivery_method.rb#idempotency_key`): ① `X-BD-Outbound-Idempotency` 헤더 존재 시 그 값 우선 → ② 부재 시 기존 내용 해시(잡 밖 경로 폴백 — 직접 `deliver_now`·`deliver!`·테스트 한정으로 유지, 주석에 용도·한계 명시).

| 파일 | 내용 |
|---|---|
| `app/jobs/outbound_mail/delivery_job.rb` (신규) | `ActionMailer::MailDeliveryJob` 서브클래스. 렌더(부모 본문 복제 — kwargs·params 분기 유지)→헤더 주입→배달. 헤더값 `"job.<정제 job_id>"` |
| `config/environments/production.rb` | `config.action_mailer.delivery_job = "OutboundMail::DeliveryJob"`(문자열 — railtie가 on_load 시점에 constantize, 실측으로 부트 순서 안전 확인). dev·test는 기본 잡 유지 → 기존 테스트 단정 무영향 |
| `app/services/outbound_mail/delivery_method.rb` | 키 파생 순서 전환·모듈 주석 재작성(아래 W-2) |

**잡 키 설계 — "이벤트별 유일 + 재시도 동일"을 동시에 충족:**
- 이벤트 유일: 새 `deliver_later` = 새 job_id = 새 키. 본문이 정적인 AUTH-7.3 잠금·AUTH-7.4 신규 IP 통보가 (수신자, IP)마다 영구 흡수되던 결함(202 idempotent_replay 무음 소멸)을 해소 — C-1.
- 재시도 동일: `retry_job`이 같은 인스턴스를 재 enqueue해 job_id 보존(Rails 8.1 `activejob/exceptions.rb:158` 실측) → 같은 키 재사용 → API 멱등 흡수로 중복 발송 없음(SEC-5).
- job_id 실측: Rails 8.1.4.1은 `SecureRandom.uuid`(`activejob/core.rb:105` — 리뷰 지시서의 "ULID"와 다름). UUID 문자셋 `[a-f0-9-]` ⊂ API 규격이나, `gsub(/[^A-Za-z0-9._-]/)` 정제를 유지해 생성기 교체에도 규격을 보장. `job.`+36자 = 40자(규격 8~128자 충족).
- 헤더 유출 없음: 헤더는 메모리상 Mail 객체에만 존재 — `build_payload`가 명시 필드로 payload를 재조립하므로 payload JSON·발송 이메일에 키가 노출되지 않는다(스모크로 단정).

**재시도 정책(W-5 동시 해소):** `retry_on OutboundMail::ApiError, wait: :polynomially_longer, attempts: 5`.
- retryable 오류만 재시도: retry_on에 `if:` 옵션이 없음을 Rails 8.1.4.1 실측(`activejob/exceptions.rb:64` — wait·attempts·queue·priority·jitter·report만) → perform의 `rescue ApiError`에서 `retryable?` 필터링(retryable은 재상승해 retry_on으로, 비재시도 코드는 error 레벨 로그 1행과 함께 버림 — code·status만 기록, message는 원문 응답 본문을 운반할 수 있어 미기록).
- 5회 소진 시 예외 재상승 → 잡 실패로 가시 기록(Solid Queue).
- 잡 밖 경로는 이 잡을 거치지 않아 재시도 없음(기존대로 실패 가시 — T-9 유지).
- 재렌더 본문 로테이션(재설정 메일) 재시도의 409 경계: 1차 시도가 서버 접수 후 응답만 소실된 경우만 가능하고 이때 1차 메일은 이미 발송된 상태 → 버림이 정답(모듈 주석에 문서화).

### 2. W별 반영 내역

| 항목 | 내용 |
|---|---|
| W-2 | 409 "구조상 불가" 주장 정정 — 내용 해시 키는 to·subject·본문만 커버해 from.name·reply_to·cc·bcc 변경 시 같은 키+다른 payload 가능. 잡 키 전환으로 커플링 해소·폴백 한계는 잡 밖 경로 한정으로 주석 문서화(§2.1 표 3행 "409 불가능" 서술도 본 섹션으로 정정) |
| W-3 | 폴백·성공 로그의 수신자 마스킹 — 로컬부 앞 2자+`***@도메인`(`masked_email` — @ 없는 비정형 값은 원형 유지). `masked_recipients` 헬퍼로 두 로그 기준 통일 |
| W-4 | 성공 발송 로그 INFO 1행 신설(`[OUTBOUND_MAIL:sent]` — `id`·`message_id`·`status`·마스킹된 수신자. P4 로그 수준). 202 스냅샷은 기존대로 반환값으로도 유지 |
| W-6 | AdminMailer 헤드 주석 갱신 — "이메일 서비스 미지정…기술 부채" → F-EMAIL 전환 서술(production DeliveryJob·재시도·dev/test 유지) |
| W-5 | C-1의 DeliveryJob + retry_on으로 해소(위 재시도 정책). `ApiError#retryable?`가 실제 사용처를 갖게 됨 |
| W-1 | 코드만 변경 — PRD AUTH-8 "Idempotency-Key=메시지 ID" 문구는 오케스트레이터 후속(잡 키 `job.<job_id>`가 새 구현 확정 문언) |

### 3. 검증 기록

- `bin/rubocop` — 400 files, **0 offenses**. `bin/rails zeitwerk:check` — **pass**.
- **runner 스모크**(stub 전용·실호출 0 — `/tmp/bd_smoke_phase6.rb`): ① `rescue_handlers`에 `OutboundMail::ApiError` retry_on 존재 + `retryable?` 분류(429·TIMEOUT=true / 400·409=false) ② 잡 경로 키=`job.<job_id>`·새 이벤트(같은 admin·같은 IP) 새 키(C-1 회귀)·헤더가 payload JSON 미유출 ③ 비재시도(400) 버림(예외 미상승)/retryable(TIMEOUT) 상승→retry_on 전파 ④ 직접 경로 폴백 키 `bd.`+해시 결정성·헤더 우선 ⑤ 폴백 분기 실호출 0·정상 복귀 ⑥ 로그 — sent 1행(id·message_id)·마스킹(`op***@example.com`)·전체 주소 무노출. **전부 통과**.
- **production 부트 실측**: `RAILS_ENV=production runner` — `delivery_job=OutboundMail::DeliveryJob`(on_load constantize 성공)·`delivery_method=outbound_mail_api`·`raise_delivery_errors=true`.
- **전체 테스트**: 1,399 runs·8,632 assertions — **0 failures, 3 errors**. 3 errors(AUTH-7.3/7.4·AUTH-8 컨트롤러 테스트의 "SMTP From address may not be blank")는 **Phase 6 무관·기존 상태**임을 A/B로 입증: HEAD 버전 `application_mailer.rb`(`default from: "from@example.com"`)로 임시 교체 시 3건 모두 통과(27 runs 0 errors, 원복 완료). 원인 = F-EMAIL 단계의 `default from: mailer_from_header`(로컬 credentials에 `outbound_mail.from_email` 미등록 → nil) + Mail 2.9.1 `TestMailer#deliver!`의 SmtpEnvelope 봉투 검증 신설 — 백트레이스에 Phase 6 파일이 전혀 없음. **후속(오케스트레이터 판정)**: 로컬 credentials에 from_email 등록 또는 Tester 단에서 from 미단정 경로 정비 필요.
- 스모크 실행 부산물 실측: dev는 `ActionMailer::Base.raise_delivery_errors`가 기본 false라 Mail gem `do_delivery`가 배달 예외를 흡수한다 — production.rb의 `true` 지정이 잡의 버림/재시도 분기가 작동하는 전제(기존 유지).

### 4. Rule ID 매핑 갱신(Phase 6 기준)

| Rule ID | 갱신 |
|---|---|
| AUTH-7.4·7.3 | 반복 이벤트 통보가 잡 키로 이벤트별 실발송 — 무음 소멸 해소(C-1) |
| SEC-5 | 멱등 체계 = 잡 식별자 키(이벤트 유일·재시도 동일) + 잡 밖 내용 해시 폴백(한계 문서화) |
| EXT-1(이메일 행) | W-5 해소 — retryable 코드 polynomially_longer 5회 재시도, 비재시도 버림 |
| P4 | 성공 발송 1행(id·message_id)·폴백/성공 수신자 마스킹·버림 로그(code·status만) |

### 5. 후속 최소 수정(동일일 — 오케스트레이터 지시): from 상수 폴백
- `application_mailer.rb` — `mailer_from_header`가 credentials `outbound_mail.from_email` 부재 시 상수 폴백 `DEFAULT_FROM_EMAIL = "badeuldon@veloloop.kr"`(운영 동일 주소·config 아님)를 반환해 메일러 봉투가 항상 유효(위 3 errors의 근본 차단). 실제 발신 강제(DeliveryMethod credentials 재강제·MISSING_CREDENTIALS fail-fast)는 불변 — **봉투 파탄 방지 전용**(주석 명시).
- 재검증: 전체 **1,399 runs·8,643 assertions — 0 failures·0 errors**(기존 3 errors 해소)·`bin/rubocop` 400 files 0 offenses·`bin/rails zeitwerk:check` pass. 커밋·실호출 없음.
- Tester 발견 방어(동일일): `DeliveryMethod`에 `attr_accessor :settings` 추가(`initialize`의 `@settings = settings` 저장은 기존 유지) — Mail 2.9.1 `Message#deliver!`(bang)가 `delivery_method.settings[:return_response]`를 참조하므로 임의 bang 경로 대비 표준 배달 방식 규격 정합(현재 호출부는 non-bang 경로라 무영향). 지정 테스트 `test/{services,jobs}/outbound_mail/`·`test/mailers/outbound_mail_delivery_integration_test.rb` 39 runs **0 failures**·rubocop 406 files 0 offenses·zeitwerk pass + stub으로 `Mail::Message#deliver!` self 반환 실측 확인(실호출 0).
