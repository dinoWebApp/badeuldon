# 07_test_report — CLIENT-3/4·PROMISE-5 런 Phase 7 (검증·보강·전체 게이트)

작성: Tester(절약 모드) · 2026-11-10
대상: F-CLIENT 지급 성적표(CLIENT-3/4·PROMISE-5·Q14) + Phase 6 수정(C-1 모집단 일치·W-1 배지 색). 기존 13건(쿼리 9 + 컨트롤러 5… 실측 9+5=개별 파일 기준 아래 표) 검증 + 리뷰 Tester 중점 6건 보강.

## 최종 결과

- **전체 `bin/rails test`: 967 runs · 5,466 assertions · 0 failures · 0 errors · 0 skips** (기준 954건 회귀 0 + 보강 +13)
- `bin/rubocop` 신규·수정 테스트 파일 5개 — **no offenses**
- 외부 API(솔라피·포트원) 실호출 0건 — 보강 테스트는 전부 내부 조회 경로만 사용
- **코드 버그 0건** — Phase 6 수정(C-1·W-1)이 테스트로 재확인됨

## 리뷰 6건 처리 대조표 (05_review Tester 중점)

| # | 중점 영역 | 처리 | 결과 |
|---|---|---|---|
| 1 | C-1 재발 방지(voided·draft 모집단 일치) | 기존 쿼리 테스트 존재 확인 + 신규 "voided·draft 약속 건은 이행률·평균 지연 집계에서도 제외된다"(scorecard 쿼리 — 이행률 nil·avg nil·목록 empty 동시 단언, promised 상태에서 void! 시나리오) | 통과 |
| 2 | 배지 반올림 경계 + 이행률 80% 색 | 신규 helper 단위 테스트 5건(`test/helpers/app/clients_helper_test.rb`) — diff 정확 1일 노출(느림=주황·빠름=emerald, W-1 색 판정)·diff 0(반올림 상쇄) 미노출·지표 결손·거래처 1개 미노출 + 쿼리 레벨 반올림 상쇄 테스트(두 평균 모두 0.5→1) | 통과 |
| 3 | 연말 6개월 창 | 신규 쿼리 테스트 — travel_to 2027-01-15, 라벨 2026-08~2027-01(연 롤오버)·2026-12 +3·창 밖(2026-07) 버림·빈 달 nil | 통과 |
| 4 | this_week 약속 시간 경과 | 신규 쿼리 테스트 — 접수 당일(약속일==오늘 경계) pending → 자정 경과 +1일 broken 전이(travel 2회·kind: this_week) | 통과 |
| 5 | 발행 폼 JS 시스템 테스트 | 신규 `test/system/app_invoice_form_scorecard_test.rb` — 실제 브라우저: 초기 hidden → select change → fetch 응답 조각 삽입("평균 지급 지연일 1일·이행률 100%") → 프롬프트 복귀 시 조각 제거·hidden 복원 | 통과 |
| 6 | 조기 입금(음수 지연) | 신규 3건 — 쿼리(−3·−1 → avg −2·이행률 100%), helper("2일 전"/"0일"/nil="-"·경향 막대 abs 정규화 50%/100%/최소 12), 통합 뷰(show가 "2일 전" 렌더·"-" 오노출 없음·거래처 1개 배지 미노출) | 통과 |

## 보강 테스트 파일 (신규 2 + 수정 3, +13 tests)

| 파일 | tests | 내용 |
|---|---|---|
| `test/helpers/app/clients_helper_test.rb` (신규) | 5 | 비교 배지 경계·방향 색(W-1)·delay/rate 텍스트·경향 막대 음수 정규화 |
| `test/system/app_invoice_form_scorecard_test.rb` (신규) | 1 | 발행 폼 Stimulus client-scorecard fetch E2E |
| `test/queries/clients/payment_scorecard_query_test.rb` (+4) | — | 연말 창·음수 평균·반올림 상쇄·voided 집계 제외(C-1) |
| `test/queries/clients/promise_compliance_query_test.rb` (+1) | — | this_week 약속일 경계→도과 전이(seed에 kind 인자 추가) |
| `test/controllers/app/clients_scorecard_test.rb` (+2) | — | 조기 입금 뷰 "N일 전"·느린 배지 주황 렌더(W-1) |

## 기존 스위트와의 충돌 확인 (게이트 7-S)

- DASH-5(`Reports::ClientDelayQuery` — 만기 대비)와 신규 CLIENT-4(약속일 대비) 쿼리가 서로 다른 파일·모집단으로 분리 — 전체 스위트 동시 통과로 회귀 없음 확인
- 기존 954건(679건 기존 + Phase 5~6 13건 포함) 전부 통과 — 클라이언트 show 확장(invoices_controller clients 변수)이 기존 clients/invoices 컨트롤러 테스트에 영향 없음

## 테스트 오류 자체 수정 이력 (코드 버그 아님 — 3건)

1. 시스템 테스트: hidden 요소 `find` 실패 → `visible: :all` 지정
2. 시스템 테스트: 시드 지연 +2로 기대 "1일" 불일치(시드 산수 실수) → paid_on 수정
3. 통합 테스트: 배지 diff가 (3+2)/2=1.5→2로 상쇄되어 미노출(동작이 오히려 경계 규격 준수) → 시드를 +3/+1로 조정해 diff 1 확보

## 코드 버그 절

없음 — 0건.
