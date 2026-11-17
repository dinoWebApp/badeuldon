# 03_implementation — Phase 6 수정 (05_review CHANGES_REQUESTED B1·C3·W7) (2026-11-16 · Developer)

**status: DONE** — 리뷰 지적 사항만 최소 수정. 테스트·마이그레이션·routes·커밋 없음.

## B-1 (BLOCKER) — 입금 성공 경로 NoMethodError

- `app/controllers/app/payments_controller.rb:11-19` — `create`가 서비스 인스턴스를 `@record_service`로 유지하고 `@payment = @record_service.call`로 변경.
- 동 파일 `success_notice`(L44-53)·`over_notice`(L56-58) — `@payment.post_paid_record?`·`@payment.over_amount` → `@record_service.*` 교체. 서비스 계약(record_service.rb:38-45 공개 리더)은 무변경.
- 뷰 참조 확인: grep 결과 두 리더의 참조는 컨트롤러뿐(뷰·로케일 0건) — 추가 정합 불요.
- 422 경로의 `@payment = e.payment`(Payment 인스턴스)는 기존 그대로 — 영향 없음.

## C-1·C-2 (CRITICAL) — dunning_active? 상태 한정 (1줄 판정점)

- `app/models/subscription.rb:59-65` — `def dunning_active? = active? && (dunning_stage.positive? || next_retry_at.present?)`. W-7(nil 비교)도 이 판정점에서 해소.

**C-1 흐름 닫힘 추적**: 갱신 실패(stage=1·next_retry_at=D+1) → 사용자 cancel!(status: cancelled) → D+1 `DunningRetryJob#perform` 첫 가드 `!subscription.dunning_active?`(L20)가 true → 즉시 종료 → 재차감 없음. `retry_charge`(upgrade_service.rb:112-122)로 직접 진입해도 첫 분기 `dunning_active?` false → elsif도 false → no-op. **무단 차감 경로 소멸.**

**C-2 흐름 닫힘 추적**: 3회 소진 `advance_dunning!`가 stage=3·next_retry_at=nil·cancel! → 다음 일간 `SubscriptionRenewalJob`(due_subscriptions는 cancelled 포함) → `renew`: 첫 분기 `dunning_active?` **false**(cancelled) → elsif active+빌링키 false → `elsif active? || renewal_due?(cancelled+주기 종료=true)` → **`expire!` 도달 복원** → Free 강등·빌링키 폐기. cancelled+plus 영구 잔존 소멸.

## C-3 (CRITICAL) — 토글 저장 실패 500

- `app/controllers/app/notification_settings_controller.rb:10-13` — `render :update` → `head :unprocessable_entity`(리뷰 권장안 ① — 토글 폼 1개 부분 갱신 경로에 충분).

## WARNING 반영 내역

| 항목 | 처리 |
|:---|:---|
| W-5 | `payments_controller.rb:58` 플래시 문구 "청구액을" → "남은 잔액을" 정정 |
| W-4 | `.gitignore`에 `config/locales/*.bak` 추가 |
| W-6 | `app/models/payment.rb:1-7` — 구 결정 #3(초과 차단) 문언을 Q22(기록·감사 비고)로 갱신. `app/services/audit_logs/record_service.rb:2-4` — action 목록에 `payment_over_recorded` 추가 |
| W-3 | `app/controllers/admin/orders_controller.rb:8-9` — `includes(:user)` → `includes(user: :subscription)`로 해소(구조 간단 — 적용). 뷰의 `order.user.subscription`(index.html.erb:78)이 로딩 대상 |
| W-7 | 코드 1줄 방어 적용: `dunning_retry_job.rb:22`·`upgrade_service.rb:114-115` 비교에 `next_retry_at.present?` 가드 추가 — nil이면 각각 retry_charge 위임/즉시 차감 경로로 흡수(NoMethodError 불가) |
| W-1 | **미반영**(스키마 과제 — message_logs 부분 유니크 인덱스. 마이그레이션 금지 제약. 3-S 후속 런 과제로 인계) |
| W-2 | **미반영**(PRD 문언 결정 필요 — 오케스트레이터 판정 사항. Phase 7 인계) |

## 부대 정합

- `app/jobs/subscription_renewal_job.rb:3-4` 헤더 주석 — 리뷰 C-2 권장대로 "즉시 만료 강등(dunning 미실시)" → PLAN-5 확정 문언(dunning 스케줄·3회 소진 cancelled)으로 갱신. 로직 무변경.

## 자가 검증

- 수정 9파일 `bin/rubocop` — 0 offenses
- `bin/rails zeitwerk:check` — 통과
- `bin/rails runner` 부분 스모크 — cancelled+stage3/nil → dunning_active? false(C-2), active+stage1 → true(C-1), RecordService 리더 응답(B-1) 확인 OK
- 전체 테스트·부트는 Phase 7·8 영역 — 미실행(제약 준수)

## Phase 7 분기 — BUG-1~4 수정 (2026-11-16 · Developer)

07_test_report.md의 코드 버그 4건 최소 수정 + 파생 버그 2건(재발견) + 테스트 오류 2건(최소 수정). 게이트 전부 통과.

### 지시 버그 4건

| 버그 | 파일 | 수정 내역 |
|:---|:---|:---|
| BUG-1 | `app/models/user.rb` | `tax_invoice_ready?`를 private 구간(172행 부근)에서 `next_remind_slot` 직전 public 영역으로 이동(파일 내 배치만 — 로직 불변) |
| BUG-2 | `app/services/payments/record_service.rb` | `call`의 `payment` 지역변수를 인스턴스 변수 `@payment`로 승격 — rescue에서 nil Payment로 InvalidPayment 생성하는 결함 제거. `record_payment!`도 `@payment`로 할당해 `save!` 예외 시에도 errors 보유 보장 |
| BUG-3 | `app/helpers/app/profiles_helper.rb` + `app/views/app/profiles/edit.html.erb:126` | `remind_wday_options` 헬퍼 메서드 신설(`bank_options` 선례), 뷰는 상수 직접 참조 → 메서드 호출로 변경 |
| BUG-4 | `app/services/noti/weekly_digest_service.rb` | `variables`를 `@variables ||= build_variables` 인스턴스 메서드로 승격 — `skip_no_template!`·`failed` 분기의 스코프 밖 지역변수 참조(NameError) 제거 |

### 재발견 파생 버그 2건 (테스트 게이트 실행 중 확인 — 최소 수정)

| 위치 | 결함 | 수정 |
|:---|:---|:---|
| `app/controllers/app/profiles_controller.rb:30` (`remind_profile_params`) | 파라미터에 `remind_allowed_wdays` 키가 없어도(기존 6필드 폼) `""`로 덮어써 "월~금 최소 1일" 검증에 항상 걸림 → 프로필 저장 전 경로 422(profiles 4건 + clients complete_profile_of 경유 6건 실패의 근원) | `attrs.key?(:remind_allowed_wdays)` 가드 — 키가 있을 때만 csv 변환·할당 |
| `app/services/payments/record_service.rb` (`record_payment!`) | `@amount.to_i` 선징제가 Payment `only_integer` 검증을 무력화 — "1.5"→1 절삭 후 303 통과(금액 무결성) | 금액은 원문자열을 그대로 Payment 검증에 통과. 원클릭(nil)+잔액 0(이중 클릭)은 `rejected_payment("입금 금액을 입력해 주세요")` base 오류로 422 흡수(Q22 경계). `over_amount`는 저장 성공 후 캐스팅된 정수로 산정 |

### 테스트 자체 오류 2건 (최소 수정 — 근거 기록)

| 파일 | 오류 | 수정 |
|:---|:---|:---|
| `test/test_helpers/fake_solapi_client.rb` + `test/services/noti/weekly_digest_test.rb` 2건 | 테스트가 `assert_empty fake.calls`로 "성공 호출 0건"을 단정하나 FakeSolapiClient는 raise 전에 호출을 기록하는 것이 기존 컨벤션(no_template_skip_test가 실패 호출을 `calls.count == 1`로 단정) — 구조적으로 불가능한 기대 | 헬퍼에 `successful_calls`(예외 미발생 호출만 기록) 추가, 테스트 2건의 단정을 `successful_calls`로 변경 |
| `test/services/subscriptions/dunning_retry_test.rb:237` (ADMIN-4 뷰) | 시간 폭탄 — `admin_login(at: 11:07:41)` 후 GET이 실제 실행 시각에 수행되면 IDLE_TTL(2시간) 비활동 만료로 303(13:07 KST 이후 실행 시 항상 실패. 11:47 케이스는 우연히 통과) | GET·단정을 `travel_to(11-16 12:00)`로 감싸 실행 시각 비의존화 |

### 게이트 결과

| 게이트 | 결과 |
|:---|:---|
| `bin/rails test` 전체 | **1,241 runs / 7,047 assertions / 0 failures / 0 errors / 0 skips** (Tester 시점 1,241/9 failures/58 errors → 녹색 수렴) |
| `bin/rubocop` | 354 files inspected, no offenses |
| `bin/rails zeitwerk:check` | 통과 |
| BUG-4 실동작 (`bin/rails runner` RAILS_ENV=development) | `Noti::WeeklyDigestService.new(user:).call` → `:skipped` 반환, MessageLog `status=skipped / error_code=NO_TEMPLATE / variables 기록 / phone 기록` 확인 — 실솔라피 호출 없음(credentials 부재 fail-fast — REM-10 준수) |

### 제약 준수

- 버그 수정 외 코드 변경 없음(위 표의 6파일 + 테스트 2파일만 접촉) · git 커밋 없음 · PRD/AGENTS/01·02·05 무수정 · 외부 API 실호출 0건
