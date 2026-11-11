# 07_test_report — INV-7 반복 청구 + PAY-6 PDF 병렬 배치 (2026-11-11, Tester 절약 모드)

## 게이트 결과 (Phase 7)

| 스위트 | 결과 |
|---|---|
| `bin/rails test` (기본 — test/system 제외 러너 구조 실측) | **1008 runs, 5650 assertions, 0 failures, 0 errors, 0 skips** |
| `bin/rails test:system` (기본 러너가 시스템 테스트를 로드하지 않음을 실측 — 별도 실행 필수) | **11 runs, 84 assertions, 0 failures, 0 errors, 0 skips** — 신규 PDF 시스템 테스트 포함 |
| `bin/rubocop` (전체 283파일) | **0 offenses** |
| 합계 | **1019 runs · 0 실패 · 코드 버그 0건** |

- 실호출 0건: PDF은 send_data 응답 수령, 솔라피 경로는 DeliverJob enqueue만 검증(기존 stub 체계 유지).
- test DB 잔존 없음(트랜잭션 롤백·fixtures). 임시 파일 /tmp 정리 완료.

## 리뷰어 중점 제안 5건 처리

| # | 제안 | 처리 |
|---|---|---|
| ① | PDF 시스템 테스트(U1 실로그인 → paid 상세 → 다운로드 → %PDF·파일명) | **신규 작성** — `test/system/app_invoice_pdf_test.rb`. headless Chrome의 파일 다운로드 경로 통제 대신 동일 인증 쿠키의 same-origin fetch로 응답 본체를 브라우저에서 직접 수신: `%PDF-` 시그니처·>10KB(폰트 임베드 — B-2 회귀)·Content-Disposition attachment 단정. 다운로드 버튼 노출(Q17 마감 조건)은 `assert_link "수금완료 증빙 PDF"`로 검증 |
| ② | recurring CRUD 정식 컨트롤러 테스트 | **부재 확인 → 신규 작성** — `test/controllers/app/recurring_invoices_controller_test.rb` 7건: index/new 200·create 303(next 초기화·품목 저장)·**day 29 → 422**·**타인 스케줄 → 404**(show_exceptions=:rescuable이라 404 렌더 단정)·cancel 303+이력 보존(P4)·상세 hold 배너 렌더(⑤)·사유 없으면 배너 미렌더. 전이 가드(W-1)는 기존 recurring_transitions_test가 담당 — 중복 없음 |
| ③ | IssueJob 멱등(같은 날 2회 perform) | **정식화** — issue_service_test에 추가: 2회 perform 후 Invoice 수·인큐 수 불변·커서 이중 이동 없음(SEC-5 준용 주석) |
| ④ | W-2 skipped(NO_TEMPLATE) 정식 회귀 | **기존 커버 확인·스킵** — `test/services/reminders/no_template_skip_test.rb`가 이미 FakeSolapiClient MISSING_TEMPLATE → `:skipped` + MessageLog `skipped/NO_TEMPLATE` + sent_at nil + 실호출 시도 1회까지 assert함. 신규 중복 작성 불요 |
| ⑤ | recurring 상세 hold 사유 배너 렌더 | **②에 포함** — 컨트롤러 테스트 수준에서 사유 있음/없음 양방향 단정 |

## 비고 정리 (코스메틱)

- `test/services/recurring_invoices/issue_service_test.rb:153` 테스트명 "due_today" → "due_or_overdue"
- `test/models/recurring_invoice_test.rb` 헤더 주석 "due_today 스코프" → "due_or_overdue 스코프"

## 코드 버그

없음. 실패 1건은 테스트 오류(타인 스케줄 404를 raise 단정으로 작성 — test 환경 `show_exceptions = :rescuable`에서는 미들웨어가 404를 렌더하고 예외는 상승하지 않음) → 자체 수정 후 통과. 기존 스위트 충돌(recurring 마이그레이션·NO_TEMPLATE 분기·upgrade_service 쿠폰 정산) 없음 — 전체 게이트로 확인.

## 러너 구조 실측 (기록 — 향후 게이트 절차 참고)

`bin/rails test`는 `test/system/**`을 로드하지 않음(`-n` 프로브로 알려진 시스템 테스트 0 runs 실측). 시스템 테스트는 `bin/rails test:system` 별도 실행 필요 — "bin/rails test 전체" 게이트는 사실상 기본+시스템 2회 실행이 전체이다.
