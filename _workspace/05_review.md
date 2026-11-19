# 05_review — F-EMAIL 자체 메일 API 연동 (2026-11-20, 일반 모드 · reviewer)

## 상태: **CHANGES_REQUESTED** (CRITICAL 1 · WARNING 6)

- 리뷰 범위: `app/services/outbound_mail/{api_error,client_service,delivery_method}.rb`·`config/initializers/outbound_mail.rb`·`config/environments/production.rb`·`app/mailers/application_mailer.rb` (03 §1 목록 기준 — 작업 트리의 solapi/tax/credentials 변경은 제외)
- 검증 방법: 코드 전수 + Rails 8.1.4 젬 소스 실측(`delivery_methods.rb`·`mail_delivery_job.rb`·`rescuable.rb`) + 콜사이트·뷰·credentials 키 존재 여부(불리언만) 실측. 코드 수정 0건.
- 총평: 래퍼·배달 방식·폴백·등록 시점의 설계와 실측 근거는 솔라피/포트원 선례에 정합하고 대부분의 집중 검증 항목을 통과했다. 그러나 **SHA-256 콘텐츠 해시 멱등 키가 '새 이벤트'와 '재시도'를 구분하지 못해**, 본문이 정적인 보안 통보(AUTH-7.3/7.4)의 반복 이벤트가 메일 서버의 영구 idempotent_replay에 흡수되어 **조용히 미발송**되는 결함이 있다. 운영 개시 전 수정을 권고한다.

---

## 이슈

### C-1 (CRITICAL) — 반복 이벤트 멱등 흡수: AUTH-7.4/AUTH-7.3 보안 통보 메일 무음 소멸

- `rule_id`: AUTH-7.4(주)·AUTH-7.3·P4
- `file:line`: `app/services/outbound_mail/delivery_method.rb:112-116`(`idempotency_key` — 수신자·제목·본문의 SHA-256)
- **문제**: 멱등 키가 렌더 결과 콘텐츠에서만 파생되므로, 본문이 정적인 통보 메일은 **(수신자, IP) 쌍마다 키가 영구 고정**된다. 메일 서버는 `UNIQUE (api_client, idempotency_key)`(OUTBOUND_MAIL_API.md §Idempotency 동작 — TTL 없음)로 같은 키+같은 payload에 **202를 내며 기존 메시지를 반환(재발송 없음)**한다. 즉 두 번째 이벤트는 앱 입장에서 "성공"이지만 실제 이메일은 존재하지 않는다.
- **실측 트리거(현실적·반복 가능)**:
  - `app/controllers/admin/sessions_controller.rb:166-171` — `notify_new_ip`는 `last_login_ip != request.remote_ip`일 때마다 발동한다. 사무실(A)/자택(B) IP를 오가는 관리자는 **매 로그인마다 통보가 발생**하는데, 본문(`app/views/admin_mailer/new_login.text.erb:2` — 변수는 admin.email·ip뿐)은 (관리자, IP)마다 동일 → 두 번째 A 로그인부터 알림이 전부 흡수된다.
  - `app/controllers/admin/sessions_controller.rb:84-87` — unlock→재잠금 시 `locked_out`(변수=admin.email뿐 — `locked_out.text.erb`)도 동일 본문 → 재잠금 통보 미발송.
- **03 §2.1 분석의 간극**: 개발자는 "재시도·재실행 모두 동일 키 → 완전 멱등"을 장점으로 기술했으나, 이는 **같은 잡의 재실행**에 대한 서술이다. **새 이벤트(새 deliver_later)**가 같은 콘텐츠를 만드는 경우는 분석 범위 밖이었고, `MailDeliveryJob`에 retry_on이 없어(실측 재확인 — 아래 통과 근거 T-9) 현재 이 키 설계가 주는 유일한 실효가 바로 이 이벤트 억제다.
- `suggestion`: 03 §2.1이 스스로 제안한 **잡 식별자 기반 키로 승격**(지금 수행 권장): `ActionMailer::MailDeliveryJob` 서브클래스(`config.action_mailer.delivery_job`)에서 `job_id`(재시도에 보존)를 전달해 키 파생에 포함 — "이벤트별 유일 + 재시도 동일"을 동시에 충족하고 C-1·W-2가 함께 해소된다. 근시일 대안: 이벤트 식별자(admin_session id·lockout 감사 행 id)를 메일러에서 `mail.headers`로 전달하고 `idempotency_key` 파생에 포함(임의 헤더가 payload에 유출되지 않음은 `build_payload`가 명시적으로 재조립하므로 보장됨).

### W-1 (WARNING) — PRD AUTH-8 '구현 확정' 문구와 메커니즘 불일치(문서 정합)

- `rule_id`: AUTH-8
- `file:line`: `PRD.md:107`(문구) ↔ `app/services/outbound_mail/delivery_method.rb:12-24`(구현)
- PRD v0.43 AUTH-8은 "**Idempotency-Key=메시지 ID**(잡 재시도 멱등)"로 구현 확정 기재. message_id가 렌더 직후 nil임을 실측해 SHA-256 파생으로 대체한 것은 타당하나(지시 메커니즘의 원천 불가는 인정), ① PRD가 단일 소스인 이상 괄호 목적 "잡 재시도 멱등"도 현재 미충족(retry 부재 + 재시도를 도입해도 재설정 링크 로테이션으로 재렌더=새 키)이므로 **PRD 문구 개정이 후속으로 필요**하다. 02_prd_update 후속 또는 C-1 수정 시 함께 반영.

### W-2 (WARNING) — "같은 키 ↔ 같은 payload 구조적 보장(409 불가)" 주장은 성립하지 않음

- `rule_id`: SEC-5
- `file:line`: `app/services/outbound_mail/delivery_method.rb:21-23`(주석)·`_workspace/03_implementation.md` §2.1 표
- 멱등 키는 `to·subject·body`만 커버하고 payload의 **`from.name`·`reply_to`·`cc`·`bcc`는 키에 미포함**이다. 동일 본문 이벤트 재발(C-1 시나리오)과 credentials 정책 변경(예: from_name·reply_to 추가)이 겹치면 같은 키+다른 payload → **409 IDEMPOTENCY_CONFLICT** → ApiError(재시도 불가) → 잡 실패(가시적이나 메일은 역시 미발송). 주석·03 문서의 "구조상 발생하지 않는다" 서술을 정정하고, C-1의 job_id 기반 전환으로 키-페이로드 커플링을 끊을 것.

### W-3 (WARNING) — 폴백 로그의 수신자 전체 주소 노출 (확인 요청 성격)

- `rule_id`: P4/개인정보
- `file:line`: `app/services/outbound_mail/delivery_method.rb:49-50`
- 폴백 로그가 `to=<이메일 전체>`·`subject=`를 기록한다. 본문 미기록은 준수했으나 리뷰 기준('로그에 본문·수신자 미노출')과는 배치된다. 다만 운영 전환 확인(03 §4.3 `grep OUTBOUND_MAIL`)에 to·subject가 실제 필요하고, 프로젝트 내 이메일 로그 선례(audit_logs 이메일 스냅샷 — ADMIN-3)가 있어 **수용 가능**하나 마스킹(예: `h***@domain`) 권장. 오케스트레이터 판정 요청.

### W-4 (WARNING) — 성공 발송의 앱 쪽 기록 0행 (P4 '로그 수준' 미달)

- `rule_id`: P4
- `file:line`: `app/services/outbound_mail/delivery_method.rb:54`(202 스냅샷 반환값이 버려짐)
- 실발송 성공 시 앱 로그에 어떤 흔적도 남지 않는다(기록은 메일 서버 MailApiMessage에만 존재). 01_plan은 "P4(발송 기록: 로그 수준)"을 선언했다. 성공 1행(`id`·수신자만 — 본문 없음) 로그 추가 권장. W-3과 마스킹 기준을 통일해 결정.

### W-5 (WARNING) — 01_plan 대비 미구현: 429/5xx 잡 재시도 없음

- `rule_id`: EXT-1·SEC-5
- `file:line`: `app/services/outbound_mail/api_error.rb:11-24`(retryable? — 사용처 없음)
- 01_plan은 "API 5xx/429 시 잡 재시도(Solid Queue retry_on)"를 명시했으나 `retryable?` 분류만 존재하고 실제 재시도는 없다(실패 잡 종결·수동 재실행 필요). 낮은 트래픽·분량 한도(분 30/일 100)·문서화되어 있어 v1 수용 가능하나, **계획-구현 편차로 기록**한다. C-1의 DeliveryJob 서브클래스 도입 시 `retry_on ApiError, if: :retryable?` 설계와 함께 정리할 것(같은 job_id로 안전 재시도가 가능해진다).

### W-6 (WARNING) — AdminMailer 헤더 주석 시효 만료 (Developer 판정 요청 항목 — 수정 권고)

- `file:line`: `app/mailers/admin_mailer.rb:1-2`
- "이메일 서비스 미지정으로 Action Mailer 기본 발송… 실발송 연결은 기술 부채" — 이번 전환으로 과거 서술이 됐다. 주석 1행이지만 신뢰성 문서이므로 정정 권고(이번 스코프에 포함해도 무방 — 파일 2줄 수정).

---

## 통과 근거 (집중 검증 항목별)

| # | 항목 | 판정 |
|---|---|---|
| T-1 | **폴백 안전성**: `deliver!`가 `client.configured? == false`면 로그 1행 후 `return`(delivery_method.rb:47-52) — 예외 없이 정상 복귀하므로 production `raise_delivery_errors = true`(production.rb:64)와 무충돌. credentials 실측: `outbound_mail` 블록 미등록 상태(키 불리언 확인만 — 값 미열람) → 현재 로컬에서 폴백 경로가 실제 활성 경로. token만 있고 `from_email` 없는 운영 실수는 fail-fast(`MISSING_CREDENTIALS` — 조용한 통과 아님) — 설계 의도대로 | 통과 |
| T-2 | **토큰 처리**: token은 `Authorization` 헤더에만 사용·로그·예외 메시지·inspect 경로 전무. ApiError message는 오류 본문/네트워크 예외 메시지만 운반(토큰 미포함). Idempotency-Key는 파생 해시라 민감 아님 | 통과 |
| T-3 | **SSRF/헤더 주입**: base_url은 credentials(신뢰원) 전용·스킴별 SSL은 로컬 http 검증 지원(문서 명시 목적). Idempotency-Key는 `IDEMPOTENCY_KEY_PATTERN`(client_service.rb:23)으로 CRLF 불가 문자셋만 송신 전 검증. 바디는 JSON.generate로 이스케이프 | 통과 |
| T-4 | **payload 조립**: from/reply_to credentials 강제(메일러 지정 무시 — delivery_method.rb:82-94)·to/cc/bcc 매핑(`{email:}` 배열·빈 배열 유지는 사양 예시와 정합)·multipart/단일 파트 모두 처리(text+html 없으면 네트워크 전 fail-fast)·`.compact` 이중 방어(DeliveryMethod+ClientService)로 null 필드 미송신 | 통과 |
| T-5 | **Idempotency-Key 문자셋/길이**: `bd.`+SHA-256 hex64 = 67자·`[A-Za-z0-9._-]` — API 규칙(8~128자) 충족 + 송신 직전 패턴 검증(client_service.rb:49-52) | 통과(단, 파생 원천은 C-1) |
| T-6 | **등록 시점**: Rails 8.1.4 `delivery_methods.rb` 실측 — `add_delivery_method`는 클래스 객체 저장(개발자 주석 정확)·`wrap_delivery_behavior`는 배달 시점에 registry 조회. `after_initialize` 등록으로 부트 순서 안전(배달은 항상 부트 이후 — deliver_later 잡 프로세스도 전체 부트 수행). 테스트 시먼트 `outbound_mail_api_settings`도 Rails 공식 settings 전달 경로와 일치(실측) | 통과 |
| T-7 | **default_url_options 교정**: example.com→`badeuldon.kr`·https(production.rb:69) — 재설정 링크 회귀 해소. test.rb의 example.com은 Rails 표준 관행·기존 테스트 단정 무영향. (기존 프로덕션 메일은 애초에 미발송 상태였으므로 '링크 파탄'은 잠재 결함이었고 지금 수정됨) | 통과 |
| T-8 | **202 처리·오류 매핑**: `Net::HTTPSuccess`는 2xx 전체(202 포함) → data 3키 스냅샷. 오류는 상태+code 정규화·`HTTP_<status>` 폴백·원문 본문 보존(P4 진단). RETRYABLE_CODES 근거는 OUTBOUND_MAIL_API.md §2 오류 표와 정합(모호 실패·일시 장애 / 4xx·409 제외 — 409는 W-2 시나리오에서만 발생 가능) | 통과 |
| T-9 | **MailDeliveryJob 재시도 부재(Developer 실측 재확인)**: 젬 소스 — `rescue_from StandardError → handle_exception → rescue_with_handler(exception) \|\| raise`(rescuable.rb:15-17)·retry_on 정의 없음. raise_delivery_errors=true에서 ApiError는 잡 실패로 가시 기록됨. "재렌더 케이스는 자동 발생하지 않는다"는 서술 정확 | 통과 |
| T-10 | **재설정 링크 재발송 = 새 메일(AUTH-8 수용성 판정)**: `has_secure_password` reset token는 exp 타임스탬프 기반 로테이션 → 재렌더 시 새 키·새 메일. 유효 링크 2개 공존(≤15분)은 Rails 표준 재발송 동작이며 "1회성(사용 시 password_salt 불일치로 무효)·단기 만료(15분)" 규칙은 무결 — **AUTH-8 위반 아님**. PRD가 "Rails 인증 표준 플로우"를 명시한 점과도 정합 | 통과(근거 기록) |
| T-11 | **아키텍처**: 순수 Ruby 래퍼(AR 비의존)·credentials 기본값+주입·fail-fast — 솔라피/포트원 래퍼 패턴 일치(규약 §4 의존 방향 위반 없음). 도메인 네임스페이스 `app/services/outbound_mail/`·네이밍 규약 §5 부합. 커스텀 배달 방식 규격(initialize(settings)/deliver!(mail))은 Rails 8.1 동작과 실측 정합. 기존 메일러·deliver_later 호출부 0줄 수정 — 컨벤션상 모범적 전환 | 통과 |
| T-12 | **기존 테스트 무영향 구조**: test 환경 `:test` 배달 유지(test.rb:37)·메일러 미수정 → `passwords_mailer_test`(from 미단정)·`passwords_controller_test`·`admin/sessions_controller_test`의 `assert_enqueued_email_with`·deliveries 단정은 구조적으로 무영향 | 통과(Phase 7 실행 확인 — T-13 참조) |

## Rule ID 준수 매핑

| Rule ID | 판정 |
|---|---|
| AUTH-8 | **대체 준수** — 자체 Outbound Mail API·커스텀 배달 방식·발신 강제(badeuldon@veloloop.kr — credentials)·등록 전 로그 폴백 ✓. Idempotency-Key 메커니즘은 PRD 문구에서 편차(W-1)·링크 1회성/15분 만료 유지(T-10) |
| AUTH-7.4 | 경로 전환 ✓ — 단 반복 IP 이벤트 통보 무음 소멸(**C-1**) |
| AUTH-7.3 | 경로 전환 ✓ — 재잠금 통보 무음 소멸(**C-1**) |
| AUTH-7.6 | 준수 — 재설정 메일 동일 경로·토큰 로테이션으로 새 이벤트별 정상 발송 |
| EXT-1(이메일 행) | 준수 — OUTBOUND_MAIL_API.md 사양(Bearer·Idempotency-Key 헤더 승격·202=접수·오류 표 매핑) |
| SEC-5 | 부분 준수 — Idempotency-Key 멱등 체계는 있으나 파생 원천 결함(C-1)·키-payload 커플링 주장 오류(W-2) |
| P4 | 부분 준수 — 폴백 기록 ✓·성공 발송 앱 기록 0행(W-4)·수신자 로그 노출(W-3) |

## Tester 중점 지시 (Phase 7 — 10항목)

1. **멱등 키 결정성/로테이션 분리 검증**: 정적 본문(AdminMailer.locked_out 재렌더)은 동일 키·재설정(reset) 재렌더는 상이 키 — `freeze_time` 2초 경과 케이스 포함(토큰 exp 타임스탬프 의존).
2. **C-1 회귀(수정 후 필수)**: 같은 admin·같은 IP의 두 번째 new_login 이벤트가 서로 다른 키를 갖는지(이벤트 식별자/job_id 주입 검증)·동일 잡 재수행 시에는 동일 키인지.
3. **폴백 분기**: token 없는 stub client 주입 → 실호출 0(spay)·로그 1행(본문·링크 미포함 단정)·`deliver!` 예외 없이 정상 복귀.
4. **실전송 분기**: stub client 주입 → payload 단정 — from/reply_to 강제(메일러 from 무시)·to/cc/bcc 매핑·text/html 파트·nil compact(html 없는 메일에 html_body 키 부재)·`idempotency_key`가 JSON 바디에 없고 헤더로만 전달.
5. **본문 없는 메일 fail-fast**: 파트 없는 Mail 조립 → `INVALID_REQUEST` ApiError(네트워크 스파이 0).
6. **ClientService 단위**: fake `Net::HTTP*` 응답으로 202 스냅샷 3키·403/409/429 code 매핑·`retryable?`(429 true·409/400 false)·오류 본문 3형식 탐색+빈 본문/비JSON 방어·키 규격 위반 fail-fast. **Net::HTTP fake 응답 생성 인자 순서 함량 주의**(03 §6.1 — httpv, code, message).
7. **잡 실패 전파**: `raise_delivery_errors = true`에서 ApiError가 잡 실패로 종결되는지(perform_enqueued_jobs + 실패 기록 단정) — 재시도 없음 확인.
8. **링크 유효성(회귀)**: 재설정 링크가 `https://badeuldon.kr/passwords/...`인지 — 기존 `passwords_mailer_test`의 `%r{/passwords/}` 단정 갱신 포인트(프로토콜·host 단정 추가 권장). config 전수 `example.com` 잔존 grep.
9. **기존 테스트 무영향 회귀**: `passwords_controller_test`·`admin/sessions_controller_test`의 `assert_enqueued_email_with`·deliveries 단정 통과 확인(03 §6.2 주장 검증).
10. **부트 등록 스모크**: 부트 후 `ActionMailer::Base.delivery_methods[:outbound_mail_api]` 등록·`outbound_mail_api_settings` 주입 경로 동작(런타임 확인).

## 수정 후 재리뷰 범위

C-1 수정(키 파생 전환)은 `delivery_method.rb`·신규 DeliveryJob·initializer·production.rb(delivery_job 지정)에 걸치므로 **재리뷰 대상**. W-1~W-6은 문서·보조 수정으로 동시 반영 권장(재리뷰에서 확인만).
