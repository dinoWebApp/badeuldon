# 07_test_report — F-EMAIL 자체 메일 API 연동 (2026-11-20, Phase 7 Tester · 일반 모드)

- **최종 게이트**: `bin/rails test` — **1,438 runs · 8,917 assertions · 0 failures · 0 errors · 0 skips** · `bin/rubocop` — **406 files, no offenses**
- **코드 버그: 0건** — 실행 과정의 전 실패(초기 12건 + 환경 의존 3건)는 전부 테스트 측 오류였고 자체 수정 후 재실행으로 해소했다. Developer 소스(app/·config/)는 1줄도 접촉하지 않았다(작업 트리의 `app/`·`config/` `M` 항목은 03 §6.4 기재의 Phase 6 잔존분 — 터치 0).
- 신규 테스트 **39건(테스트 4파일 + 헬퍼 2파일)** — 기저 1,399(03 §Phase 6 기록) → **1,438**. 기존 테스트 갱신 0건(passwords_mailer_test의 host 단정 권장은 기존 파일 대신 신규 통합 테스트로 충족 — §2-③).
- **API 실호출 0건** — 외부 경계 3중 방어선(§5) + 로컬 credentials에 `outbound_mail.token` 미등록이라 `configured? == false`로 실호출이 구조적으로 불가한 상태까지 겹보험. 전 테스트가 stub 주입으로만 동작했다.

### 환경 의존 결함 밀봉(2026-11-20 bin/ci 후속)

- **결함(테스트·코드 무관)**: 운영자가 로컬 credentials에 `outbound_mail` 블록(token·from_email·from_name·reply_to)을 등록하면서 "credentials 부재"를 전제한 단정 3건이 실패 — `delivery_method_test` reply_to compact·from_email 누락 fail-fast·`integration_test` DEFAULT_FROM_EMAIL 폴백.
- **밀봉 조치**: `with_sealed_outbound_mail_credentials` 헬퍼 신설(Rails.application.credentials 스텁 — initialize 폴백이 `settings[:x] || credentials` 형태라 **명시 nil 주입은 `||`를 통과해 부재 강제가 불가**하므로 credentials 자체가 유일한 밀봉 지점). ①②번은 밀봉 블록으로 부재 상태 강제, ③번은 ambient(등록 여부 무관 — 유효 이메일만 단정) + 밀봉(폴백 상수 격리 — 부트 시점 계산 default은 재평가 후 원복) 이원화. ambient credentials 의존 단정 전수 재점검 — 나머지 36건은 settings 주입이 `||` 우선이라 원래 환경 독립임을 확인(credentials 등록 상태에서 전체 1,438 runs 재통과).

---

## 1. 신규 테스트 파일 (4파일 · 39건 + 헬퍼 2)

| 파일 | 건수(단언) | 커버 |
|---|---|---|
| `test/test_helpers/fake_outbound_mail_client.rb` | — | 솔라피 FakeSolapiClient 선례 준용 대역 — configured? 토글·payload 기록·raise_on callable(호출 횟수 기반 실패 주입 — 재시도 시나리오)·idempotency_keys 접근자 |
| `test/test_helpers/outbound_mail_stubbing.rb` | — | ① `with_outbound_mail_client`(생성자 교체 — 잡 계층 주입) ② `with_outbound_mail_logger`(StringIO — [OUTBOUND_MAIL:*] 로그 단정) ③ `with_outbound_mail_delivery`(**production 시뮬레이션** — 클래스 레벨 delivery_method·outbound_mail_api_settings·raise_delivery_errors 3종 세팅/원복) ④ FakeOutboundMailTransport(Net::HTTP.start 교체 — PortOneStubbing.with_http_transport와 짝) |
| `test/services/outbound_mail/client_service_test.rb` | 11(97) | 202 스냅샷 3키 파싱·POST /api/v1/emails·Bearer·Content-Type·`Idempotency-Key` 헤더 승격+바디 제외·최상위 null compact(html_body·reply_to 미송신)·token 부재 configured? false→MISSING_CREDENTIALS fail-fast(실호출 0)·키 규격 위반 5종 fail-fast(네트워크 왕복 없음)·403 code 정규화+비재시도·오류 본문 3형식 탐색({code}·{error:}·{data:} — [INFERENCE] I-1)·빈 본문/비JSON 방어(HTTP_400·원문 보존)·429/502/503(MANUAL_REVIEW 포함) 재시도 대상·409/400/401/MISSING_CREDENTIALS 제외·타임아웃→TIMEOUT·접속 실패→CONNECTION(모두 retryable) |
| `test/services/outbound_mail/delivery_method_test.rb` | 12(69) | multipart text+html 파트 조립·**from/reply_to credentials 강제(메일러 from을 attacker로 바꿔도 교체 단정)**·to/cc/bcc 매핑(nil→빈 배열 유지)·단일 text 파트(html_body·reply_to·name 키 소멸 — compact)·단일 text/html 파트·from_email 누락 MISSING_CREDENTIALS fail-fast(전송 시도 0)·**본문 없는 메일 INVALID_REQUEST fail-fast(네트워크 스파이 0)**·`X-BD-Outbound-Idempotency` 헤더 우선(잡 경로)·폴백 `bd.`+SHA256 67자 결정성(동일 내용 동일 키·타 메일 상이 키)·**정적 본문(locked_out)은 travel 2초 후에도 동일 키 / reset 재렌더는 exp 타임스탬프 로테이션으로 상이 키(지시 1 — freeze_time)**·폴백 분기(configured false → 실호출 0·로그 정확히 1행·수신자 마스킹 `al***@`·전체 주소·링크 미노출·예외 없이 정상 복귀)·@ 없는 비정형 수신자 원형 유지·성공 sent 로그 1행(id·message_id·마스킹·본문 미기록·스냅샷 반환 유지)·**전체 체인(DeliveryMethod→ClientService→전송 계층)에서 키는 JSON 바디에 없고 헤더로만** |
| `test/jobs/outbound_mail/delivery_job_test.rb` | 9(50) | **C-1 회귀(최우선)** — 같은 admin·같은 IP의 new_login 2회 = 서로 다른 `job.<uuid>` 키로 **실제 2회 발송**(멱등 흡수 없음·키 규격 8~128자)·locked_out 반복 이벤트도 2회 실발송(AUTH-7.3)·**같은 job_id 재수행 = 같은 키**·retryable(TIMEOUT) 1차 실패 → **retry_job이 같은 job_id로 재적재(scheduled_at 백오프)** → travel 1시간 후 재시도 성공·**재시도 동일 키(SEC-5 — idempotent_replay 중복 없음)**·retryable 코드 perform에서 재상승(retry_on 전파)·**5회 소진 시 예외 재상승(잡 실패 가시 — Solid Queue)·5회 시도 한도**·비재시도(400) 버림(재적재 없음·discard 로그 code·status·job_id만 — **message 원문·수신자 미기록 단정**)·retry_on 선언 존재(부모 MailDeliveryJob은 부재 — W-5)·**잡 키가 payload JSON·메일 본문으로 유출되지 않음**(전송 계층까지 전체 체인) |
| `test/mailers/outbound_mail_delivery_integration_test.rb` | 7(50) | **부트 등록 스모크**(`delivery_methods[:outbound_mail_api]` 등록·settings 접근자 응답·주입 경로 런타임 배달 — 지시 10·T-6)·U1 재설정 플로우 deliver_later→배달 방식 payload 도달(**테스트 환경은 기본 잡 — 내용 해시 폴백 키 `bd.`** — production은 DeliveryJob·`job.` 키 별도 검증)·**재설정 링크 `https://badeuldon.kr/passwords/` 단정(text+html — production default_url_options 주입)**·**production.rb 단정**(raise_delivery_errors=true·delivery_method=:outbound_mail_api·delivery_job="OutboundMail::DeliveryJob"·default_url_options host=badeuldon.kr https·유효 설정에 example.com 잔존 0(주석 제외)·문자열 지정 상수화→MailDeliveryJob 서브클래스 확인)·**관리자 3종(잠금·신규 IP·재설정) 배달 방식 3건 발송+서로 다른 키**·관리자 3종 각각 payload(수신자·제목·본문 키워드·폴백 키)·**from 봉투 폴백**(credentials 부재 환경에서 `ApplicationMailer.mailer_from_header`·PasswordsMailer·AdminMailer 봉투 = DEFAULT_FROM_EMAIL `badeuldon@veloloop.kr` — Mail 2.9.1 SmtpEnvelope 파탄 차단 확인) |

## 2. 시나리오 ↔ Rule ID 매핑

| Rule ID | 시나리오(위 표 근거) |
|---|---|
| **AUTH-8** | U1 재설정 메일 deliver_later→배달 방식 payload 도달·**링크 `https://badeuldon.kr/passwords/`**(text+html)·production.rb host 단정·재렌더 로테이션(새 키=새 메일)·봉투 from 폴백 유효 |
| **AUTH-7.3** | locked_out 반복 이벤트 잡 키로 이벤트별 실발송(C-1 회귀)·정적 본문 동일 키(재시도 멱등)·관리자 3종 payload(제목·본문 키워드) |
| **AUTH-7.4** | **같은 admin·같은 IP 두 번째 new_login = 다른 키로 실제 2회 발송**(C-1 핵심 회귀)·신규 IP 통보 payload 정합 |
| **AUTH-7.6** | 관리자 재설정 메일 동일 경로 3종 발송 커버·token_url 본문 반영 |
| **EXT-1(이메일 행)** | POST /api/v1/emails·Bearer·202 접수 스냅샷 3키·오류 표 매핑(403/409/429/502/503·HTTP_폴백)·**W-5 해소 — retryable 5회·polynomially_longer 백오프·비재시도 버림** |
| **SEC-5** | 멱등 체계 전면 검증 — ① 잡 키: 이벤트별 유일(새 deliver_later=새 키)+재시도 동일(같은 job_id) ② 폴백 키: 결정적 내용 해시(bd.+hex64=67자·규격 문자셋) ③ 키는 Idempotency-Key 헤더로만(payload JSON·메일 본문 미유출) ④ 키 규격 위반 네트워크 왕복 없이 fail-fast |
| **P4** | 폴백 로그 1행(수신자 마스킹 `al***@`·@ 없는 값 원형·전체 주소·본문·링크 미노출)·성공 sent 로그 1행(id·message_id·마스킹)·버림 로그(code·status·job_id만 — message 원문·수신자 미기록)·오류 원문 본문은 ApiError.message로만 운반(로그 미기록) |
| **TIME-1** | freeze_time·travel 기반 — reset 토큰 exp 로테이션 2초 경계·재시도 백오프 1시간 여유 |

## 3. 리뷰 10항목 커버 표 (05_review 「Tester 중점 지시」)

| # | 지시 | 결과 | 테스트 |
|---|---|---|---|
| 1 | 멱등 키 결정성/로테이션 분리(freeze_time 2초 포함) | 통과 — locked_out 재렌더 travel 2초 후 동일 키·reset 재렌더 상이 키(exp 타임스탬프)·동일 순간 결정성·타 메일 상이 키 | delivery_method 3건 |
| 2 | **C-1 회귀(수정 후 필수)** | 통과 — new_login 동일 (admin, IP) 2회 = 서로 다른 `job.` 키로 실제 2회 발송(흡수 0)·동일 job_id 재수행 = 동일 키·locked_out도 동일 | delivery_job 3건 |
| 3 | 폴백 분기(token 없는 stub) | 통과 — 실호출 0·로그 정확히 1행·전체 주소/본문/링크 미노출·`deliver!` 예외 없이 정상 복귀(nil 반환) | delivery_method 2건 |
| 4 | 실전송 payload 단정 | 통과 — from/reply_to 강제(메일러 from 무시 공격 시나리오)·to/cc/bcc 매핑·text/html 파트·nil compact(html_body·reply_to 키 부재)·**idempotency_key가 JSON 바디에 없고 헤더로만**(단위+전체 체인+잡 체인 3중) | delivery_method 5건 + client_service 2건 + delivery_job 1건 |
| 5 | 본문 없는 메일 fail-fast | 통과 — INVALID_REQUEST·네트워크 스파이 0 | delivery_method 1건 |
| 6 | ClientService 단위 | 통과 — 202 스냅샷 3키·403/409/429 매핑·retryable?(429/502/503 true·409/400/401 false)·본문 3형식+빈/비JSON 방어·키 규격 위반 fail-fast·**Net::HTTP fake 인자 순서(httpv·code·message) 준수**(03 §6.1 함정) | client_service 11건 |
| 7 | 잡 실패 전파(raise_delivery_errors=true) | 통과 — production 시뮬레이션(3종 클래스 설정)에서 retryable 재상승→retry_on·**5회 소진 시 예외 재상승=잡 실패 가시**·비재시도 버림(재적재 0·가시 로그)·잡 밖 경로는 재시도 없이 예외 가시(MISSING_CREDENTIALS·INVALID_REQUEST) | delivery_job 4건 + delivery_method 2건 |
| 8 | 링크 유효성(회귀) | 통과 — `https://badeuldon.kr/passwords/` 단정(text+html)·production.rb host+protocol 단정·**유효 설정 example.com 잔존 0**(주석 제외 — 지시의 "config 전수 grep"은 주석 예시 3곳까지 포함하면 과잉이므로 활성 설정 기준)·기존 passwords_mailer_test의 `%r{/passwords/}` 단정 무영향 통과 | integration 2건 |
| 9 | 기존 테스트 무영향 회귀 | 통과 — passwords_controller_test·admin/sessions_controller_test·passwords_mailer_test **28 runs 231 assertions 개별 통과** + 전체 스위트 1,438 runs 0 failures(`assert_enqueued_email_with`·deliveries 단정 전부 유지) | 전체 스위트 |
| 10 | 부트 등록 스모크 | 통과 — `delivery_methods[:outbound_mail_api] == OutboundMail::DeliveryMethod`·`outbound_mail_api_settings` 접근자 존재·**settings 주입 경로 런타임 배달 성공**(등록 심볼→DeliveryMethod.new(settings)→stub client 호출) | integration 1건 |

## 4. 발견 사항 (코드 버그 판정)

### BUG 없음 · 관찰 1건(수정 불필요 — 잠재 파탄 경로 기록용)

- **`OutboundMail::DeliveryMethod`에 `attr_accessor :settings` 부재** — Mail 2.9.1 `Message#deliver!`(bang)이 배달 후 `delivery_method.settings[:return_response]`를 참조해 NoMethodError가 난다(실측 — 부트 스모크 초기 실패로 발견).
- **생존 경로 무영향 판정 근거**: production의 전 deliver 호출부 4곳은 `deliver_later` → DeliveryJob `perform` → `MessageDelivery#deliver_now` → `message.deliver`(**non-bang**) → `do_delivery` → `DeliveryMethod#deliver!(mail)` 순서로, `.settings` 참조가 없는 Mail `deliver`/`do_delivery` 경로다(젬 소스 실측: message.rb `deliver`·`do_delivery` — `.settings`는 bang `deliver!`에만 존재). 실제로 부트 스모크를 non-bang `deliver`로 수행하면 정상 발송된다.
- 분류: **코드 버그 아님**(현재 동작 불일치 없음) — 단, Rails 가이드의 커스텀 배달 방식 관례(`attr_accessor :settings`)와의 편차이며 향후 `deliver_now!`·`message.deliver!` 직접 호출 시 파탄하는 잠재 경로다. Developer 후속으로 1행 추가(`attr_accessor :settings` + initialize에서 대입)를 권장한다. 지시 제약(소스 수정 금지)에 따라 이번 스코프에서 수정하지 않았다.

### 실행 과정 테스트 오류(자체 수정 — 12건, 원인 5종)

1. Net::HTTP 응답 대역 기대값 오류 — `from.name` 중첩 null은 DeliveryMethod 내부 compact가 담당(ClientService compact는 최상위만), 빈 본문 오류는 message nil(예외 기본 문구) → 기대값 정정.
2. `assert_not_match` 오타(minitest는 `assert_no_match`).
3. freeze_time 블록 내 중첩 travel_to 가드 → `travel 2.seconds`(비블록) 전환.
4. **reset 재렌더 결정성 단정에 freeze_time 누락**(시간 미고정 시 exp 로테이션으로 키가 바뀌는 것이 설계 동작) — freeze_time 후 단정.
5. FakeOutboundMailTransport 위치(client_service_test 전용 → 헬퍼로 이동)·단일 text 테스트의 reply_to 오염·**production 시뮬레이션 부재**(잡 체인이 :test 배달로 향해 fake 미호출)·**sim settings에 from_email 미주입**(credentials 부재 → MISSING_CREDENTIALS fail-fast — 설계대로 동작하는 것을 테스트 환경이 자극)·rescue_handlers Array 구조·JSON 키 문자열 비교·Hash#each_value 비구조화·bang `deliver!`의 `.settings`(위 관찰) → 전부 테스트 측 정정 후 재실행.

## 5. 실호출 0 방어선

1. **단위**: DeliveryMethod settings `client:` 주입(FakeOutboundMailClient) — 정규 검증 경로(03 §6).
2. **잡 계층**: `with_outbound_mail_client` 생성자 교체(SolapiStubbing 선례) — DeliveryMethod의 지연 기본 생성(`ClientService.new`) 가로챔.
3. **전송 계층**: `with_http_transport`(PortOneStubbing 선례) — 실제 ClientService를 통과하는 체인 테스트에서 Net::HTTP.start 교체.
4. **구조적 방어**: 로컬·테스트 credentials에 `outbound_mail.token` 미등록(불리언 실측) → `configured? == false` → DeliveryMethod 폴백·ClientService MISSING_CREDENTIALS로 HTTP 시도 자체가 불가.
5. 잡 체인은 `with_outbound_mail_delivery`로 production 3설정(delivery_method·settings·raise_delivery_errors)만 시뮬레이션 — 자격증명은 주입하지 않는다.

## 6. 후속 제안 (오케스트레이터 판정 대상)

1. 위 관찰 — `OutboundMail::DeliveryMethod`에 `attr_accessor :settings` 1행 추가 권장(잠재 파탄 경로 제거·Rails 관례 정합).
2. 05_review W-1(PRD AUTH-8 "Idempotency-Key=메시지 ID" 문구) — 구현 확정 문언은 `job.<job_id>`(새 잡)·`bd.`+내용 해시(잡 밖)이므로 02_prd_update 후속 반영 필요(재확인).
3. 재리뷰 범위(05 §수정 후 재리뷰) — C-1 수정 파일(delivery_method.rb·DeliveryJob·initializer·production.rb)은 본 테스트가 전부 커버했다. W-3·W-4 로그 마스킹/성공 기록도 단정 완료.
