# T3 — 픽스처 날짜 폭탄 근본 해소 (03 구현)

소유 파일만 수정: `test/fixtures/invoices.yml` · `test/fixtures/payment_passes.yml` (앱 코드·테스트 코드 변경 0)

## 1. 행별 판별표 — invoices.yml `token_expires_at`

모든 행의 기존 고정값은 `due_on + 60일 end_of_day`(모델 발행 규칙)와 일치. 테스트는 전부
travel_to 과거 고정 시점(2026-10-12~18, KST)에서 판정하므로 상대 미래값 전환은 논리적으로 안전.
예외는 아래 "경계 판정" 행.

| 픽스처 행 | 기존 고정값 | 용도·사용 테스트(대표) | 판정 | 새 값 |
|:--|:--|:--|:--|:--|
| delta_issued | 2026-11-30 | 유효 링크 표본(최다 사용 — viewer 컨트롤러·시스템·reminders) **+ 만료 경계**: `ViewerControllerTest`가 travel_to("2026-12-01")로 만료 404 기대 | **보류** — 교차 의존(남은 우려 참조) | 고정 유지 + 보류 사유 주석 |
| delta_overdue | 2026-10-31 | **만료 경계**: `InvoiceTest` "reminders_dispatchable은 만료 링크를 제외한다" — travel_to("2026-10-31 23:00") 포함 / travel_to("2026-11-01") 제외 | **보류** — travel_to 고정이라 날짜 폭탄 아님(영구 재현), 경계 판정에 쓰이므로 규칙상 전환 금지 | 고정 유지 |
| delta_due_soon | 2026-12-14 | 유효 링크(무효 토큰 매트릭스에서는 void!로 폐기 — 만료일 미관여)·DASH 뱃지 | 상대 전환 | `<%= ACTIVE_TOKEN_EXPIRES_AT %>` |
| delta_viewed | 2026-12-19 | 유효 링크·열람 상태 | 상대 전환 | `<%= ACTIVE_TOKEN_EXPIRES_AT %>` |
| delta_promised | 2026-12-24 | 유효 링크·약속(매트릭스에서 regenerate_token! — 만료일 미관여) | 상대 전환 | `<%= ACTIVE_TOKEN_EXPIRES_AT %>` |
| delta_partially_paid | 2026-12-29 | 유효 링크·부분입금 | 상대 전환 | `<%= ACTIVE_TOKEN_EXPIRES_AT %>` |
| delta_paid | 2026-11-18(**이미 과거**) | paid 종결 — viewer에서는 위조 파라미터 id로만 사용(`viewer_promises_test`), 링크 유효성 미기대(오늘 기준 이미 만료 상태로 스위트 통과 실측) | 상대 전환(유효 기준 유지) | `<%= ACTIVE_TOKEN_EXPIRES_AT %>` |
| delta_voided | 2026-11-13(**이미 과거**) | token nil — 만료일 무의미·과거 만료 의미만 | 과거 상대 전환 | `<%= EXPIRED_TOKEN_EXPIRES_AT %>` (=10.days.ago.end_of_day) |

`ACTIVE_TOKEN_EXPIRES_AT = 30.days.from_now.end_of_day` — 파일 상단 ERB 상수로 정의(로드 시점 Rails TZ=KST 평가, TIME-1 오프셋 유지).

## 2. payment_passes.yml

| 행 | 기존 | 용도·사용 테스트 | 판정 | 새 값 |
|:--|:--|:--|:--|:--|
| delta_active_pass | 2026-12-30(폭탄 본체) | 6개 테스트 파일이 참조하나 2026-11-26 수정(C-1·X-1)으로 전부 "테스트 안에서 패스 직접 생성"으로 바뀌어 usable 만료일 의존 제거 — 남은 사용처는 존재·목록 렌더뿐(grep 실측, 만료일 단언 0) | 상대 전환 | `expires_at: <%= 90.days.from_now.end_of_day %>` |

양 파일 헤더에 "만료·유효 기간은 상대값이다 — 고정 날짜를 새로 넣지 않는다(test-date-time-bombs 패턴 3)" 추가.

## 3. 변환 전후 diff 요약

- invoices.yml: 헤더 주석 확장(패턴 3·보류 예외 명시) + ERB 상수 블록 신설 + `token_expires_at` 8행 중 6행 상대 전환(활성 5·과거 1), 2행 고정 보류(주석 포함).
- payment_passes.yml: 헤더 주석 확장(폭탄 선례 명시) + `expires_at` 상대 전환.

## 4. 테스트 실행 결과

지정 파일 6개, `DATABASE_URL=sqlite3:tmp/parallel/T3/test.sqlite3`:

```
test/models/invoice_test.rb  test/controllers/viewer_controller_test.rb
test/models/payment_pass_test.rb  test/controllers/app/billings_controller_test.rb
test/controllers/viewer_promises_test.rb  test/controllers/app/profiles_controller_test.rb
→ 139 runs, 838 assertions, 0 failures, 0 errors, 0 skips
```

- 1차 실행(3 failures): delta_issued를 상대 전환해 viewer 만료 경계 2건 실패 → 보류로 복귀해 해소. 나머지 1건(IPv6 45자, viewer_controller_test:147)은 T2가 소유하는 IP 헬퍼 변경 진행 중 재결합으로 판단 — 2차 실행에서는 자연 해소(T2 결과에 좌우됨, 본 태스크 범위 밖).

## 5. 보류 행과 사유

1. **delta_issued (2026-11-30)** — 근본 해소가 **테스트 수정 없이는 불가능한 교차 의존**:
   - `ViewerControllerTest`("만료된 토큰…404"·"무효 토큰 4종 본문 동일")는 travel_to("2026-12-01")로 이 픽스처의 만료를 **경계 판정**에 쓴다 → 만료일이 2026-12-01보다 과거여야 영구 통과.
   - 반면 시스템 테스트(`viewer_test`·`viewer_promise_test`·`viewer_refusal_test`)는 travel 없이 wall-clock에서 유효 링크로 쓴다 → 만료일이 영구 미래여야 함.
   - 단일 픽스처로 양립 불가. 현 고정값은 **2026-11-30까지는 통과, 2026-11-30 이후 시스템 테스트 3파일이 실패하는 진짜 폭탄** — 해소는 테스트 수정이 필요해 금지 규칙상 보류.
   - **권장 후속(3-S 또는 별도 위임)**: viewer 컨트롤러 테스트의 만료 경계를 `delta_overdue`(이미 과거 경계용으로 확정된 행)로 옮기거나, 테스트 내 `travel_to(invoices(:delta_issued).token_expires_at + 1.minute)` 상대화 → 그 뒤 delta_issued를 상대값으로 전환.
2. **delta_overdue (2026-10-31)** — `InvoiceTest`가 travel_to 고정 시점에서 양방향 경계 판정. travel_to는 오늘 날짜와 무관하므로 폭탄 아님 — 영구 고정 유지가 정답.

## 6. 남은 우려

- delta_issued 폭탄은 **2026-11-30에 터진다**(시스템 테스트 viewer 3파일). 본 배치 7-S 전체 테스트가 그 전에 실행된다면 통과하지만, 병합 전에 위 권장 후속을 반영할 것을 강력 권고.
- `test/fixtures/invoices.yml`의 `due_on`·`issued_at` 등 나머지 고정 날짜는 travel_to 기준일(2026-10-12) 앵커로 쓰이므로(패턴 2 교훈) 이번 범위에서 의도적으로 유지.
- viewer_controller_test의 IPv6 실패 1건은 T2 소유 — 본 태스크와 무관하나 최종 3-S에서 T2 결과 확인 필요.
- zeitwerk:check는 ERB 픽스처 문법을 검증하지 않아 미실행 — 대신 테스트 실행에서 픽스처 로드 오류 0으로 확인.

## 후속 — delta_issued 폭탄 해소·재발 방지 가드

### 변경 내용
1. **viewer_controller_test.rb** (후속 소유 허가분) — 만료 경계 travel_to 2곳을 픽스처 상대 시각으로 교체:
   - L258 주석 갱신("만료 2026-11-30 23:59:59" → "만료 = 만기일 + 60일 end_of_day (상대값)"), L260 `travel_to(Time.zone.parse("2026-12-01 09:00"))` → `travel_to(invoice.token_expires_at + 1.minute)`
   - L311 `travel_to(Time.zone.parse("2026-12-01 09:00"))` → `travel_to(expired.token_expires_at + 1.minute)`
   - 단언(404·VIEW-6 문구·상태 불변·본문 동일)은 불변.
2. **invoices.yml** — `delta_issued.token_expires_at` → `<%= ACTIVE_TOKEN_EXPIRES_AT %>`. "변환 보류" 4줄 주석 삭제, 한 줄 주석으로 교체("활성 링크 — 상대값, travel 없는 시스템 테스트가 유효 링크로 사용"). 헤더 예외 문장은 기존대로 delta_overdue만 고정 예외(정정 불요 — 이미 그렇게 기술돼 있었음).
3. **test/fixtures_no_future_date_test.rb 신설** — `test/fixtures/*.yml` 전수(동적 Dir): 줄 단위 ERB 블록(`<%…%>`, 여러 줄 헤더 포함) 추적 후 ERB 밖에서 `20\d{2}-\d{2}-\d{2}` 리터럴 추출 → `Date.parse` → `Date.current` 초과 시 파일·라인·날짜 나열로 실패. `# fixtures_no_future_date` 인라인 마커 줄은 제외(사유 명시 요건). wall-clock 실행, travel 없음.

### 조사 결과 — 픽스처 미래 고정 리터럴 전수(2026-11-26 기준)
- 전체 `test/fixtures/*.yml` ERB 블록 밖 날짜 리터럴 전수 조사 → **미래 고정 리터럴 0건**(invoices.yml 최대값 2026-11-11 due_on·payment_passes 0건). 먼 미래("사실상 무기한") 값도 없음 → **인라인 마커 예외 0건**, 가드는 즉시 통과 상태로 신설.

### 테스트 결과
- 단위 6파일(viewer_controller·viewer_refusal·viewer_promises·viewer_promises_rate_limit·invoice_test·가드): **100 runs, 604 assertions, 0 failures**.
- 시스템 4파일(viewer_test·viewer_refusal·viewer_promise·app_invoice_reminders): **14 runs, 98 assertions, 0 failures**.
- rubocop(viewer_controller_test·가드): **0 offenses**.

### 보고 — 소유 밖 잔존 의존 (3-S에서 처리 필요)
- **`test/controllers/app/invoices_controller_test.rb:651-668` "만료 임박·만료 표기는 유효기간 7일 전·경과로 분기한다 (SHARE-2)"** — delta_issued의 만료를 2026-11-30으로 **정확히 고정 의존**: travel_to("2026-11-24")에서 "만료 임박" 배지 + 리터럴 문구 `"2026-11-30까지 열람할 수 있습니다."` 단언, travel_to("2026-12-01")에서 "링크 만료" 단언. delta_issued가 상대값(30일 뒤)이 된 지금 **이 테스트 3단언은 실패한다** — 본 파일은 후속 소유 범위 밖(T2·T4·T5 아님 — 공유)이라 수정하지 않았다. 같은 방식의 상대화 필요: 만료 임박 경계를 `travel_to(invoice.token_expires_at - 6.days)` 등으로, 문구 단언은 `I18n/동적 조립` 또는 `token_expires_at.strftime` 보간으로 교체.
- 그 밖의 `2026-11-30`·`2026-12-01` grep 히트는 구독 current_period_end(PLAN)·약속일 파라미터·업그레이드 시나리오 등으로 delta_issued와 무관 — 영향 없음.

### 후속 2 — invoices_controller_test 잔존 의존 해소
- **변경**: `test/controllers/app/invoices_controller_test.rb` "만료 임박·만료 표기는 유효기간 7일 전·경과로 분기한다 (SHARE-2)"(651행) 고정 travel 3곳·리터럴 문구를 픽스처 상대 시각으로 교체 — `travel_to(token_expires_at - 6.days)`(임박)·`+ 1.minute`(경과)·`- 20.days`(정상). 문구 단언은 `expires_on.strftime('%Y-%m-%d')` 보간 — 뷰 헬퍼 `display_date`가 `%Y-%m-%d`(app/helpers/app/base_helper.rb:118)로 확인됨. 임박 판정은 헬퍼가 시각 단위(`expires_at > 7.days.from_now`, InvoicesHelper::LINK_EXPIRY_SOON_DAYS)라 `- 6.days`로 확실히 임박 구간 진입. 단언 의미 불변.
- **grep 잔존**: `2026-11-30|2026-12-01` 히트는 구독 current_period_end(PLAN)·약속일 파라미터·업그레이드 시나리오 등 delta_issued 무관 값과 가드 테스트의 역사 서술 주석(test/fixtures_no_future_date_test.rb:7-8 — 동작 의존 없음)뿐. 픽스처 yml 0건.
- **결과**: 지정 5세트(invoices_controller·viewer_controller·invoice_test·가드·test/services/invoices) **123 runs, 746 assertions, 0 failures** · rubocop(invoices_controller_test) 0 offenses.
- **완결**: delta_issued 날짜 폭탄(2026-11-30 발화 예정) 근본 해소 — 3개 테스트 파일 전부 픽스처 상대값 기준으로 전환, 재발 방지 가드 상시 가동.
