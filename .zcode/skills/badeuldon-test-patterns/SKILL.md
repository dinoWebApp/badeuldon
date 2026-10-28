---
name: badeuldon-test-patterns
description: 받을돈 테스트 패턴 스킬. minitest + fixtures 기반 계층별(모델/서비스/컨트롤러/시스템) 테스트 템플릿, Rule ID별 시나리오 도출 방법, 외부 API(핵클·토스페이먼츠) stub 처리, 테스트 실행 명령어를 제공한다. 받을돈 테스트를 작성·실행할 때 사용한다.
---

# 받을돈 테스트 패턴 (minitest + fixtures)

## 이 스킬의 목적

Rule ID → 검증 가능한 시나리오 → 계층별 minitest 코드로 변환하는 표준 패턴을 제공한다. 테스트의 기준은 항상 PRD — 시나리오 도출이 막히면 PRD §6 해당 기능 명세로 돌아간다.

## 계층 선택 기준

| 계층 | 대상 | 위치 |
|:---|:---|:---|
| 모델 테스트 | 검증·enum 상태 전이·scope·도메인 메서드 | `test/models/` |
| 서비스 테스트 | 트랜잭션·외부 API 래핑·발송 규칙 | `test/services/{도메인}/` |
| 컨트롤러 테스트(통합) | 라우트·권한·응답 코드·리다이렉션 | `test/controllers/` |
| 시스템 테스트 | 브라우저 E2E — 뷰어(③) 인앱 동작, 수금 루프 | `test/system/` |

시스템 테스트는 핵심 유저 여정(발행→열람→응답→마감)에만. 나머지는 아래 계층으로 충분하다.

## Rule ID → 시나리오 도출

각 Rule ID마다 최소 3종(정상/경계/예외)을 도출한다. 예(INV-4 상태 전이):

- 정상: 발행 → 열람 → 약속 → 수금완료 경계값 통과
- 경계: 만기일 당일(연체 아님), 부분입금 후 잔액 0 도달 시 수금완료 전이
- 예외: 발행 후 본문 수정 시도(INV-5 위반) → 실패/무효 경유 강제

발송 도메인(REM) 필수 시나리오: 평일 09-18시 창 내/외(REM-3), 동일 단계 재발송 차단(SEC-5), 5통 상한 도달(REM-12), 약속 등록 후 재스케줄(PROMISE-3), 채무자 입금 회신은 마감 불가(PROMISE-7).

## 모델 테스트 템플릿

```ruby
# test/models/invoice_test.rb
require "test_helper"

class InvoiceTest < ActiveSupport::TestCase
  fixtures :users, :clients, :invoices

  test "만기 경과 시 overdue여야 한다 (INV-4)" do
    invoice = invoices(:issued_unpaid)
    travel_to(Time.zone.parse("2026-11-10 09:00")) do   # KST 고정 가정 — TIME-1
      assert invoice.overdue?
    end
  end

  test "발행 후 상태는 미열람이다 (INV-4)" do
    assert_equal "issued", invoices(:issued_unpaid).status
  end
end
```

## 서비스 테스트 템플릿 (외부 API stub 필수)

```ruby
# test/services/reminders/dispatch_service_test.rb
require "test_helper"

module Reminders
  class DispatchServiceTest < ActiveSupport::TestCase
    fixtures :users, :clients, :invoices

    test "발송 창 밖(토요일)에서는 발송하지 않는다 (REM-3)" do
      HackleMessage.stub(:send, ->(*) { raise "must not send" }) do
        travel_to(Time.zone.parse("2026-10-10 10:00")) do   # 토요일
          assert_raises(SendWindowViolation) do
            DispatchService.new(invoice: invoices(:issued_overdue), step: :d1).call
          end
        end
      end
    end

    test "동일 단계 재발송은 멱등하게 차단된다 (SEC-5)" do
      invoice = invoices(:issued_overdue)
      DispatchService.new(invoice:, step: :d1).call
      assert_no_difference -> { invoice.reminders.count } do
        DispatchService.new(invoice:, step: :d1).call
      end
    end
  end
end
```

**외부 API(핵클·토스페이먼츠)는 절대 실호출하지 않는다** — wrapper 모듈을 stub/주입으로 대체. 시간 의존 로직은 `travel_to`로 KST 시각을 고정.

## 컨트롤러(통합) 테스트 템플릿

```ruby
# test/controllers/app/invoices_controller_test.rb
require "test_helper"

class App::InvoicesControllerTest < ActionDispatch::IntegrationTest
  fixtures :users, :invoices

  test "타 사용자 청구서 접근은 거부된다 (소유권 격리)" do
    sign_in users(:alpha)
    get app_invoice_path(invoices(:beta_invoice))
    assert_response :not_found
  end

  test "생성 성공은 303, 검증 실패는 422 (Turbo 규약)" do
    sign_in users(:alpha)
    assert_difference("Invoice.count") do
      post app_invoices_path, params: { invoice: valid_invoice_attrs }
    end
    assert_redirected_to app_invoice_path(Invoice.last)
    # 실패 케이스
    post app_invoices_path, params: { invoice: invalid_invoice_attrs }
    assert_response :unprocessable_entity
  end
end
```

## 시스템 테스트 (뷰어 인앱 = 필수 QA, VIEW-1)

```ruby
# test/system/viewer_test.rb
require "application_system_test_case"

class ViewerTest < ApplicationSystemTestCase
  test "채무자가 링크를 열고 약속 버튼으로 응답한다 (PROMISE-1/2 — 무가입)" do
    invoice = invoices(:issued_unpaid)
    visit viewer_path(invoice.token)
    assert_text "청구서"                      # VIEW-2 발행인 표시 확인
    click_on "입금 예정일 지정"
    # ... 달력 선택 후 접수 확인 (PROMISE-4: U1 알림은 stub 검증)
  end
end
```

## fixtures 규칙

- `test/fixtures/{모델}.yml` — 사용자(alpha/beta), 거래처, 청구서(상태별 최소 1건: draft/issued/viewed/overdue/promised/partially_paid/paid/voided) 표준 세트 유지
- 토큰 fixture는 고정값 — 추측 불가 테스트는 모델 생성 경로로 별도 검증(SHARE-1)
- 금액은 정수(원)로

## 실행 명령어

```bash
bin/rails test                                   # 전체
bin/rails test test/models/invoice_test.rb       # 파일
bin/rails test test/models/invoice_test.rb -n /overdue/   # 케이스
bin/rails test:system                            # 시스템 (브라우저)
```

## Tester 완료 전 자체 점검

- [ ] 관련 Rule ID별 정상/경계/예외 시나리오 모두 커버
- [ ] 외부 API 실호출 0건 (stub/주입 확인)
- [ ] 테스트 소스에서 미사용 정의 제거, RuboCop 통과, **들여쓰기 2칸(Ruby) 준수**
- [ ] 실패 시 원인 분류 명시: 코드 버그 vs 테스트 오류
- [ ] 기존 테스트 전체 회귀(`bin/rails test`) 통과
- [ ] `_workspace/07_test_report.md` 작성 (통과/실패 건수, 실패 상세, 원인 분류)
