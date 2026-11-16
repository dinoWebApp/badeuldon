# 07_test_report — TAX-1/2 전자세금계산서 발행 (2026-11-16, Tester)

## Status: 코드 버그 1건 발견(Phase 6 분기 필요) — 신규 테스트 80건 전부 통과

- 신규 테스트: **80 runs · 394 assertions · 0 failures · 0 errors** (8파일 + 테스트 헬퍼 2건)
- 전체 스위트: **1,183 runs · 6,637 assertions · 2 failures · 11 errors** — 실패·에러 13건 전부가
  아래 **코드 버그 B-1 단일 원인**(기존 스위트 회귀). 그 외 회귀 0.
- RuboCop 전체 342파일 **0 offense** · zeitwerk 통과. 외부 API(바로빌·포트원·솔라피) 실호출 0
  (FakeBaroBillClient·BaroBillStubbing·FakePortOneClient·PortOneStubbing·FakeSolapiClient 주입).

## 코드 버그 발견 (Developer 수정 대상 — Tester 미수정)

### B-1 — 청구 상세 부분 렌더의 컨트롤러 상대 경로로 422 재렌더 전면 파탄 (BLOCKER급 회귀)

- **파일**: `app/views/app/invoices/show.html.erb:36` — `<%= render "tax_invoice_panel" %>`
- **재현**: `App::PaymentsController#create`가 422로 `invoices/show`를 재렌더하는 순간 부분
  탐색이 `app/payments/_tax_invoice_panel`부터 이뤄져 `ActionView::Template::Error: Missing
  partial app/payments/_tax_invoice_panel`로 크래시한다. App::PromisesController 동일.
- **파급(전체 스위트 13건 실패·에러 전부)**:
  - `test/controllers/app/payments_controller_test.rb` 9건 에러 (INV-4 재등록 422 재렌더 계열)
  - `test/controllers/app/promises_controller_test.rb` 2건 에러
  - `test/controllers/app/payments_reminders_test.rb` 1건 에러
  - `test/integration/payments_concurrency_test.rb` 2건 실패 — 동시 요청 1건이 422 재렌더
    크래시로 응답 status 0(`Expected [303, 422], Actual [0, 303]`)
- **수정 제안(1줄)**: `render "invoices/tax_invoice_panel"` (F-REM 이후 렌더는 파셜 선두에
  컨트롤러 경로를 명시하는 선례 — `invoices/show`의 나머지 파셜 렌더도 동일 스타일 확인).
  이번 TAX 런 working tree에서 신설된 렌더 1줄이 원인(`git diff` 확인) — 직전 커밋에서는
  전체 스위트 통과 상태.

### 테스트 오류 1건 자체 수정 (테스트 날짜 부패 — TIME-1 위반, 소스 무관)

- `test/controllers/app/invoices_reminders_test.rb:150` — "만기 도과 + 미래 약속" 수동 발송
  테스트가 실제 오늘(2026-11-16)에 의존해 `promised_on: 2026-11-11` 생성이 약속 검증(오늘
  이후)으로 거부됨(2026-11-11 이전 작성일 기준 통과하던 날짜 부패). 미래일(2026-12-11)로
  생성 후 기존의 `update_column` 소급(11-10)은 유지 — 시나리오 의도 불변. 해당 파일 18건 재통과.

## 실행 결과 (파일별)

| 파일 | runs | 결과 |
|---|---|---|
| test/services/tax_invoices/issue_service_test.rb | 11 | 통과 |
| test/services/tax_invoices/cancel_service_test.rb | 5 | 통과 |
| test/services/tax_invoices/register_corp_service_test.rb | 7 | 통과 |
| test/services/tax_invoices/create_order_service_test.rb | 3 | 통과 |
| test/services/orders/fulfill_tax_invoice_service_test.rb | 5 | 통과 |
| test/jobs/tax_invoices/poll_state_job_test.rb | 6 | 통과 |
| test/services/baro_bill/client_service_test.rb | 8 | 통과 |
| test/controllers/app/tax_invoices_controller_test.rb | 19 | 통과 |
| test/controllers/app/tax_invoice_settings_controller_test.rb | 9 | 통과 |
| test/controllers/app/tax_invoice_callback_test.rb | 3 | 통과 |
| test/controllers/webhooks/tax_invoice_settle_test.rb | 4 | 통과 |
| (신규 헬퍼) test/test_helpers/fake_baro_bill_client.rb · baro_bill_stubbing.rb | — | 실호출 방어선 |

## Tester 중점 11항목 커버 상태 (05_review §Tester 중점 지시)

| # | 항목 | 커버 | 근거 테스트 |
|---|---|---|---|
| 1 | 콜백 착지 C-1 회귀 | ✅ | tax_invoice_callback_test — tax_invoice 주문 → 발행 주문 show 착지·세금계산서 문구(패스 문구 부정 단정). legal_doc·pass 기존 착지·문구 회귀 방지 2건 |
| 2 | 이중 결제 차단 C-2 | ✅ | tax_invoices_controller_test C-2(paid 주문 존재 create 차단·기존 주문 안내·주문 수 불변) + 패널 `:paid_pending` 분기(재결제 버튼 미노출) + fulfill 테스트의 GuardFailed 흡수(paid·레코드 미생성 상태 도달 가능성 재현) |
| 3 | 부가세 포함 Σ품목 C-3 | ✅ | issue_service_test C-3 3건 — 별건 다중 행·포함 다중 행·포함 단일 행 경계. Σ품목.Amount=AmountTotal·Σ품목.Tax=TaxTotal·정수 연산(마지막 행 잔액 조정) 전부 정확 일치 확인(**수정 후 정상 동작 실증**) |
| 4 | 폴링 상태 머신 C-4 | ✅ | poll_state_job_test — 3014+NTS4→issued(승인번호 캡처)·NTS5→failed·진행 중 재큐·**10회 소진→failed 확정**(retry_on 소진 분기 직접 구동)·종결 상태 no-op·RecordNotFound discard |
| 5 | 웹훅 중복 settle | ✅ | tax_invoice_settle_test — Transaction.Paid 2회 → TaxInvoice 1건·PollStateJob 인계 1회·패스 발급 없음(product=collection_pass 함정 확인) |
| 6 | 콜백·웹훅 경합 | ✅ | fulfill_tax_invoice_service_test 중복 settle(SEC-5) — paid 전환 1회·발행 1회·metadata 병합(invoice_id 보존 — B-1 회귀 단정 포함) |
| 7 | 가드 사얄 5종 | ✅ | IssueService 5종(설정 미완료·사업자번호 없음·미결제·중복 요청·paid 아님) 각각 안내 문구 단정 + 컨트롤러 create 가드 3종 안내·303 수렴 |
| 8 | 취소 경계 | ✅ | cancel_service_test + cancel 컨트롤러 — pending 취소 성공(5031 기록)·SOAP 일시 오류 재시도 문구(W-5)·음수 코드 정정 안내(W-5)·재취소 차단·**canceled 후 재발행 차단(1건 1발행)** |
| 9 | 소유권 격리 | ✅ | 타인 tax_invoice 주문 show/cancel 404·타인 청구 new 차단 |
| 10 | 설정 경계 | ✅ | settings 테스트 — -32000 흡수·9자리 corp_num 외부 호출 전 422(W-3·클라이언트 미호출 단정)·조작 tax_type 500 아님 422(W-3)·CheckCERTIsValid false 시 마킹 미변경·true 시에만 마킹 |
| 11 | SURF-3 | ✅ | 설정·미리보기 화면 noindex 메타 단정(/app prefix 정책 경유) |

그 외: BaroBill::ClientService 단위(savon_factory 대역 — 오류코드 -32000·SOAP 코드 정규화·TESTBED/RELEASE wsdl 전환·CORPSTATE/TI 구조체 파싱·CERT URL), CreateOrderService(300원 Q21·pending 재사용 멱등·청구별 분리), 레코드 유실 회귀(FulfillTaxInvoiceService metadata 병합).

## 참고 관찰 (버그 아님 — 동작 확인)

- 청구 상세 패널은 취소(canceled) 후에도 "발행 취소" 라벨로 기록을 표시한다(P4 레코드 유지 정책
  — 발행 버튼은 노출되지 않음). 위임 지시의 "취소 후 비노출"은 발행 버튼 기준으로 해석해
  실제 구현 동작(레코드 표시·버튼 비노출)을 단정했다.
- PollStateJob의 retry_on 소진 판정은 Active Job의 `exception_executions`(예외 배열 key
  `"[클래스명]"`) 기준 — 테스트가 이 카운터로 소진 시점을 재현한다(10회 소진 → failed 확정 확인).

## 산출물

- 신규 테스트 10파일 + 헬퍼 2건 (위 표). 기존 fixture 변경 0건(파괴 없음).
- `test/controllers/app/invoices_reminders_test.rb` 날짜 부패 최소 복구 1건(테스트 파일만).
- 소스 코드(테스트 외) 수정 0건 — B-1은 보고만 수행(Phase 6은 오케스트레이터 분기).
