# 03_implementation — T-D1 INV-7 반복 청구 (2026-11-11, 병렬 배치 절약 모드)

## 변경 파일 목록 (소유권 화이트리스트 준수)

| 파일 | 구분 | 내용 |
|---|---|---|
| `db/migrate/20261111040001_create_recurring_invoices.rb` | 신규 | recurring_invoices + recurring_invoice_items 2테이블 |
| `app/models/recurring_invoice.rb` | 신규 | 스케줄 모델 — enum status/tax_mode·검증·advance!/hold!/due_today |
| `app/models/recurring_invoice_item.rb` | 신규 | 스냅샷 소스 품목(상한 InvoiceItem 상수 공유) |
| `app/models/user.rb` | 수정 1줄 | `has_many :recurring_invoices, dependent: :destroy` |
| `app/models/client.rb` | 수정 1줄 | `has_many :recurring_invoices, dependent: :destroy` |
| `app/services/recurring_invoices/issue_service.rb` | 신규 | 발행 플로우(보류·한도 skip·issue! 재사용·advance!/hold!) |
| `app/jobs/recurring_invoices/issue_job.rb` | 신규 | 매일 스캔·개별 실패 계속 처리 |
| `config/recurring.yml` | 수정 | `recurring_invoices_issue` 06:30 KST(production+development) — ※ 화이트리스트에 없으나 지시서 4번이 recurring.yml 추가를 명시하여 포함 |
| `app/controllers/app/recurring_invoices_controller.rb` | 신규 | index/new/create/show + pause/resume/cancel |
| `app/views/app/recurring_invoices/{index,new,show}.html.erb` | 신규 | U1 화면 3종(DESIGN 준수 — 에메랄드 액센트·min-h-11 터치 타깃·상태색) |

수정 금지 파일(routes·layouts·invoices_controller·invoices show 뷰·PRD/AGENTS·PDF 관련)은 일절 건드리지 않음.

## 스키마

**recurring_invoices**: user_id FK(cascade)·client_id FK(cascade — 주석 명시: client 삭제는 발행 이력 보유 시 모델 가드 차단, 가드 통과 삭제는 has_many dependent + on_delete cascade로 연쇄 정리)·last_invoice_id FK→invoices(null 허용, on_delete restrict — 발행 계열 청구는 삭제 경로 없어 P4 보존)·day_of_month int null:false·tax_mode int default 0·withholding_enabled bool default false·hold_if_unpaid bool default false·status int default 0 null:false·last_issued_on date·next_issue_on date null:false·last_skip_reason string·timestamps + `(user_id, next_issue_on)` 복합 인덱스.

**recurring_invoice_items**: recurring_invoice_id FK(cascade)·name string null:false·quantity int null:false default 1·unit_price int null:false default 0·timestamps.

## 발행 불변식 (02_prd_update 확정 해석 2 대응)

| 불변식 | 구현 위치 |
|---|---|
| 스케줄당 월 1회(next_issue_on==today) | `RecurringInvoice.due_today`(Job 스캔) + IssueService 재확인 — 성공·skip 모두 next_issue_on을 다음 달 N일로 이동 → 재실행 무해(멱등) |
| 보류·한도 skip은 스케줄 상태에 사유 기록 | `hold!(reason)` → last_skip_reason(NOTI-3 통보 데이터·show 화면 표시) |
| 발행은 기존 issue! 재사용 | IssueService#issue — 채번 INV-1·토큰 SHARE-1·PLAN-1 최종 게이트·수금 패스 PLAN-4 전부 상속. 만기는 초안 생성 시 발행일+30일 명시(INV-3 준용) |
| last/next 갱신은 발행 커밋 성공 후 | `advance!(invoice)`는 issue! 반환 true 뒤에만 호출 |
| 직전 청구 미수 판정 | `Invoice.unsettled.exists?(id: last_invoice_id)` — 메모리 캐시 아닌 DB 최신 상태(mark_paid!의 update_all로 메모리 status가 늦는 결함 방지 — 테스트 실측으로 발견·수정) |

## Q15/Q16 반영

- **Q15(NOTI-3 템플릿 미등록)**: skip 시점 알림톡은 이번 범위 제외 — hold!(reason)이 상태 기록만 하고 enqueue 지점 없음. **인계**: ALIMTALK_TEMPLATES.md B-5(noti_recurring_issued/held) 솔라피 등록 후, IssueService#issue의 `enqueue_issue_notice` 아래에 U1 통보 DeliverJob enqueue를 추가하면 된다(채무자 issue_notice는 이미 인큐됨 — 발송 실패는 DeliverJob 실행 시 발생해 발행 무영향 확인). show 화면에 last_skip_reason 배너를 두어 등록 전까지 U1이 확인 가능.
- **Q16(PLAN-1)**: 사전 skip(user.monthly_invoice_limit_reached?) + issue! 최종 게이트 이중 — 초과 발행을 만들고 되돌리는 낭비 없이 사유 기록. dev runner 실측에서 한도 초과 시 RESULT=held 확인.

## 라우트 계약 확인 (3-S 결선용 — 이번엔 미결선)

`resources :recurring_invoices, only: %i[index new create show]` + `member { patch :pause; patch :resume; patch :cancel }` → 헬퍼: `app_recurring_invoices_path`·`new_app_recurring_invoice_path`·`app_recurring_invoice_path(schedule)`·`pause_app_recurring_invoice_path(schedule)`·`resume_app_recurring_invoice_path(schedule)`·`cancel_app_recurring_invoice_path(schedule)`. 뷰·컨트롤러는 이 헬퍼명으로 작성 완료 — 결선에서 routes만 추가하면 즉시 동작. 3-S 스모크 항목: create 303(성공)/422(품목 없음·day 29)·pause/resume 303·cancel 303(turbo_confirm).

## 테스트

- `test/models/recurring_invoice_test.rb`(9건) — day 1~28 한정(0·29·31 차단)·소유권 격리·품목 필수·next 초기화 당월/다음달 경계·advance! 월 경계(11-28→12-28)·hold! 사유 기록·due_today(paused/future 제외)
- `test/services/recurring_invoices/issue_service_test.rb`(7건) — 정상 발행(스냅샷·채번·토큰·만기+30·DeliverJob 인자 `[invoice_id, "issue_notice", "debtor"]`)·재실행 멱등·직전 미수 보류·직전 완납 발행·hold 미설정 무시 발행·한도 skip(Q16)·IssueJob 스캔(paused 제외·인큐 1건)
- 신규 16건 전부 통과. **전체 스위트 989건 중 2 failures + 5 errors — 전부 T-D1 스코프 밖**: 5 errors는 T-D2가 invoices/show.html.erb:451에 넣은 `payment_pdf_app_invoice_path`가 routes 결선(3-S) 전이라 발생, 2 failures(PaymentsConcurrency `[0,303]`·Admins::SignupStatsQuery 창 경계)도 동일하게 T-D2 병렬 실행/시간 의존 영역 — 병렬 태스크 소유권 규칙상 수정하지 않음(3-S 결선·Phase 5에서 해소 대상).

## 자기 스코프 검증 결과

- 마이그레이션 up/down roundtrip 실측 완료(reverted→migrated)·schema.rb 갱신 확인
- `bin/rails zeitwerk:check` 통과, 소유 10파일 `bin/rubocop` 0 offense
- runner 실측(dev): RESULT=issued(채번 BD-YYYYMMDD-NNN·품목 스냅샷·due+30·원천징수 net 106700·advance! next=12/10)·RESULT=held(한도 skip 사유 기록)·Job perform 무오류. 임시 레코드 전부 정리 확인
- 지시서 화이트리스트에 없던 유일 변경 = `config/recurring.yml`(지시서 4번 명시 항목) — routes·nav·기타 공유 파일 미수정

## Phase 6 — 리뷰 수정 (2026-11-11, CHANGES_REQUESTED → 재리뷰 제출)

| 이슈 | 수정 내용 | 재검증 |
|---|---|---|
| **B-1** 계정 삭제 파탄 | user.rb: `has_many :recurring_invoices`를 invoices **앞**(sessions 다음)으로 이동 + 선언 순서=destroy 실행 순서·last_invoice restrict 해소 근거 주석 문서화. AccountPurgeService: `rescue ActiveRecord::InvalidForeignKey` → 관리자 안내 오류 변환(500 방지·마지막 방어선 주석) | 신규 회귀 테스트: 완납 청구 1건 + last_invoice 설정 스케줄 보유 사용자 purge 성공(연쇄 0건·미수 가드 통과 명시) — account_purge_service_test 통과 |
| **C-1** 이중 발행 창 | IssueService#call 본문을 `schedule.with_lock` 트랜잭션으로 감쌈 — 잠금 후 next_issue_on 재판정(동시 실행 → 2번째는 skipped)·issue!+advance! 동일 트랜잭션(advance! 실패 시 발행까지 롤백)·**알림 인큐는 커밋 후 전용**(enqueue_notifications 분리) | 강제 실패 테스트: advance! raise 시 Invoice 0건·커서 유지·인큐 0건, 재실행 시 1회 발행 — 통과 |
| **C-2** 커서 equality | 스캔 `due_today` → `due_or_overdue`(`next_issue_on: ..Date.current`)·서비스 가드 `<= Date.current`·**커서 기준을 구값(next_issue_on)으로**(advance!·hold! 모두) — 지연 발행의 발행일 드리프트 제거 | 3일 미실행 테스트: next_issue_on=오늘-3 → 1회 발행·커서=구값 기준 다음 달 10일 — 통과 |
| **W-1** cancelled resume | pause는 `active?`만·resume는 `paused?`만 허용, 위반 시 303 리다이렉트+alert(서버 가드) | 컨트롤러 테스트 4건(cancelled resume 거부·active 중복 resume 거부·paused 중복 pause 거부·정상 전이) — 통과 |
| **W-2** Q15 방침 (b) | SendService: MISSING_TEMPLATE ApiError → `skipped(NO_TEMPLATE)` MessageLog 기록 후 `:skipped` 정상 종료(재시도 없음). IssueService: 커밋 후 `noti_recurring_issued`(U1)·held 시 `noti_recurring_held`(U1, last_invoice 있는 경우) 인큐. SendService 변수 맵에 `보류사유`(스케줄 last_skip_reason 역조회)·button_url held 분기(/app/recurring 스케줄 상세·폴백 목록) | 신규 no_template_skip_test: FakeSolapiClient MISSING_TEMPLATE → skipped+NO_TEMPLATE·예외 미상승 통과. IssueService 테스트: issued 시 인큐 2건(issue_notice+noti_recurring_issued)·held 시 noti_recurring_held 인큐 — 통과 |
| **W-3** create 19줄 | 위조 품목 가드를 `before_action :reject_forged_items`(create 전용)로 추출 — create 10줄 이내 | 해당 통합 테스트(리뷰어 422 실측 케이스 재현 포함) 통과 |

부대 변경: recurring.yml 무변경(기존 06:30 KST 유지 — C-2 완화는 잡 스코프에서 흡수). B-2는 T-D2 산출 문서의 Phase 6 절 참조.

게이트: 소유 14파일 rubocop 0 offense·zeitwerk 통과·수정 연관 테스트 37건(T-D1) + reminders 스위트 68건 + purge/invoices/payments 컨트롤러 136건 전부 통과. 전체 스위트는 Phase 7(전체 금지 준수).
