# 03_implementation — INV-7+PAY-6 병렬 배치 3-S 결선 (2026-11-11, 절약 모드)

T-D1(반복 청구)·T-D2(PAY-6 PDF) fan-out 완료 후 공유 파일 결선·검증 기록. fan-out 상세는
`_workspace/parallel/T-D1/03_implementation.md`·`_workspace/parallel/T-D2/03_implementation.md` 참조.

## 결선 변경 파일

| 파일 | 변경 |
|---|---|
| `config/routes.rb` | ① app 네임스페이스에 INV-7 라우트 신설: `resources :recurring_invoices, only: %i[index new create show]` + `member { patch :pause; patch :resume; patch :cancel }` — 계약(02_prd_update 확정 해석 1) 그대로 ② 기존 `resources :invoices` member 블록에 `get :payment_pdf` 병합(PAY-6) |
| `app/helpers/app/base_helper.rb` | nav에 "반복 청구"(`app_recurring_invoices_path`·start_with? active 기존 문법 준용) 1행 추가 |

## 컨트롤러·헬퍼 실명 확인

- `app/controllers/app/recurring_invoices_controller.rb` 존재 — index/new/create/show/pause/resume/cancel 액션 실측 확인, T-D1이 보고한 헬퍼명 6종(`app_recurring_invoices_path`·`new_app_recurring_invoice_path`·`app_recurring_invoice_path`·`pause_/resume_/cancel_app_recurring_invoice_path`)과 라우트 일치
- `app/controllers/app/invoices_controller.rb` — `payment_pdf` 액션·`before_action :set_invoice`(Current.user 스코프) 존재 확인, `payment_pdf_app_invoice_path` 뷰 참조와 일치 → 정렬 수정 0건

## 마이그레이션

- `bin/rails db:migrate` — recurring 2테이블 마이그레이션 이미 적용 상태(T-D1이 roundtrip 실측), 결선 시 무출력(최신) 확인. `db/schema.rb`에 recurring_invoices 9곳 존재 — 동기 확인

## 스모크(비인증 curl — dev 서버 3002)

| 경로 | 결과 |
|---|---|
| GET /app/recurring_invoices | 302 → /session/new |
| GET /app/recurring_invoices/new | 302 → /session/new |
| GET /app/invoices/1/payment_pdf | 302 → /session/new |
| GET /admin/session/new | 200 (로그인 화면 — 정상) |
| GET /up | 200 |

※ 지시서 예상 "303"과 달리 인증 가드는 기존 `Authentication` concern의 `redirect_to`(302) — 기존 /app 전 표면과 동일한 선행동이라 정상. 변경 없음. 서버 정리 완료(pid kill).

## 컨트롤러 최초 HTTP 검증(U1 Integration — 임시 테스트, 실행 후 삭제·레코드 트랜잭션 롤백)

5 runs, 41 assertions, 0 failures, 0 errors:

1. recurring index 200 · new 200 · **create 303**(RecurringInvoice 생성 실측 — day_of_month=10·active)
2. create 실패(품목 없음·day 29) → **422**
3. payment_pdf 미마감(issued) → 상세 redirect + alert("수금이 마감된 청구서만 증빙을 내려받을 수 있습니다.")
4. payment_pdf paid → **200 PDF**, `%PDF` 헤더·바이트 >10KB(Prawn+Pretendard 한글 폰트 렌더)
5. 타인 소유 청구 payment_pdf → **404**(소유권 격리)
6. recurring pause → 303(paused) · resume → 303(active) · cancel → 303(cancelled)

## 전체 스위트 7건 재확인 (T-D1 보고)

- **5 errors(payment_pdf_app_invoice_path 미정의 라우트)** — 이번 결선으로 소멸 확인: 임시 통합 테스트로 뷰·컨트롤러 HTTP 실측 통과
- **PaymentsConcurrency** — 개별 실행(`bin/rails test test/models/payment_pass_concurrency_test.rb test/queries/admins/signup_stats_query_test.rb`)에서 **통과**. 병렬 실행 환경 의존 확인
- **Admins::SignupStatsQuery 경계 테스트** — 개별 실행에서 **재현(1 failure)**. 원인 분석: 테스트가 시드 시점에 `30.days.ago.beginning_of_day`(실행일 기준)로 가입 시각을 심고, 단정은 `travel_to("2026-11-10 09:00")` 안에서 다시 `30.days.ago`를 계산 — 실행일이 11-10이 아니면 창 기준이 어긋난다(오늘 11-11 시드 → 창 시작 11-10 → 시드 2건 모두 포함). **시간 의존 테스트 결함이며 본 배치 변경과 무관**. 결선 스코프 준수(테스트 수정 보고만): 수정안은 시드와 단정의 기준 시각을 고정값으로 일치시키는 것(예: 양쪽 `Time.zone.parse("2026-11-10 09:00")` 기준 30일 전 자정). Phase 5 리뷰어 판정 대상

## 게이트

- `bin/rails zeitwerk:check` 통과
- `bin/rubocop config/routes.rb app/helpers/app/base_helper.rb` — 2 files, 0 offenses
- 전체 테스트 스위트 실행 금지 준수(Phase 7에서 수행) — 위 개별 확인만 수행
- PRD·AGENTS·문서 미수정. 임시 파일(/tmp 서버 로그·임시 테스트) 정리 완료

## 수선 (2026-11-11, 절약 모드 — 테스트 결함 2건)
- 결함 1: test/queries/admins/signup_stats_query_test.rb — 30일 창 경계 테스트의 시간 의존 시딩(30.days.ago)을 고정 기준 시각(2026-11-10 09:00) 역산으로 수선, 실행일 무관 통과
- 결함 2: test/controllers/app/dashboards_controller_test.rb — nav 잠금 메뉴 개수 8 → 9 갱신(반복 청구 메뉴 추가, 2026-11-11)
