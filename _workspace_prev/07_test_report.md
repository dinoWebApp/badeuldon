# 07_test_report.md — F-PLAN 구독·과금 테스트 보고서

- **일자**: 2026-10-15 (KST)
- **작성**: PlanTester (badeuldon-tester)
- **대상**: F-PLAN 구독 생명주기·한도 전환·결제·수금 패스·웹훅 (`_workspace/03_implementation.md` · PRD §6.10 PLAN-1~8)
- **코드 수정**: 없음 — `app/` 무변경. 변경은 `test/`와 `test/fixtures/`만 (규칙 준수)

---

## 1. 최종 결과

| 검증 | 결과 |
|---|---|
| `bin/rails test` (전체 회귀 포함, 최종 HEAD) | **484 runs, 2,929 assertions, 0 failures, 0 errors, 0 skips** |
| 신규 F-PLAN 테스트 (본 보고 산출) | **109 cases / 13 files — 전부 통과** |
| `bin/rubocop` | **135 files inspected, no offenses** |
| `bin/rails zeitwerk:check` | 통과 ("Otherwise, all is good!") |
| 토스 API 실호출 | **0건** — 전송 계층(Net::HTTP.start) 스텁 + `FakeTossClient` 주입만 사용 |

기존 366 runs 기준에서 +109건 증가, 기존 스위트 실패 0건 유지(회귀 없음).

---

## 2. 신규 테스트 파일

| 파일 | 건수 | 커버 |
|---|---|---|
| `test/models/subscription_test.rb` | 15 | 가입 시 Free 자동 생성·1인 1구독(고유 인덱스)·생명주기 4전이(trialing/active/cancelled/expired)·재가입 즉시 active·체험 1회(used_trial)·체험 중 조기 등록 주기 기준·한도 판정점(Free 경계 4/5·2/3, Plus 무제한)·레거시 폴백·customer_key 발급/중복 |
| `test/models/order_test.rb` | 4 | 정가 단일 지점(Plus 9,900·패스 4,000)·pending 기본값·금액/주문번호 검증·orderId 고유 |
| `test/models/payment_pass_test.rb` | 7 | 10건/90일 상수·usable? 경계(잔여 0·만료)·use! 차감·11번째 UsesExhausted·만료 차단·usable 스코프 |
| `test/models/payment_pass_concurrency_test.rb` | 1 | **with_lock 실스레드 동시 사용** — 잔여 1건에 2스레드 → 정확히 1회 차감, 1건 UsesExhausted, 음수 불가 |
| `test/models/plan_limit_transition_test.rb` | 6 | **한도 전환 회귀** — Free 거래처 6번째 차단/Plus 전환 6번째 성공(alpha), Free 월 3건 차단/Plus 4번째 성공(gamma), 구독 없는 레거시 폴백 차단 ×2 |
| `test/services/toss_payments/client_service_test.rb` | 9 | confirm/issue/charge/get_payment 요청 구성(경로·바디·POST/GET)·Basic Auth(secret_key, 무비번)·비2xx→ApiError(status/code/message)·빈 본문→`{}`·타임아웃→TIMEOUT·접속실패→CONNECTION |
| `test/services/subscriptions/upgrade_service_test.rb` | 22 | 체험 시작(+14일·토스 무호출·레거시 즉석 생성)·이중 체험/재체험 가드·카드 등록(빌링키 저장·즉시 active·주기 시작·authKey 누락/발급 실패)·해지(기간 유지·Free 거부·체험 중 허용)·만료 강등(정보 폐기·used_trial 유지·멱등)·갱신(주문 paid 9,900원·주기 연장)·명확 실패(즉시 만료)·**모호 실패(TIMEOUT→pending 유지)**·멱등키 재사용·남은 주기 무차감·settle_renewal(웹훅 회복·비갱신 주문 가드) |
| `test/services/orders/purchase_service_test.rb` | 6 | 승인→paid+패스 10건(+90일)·서버 원값(orderId·amount) 전달·재승인 거부(SEC 멱등)·명확 실패→failed·**모호 실패 재확인 DONE→정상 합류**·**모호 실패 미승인→pending+paymentKey 보존(pending_recovery)** |
| `test/services/orders/purchase_service_concurrency_test.rb` | 1 | **with_lock 실스레드 이중 결제** — 동시 승인 2건 → 발급 정확히 1회, 1건 "이미 처리된 결제" 흡수 |
| `test/controllers/app/billings_controller_test.rb` | 9 | 비인증 302·Free/체험/이용중/해지예정 배지·플랜 카드(9,900원·무제한 문구)·체험 CTA 분기·PLAN-6 환불 불가 고지·패스 요약(만료 제외)·체크아웃 파셜(본인 pending만·타인/처리된 주문 차단) |
| `test/controllers/app/subscriptions_controller_test.rb` | 10 | 비인증 302·체험 시작 303→trialing·재체험 303 알림 거부·카드 등록 303→active+빌링키 저장·위젯 콜백(authKey 카멜케이스 GET)→active·발급 실패 303 알림·해지(cancel 경로) 303→cancelled·Free 해지 거부·체험 중 해지 허용 |
| `test/controllers/app/orders_controller_test.rb` | 7 | 비인증 302·4,000원 정가 주문 303→체크아웃 전환·대기 주문 재사용(연타 멱등)·콜백 승인 303→paid+패스·승인 실패 303 알림→failed·사용자 취소 흡수·타인 주문 콜백 404 |
| `test/controllers/webhooks/toss_controller_test.rb` | 12 | DONE/CANCELED/ABORTED 매핑·**이벤트 값 미신뢰(재조회 기준 확정)**·재시도 멱등·비매칭 이벤트·파싱 실패 200·미지정 paymentKey 200·비인증 허용·**회복 4종**: paymentKey 보존 pending 패스 DONE→발급, orderId 보조 매칭→settle_renewal(주기 연장), orderId 불일치 흡수(위조 결합 차단), paymentKey 없는 이벤트 흡수 |
| **합계** | **109** | |

---

## 3. 시나리오 도출 기준 충족 (정상/경계/예외)

- **구독 생명주기**: Free 생성(정상) → 체험 +14일(경계 — 종료일 검증) → 카드 등록 active(정상) → 해지 cancelled·기간 유지(정상) → 만료 expired·정보 폐기(예외) → 재가입 즉시 active(예외) → 재체험 거부(예외·이슈 #2)
- **한도 전환**: Free 4개/5개·2건/3건 경계값, Plus 무제한, 레거시(구독 행 없음) 상수 폴백 — 모델 판정점 + Client/Invoice 발행 경로 회귀 모두
- **수금 패스**: 잔여 1/0 경계·만료 당일 경계·10회 소진 후 11번째 차단(예외)·동시 사용 1회(with_lock)
- **결제**: 승인 성공/이미 처리/명확 실패/**모호 실패 3분기**(재확인 DONE 합류·pending 보존)·이중 콜백 동시성
- **웹훅**: 상태 매핑 전종·무결성(재조회 우선)·항상 200·멱등·비인증·회복 경로(이슈 #1·#4)

---

## 4. 실행 중 발견·분류한 이슈

### 코드 버그 (개발자 수정 완료)
| # | 내용 | 분류 | 처리 |
|---|---|---|---|
| B-1 | `resource :billing` 라우트가 `App::BillingsController`(부재)로 매핑 — GET /app/billing 전체가 MissingController 500. 사이드바 「요금제」 메뉴·거래처 배너 링크까지 전파되는 CRITICAL | **코드 버그** (컨트롤러/라우트 명명 불일치) | PlanDeveloper가 controller/helper/view를 `Billings*` 복수형으로 리네임하여 수정. 수정 후 내 9건 렌더 테스트 전부 통과 — 통합 세션 재검증도 개발자가 수행 |

### 테스트 오류 (자체 수정 — 코드 무관)
| # | 내용 | 수정 |
|---|---|---|
| T-1 | `issue!` 실패 시에도 인메모리 객체의 status는 `:issued`로 세팅됨 → draft? 대신 당월 발행 수 DB 카운트로 검증 변경 | 완료 |
| T-2 | 중복 주문 테스트에서 `valid?` 호출 전 `errors` 참조 | 완료 |
| T-3 | minitest 6에는 `Object#stub`이 없음(minitest-mock 별도 gem 미도입) → `test/test_helpers/toss_stubbing.rb`(클래스 메서드 임시 교체+원본 복원) 작성해 해결 | 완료 |
| T-4 | 웹훅 헬퍼 keyword 불일치(`paymentKey:` vs `payment_key:`)·재조회 응답에 paymentKey 누락 | 완료 |

### 명세-구현 차이 (관측 — 오케스트레이터 확인 권고)
- 지시서의 "이미 Plus면 **422**" → 구현은 Turbo PRG 관례에 따라 **303 리다이렉트 + alert 플래시**("이미 Plus를 이용 중입니다"), 상태 무전이. 기존 컨트롤러 규약(생성 성공 303/검증 실패 422는 폼 렌더 경로에만 적용)과 일관되어 테스트는 구현 계약(303+alert+무전이)을 고정함. PRD상 사용자 영향 없음으로 판단하나 확정은 오케스트레이터 몫.

---

## 5. 협업 기록

- **PlanFixDeveloper**: 리뷰 수정 7건(#1 모호실패 회복, #2 used_trial, #3 activate 주기 기준, #4 갱신 선주문 멱등, #5 update/cancel 경로 분리, #6 Free 해지 거부, #7 발행-패스 소비) 반영에 맞춰 본 스위트를 최종 HEAD 기준으로 재정렬. 분업: 웹훅 회복 4건·이중 경합은 본 스위트, #1 서비스 레벨·#3·#5·#7은 `test/f_plan_review_fix_test.rb`(9건 — 병합 초기 2건 red를 원인 분석해 인계 → 수정 완료, 최종 HEAD에서 0 failures 확인). 내 파일 2곳의 cancel 경로는 이슈 #5에 맞게 동료가 수정 반영.
- **PlanDeveloper**: B-1 수정·통합 실측 보고.
- **fixture 제약**: `fixtures :all` 전역 적재 특성상 alpha/beta/gamma/delta에 구독 행을 두면 기존 PLAN-1 폴백(구독 없음 = Free 상수) 테스트가 깨진다 → 신규 사용자 `epsilon`(profile 완료)을 `users.yml`에 추가하고 `subscriptions.yml`은 epsilon 1행(plus/active)만 유지. 나머지 생명주기 상태는 테스트 내 `create_subscription!`로 생성. `orders.yml`은 paid 확정 주문 1건만 두고 pending은 테스트 내 생성(Orders#create의 pending 재사용 멱등이 fixture와 충돌하기 때문).

---

## 6. 토스 실호출 방지 근거

- 서비스/컨트롤러 경로: `TossPayments::ClientService` 대신 `FakeTossClient`(test/test_helpers/fake_toss_client.rb) 주입 — 호출 인자 기록으로 서버 원값(orderId·amount·멱등키) 전달까지 검증.
- 순수 클라이언트(ClientServiceTest): `Net::HTTP.start`를 스텁 — 실제 소켓 생성 없이 요청 구성·응답 파싱·오류 정규화 검증.
- 전체 스위트에서 외부 네트워크 의존 0건.

---

## 7. 재현 명령어

```bash
bin/rails test                                              # 전체 (484 runs, 0 failures)
bin/rails test test/models/subscription_test.rb \
  test/models/order_test.rb test/models/payment_pass_test.rb \
  test/models/payment_pass_concurrency_test.rb \
  test/models/plan_limit_transition_test.rb \
  test/services/toss_payments/ test/services/subscriptions/ test/services/orders/ \
  test/controllers/app/billings_controller_test.rb \
  test/controllers/app/subscriptions_controller_test.rb \
  test/controllers/app/orders_controller_test.rb \
  test/controllers/webhooks/toss_controller_test.rb         # 신규 109건
bin/rubocop                                                 # 135 files, no offenses
```
