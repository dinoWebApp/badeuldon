# 07_test_report — 세금계산서 발급 자격 차단(TAX-3) + 운영 준비 게이트(TAX-4)

2026-11-24 · Tester · 대상: 미커밋 구현(app/config 12파일 + 신설 2파일) · 앱 코드는 수정하지 않았다.

## 결과 요약

| 게이트 | 결과 |
|:---|:---|
| 세금계산서 관련 테스트(13파일 + 신규 5파일) | **158 runs · 863 assertions · 0 failures · 0 errors** |
| 전체 `bin/rails test` | **1,529 runs · 9,561 assertions · 0 failures · 0 errors · 0 skips** (이전 기준선 1,477 → +52건) |
| 전체 `bin/rails test:system` | **13 runs · 117 assertions · 0 failures · 0 errors** (1회 통과 — 알려진 로그인 경합 플레이크 미발생) |
| `bin/rubocop test/` | 195 files inspected, **no offenses** |
| 코드 버그 | **0건** — 실패·에러 전무, 원인 분류 대상 없음 |

시작점이었던 기존 실패(꺼짐 기본값 상태 19건 + 켜짐 1건)는 모두 해소됐다. 지시서 기록(꺼짐 20건 = 12+8)과 실측(19건 = 11+8)에 1건 차이가 있었으나 전부 같은 원인(리다이렉트 대상이 `/app`으로 바뀐 것)이고 갱신 후 전부 통과라 영향 없다.

## 구조 — 테스트 환경의 스위치 기본 켬

- **신규** `test/test_helpers/tax_invoice_feature_helper.rb` — `with_tax_invoice_feature(enabled)` 블록 헬퍼. `ensure`로 원래 값 복원.
- **수정** `test/test_helper.rb` — `ActiveSupport::TestCase` setup에서 `config.x.tax_invoice_enabled = true`(기존 세금계산서 테스트의 전제 보전), teardown에서 부팅 값 복원(테스트 간 누수 방지).
- 꺼짐이 필요한 케이스는 전부 `with_tax_invoice_feature(false)` 블록으로 격리했다. fail-closed **파싱** 자체는 초기자를 `load`하는 단위 테스트(`test/config/tax_invoice_initializer_test.rb`)가 담당 — 부팅 9회 없이 ENV 9값을 검증한다.

## 추가·변경한 테스트 파일

| 파일 | 구분 | 내용 |
|:---|:---|:---|
| `test/test_helpers/tax_invoice_feature_helper.rb` | 신규 | 토글 블록 헬퍼 |
| `test/test_helper.rb` | 수정 | 기본 켬 setup/teardown + 헬퍼 include |
| `test/models/tax_invoice_test.rb` | 신규 8건 | `feature_enabled?` 단일 판정점(ENV 비의존)·`FEATURE_DISABLED_NOTICE` 상수·`User#tax_invoice_eligible?` 3값·문구 2종(TAX-3 단일 출처) |
| `test/config/tax_invoice_initializer_test.rb` | 신규 3건 | ENV 9값 fail-closed 파싱(`"true"`만 켜짐; 미설정·`"false"`·`TRUE`·`True`·`1`·`yes`·`" true"`·`"true "` 꺼짐)·로드 후 판정점 확인 |
| `test/controllers/app/tax_invoice_gate_test.rb` | 신규 22건 | TAX-4 꺼짐 전체 + 패널 우선순위 매트릭스 9건 + 사이드바 순서 |
| `test/controllers/app/tax_invoice_eligibility_test.rb` | 신규 12건 | TAX-3 정상/경계/예외(간이과세 7건·면세 1건 통합) |
| `test/controllers/app/tax_invoices_controller_test.rb` | 수정 1건 | 가드 리다이렉트 대상을 `new` → 청구서 상세로 갱신(리뷰 C-1 반영 — 테스트 의도·규칙은 유지) + 파일 헤더에 켜짐 전제 명시 |
| `test/controllers/app/tax_invoice_settings_controller_test.rb` | 수정 0건 | 파일 헤더에 켜짐 전제 명시만(기본 켬으로 전부 통과) |
| `test/services/tax_invoices/create_order_service_test.rb` | +2건 | `IneligibleUser`(간이·면세) — message 단일 출처 일치·주문 0건 |
| `test/services/tax_invoices/issue_service_test.rb` | +3건 | `GuardFailed`(간이·면세) 기록 0건·SOAP 미호출 + 가드 순서(자격 > 설정) |
| `test/controllers/webhooks/tax_invoice_settle_test.rb` | +2건 | TAX-3 ④ 웹훅 경로(결제 성립·발행 차단) + TAX-4 스위치 무관성(settle은 꺼짐에도 정상 발행) |

신규 테스트 총 **52건** = 전체 증분(+52)과 일치. 소유권 제한 3파일(`Gemfile.lock`·`test/application_system_test_case.rb`·`test/test_helpers/capybara_chrome_compat.rb`)은 미접촉(git status 대조). 외부 API 실호출 0건 — 바로빌은 기존 `with_baro_bill_client(FakeBaroBillClient.new)` 방식, 포트원은 기존 `PortOneStubbing`을 그대로 사용했다.

## Rule ID별 시나리오 매트릭스

### TAX-3 — 발급 자격(Q25 — 발행만 차단·영구)

| 구분 | 시나리오 | 검증 위치 |
|:---|:---|:---|
| 정상(general) | `new` 200 + "수수료 결제하고 발행 요청" 버튼 | eligibility |
| 정상(general) | 패널 ready — 발행 링크·300원 고지, 안내 문구 없음 | gate 매트릭스 ready |
| 정상(general) | 설정 화면 발급 불가 안내 없음 + 인증서 완료 안내 "이제 … 발행할 수 있습니다" | eligibility |
| 경계 | 과세 선택지 3종 유지 + 저장 성공(바로빌 스텁 — `barobill_id` 채번·tax_type 반영) | eligibility |
| 경계 | 기존 발행 내역 조회(기록 분기)·취소 성공 — 자격 무관 허용 | eligibility |
| 예외(간이·면세) | ① 패널 "발급 불가" + 문구 + 발행 링크 없음 | eligibility·gate |
| 예외 | ② `new` → **청구서 상세** 리다이렉트 + 안내 플래시(리뷰 C-1) | eligibility(간이·면세) |
| 예외 | ② `create` → 청구서 상세 + 주문 0건 | eligibility(간이·면세) |
| 예외 | ③ `CreateOrderService::IneligibleUser` — message == 단일 출처 문구, 주문 미생성 | create_order_service(간이·면세) |
| 예외 | ④ `IssueService::GuardFailed` — 기록 0건·SOAP 호출 0건 | issue_service(간이·면세) |
| 예외 | ④ 가드 순서 — 자격 가드가 설정 가드보다 앞선다 | issue_service |
| 예외 | pending 주문 `show` — 결제 버튼·`portone-payment` 위젯 없음(리뷰 C-2) | eligibility(간이·면세) |
| 예외 | 설정 2단계(인증서 등록) 숨김 + 안내 박스(리뷰 W-3) | eligibility |
| 예외 | 저장 성공 플래시에 "다음으로 공동인증서" 없음 | eligibility |
| 예외 | 인증서 확인 성공 안내에 발행 가능 문언 없음 | eligibility |

### TAX-4 — 운영 준비 게이트(Q26 — 기본 꺼짐·fail-closed)

| 구분 | 시나리오 | 검증 위치 |
|:---|:---|:---|
| 스위치 | ENV 9값 파싱 — `"true"`만 켜짐, 나머지 전부 꺼짐 | initializer |
| 스위치 | 모델은 config만 읽는다 — ENV true여도 config 꺼짐이면 꺼짐 | models/tax_invoice_test |
| 꺼짐① | 사이드바 "전자세금계산서" 비노출 | gate |
| 꺼짐② | 패널 "준비 중" — 상수 문구 + 보조 문장, 발행 링크 없음 | gate |
| 꺼짐② | 기존 발행 기록 있는 청구는 기록 표시 유지(승인번호·주문 링크) | gate |
| 꺼짐③ | `new`·`create` → `/app` 리다이렉트 + 상수 플래시 + 주문 미생성 | gate 2건 |
| 꺼짐③ | 설정 4액션(show·update·register_certificate·confirm_certificate) → `/app` + 상수 플래시, 저장 미수행 | gate 3건 |
| 꺼짐④ | paid 주문 `show` 200(발행 상태 표시) | gate |
| 꺼짐④ | paid 발행 `cancel` 성공(canceled 전이) | gate |
| 꺼짐④ | pending 주문 `show` — 200 유지 + 결제 위젯 미렌더(리뷰 C-2) | gate |
| 회귀 | 소유권 격리 — 꺼짐 상태에서도 타인 주문 show·cancel 404 | gate |
| 켜짐 | 메뉴 순서 회귀 — "추심 안내" < "전자세금계산서" < "공지" | gate |
| 켜짐 | 기존 세금계산서 테스트 전수 통과 + settle 경로는 스위치와 무관하게 발행 수행 | 13파일 158 runs + settle |
| 매트릭스 | 기존 기록 > paid_pending·꺼짐·자격 없음(복합 조건 1건) | gate |
| 매트릭스 | paid_pending > 꺼짐(리뷰 W-1 — 주문 링크 보전·재결제 버튼 없음) | gate |
| 매트릭스 | paid_pending > 자격 없음(W-1) | gate |
| 매트릭스 | 꺼짐 > 자격 없음 / 꺼짐 > settings_missing / 자격 없음 > settings_missing / settings_missing > client_missing / client_missing > ready / ready | gate 6건 |

### 문구 단일 출처·기타 회귀

- **TAX-3 문구**: 패널·`new`/`create` 플래시·설정 화면·저장 플래시·인증서 안내·`IneligibleUser`/`GuardFailed` message가 전부 `User#tax_invoice_ineligibility_notice`와 **exact-equality**(el.(assert_equal)) 검증 — 12건.
- **TAX-4 문구**: 플래시 7액션·패널·pending 주문 차단이 전부 `TaxInvoice::FEATURE_DISABLED_NOTICE`와 일치.
- **noindex**: 기존 "설정·발행 화면 noindex"(SURF-3) 켜짐 상태 통과. **인증서 완료 안내 조건화**: 정상/예외 양방향 검증. **콜백 착지·웹훅 멱등**: 기존 7건 통과 + 스위치 무관 1건 신설.
- `test/controllers/app/dashboards_controller_test.rb`(네비 12개 단정) — 기본 켬 상태에서 기존 단정 그대로 통과(변경 불요 확인).

## 실행 결과 상세

| 명령 | 결과 |
|:---|:---|
| `bin/rails test test/controllers/app/tax_invoices*_test.rb tax_invoice_gate_test.rb tax_invoice_eligibility_test.rb webhooks/tax_invoice_settle_test.rb webhooks/portone_controller_test.rb test/services/tax_invoices/ fulfill_tax_invoice_service_test.rb test/jobs/tax_invoices/ test/models/tax_invoice_test.rb test/config/tax_invoice_initializer_test.rb dashboards_controller_test.rb` | 158 runs · 863 assertions · 0 failures · 0 errors |
| `bin/rails test` (전체) | 1,529 runs · 9,561 assertions · **0 failures · 0 errors · 0 skips** |
| `bin/rails test:system` (전체) | 13 runs · 117 assertions · **0 failures · 0 errors** |
| `bin/rubocop test/` | 195 files · no offenses |

참고 — 시작 시점에 테스트 DB stale로 fixture FK 검증 오류(28 errors)가 발생해 `bin/rails db:test:prepare`로 재구성했다. 코드·테스트와 무관한 환경 문제였다.

## 발견한 코드 버그

**0건.** 리뷰 C-1(`new` 차단)·C-2(pending 주문 결제 진입)·W-1(우선순위)·W-2(concern·상수)·W-3(설정 화면)·W-4(문구) 수정분이 모두 의도대로 동작함을 테스트로 확인했다. 별도 Developer 위임 불요.

## 남긴 리스크

1. **시스템 테스트 미포함** — TAX-3/4의 브라우저 E2E는 신설하지 않았다(기존에도 세금계산서 시스템 테스트 부재). 컨트롤러 HTTP 통합 테스트가 응답·리다이렉트·위젯 미렌더까지 검증하므로 커버리지 격차는 작으나, 인앱 실기 QA 때 스위치 켜짐 상태의 발행 플로우 육안 확인이 필요하다.
2. **이미 열린 결제 위젯은 서버가 못 막는다** — pending 주문 `show`의 체크아웃 미렌더(리뷰 C-2)는 렌더 계층 방어다. SDK 직접 호출 경로의 최종 방어선은 운영 노트(배포 시 `Order.pending.tax_invoices` 실패 처리 절차)다 — Phase 9(AGENTS.md 운영 노트 기록)에서 반영 필요.
3. **테스트 기본 켬은 config 조작 방식** — ENV 파싱과 분리돼 있고, 실부팅 fail-closed는 초기자 `load` 테스트가 담당한다. 운영에서는 deploy.yml env의 `"true"` 문자열 정확성이 여전히 사람 손에 달려 있다(오타 시 꺼짐 — 안전한 쪽).
4. **과세 유형 기본값 일반과세** — 간이과세자가 기본값을 그대로 두면 자격 판정을 통과한다(02_prd_update 후속 과제 — PRD 설계 영역, 테스트로 막을 수 없는 구조적 리스크).
5. **켜짐+포인트 미충전** 조합("결제만 되고 발행 실패")은 스위치 켜기 전제(운영 준비 완료)로 흡수된다 — Q26 운영 규율 영역.
