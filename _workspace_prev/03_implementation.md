# 03 구현 산출 — F-SALES 후속: 인증번호 알림톡 전환 (AUTH-9)

- 실행: 2026-11-19 · Standard · 최소 수정(사용자 정정 설계 반영 — 솔라피 대체문자가 폴백 담당, 코드 폴백 없음)
- 제약 준수: 테스트 작성 없음(Phase 7 Tester 몫) · PRD/AGENTS/01_plan 미수정 · 커밋 없음 · 솔라피 실호출 없음(stub 주입 스모크만)

## 수정 파일

### 1. `app/services/phone_verifications/send_service.rb`
- L10-12: `TEMPLATE_KEY = "phone_verification"` 상수 신설(레이트리밋 상수 아래).
- L1-8(헤더 주석): "SMS 발송" → "알림톡 우선 전환" 명세 갱신. 템플릿 등록 문구·변수명 "인증번호" 고정 명시.
- L31: `send_sms` 직접 호출 → `deliver!(code)` 위임.
- L41-55(`deliver!` 신설, private):
  - `@client.template_ids.key?(TEMPLATE_KEY)` → `send_alimtalk(template_key:, to:, variables: { "인증번호" => code })` **단독**. 알림톡 실패 시 SMS 코드 폴백 없음 — 대체문자는 솔라피 템플릿 대체문자 필드가 담당(REM-5, 2026-11-03 확정·주석 명시). 실패는 기존 `rescue Solapi::ApiError`(행 destroy → rate limit 미소진)로 흡수.
  - 키 부재(템플릿 등록 전 임시) → 기존 `send_sms` 경로(NOTI-3 선례 — 등록 공백기 가입 무중단).
- 불변: 정규화·형식 검증·rate limit·코드 발급·마스킹·발송 실패 시 행 destroy 로직 전부 기존 그대로.

### 2. `app/services/solapi/client_service.rb`
- L52-57: public 접근자 `template_ids` 신설 — credentials `solapi.template_ids` 맵 읽기 전용 노출(initialize에서 `nil → {}` 보장). 도메인 계층의 알림톡/SMS 분기 판정용. 송신 로직·바디 규격 변경 없음.

## 분기 명세

| 조건 | 경로 | 실패 시 |
|---|---|---|
| `template_ids`에 `phone_verification` 있음 | `send_alimtalk(인증번호=code)` 단독 | `Solapi::ApiError` → 행 destroy(레이트리밋 미소진)·사용자 실패 안내. **SMS 코드 폴백 없음**(솔라피 대체문자 REM-5 담당) |
| 키 부재(등록 전) | 기존 `send_sms(verification_message)` | 동일(기존 경로 그대로) |

## 자가 검증

- `bin/rubocop` (수정 2파일) — 0 offenses.
- `bin/rails runner` 스모크 3건(stub 주입·실호출 없음) — 전부 OK:
  1. 키 부재 → `send_sms` 단독 호출·본문에 발급 코드 포함
  2. 키 존재 → `send_alimtalk` 단독(SMS 미호출)·`variables == { "인증번호" => code }`·template_key 일치
  3. `Solapi::ClientService.new(template_ids: nil).template_ids == {}` 보장

## 운영 안내 (솔라피 템플릿 등록)

1. **템플릿 등록**: 솔라피 콘솔(카카오채널 '받을돈' 발신 프로필 REM-1)에 알림톡 템플릿 등록 — 검수 승인 필요.
   - 문구: `[받을돈] 가입 인증번호는 [#{인증번호}]입니다. 5분간 유효합니다.` — 변수명 **인증번호** 1개(코드와의 키 일치 필수).
   - **대체문자 필드 설정 필수(REM-5)**: 알림톡 발송 실패(미수신 앱 부재 등) 시 이 대체문자가 SMS로 대신 발송된다 — 서비스 코드의 SMS 폴백은 없음. 예: `[받을돈] 가입 인증번호는 [#{인증번호}]입니다. 5분간 유효합니다.` 동일 문구로 지정.
2. **credentials 키 추가 시점**: 승인된 템플릿 코드를 `config/credentials.yml.enc`의 `solapi.template_ids.phone_verification`에 추가(`rails credentials:edit`) → 배포 즉시 코드 변경 없이 알림톡 경로로 자동 전환된다(키 부재 중엔 SMS 경로 유지 — 가입 무중단).
3. pf_id(카카오채널 발신 프로필)는 알림톡 경로에 필수 — `solapi.pf_id` 설정 확인.

## Rule ID 매핑

- AUTH-9: 알림톡 우선(템플릿 `phone_verification`·등록 전 SMS 폴백) 전환 반영. rate limit·5분 만료·1회용·검증 제한은 기존 구현 그대로(변경 없음).
- REM-5: 대체문자 정책(코드 폴백 부재의 근거 — 주석 명시).
- NOTI-3: 등록 전 skipped 대신 "SMS 임시 경로"로 가입 무중단 유지(선례 참조).

## 알림톡 3작업(2026-11-19)

### A. ClientService 템플릿 키 정규화(결함 수정)

- `app/services/solapi/client_service.rb` L43: `@template_ids = (template_ids || {}).stringify_keys`
  - 사유: credentials `solapi.template_ids`를 심벌 키(`:phone_verification:`)로 작성해도 조회는 항상 문자열 키(`@template_ids[template_key.to_s]`)라 전부 MISSING_TEMPLATE로 떨어졌다. 주입분 포함 stringify_keys 정규화로 심벌·문자열 어느 YAML 스타일이든 동작(주석 기록).
- `send_alimtalk`·`template_ids` 접근자 로직 변경 없음 — 정규화만.

### B. PhoneVerifications::SendService — 알림톡 실패 시 SMS 폴백

- `app/services/phone_verifications/send_service.rb` `deliver!` 개편:
  - 키 존재 시 `send_alimtalk`를 `begin/rescue Solapi::ApiError`로 감싸고, 실패(템플릿 검수중·미승인 — 솔라피가 요청 자체를 거부·대체문자도 미발동) 시 `send_sms` 코드 폴백. 주석에 "검수중 가입 무중단" 사유 기록.
  - 승인 후 정상 발송에서는 폴백 미발동 → 이중발송 없음. 키 부재(등록 전)는 기존 SMS 경로 유지.
  - SMS 폴백마저 실패하면 기존 상위 rescue(`Solapi::ApiError` → PhoneVerification 행 destroy·rate limit 미소진)로 흡수 — 변경 없음.

### C. noti_tax_issued — 전자세금계산서 발행 완료 알림(TAX-2·신규)

- `app/services/tax_invoices/notify_issued_service.rb` 신규 — `Tickets::NotifyAnswerService` 선례 패턴(반환 :sent/:skipped/:failed·MessageLog P4 기록·NO_PHONE skip·ApiError → failed):
  - TEMPLATE_KEY `"noti_tax_issued"`·수신: invoice.user(U1)·recipient_role :user·digest=false.
  - 변수: `발행인명`(display_name)·`거래처명`(client.name)·`금액`(total_amount comma — ActiveSupport::NumberHelper)·`승인번호`(nts_send_key)·`url`(`badeuldon.kr` + app_invoice_path — LINK_HOST 선례).
  - MISSING_TEMPLATE → failed가 아닌 **skipped(NO_TEMPLATE)** — 키가 credentials에 아직 없는 등록 전 공백기가 정상 경로(NOTI-3 선례). 그 외 ApiError → failed 기록 후 종료(잡 무중단).
  - **멱등 키**: `MessageLog.where(invoice_id:, template_key: "noti_tax_issued", status: [:sent, :skipped, :failed]).exists?` — 폴링 재실행 대비 1회성 가드(pending 슬롯 유니크와 무관한 애플리케이션 수준 판정). 이미 확정 이력이 있으면 생성 전 `:skipped` 반환(로그 미생성).
  - PLAN-3 상한 밖(U1 이벤트 알림 — noti_* 계열과 동일 범주, 헤더 주석 명시).
- **폴링 Job 훅**: `app/jobs/tax_invoices/poll_state_job.rb` perform — `tax_invoice.update!(status: :issued)`(nts_send_key 캡처 update! 뒤) 직후 `TaxInvoices::NotifyIssuedService.call(tax_invoice:)` 1회. 잡은 서비스 호출만(발송 로직 직접 배제 — 규약).

### 자가 검증(rubocop 0 · zeitwerk OK · runner 스모크 3건 — 실호출 없음·트랜잭션 롤백)

1. 심벌/문자열 양쪽 template_ids로 `send_alimtalk` dry 경로 템플릿 조회 성공(MISSING_TEMPLATE 미발생, phone_verification·noti_tax_issued 모두).
2. 인증 서비스 폴백: stub 알림톡 `Solapi::ApiError` → `send_sms` 호출 단정·Result 성공.
3. NotifyIssuedService dry: sent(MessageLog 기록) / sent 이력 존재 시 재호출 `:skipped`·재발송 0회 / NO_PHONE skip.
