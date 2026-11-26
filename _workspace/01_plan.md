# 01_plan — 병렬 배치(절약): 남은 후속 — 판단 위임 (2026-11-26, lite 모드·parallel)

## 배경

사용자: "남은 후속을 알아서 판단해서 진행해주세요. 현재 운영 서버의 계정들은 100프로 테스트 계정들입니다. 관련 정보들은 다 삭제해도됩니다."

### 사용자 발언으로 해소된 것 (문서 반영 — 코드 변경 없음)
1. **결정 필요 ①(약관 제11조 당일 시행 vs 제14조 30일 공지) → 해소.** 운영 회원 9개가 전부 테스트 계정이므로 "개정 전 약관으로 계약한 실제 회원"이 없다 — 2026-11-26 당일 공고·시행과 부칙 문장("정식 오픈 전 공고·같은 날 시행, 이후 개정은 제14조 ②")이 그대로 유효하다. 약관 수정 없음. 런칭 테스트 문서 §1-7·체크리스트 §8-6을 "확인 완료"로 갱신한다.
2. **운영 테스트 계정·데이터 삭제 — 지금은 실행하지 않는다.** 삭제 허용은 받았지만(되돌릴 수 없는 운영 데이터 삭제) 런칭 테스트 계획이 기존 Plus 계정을 U1-C로 쓰고 있어 지우면 테스트 준비가 깨진다. 런칭 테스트의 정리 단계(`LAUNCH_TEST_CHECKLIST.md` §6) 또는 별도 요청 때 실행하는 것이 맞다고 판단했다.

### 오케스트레이터 판단 — 이번 배치에 넣을 것 (코드)
직전 두 배치의 완료 보고가 남긴 후속 중 **코드로 바로 되고 리스크가 관리 가능한 것** 4건.

| ID | 태스크 | Rule ID | 규모 | 왜 하는가 |
|:--|:--|:--|:--|:--|
| T1 | **감사 로그 IP — 서비스 계층 12곳 보완**: 서비스가 감사를 남길 때 컨트롤러의 `ClientIp.of(request)` 값을 전달받아 기록 | ADMIN-2·Q32 | Standard | 오후 배치 T2에서 컨트롤러 계층은 통일했으나 서비스 계층(`payments/record_service`·`admins/{role,member_admin,account_purge}_service`·`orders/refund_service`)은 IP가 비어 있다 |
| T2 | **수신 거부 레거시 nil 폴백 제거**: `refused_phone`이 없는 거부 행을 상속 원천으로 보던 방어 경로를 없애고, 테스트의 단독 마킹을 헬퍼로 통일 | VIEW-7·Q30 | Small | 운영엔 nil 행이 없고(T4 소급) 폴백은 "우회 마킹이 옛 한계를 부활시켜도 통과시키는" 기술 부채 — 리뷰가 2단계 제거를 권고 |
| T3 | **탈퇴·계정 삭제 시 결제 기록 비식별 보관(5년)**: 회원 행이 삭제될 때 주문(결제·환불)의 **식별 불가능한 사본**을 별도 테이블에 남기고 5년 뒤 파기 | AUTH-1.5·ADMIN-3, 개인정보방침 §3 | Standard+마이그레이션 1건 | 결정 필요 ②(법정 5년 보존 vs 탈퇴 시 삭제)의 구현 — 오후 보고에서 "주문을 식별 불가능하게 바꿔 보관"을 권장했던 안. 방침 §3이 이미 "계약·결제 기록 5년 보존"을 예외로 못박고 있어 코드가 방침을 따르게 한다 |
| T4 | **기술 부채 2건**: 픽스처 가드 강화(ERB와 같은 줄에 섞인 날짜·슬래시·점 날짜도 탐지) + 대시보드 서비스 헤더 주석 2중화 정리 | (테스트 자산) | Fast | 리뷰 O-2·메모 |

### 판단상 이번 배치에서 **빼는 것**
| 후속 | 빼는 이유 |
|:--|:--|
| 시작 09시 좁은 창 회원의 **전날 사전통보** | 알림톡 템플릿 문구("오늘 … 발송 예정")가 내일 발송과 맞지 않아 **새 템플릿 등록·솔라피 검수**(외부 서비스·검수 주기)가 필요한 제품 변경 — 자동 배치로 진행할 성격이 아님. 현행은 대시보드 카드가 취소 창을 제공(PRD REM-11 기록) |
| 대시보드 후보별 쿼리 수 최적화 | 후보가 날짜 범위로 좁혀져 실영향이 작고, 발송 심장부(`DispatchService`)에 배치 조회 경로를 추가하는 리스크가 큼 |
| 티켓(분쟁 처리) 기록 3년 보관 | 티켓 본문은 개인정보를 품어 비식별화 기준 설계가 필요(법무) — T3는 구조화된 결제 기록으로 한정 |
| 운영 테스트 계정 삭제 | 위 2번 |

## 병렬 안전 판정 (§6.14 3조건)

| 조건 | 판정 | 근거 |
|:--|:--|:--|
| 1. 파일 소유권 분리 | **충족** | 아래 표. 단 **T1·T3이 모두 계정 삭제 경로와 관련**하나 — T1은 서비스 인자(`ip:`)만, T3은 `User` 모델 콜백만 건드려 파일이 겹치지 않는다(`account_purge_service.rb`는 T1 소유, T3은 무수정) |
| 2. 의존 없음 | **충족** | 서로의 산출물을 참조하지 않음 |
| 3. 공유 파일 비수정 | **충족** | 마이그레이션·`config/recurring.yml`은 T3 단독. routes·PRD·AGENTS·progress.json은 태스크가 직접 수정하지 않음 |

## 파일 소유권 표

| 태스크 | 앱 코드 | 테스트 |
|:--|:--|:--|
| T1 | `app/services/payments/record_service.rb` · `app/services/admins/role_service.rb` · `app/services/admins/member_admin_service.rb` · `app/services/admins/account_purge_service.rb` · `app/services/orders/refund_service.rb` · 호출처: `app/controllers/app/payments_controller.rb` · `app/controllers/admin/base_controller.rb` · `app/controllers/admin/admins_controller.rb` · `app/controllers/admin/members_controller.rb` · `app/controllers/admin/orders_controller.rb` | `test/services/payments/` · `test/services/admins/` · `test/services/orders/` · `test/controllers/admin/{admins,members,orders}_controller_test.rb` · `test/controllers/app/payments_*_test.rb` |
| T2 | `app/models/client.rb` | 신설 `test/test_helpers/refusal_test_helper.rb` + `test/test_helper.rb`(require 1줄) · 단독 마킹을 쓰는 테스트(아래 목록) · `test/models/client_test.rb`(센서 테스트 반전) |
| T3 | `db/migrate/`(신설 1건) · `db/schema.rb` · `app/models/withdrawn_payment_record.rb`(신설) · `app/models/user.rb`(콜백 1개) · `app/jobs/withdrawn_payment_records/purge_job.rb`(신설) · `config/recurring.yml` | 신설 `test/models/withdrawn_payment_record_test.rb` · `test/jobs/withdrawn_payment_records/` · `test/services/users/withdrawal_service_test.rb` |
| T4 | `app/services/dashboards/reminder_actions_service.rb`(**주석만**) | `test/fixtures_no_future_date_test.rb` |

금지(전 태스크 공통): `config/routes.rb` · `db/`(T3 외) · `PRD.md`·`AGENTS.md`·런칭 테스트 문서 · `config/locales/*` · `test/fixtures/*` · `config/recurring.yml`(T3 외) · 다른 태스크의 소유 파일.

## 확정 규칙 (Phase 2에서 PRD에 기록)

### T1 서비스 계층 감사 IP
- 서비스 진입점에 선택 인자 `ip: nil`을 추가하고 서비스 안의 `AuditLogs::RecordService.call`에 `ip:`를 넘긴다. 컨트롤러 호출처는 `ip: ClientIp.of(request)`를 넘긴다.
  - `Payments::RecordService.new(invoice:, amount:, paid_on:, notify_thanks: true, ip: nil)` — 입금 기록은 회원 행위(감사 액션은 기존 그대로).
  - `Admins::RoleService.create_admin!`·`change_role!`·`unlock!`·`record_denied!`에 `ip:`.
  - `Admins::MemberAdminService.toggle_suspension!`·`change_plan!`에 `ip:`.
  - `Admins::AccountPurgeService.call(admin:, user:, confirm_email:, ip: nil)`.
  - `Orders::RefundService.new(admin:, order:, reason:, client:, ip: nil)` — 감사 3종(attempt·failed·refund)에 기록.
- 인자를 주지 않는 호출(runner·기존 테스트)은 기존대로 nil — 기존 테스트가 깨지지 않아야 한다. 액션 본문 10줄 이내 유지.

### T2 수신 거부 폴백 제거
- `Client#inherit_refusal_from_same_phone`의 2순위 폴백(`.or(siblings.where(refused_phone: nil).same_phone_digits(phone_digits))`)을 **삭제** — 상속 원천은 `refused_phone == phone_digits`만. `refused_phone`이 없는 거부 행은 자기 자신만 거부(발송 차단은 유지)이고 상속을 퍼뜨리지 않는다(덜 차단하는 안전한 방향).
- 테스트 공용 헬퍼 `mark_refused(client, at: Time.current)`(`update_columns(refused_at:, refused_phone: client.phone_digits)`)를 신설하고 `test/test_helper.rb`에서 require. `update_column(:refused_at, …)` 단독 마킹을 쓰는 테스트를 전부 헬퍼로 교체(상속을 기대하는 시나리오가 정상 작동하도록). 파일: `test/queries/dashboards/todays_sends_query_test.rb` · `test/models/client_test.rb` · `test/models/invoice_test.rb` · `test/system/viewer_refusal_test.rb` · `test/system/app_invoice_reminders_test.rb` · `test/controllers/viewer_refusal_test.rb` · `test/controllers/app/invoices_controller_test.rb` · `test/controllers/app/clients_controller_test.rb` · `test/controllers/app/invoices_reminders_test.rb` (grep으로 전수 확인).
- "폴백 센서" 테스트(`client_test.rb`)는 뜻을 반전해 **"refused_phone 없는 단독 마킹 행은 상속 원천이 아니다"**를 고정.

### T3 결제 기록 비식별 보관
- 트리거: `User`의 `before_destroy`(**`prepend: true`** — `has_many :orders, dependent: :destroy`보다 먼저 실행돼야 주문이 지워지기 전에 사본을 남긴다). 회원 탈퇴(`Users::WithdrawalService`)·관리자 계정 삭제(`Admins::AccountPurgeService`)가 모두 `user.destroy!`를 쓰므로 **두 경로가 한 콜백으로 보장**된다. 같은 트랜잭션 안.
- 테이블 `withdrawn_payment_records`(식별 정보 없음): `product`(int) · `item_type`(int) · `amount`(int) · `status`(int) · `pg_order_id`(string, 유니크 — 멱등) · `pg_payment_id`(string) · `order_created_at` · `paid_at` · `refunded_at` · `withdrawn_at`(not null) · timestamps. **넣지 않는 것**: `user_id`·이메일·이름·전화번호·`pg_billing_key`·`metadata`(구매자 정보 포함 가능)·`refund_reason`(자유 텍스트).
- 모델 `WithdrawnPaymentRecord`: `self.archive!(user)` — `user.orders` 각 행을 위 컬럼으로 복사(`insert_all`·`pg_order_id` 유니크로 멱등 — `on_duplicate_skip`는 SQLite에서 미지원이면 `insert_all(..., record_timestamps: true)` 후 `ActiveRecord::RecordNotUnique` 구조가 아니면 find_or_create_by — 안전한 방식을 Developer가 테스트로 확인), `scope :expired`(withdrawn_at < 5년 전). 관리 화면은 만들지 않는다(콘솔·runner로 조회 — 문서에 조회 예시 기록).
- 파기: `WithdrawnPaymentRecords::PurgeJob`(만료 행 삭제·건수만 로그) + `config/recurring.yml` 매일 04:35 KST(production·development).
- 보존 기간은 **탈퇴 시점부터 5년**(법정 기간의 가장 보수적인 기준). 마이그레이션은 이 배치의 유일한 것.

### T4 기술 부채
- `test/fixtures_no_future_date_test.rb`: ERB 태그가 섞인 줄은 **줄 전체를 건너뛰지 말고 ERB 태그 부분만 제거한 뒤 검사**, 날짜 구분자 `-`·`/`·`.` 모두 탐지. 현재 픽스처가 모두 통과해야 함.
- `app/services/dashboards/reminder_actions_service.rb` 헤더의 ①② 규칙 설명(11~22행)을 `Reminders::SendSchedule`로 안내하는 짧은 포인터로 축소(코드 변경 없음).

## 동시성·검증 설계
- 동시성 상한 3: 웨이브 1 = T1·T2·T3, T4는 먼저 끝난 슬롯에 스폰.
- 태스크별 전용 테스트 DB `tmp/parallel/<task-id>/test.sqlite3`. T3의 마이그레이션은 전용 개발 DB에만 적용해 `db/schema.rb` 갱신, 통합 단계에서 개발 DB에 1회 적용.
- 리뷰어는 reviewer-lite(GLM-5.3-Flash/max — 오후 실측), 테스터는 tester-lite.

## 리스크

| 리스크 | 대응 |
|:--|:--|
| T3 콜백 순서 — `prepend: true`를 빠뜨리면 주문이 먼저 삭제돼 사본이 0건 | 지시서에 명시, 모델 테스트로 "탈퇴 후 보관 행 수 == 탈퇴 전 주문 수" 단언, 리뷰 집중 |
| T3가 개인정보를 보관 테이블에 복사하는 것 | 컬럼 화이트리스트를 지시서에 명시, 테스트로 `user_id`·이메일·빌링키·metadata가 보관 행에 없음을 단언 |
| T2 폴백 제거로 단독 마킹 테스트가 깨짐 | 헬퍼 일괄 교체 + 전체 대상 파일 실행, 깨진 것은 헬퍼로 해결(앱 로직 추가 금지) |
| T1 서비스 시그니처 변경의 파급 | `ip:`는 선택 인자(기본 nil) — 인자 없는 기존 호출·테스트는 무변경 통과 |
| 법적 해석(T3 보관 기준·식별 불가능성) | 오케스트레이터·리뷰어 판단은 코드·방침 정합 기준 — 법무 확인 권장을 보고에 명시 |

## 파이프라인
0 → 1-P → ✅승인(multiSelect) → 2(PRD v0.52 직렬) → 3-P(웨이브 1: T1·T2·T3 → T4) → 3-S(소유권·마이그레이션 1회·rubocop·zeitwerk) → 5 리뷰(4건 병렬) → 6? → 7 테스터 보강 → 7-S(`bin/ci`·시스템) → 8 실행 검증 → 9 문서·보고(약관 시행일 결정 해소 반영 포함).
