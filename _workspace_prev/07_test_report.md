# 07 테스트 실행 보고서 — F-SALES 후속: 인증번호 알림톡 전환 (AUTH-9)

- 실행: 2026-11-19 · Tester 프로필 (리뷰 통합 위임 — 리뷰 결과는 05_review.md 참조)

## 수치

| 항목 | 결과 |
|---|---|
| 전체 `bin/rails test` | **1,387 runs · 8,574 assertions · 0 failures · 0 errors · 0 skips** |
| `bin/rubocop` | 393 files inspected — **0 offenses** |
| 외부 API 실호출 | **0건** (FakeSolapiClient 주입 — 솔라피 stub만) |
| 코드 버그 | 0건 (테스트 오류 1건 — Python 인코딩 사고로 파일 손상, git 복구 후 Edit 도구로 재작성. 자체 해소) |

## 변경 파일

- `test/services/phone_verifications/send_service_test.rb` — 헤더 주석 전환 명세 갱신 + 신규 2건
- `test/test_helpers/fake_solapi_client.rb` — `template_ids:` 키워드 인자 확장(기본 `{}` = 키 부재 → 기존 테스트 전부 무변경 통과. SendService#deliver!가 template_ids를 요구하므로 컨트롤러 경로 대역에도 필수)

## 커버 시나리오 (신규·갱신)

1. **키 부재(템플릿 등록 전) → send_sms 호출·알림톡 미호출** — 기존 "정상 발송" 테스트에 `template_key` nil 단정 추가(기존 7건 전부 회귀 유지)
2. **키 존재 → send_alimtalk 단독** — `template_key: "phone_verification"`·`to` 정규화 번호·`variables == { "인증번호" => code }` 단정 + `send_sms` 미호출 단정
3. **알림톡 실패(Solapi::ApiError) → SMS 코드 폴백 없음** — 실패 안내·행 destroy(=rate limit 미소진)·즉시 재시도 허용까지 단정(REM-5 대체문자 위임 설계 반영)
4. 기존 유지: 형식 검증·1분 1회·1시간 3회·1시간 경과 복구·SMS 실패 시 행 destroy 회귀·마스킹 경계 — 전부 통과

## 판정

통과 — 회귀 0, 소스(테스트 외) 수정 없음, 커밋 없음.

---

# 추가 실행 — 알림톡 3작업 (2026-11-19, Tester·리뷰+테스트 통합)

## 수치

| 항목 | 결과 |
|---|---|
| 전체 `bin/rails test` | **1,399 runs · 8,643 assertions · 0 failures · 0 errors · 0 skips** (직전 1,387 → +13) |
| `bin/rubocop` | 395 files inspected — **0 offenses** |
| 외부 API 실호출 | **0건** (FakeSolapiClient 주입 + with_solapi_client — 솔라피 stub만) |
| 코드 버그 | 0건 (테스트 오류 4건 자체 수정 — FakeSolapiClient require 누락 1건·기대값 불일치 3건: phone 스냅샷 원값 선례 정합·error_message 형식·fake 원값 기록) |

## 변경 파일

- `test/services/tax_invoices/notify_issued_service_test.rb` — **신규 7건**
- `test/services/solapi/client_service_test.rb` — 신규 2건 (심벌 키 정규화·nil → 빈 Hash)
- `test/services/phone_verifications/send_service_test.rb` — 폴백 정책 전환 반영 2건 교체 + 헤더 주석 갱신
- `test/jobs/tax_invoices/poll_state_job_test.rb` — 신규 2건 (issued 훅 호출 1회·failed/canceled 경로 미호출)

## 커버 시나리오

1. **client_service_test**: 심벌+문자열 혼합 template_ids 주입 → send_alimtalk 템플릿 조회 성공(templateId 단정)·접근자 문자열 키 Hash·`template_ids: nil` → `{}` 정규 + MISSING_TEMPLATE fail-fast
2. **send_service_test**: 알림톡 실패(ApiError) → SMS 폴백 1회 호출(본문 코드 포함)·성공 Result / **알림톡 성공 → SMS 미호출**(기존 단정 유지) / 폴백 SMS마저 실패 → 행 destroy·rate limit 미소진·즉시 재시도 허용
3. **notify_issued_service_test(신규)**: sent(변수 5종 — 발행인명/거래처명/금액 콤마/승인번호/url + provider_message_id·phone 스냅샷)·NO_PHONE skip(솔라피 호출 0)·MISSING_TEMPLATE → skipped(NO_TEMPLATE)·ApiError → failed·**멱등 — sent 이력 시 재호출 :skipped·재발송·신규 로그 0(TaxInvoice reload 후)**·failed 이력도 확정으로 간주(무한 재시도 루프 방지)·PLAN-3 집합 밖 단정
4. **poll_state_job_test**: issued 전이 확정 시 NotifyIssuedService 1회 호출(확정 후 재적재본 인자 단정, 서비스 스파이 교체)·비-issued 경로(5031 재시도·NTS5 failed 확정)에서 미호출 / 기존 6건(issued 확정·failed·진행 중 재큐·C-4 소진·종결 no-op·discard) 전부 회귀 통과

## 판정

통과 — 회귀 0, 소스(테스트 외) 수정 없음, 커밋 없음. 리뷰 판정은 05_review.md 신규 섹션(APPROVED) 참조.
