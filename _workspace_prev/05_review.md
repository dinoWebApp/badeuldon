# 05 리뷰 산출 — F-SALES 후속: 인증번호 알림톡 전환 (AUTH-9)

- 실행: 2026-11-19 · Standard 압축 위임(리뷰+테스트 통합 — Tester 프로필)
- **status: APPROVED** (BLOCKER 0 · CRITICAL 0 · WARNING 2)

## 대상

- `app/services/phone_verifications/send_service.rb` — TEMPLATE_KEY 상수·`deliver!` 분기(키 존재=알림톡 단독 / 부재=SMS 임시)
- `app/services/solapi/client_service.rb` — `template_ids` public 접근자

## 검증 결과 (지정 5항목)

| # | 검증점 | 판정 | 근거 |
|---|---|---|---|
| 1 | 키 판정 주입 가능성·실호출 차단 | 통과 | `initialize(phone:, client: Solapi::ClientService.new)` — 테스트는 `client:` 주입으로 stub 가능(FakeSolapiClient 확장 완료). 컨트롤러 경로는 `with_solapi_client` 헬퍼가 가로챔. 실호출 경로 없음 |
| 2 | 키 존재 시 SMS 미호출 단정 가능 구조 | 통과 | `deliver!`가 `if/else` 배타 분기 — alimtalk 경로에서 `send_sms` 도달 불가. 테스트로 단정(assert send_sms 미호출) |
| 3 | variables 키 "인증번호" 형식 | 통과 | 도메인은 순수 키 `"인증번호"` 전달, 래퍼 `wrap_variables`가 송신 직전 `#{인증번호}` 리터럴로 래핑(스펙 계층 단일 책임 — 기존 컨벤션). `phone_verification`은 LEGACY 4종 아님 → 키 변환 없이 순수 래핑 정합 |
| 4 | rate limit·행 destroy 로직 무변경 | 통과 | `rate_limited?`·`rescue Solapi::ApiError → verification&.destroy`·마스킹·정규화 전부 기존 그대로. diff상 발송 호출부만 교체 |
| 5 | template_ids 접근자 캡슐화 | 통과(W-1) | 읽기 전용 의도이나 내부 Hash 참조를 그대로 반환 — 아래 W-1 |

## Rule ID 정합

- **AUTH-9**: 알림톡 우선·등록 전 SMS 임시 경로 — PRD 갱신 문구와 일치. rate limit(1분 1회·1시간 3회) 발송 채널 무관 동일 적용 확인.
- **REM-5**: 대체문자는 솔라피 템플릿 대체문자 필드 담당 — 코드 폴백 부재가 정합. `deliver!` 주석에 확정 이력(2026-11-03) 명시.
- **NOTI-3 선례**: 템플릿 등록 공백기 무중단 경로 유지 — 동일 패턴 재사용 정합.
- **SEC-5**: 인증 발송은 스케줄 발송이 아니므로 멱등 슬롯 대상 아님. 기존 멱등성·rate limit 미소진(행 destroy) 보호 무변경.
- **P4**: 발송 기록(PhoneVerification 행) 유지 — 알림톡/SMS 어느 경로든 기록 동일.

## 이슈 목록

### WARNING

- **W-1** `Solapi::ClientService#template_ids` — 내부 `@template_ids` 참조를 그대로 반환(방어 복사·freeze 없음). 현재 호출부는 `key?` 조회만 하여 실질 영향 없음. 다만 credentials 맵이 인스턴스 간 공유되는 구조는 아니어서(클라이언트 인스턴스별 초기화) 위험도 낮음. 후속 시 `@template_ids.freeze` 또는 반환 시 dup 권장.
- **W-2** `deliver!`는 `@client.template_ids` 응답을 `respond_to?` 검증 없이 가정 — SendService에 주입되는 모든 client 대역은 `template_ids`를 구현해야 한다. 공식 테스트 대역(FakeSolapiClient)은 본 리뷰에서 확장했으므로 해소. 신규 대역 작성 시 주석으로 계약 명시됨(정보성).

### 코드 버그

- 없음 — 2파일 모두 기존 로직 보존·분기 구조 명료. 테스트 전수 통과(아래 07 보고서).

## 판정

APPROVED — 오케스트레이터의 Phase 6(수정 위임) 분기 불요. W-1은 후속 기술 부채 후보로 기록 권장.

---

# 추가 리뷰 — 알림톡 3작업 (2026-11-19, Tester·리뷰+테스트 통합)

> 이전 섹션(인증번호 알림톡 전환 — APPROVED)의 이력은 보존한다. 단, 직전 리뷰의 "REM-5 코드 폴백 부재 정합" 판정은 본 작업에서 **정책이 전환**된 것으로(솔라피가 미승인 템플릿 요청 자체를 거부하고 대체문자도 미발동함이 실측됨), 대체가 아니라 조건부 채택이다. 상태: **APPROVED**

## 대상

1. `app/services/solapi/client_service.rb` — template_ids stringify_keys 정규화
2. `app/services/phone_verifications/send_service.rb` — 알림톡 ApiError 시 SMS 폴백
3. `app/services/tax_invoices/notify_issued_service.rb`(신규) + `app/jobs/tax_invoices/poll_state_job.rb` issued 훅

## 검증 결과 (지정 5항목)

| # | 검증점 | 판정 | 근거 |
|---|---|---|---|
| 1 | 정규화가 주입분(stub 포함)에 적용·키 충돌 없음 | 통과 | `initialize`에서 `(template_ids \|\| {}).stringify_keys` — 기본값(credentials)·주입분 모두 경유. 심벌/문자열 혼합 해시 테스트로 단정(동일 키의 심벌·문자열 공존 시 뒤 값으로 수렴하는 것은 stringify_keys의 표준 동작이며 credentials 실형태는 키 중복 없음). 운영 credentials가 실제로 심벌 키임을 runner로 확인 — 수정 전에는 모든 알림톡이 MISSING_TEMPLATE로 떨어졌을 결함이 맞다 |
| 2 | 폴백이 알림톡 "성공" 후 발동하지 않는 구조(이중발송 방지) | 통과 | `deliver!`의 `rescue Solapi::ApiError` 블록이 send_alimtalk 예외 시에만 SMS를 실행 — 성공 반환 시 rescue 미진입. 테스트로 양방향 단정(성공→SMS 0 호출 / 실패→SMS 1 호출). SMS 폴백마저 실패하면 예외가 상위 rescue로 전파되어 기존 "행 destroy·rate limit 미소진" 경로 유지 — 별도 테스트로 회귀 확인 |
| 3 | NotifyIssued: 멱등·분기·P4·PLAN-3 밖 | 통과 | 멱등 키 = `MessageLog.where(invoice_id:, template_key:, status: [sent/skipped/failed]).exists?` — 폴링 재실행 재발송 차단(sent·failed 양쪽 이력 모두 테스트). NO_PHONE→skipped(호출 전 검사)·MISSING_TEMPLATE→skipped(NO_TEMPLATE)·그 외 ApiError→failed로 잡 무중단. 전 시도 pending→확정 MessageLog 기록(P4). `sequence_sent_count`는 debtor 한정 + SEQUENCE_TEMPLATE_KEYS 미포함 — PLAN-3 상한 집합 밖 확인(테스트 단정) |
| 4 | Job 훅 issued 전이 한정·잡은 서비스 호출만 | 통과 | `update!(status: :issued)` 블록 직후 1회 호출 — `elsif NTS_FAILED`(failed)·else(재시도) 분기에서는 호출부 미도달. c canceled 전이(5031)는 어느 확정 분기도 아니다 — 알림 호출 없음을 테스트로 단정. 잡은 `TaxInvoices::NotifyIssuedService.call(tax_invoice:)` 1줄 — 발송 로직·재시도는 서비스 소유(규약 §잡) |
| 5 | 폴링 Job retry 소진 경로 회귀 | 통과 | `retry_on(attempts: 10)` 소진 핸들러·`discard_on RecordNotFound`·진행 중 재큐 — 기존 테스트 전부 무변경 통과. 훅 추가는 issued 분기 내부라 소진·재시도 경로와 교차 없음 |

## 이슈 목록

### WARNING

- **W-3** `NotifyIssuedService` — `user.phone`을 원값 그대로 MessageLog에 스냅샷(하이픈 미제거). Tickets::NotifyAnswerService와 동일 선례라 정합하나, 실제 발송 시 래퍼 `normalize_phone`이 정규하므로 기록·발송 번호 표기가 미세하게 다르다. 기능 영향 없음 — 기록 일관성 원하면 스냅샷 정규화 후보.
- **W-4** 직전 리뷰 W-1(template_ids 참조 반환, freeze/dup 없음)은 미수정 상태 — 후속 기술 부채로 유지.

### 코드 버그

- 없음 — 3작업 모두 선례 패턴(NotifyAnswerService·NOTI-3 skip·SolapiStubbing) 정합 준수.

## 판정

**APPROVED** — 3작업 전부 규약·Rule ID(TAX-2·NOTI-1·AUTH-9·SEC-5·P4) 정합. 테스트 결과는 07_test_report.md 신규 섹션 참조.
