# 01_plan — 병렬 배치: 회원 탈퇴 · 수신 거부 번호 단위 · 대시보드 오늘의 액션 (2026-11-26, 일반 모드·parallel)

## 배경

런칭 전 결정 3건(체크리스트 §8의 3·4·5번)에 대해 사용자가 "스스로 판단해 보라"고 하였고, 오케스트레이터는 세 건 모두
"고치는 쪽"(구현)으로 판단했다. 사용자가 `/badeuldon_orchestrator_parallel 진행해주세요`로 실행을 요청했다.
시점: main `d658c78`(2026-11-26 배포 완료)·작업 트리 깨끗함.

## 태스크 분해

| ID | 태스크 | Rule ID | 규모 | 실행 방식 |
|:--|:--|:--|:--|:--|
| T0 | 공유 결선(선행) — `resource :profile`에 `destroy` 추가(1줄) | AUTH-1.5 | Fast | 단독·직렬 (3-P보다 먼저) |
| T1 | 회원 탈퇴: 설정 화면 위험 구역·이메일 입력 확인·서비스·감사 로그·약관 정정 + 설정 문구 오타 수정 | AUTH-1.5, ADMIN-2, P4, LP-12 | Full | 병렬 G1 |
| T2 | 수신 거부를 같은 회원 안에서 번호 단위로: 거부 접수 시 전파 + 거래처 등록·수정 시 상속 + 등록 안내 | VIEW-7, PROMISE(응답) | Standard | 병렬 G1 |
| T3 | 대시보드 「오늘의 액션」 나머지 세 종: 오늘 발송 예정·약속일 도래·미열람 방치 | DASH-2, REM-11, DESIGN-5 | Full | 병렬 G1 |

## 병렬 안전 판정 (§6.14 3조건)

| 조건 | 판정 | 근거 |
|:--|:--|:--|
| 1. 파일 소유권 분리 | **충족** | 아래 소유권 표 — T1·T2·T3가 만지는 파일이 겹치지 않는다(테스트 파일 포함) |
| 2. 의존 없음 | **충족** | T1(회원·프로필)·T2(거래처·응답)·T3(대시보드)는 서로의 산출물을 쓰지 않는다. T3는 완성된 기존 코드(`Invoice.reminders_dispatchable`·`Invoice#reminder_cap_reached?`·`DispatchService`)만 참조 |
| 3. 공유 파일 비수정 | **충족(T0로 해소)** | 라우트는 T1만 필요 → T0가 3-P 전에 단독으로 결선. 마이그레이션 없음. PRD·AGENTS는 Phase 2(오케스트레이터). 공유 픽스처(`test/fixtures/*.yml`)·locale 파일(`config/locales/*`)은 태스크에서 수정 금지 |

## 파일 소유권 표

| 태스크 | 앱 코드 | 테스트 |
|:--|:--|:--|
| T0 | `config/routes.rb` | — |
| T1 | `app/controllers/app/profiles_controller.rb` · `app/views/app/profiles/edit.html.erb` · `app/services/users/withdrawal_service.rb`(신설) · `app/views/pages/terms.html.erb` · `app/views/admin/audit_logs/index.html.erb` · `app/models/invoice.rb`·`app/models/user.rb`(주석만 — 리뷰 반영) | `test/controllers/app/profiles_controller_test.rb` · `test/services/users/withdrawal_service_test.rb`(신설) · `test/system/app_profile_withdrawal_test.rb`(신설) · `test/controllers/pages_policy_test.rb` · `test/controllers/app/billings_controller_test.rb` · `test/controllers/admin/audit_logs_controller_test.rb` |
| T2 | `app/models/client.rb` · `app/services/promises/register_service.rb` · `app/controllers/app/clients_controller.rb` · `app/controllers/app/invoices_controller.rb` · `app/views/app/invoices/show.html.erb` · `app/services/recurring_invoices/issue_service.rb` (뒤 셋은 리뷰 반영 W-1 — 거부 거래처의 첫 안내 미예약) | `test/models/client_test.rb` · `test/services/promises/register_service_test.rb` · `test/controllers/app/clients_controller_test.rb` · `test/controllers/app/invoices_controller_test.rb` · `test/services/recurring_invoices/issue_service_test.rb` |
| T3 | `app/controllers/app/dashboards_controller.rb` · `app/queries/dashboards/`(신설 디렉터리) · `app/services/dashboards/`(신설 — 리뷰 반영 W-5 층 분리) · `app/services/reminders/dispatch_service.rb`(공개 메서드·스캔 상수 추가) · `app/views/app/dashboards/`(show.html.erb·파셜 4종) · `app/helpers/app/base_helper.rb` | `test/controllers/app/dashboards_controller_test.rb` · `test/controllers/app/dashboards_actions_test.rb` · `test/queries/dashboards/`(신설) · `test/services/dashboards/`(신설) · `test/services/reminders/dispatch_service_test.rb` · `test/system/app_dashboard_actions_test.rb`(신설) |

(소유권 표는 리뷰 반영 뒤의 최종 상태다. 2026-11-26 3-S 대조에서 소유 파일 간 불겹침은 유지됐다 — T2의 `invoices_controller.rb`·`invoices/show.html.erb`·`recurring_invoices/issue_service.rb`는 T1·T3 소유 파일과 겹치지 않는다.)

금지(전 태스크 공통): `config/routes.rb`(T0 외) · `db/` · `PRD.md`·`AGENTS.md` · `config/locales/*` · `test/fixtures/*` · `test/application_system_test_case.rb` · `test/test_helpers/*` · 다른 태스크의 소유 파일. 불가피하게 필요하면 수정하지 않고 보고서에 적는다(3-S에서 반영).

## 확정 규칙 (PRD v0.50에 기록 — AUTH-1.5 구현 확정·VIEW-7 보완·DASH-2 구현 확정·결정 기록 Q29~Q31)

### T1 회원 탈퇴

- **진입**: 설정(`/app/profile`) 최하단 위험 구역 「회원 탈퇴」. 기존 프로필 폼 밖의 별도 폼(`DELETE /app/profile`).
- **확인 절차**: ① 탈퇴 안내(되돌릴 수 없음·삭제 대상 목록)와 현재 상태 요약(미수 청구 N건·잔액 / 유료 Plus 종료일 / 잔여 수금 패스 N건) ② 이메일 직접 입력(AUTH-1.4 정규화와 같은 기준으로 일치해야 함) ③ 제출.
- **처리**: `Users::WithdrawalService.call(user:, confirm_email:, ip:)` — 트랜잭션 안에서 감사 로그(`member_withdrawal`, admin nil, 이메일 스냅샷) → `user.destroy!`(기존 연쇄 삭제: 세션·반복 청구·청구서·거래처·품목·구독·주문·수금 패스·공지 읽음·티켓·세금계산서). 뒤이어 세션 종료(기존 로그아웃 경로) → `/`로 303 + "탈퇴가 완료되었습니다…"(랜딩 레이아웃은 flash를 표시한다 — 확인함). 이메일 불일치·실패 → 설정 화면으로 303 + alert.
- **미수 청구가 있어도 탈퇴 가능**(본인 결정 — 화면에 건수·금액을 미리 보여 줌). 관리자 콘솔의 계정 삭제는 Q13대로 미수 시 차단을 유지.
- **유료 Plus·수금 패스**: 즉시 소멸, 이후 결제 없음(구독·빌링키 삭제), 남은 기간·잔여 이용권은 환불되지 않음 — 화면에 미리 고지.
- 탈퇴 뒤 청구 링크(`/b/…`)는 만료 안내. 남은 예약 잡은 `discard_on RecordNotFound`로 버려짐(기존). 같은 이메일·휴대폰으로 재가입 가능.
- **약관 제11조 정정**: ②항을 "탈퇴 시 이용 중인 유료 구독은 즉시 종료되며 이후 결제는 청구되지 않습니다. 탈퇴 시점에 남은 이용 기간에 대한 환불은 되지 않습니다."로(현행 "남은 이용 기간 종료 후 자동 결제가 중단"은 ①항의 즉시 삭제와 모순). ①항에 미수 청구 링크 폐기 명시.
- **오타 수정**: 같은 화면 "야간·주일(주말) 발송은…" → "야간·주말 발송은…".
- 범위 밖(후속·법무 검토): 개인정보처리방침의 "계약·결제 기록 5년 보존"과 탈퇴 시 주문 기록 삭제의 관계.

### T2 수신 거부 — 같은 회원 안에서 번호 단위

- **전파**: 채무자가 수신 거부를 접수하면, 접수된 거래처와 **같은 회원·같은 번호**(하이픈 제외 숫자 비교)인 다른 거래처에도 `refused_at`을 기록한다(같은 트랜잭션).
- **상속**: 거래처를 등록하거나 번호를 바꿔 저장할 때, 같은 회원의 같은 번호 거래처에 거부 이력이 있으면 `refused_at`을 물려받는다. 등록은 허용(청구서 발행·링크 직접 전달 가능)하고 안내 문구로 고지: "이 번호는 과거에 추가 안내 수신을 거부하여 받을돈 명의의 안내는 보내지 않습니다. 청구서 링크는 직접 전달해 주세요."
- **범위**: 회원 계정 안으로 한정. 다른 회원의 같은 번호 거래처에는 영향 없음(정당한 청구까지 막는 과잉 차단·회원 간 결합 방지).
- **되돌림 없음**: 거부 마킹은 지우지 않는다(기존 — 채무자 의사). 발송·화면 판정은 기존 `client.refused?`를 그대로 쓴다(전파로 일관).

### T3 대시보드 오늘의 액션 — 나머지 세 종

- **오늘 발송 예정**: 자격 있는 회원(Plus 체험 포함·수금 패스)의 미수 청구 중 오늘 14시 자동 안내가 나갈 건. 발송 대상·상한·보류·수신 거부 판정은 기존 단일 출처를 쓴다 — `Invoice.reminders_dispatchable` ∧ `DispatchService#scheduled_today_keys(invoice)`(신설 공개 메서드: 만기 예고 `invoice_notice`를 포함한 오늘 발송 스텝 전체. 기존 `steps_due_today`의 동작·결과는 불변). 카드: 발송할 안내 이름 + 액션 「보류하기」(기존 `suspend_reminders` 액션 재사용·확인창)·「청구서 확인」.
- **약속일 도래**: 최신 약속(`this_week`·`date_selected`)의 약속일이 오늘인 미수 청구. 카드: "오늘 입금 예정"·「청구서 확인」.
- **미열람 방치**: 발행 후 **3일** 이상 지났고 한 번도 열지 않은 미수 청구(상태 `issued`). 카드: 발행 후 경과 일수·「청구서 확인」.
- **표시**: PRD DASH-2 순서(오늘 발송 예정 → 약속일 도래 → 미열람 방치 → 마감 대기 → 답변 대기), 유형별 최대 5건(초과분은 "외 N건"과 청구서 목록 링크). Free 회원에게 "오늘 발송 예정"은 0건(자동 발송 없음 — 거짓 0건 카드 금지). 빈 화면 문구는 이제 참이 되므로 유지.
- **구조**: 조회는 Query Object(`app/queries/dashboards/` 3종 — 기존 `Reports::*Query` 관례), 컨트롤러가 `@변수`로 적재, 뷰는 카드형(DESIGN-5). 목록 1회 조회(N+1 방지).

## 동시성·검증 설계

- 동시성 상한 3: T1·T2·T3 동시 스폰(일반 모드 프로필 `badeuldon-developer`).
- **태스크별 테스트 DB**: 각 Developer는 `DATABASE_URL=sqlite3:tmp/parallel/<task-id>/test.sqlite3`로 자기 테스트를 격리 실행한다(사전 실측: 13 runs 0 failures·트리 무변경). 공유 `storage/test.sqlite3`를 동시에 쓰지 않는다.
- 자체 검증은 자기 소유 파일의 테스트만(전체 테스트·시스템 전체 금지). 범위 밖 회귀(신규 메서드 삽입 위치·암묵적 의존)는 3-S·7-S의 전체 테스트로 잡는다 — 지난 배치 교훈.
- 시스템 테스트는 3-S 뒤 통합 실행(개발 중에는 실행 금지 — Chrome·DB 충돌).

## 리스크

| 리스크 | 대응 |
|:--|:--|
| T1 파괴적 동작 | 본인만·이메일 입력 확인·감사 로그·되돌림 없음 고지. 컨트롤러 액션 10줄 이내 |
| T3가 핵심 `DispatchService`에 메서드 추가 | 기존 메서드 로직·결과 불변(기존 dispatch_service_test 무수정 통과) |
| T2 모델 콜백이 기존 거래처 생성·수정 경로에 영향 | 전파·상속은 `refused_at`이 있는 번호에만 동작. 전체 테스트로 회귀 확인 |
| 암묵적 전역 의존(locale·헬퍼) | 문구는 뷰에 직접(locale 파일 수정 금지). `base_helper.rb`는 T3만 수정 |
| 새 창작 문구(탈퇴 안내·약관·거래처 등록 안내·카드 문구) | Reviewer가 집중 검증(P1 톤·LP-12 금지 표현) |
| 법무: 결제 기록 보존 vs 탈퇴 시 삭제 | 이번 범위 밖 — 완료 보고에 후속으로 명시 |

## 파이프라인

0 → 1-P → ✅승인(배치 단위 1회·multiSelect) → 2(PRD v0.50 직렬) → T0(선행 결선·단독) → 3-P(T1∥T2∥T3) → 3-S(소유권 대조·rubocop·zeitwerk) → 4 → 5(태스크별 리뷰) → 6? → 7(테스트 보강) → 7-S(전체 테스트 1회·시스템) → 8(실행 검증) → 9(보고·문서).
