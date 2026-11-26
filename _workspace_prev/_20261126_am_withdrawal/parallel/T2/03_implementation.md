# 03_implementation — T2 수신 거부를 같은 회원 안에서 번호 단위로 (VIEW-7·Q30)

병렬 배치 3-P(2026-11-26) 산출물. `_workspace/01_plan.md`의 T2 확정 규칙과 PRD v0.50 §6.9 VIEW-7
"같은 회원 안에서 번호 단위(결정 기록 Q30)"를 구현했다. 소유 파일(화이트리스트)만 수정했다.

## 변경 파일

| 파일 | 변경 |
|:---|:---|
| `app/models/client.rb` | ① `#phone_digits` 신설(하이픈 제외 숫자 비교 키 — 전파·상속 공유) ② `before_save :inherit_refusal_from_same_phone` 콜백 — 같은 회원·같은 번호(숫자 비교)·거부 이력 있으면 `refused_at`을 물려받음 ③ `attr_reader :refusal_inherited` — 이번 저장에서 상속 발생 플래그 |
| `app/services/promises/register_service.rb` | `apply_reminder_state` refusal 분기에 전파 추가 — 접수 거래처 마킹(기존 `update_column`) 뒤 `propagate_refusal_to_same_phone`: 같은 회원·같은 번호·미거부 거래처에 `update_all(refused_at: Time.current)`. `call`의 기존 트랜잭션 안에서 실행. 헤더·분기 주석 갱신 |
| `app/controllers/app/clients_controller.rb` | create·update의 notice를 `client_saved_notice(client, created:)` private 메서드로 분기 — 상속이 일어난 저장은 고지 문구로 대체, 없으면 기존 문구 그대로. 액션 본문 준수(각 9줄) |
| `test/models/client_test.rb` | 4건 추가 — 하이픈 형식 차이 흡수 상속 / 다른 회원·다른 번호 무상속 / 번호 변경 수정에서 상속 / 이미 거부된 거래처 마킹 유지(되돌림 없음) |
| `test/services/promises/register_service_test.rb` | 3건 추가 — 같은 회원·같은 번호 전파(하이픈 섞임) / 다른 회원 같은 번호 무영향 / 같은 회원 다른 번호 무영향. refusal 인큐 검증은 기존 패턴(`assert_enqueued_with` — 실호출 없음) |
| `test/controllers/app/clients_controller_test.rb` | 3건 추가 — 상속 등록(303·고지 문구·`refused?` 참) / 상속 수정(고지 문구) / 무상속 등록·수정은 기존 문구 유지 |

기존 테스트는 전부 무수정 유지했다(회귀 포함 실행 확인 — 아래).

## Rule ID 매핑

- **VIEW-7·Q30 전파**: 채무자 refusal 접수 시 접수 거래처만이 아니라 같은 회원의 같은 번호(하이픈 제외 숫자 비교) 거래처 전부에 `refused_at` 기록 — `Promises::RegisterService#propagate_refusal_to_same_phone`. 다른 회원 무영향(과잉 차단·회원 간 결합 방지), 같은 트랜잭션.
- **VIEW-7·Q30 상속**: 같은 번호로 거래처를 등록·수정하면 거부 상태를 물려받음 — `Client#inherit_refusal_from_same_phone`. 등록은 허용(청구서 발행·링크 직접 전달 가능), 발송 차단은 기존 `SendService` REFUSED 가드가 `client.refused?`로 처리(수정 없음).
- **되돌림 없음(P1)**: 이미 기록된 `refused_at`은 콜백이 지우지 않음 — 번호를 바꿔도 유지(테스트로 고정).
- **PROMISE-2·P4 기존 동작 불변**: promise 기록·INV-4 전이·`finish_sequence!`·`noti_refusal` 인큐 경로 무수정(전파는 마킹 뒤 삽입).

## 사용자 가시 문구 전문 (컨트롤러 flash notice — locale 미사용)

- create + 상속: `거래처가 등록되었습니다. 이 번호는 과거에 추가 안내 수신을 거부하여 받을돈 명의의 안내는 보내지 않습니다. 청구서 링크는 직접 전달해 주세요.`
- update + 상속: `거래처 정보가 수정되었습니다. 이 번호는 과거에 추가 안내 수신을 거부하여 받을돈 명의의 안내는 보내지 않습니다. 청구서 링크는 직접 전달해 주세요.`
- 무상속: 기존 문구 그대로(`거래처가 등록되었습니다.` / `거래처 정보가 수정되었습니다.`)

지시서 create 문구의 "과과에"는 01_plan.md·update 문구의 "과거에"과 대조해 오타로 판정하고 "과거에"로 통일했다.

## 실행한 검증

- `mkdir -p tmp/parallel/T2` 후 전용 DB로 격리 실행:
  `DATABASE_URL=sqlite3:tmp/parallel/T2/test.sqlite3 bin/rails test test/models/client_test.rb test/services/promises/register_service_test.rb test/controllers/app/clients_controller_test.rb`
  → **70 runs, 368 assertions, 0 failures, 0 errors, 0 skips** (기존 63건 + 신규 10건 — 기존 회귀 없음)
- `bin/rubocop` (소유 6파일) → **6 files inspected, no offenses detected**
- `bin/rails zeitwerk:check` → 통과("all is good")

## 판정이 필요했던 부분

1. **콜백 선택 — `before_save`**: 검증(형식) 통과 후 실행되므로 번호는 숫자·하이픈만 보장되고, 신규 생성과 번호 변경 수정을 하나의 조건("refused_at 비어 있고 같은 번호 거부 이력 존재")으로 처리한다. 전화번호가 그대로인 저장에서도 무해(상속 조건은 번호·거부 이력에만 의존 — 멱등). 기존 모델 스타일(선언은 public 영역, 구현은 `private def`)을 따랐고 콜백은 1개 유지(규약 "콜백 3개 이하").
2. **SQL 비교 방식 — `replace(phone, '-', '')`**: 형식 검증(`/\A\d{2,3}-?\d{3,4}-?\d{4}\z/`)이 하이픈·숫자만 허용하므로 gsub 결과와 일치한다. 서비스·모델 모두 `Client#phone_digits` 단일 출처를 사용해 양쪽 기준이 어긋나지 않게 했다. 인덱스 불요(회원당 거래처 소수 — 풀스캔 무해, 마이그레이션 불요).
3. **전파 성격**: `update_all(refused_at: Time.current)` — 접수 마킹(`update_column`)과 같은 성격의 검증·콜백 우회 마킹. `call`의 `ActiveRecord::Base.transaction` 안에 있어 promise 기록·접수 마킹·전파·시퀀스 종결이 함께 확정된다. `where(refused_at: nil)`이라 재접수 시에도 멱등.
4. **오타 판정**: 지시서 create 문구 "과과에" → "과거에"(plan·update 문구와 대조).

## 범위 밖 수정 요청 (실행하지 않음 — 통합 단계에서 판단)

1. `app/services/reminders/send_service.rb` 등 발송 가드·화면의 `refused?` 판정 약 15곳 — **수정 불요가 설계 의도다**(전파·상속으로 `refused_at`이 일관되게 채워지므로 기존 가드가 그대로 번호 단위로 동작). 단, 다른 태스크 파일이라 확인만 했다.
2. `LAUNCH_TEST_SCENARIOS.md`의 F-07(수신 거부) — "거래처 행 단위" 서술이 있다면 Q30 반영 서술(번호 단위)로 갱신 대상. 02_prd_update에 이미 문서 계획이 있으므로 Phase 9에서 자연 반영 예상.

## 남은 우려

- 모델 콜백이 **모든 거래처 저장 경로**에서 실행된다(등록·수정·관리 콘솔 경로 포함). 거부 이력이 있는 번호가 아니면 즉시 반환되어 무해하지만, 3-S·7-S의 전체 테스트로 회귀를 확인해야 한다(플랜의 리스크 대응과 동일).
- `refusal_inherited` 플래그는 마지막 save 기준 값이다(비상속 저장에서 false로 리셋) — 컨트롤러는 저장 직후에만 읽으므로 문제 없음.
- 전파는 발송 기록(message_logs)을 소급하지 않는다 — 이미 보낸 안내는 남고 이후 발송만 차단된다(P4·기존 refusal 동작과 동일).

## 리뷰 반영(6차) — W-1·W-3·W-4

`_workspace/05_review.md` T2 절의 WARNING 중 처리 대상 3건(W-1·W-3·W-4)을 반영했다.
W-2는 이번 배치 허용·PRD 기록됨(「알려진 한계」 — 02_prd_update 경유), W-5는 Tester 담당, W-6은 운영 확인이므로 다루지 않았다.

### 변경 파일

| 파일 | 이슈 | 변경 |
|:---|:---|:---|
| `app/models/client.rb` | W-3·W-4 | ① `scope :same_phone_digits` 신설 — 전파·상속의 번호 비교 단일 출처 ② `#phone_digits`를 `gsub(/\D/)` → `to_s.delete("-")`로(SQL 정규화와 같은 함수 — 형식 검증이 숫자·하이픈만 허용하므로 결과 불변) ③ 상속 콜백 본문이 스코프를 쓰도록(`siblings.same_phone_digits(phone_digits).first`) ④ 콜백 주석을 실제 동작(「모든 저장 — 번호 변경 여부 무관」, W-3 리뷰 판정의 행 단위 시절 데이터 바로잡기 역할 명시)과 맞춤. **동작 무변경** |
| `app/services/promises/register_service.rb` | W-4 | `propagate_refusal_to_same_phone`의 raw SQL `replace(phone, '-', '')`을 `same_phone_digits` 스코프 체인으로 교체(주석도 단일 출처 명시로 갱신). 동작 무변경 |
| `app/views/app/invoices/show.html.erb` | W-1 | 초안 상세 발행 폼 — `@invoice.client.refused?`면 send_notice 체크박스(hidden 쌍 포함)·라벨 전부 미렌더하고 안내 상자(거부 접수 배너와 같은 중립 톤 — `bg-stone-50`·`ring-stone-200`, bold 제목 + 본문 2단 구성)를 렌더한다. 발행 폼·확인 대화창·버튼은 유지(발행 자체는 계속 가능). 미거부는 기존 체크박스 그대로 |
| `app/controllers/app/invoices_controller.rb` | W-1 | `issue`의 인큐 조건을 private `enqueue_issue_notice_if_needed`로 분리 — 거래처 수신 거부면 체크 파라미터와 무관하게 `issue_notice` 인큐를 건너뛴다(SendService 창 판정 `reschedule!`가 REFUSED 가드보다 앞서 생기는 「발송 예정」 pending 행 잔존을 예약 단계에서 차단 — REFUSED 가드는 최종 방어선으로 유지). `issue_success_notice`에 거부 거래처 분기 추가. 액션 본문 3줄 유지 |
| `app/services/recurring_invoices/issue_service.rb` | W-1 | `enqueue_notifications` — 발행(:issued) 시 거래처 수신 거부면 `issue_notice`를 건너뛰고 U1 통보(`noti_recurring_issued`)는 그대로 인큐. 인큐 1통을 `enqueue_issue_notice` private 메서드로 추출해 컨트롤러와 동일 판정임을 주석으로 명시. 발행·advance!·hold! 경로 무변경 |
| `test/models/client_test.rb` | W-3 | 메모만 수정한(번호 무변경) 저장에서도 상속되는 테스트 1건 추가 — 행 단위 시절 데이터 재현(같은 번호 형제를 먼저 생성한 뒤 원본만 거부 마킹) 후 `update!(memo:)`로 상속·시각·플래그 고정 |
| `test/controllers/app/invoices_controller_test.rb` | W-1 | 3건 추가 — ① 미거부 발행(체크 파라미터)은 `issue_notice` 인큐(`assert_enqueued_with` args 고정) ② 거부 거래처 발행(체크 파라미터 있음)은 DeliverJob 인큐 0건 + 거부 안내 flash + 발행은 계속 성공 ③ 거부 거래처 초안 상세 GET은 `input[name=send_notice]` 0건·체크박스 라벨 0건·안내 문구 2줄·발행 버튼 유지. 클래스에 `ActiveJob::TestHelper` include 추가 |
| `test/services/recurring_invoices/issue_service_test.rb` | W-1 | 거부 거래처 스케줄 발행 시 DeliverJob 인큐가 U1 통보 1건뿐이고 `issue_notice`(debtor)가 없음을 고정(발행·advance는 정상) |

`SendService`·`DispatchService`·routes·마이그레이션은 손대지 않았다(가드 순서 변경 금지 준수).
`test/controllers/app/clients_controller_test.rb`·`test/services/promises/register_service_test.rb`는 이번 반영에서 변경 없음(기존 10건이 W-4 단일화 회귀를 그대로 감시한다).

### 새 사용자 가시 문구 전문

- **발행 폼 안내 상자(초안 상세 — 거부 거래처만, 체크박스 대체)**:
  - 제목(bold): `이 거래처는 추가 안내 수신을 거부하여 받을돈 명의의 첫 안내는 보내지 않습니다`
  - 본문: `청구서 링크를 복사해 직접 전달해 주세요.`
  - (지시서 문장을 기존 거부 배너와 같은 제목+본문 2단 구성으로 렌더한 것 — 문장 전체는 지시서 전문과 동일)
- **발행 결과 flash(거부 거래처)**: `청구서가 발행되었습니다. 이 거래처는 추가 안내 수신을 거부하여 첫 안내는 보내지 않습니다. 링크를 복사해 거래처에 직접 전달하세요.`
- 미거부 거래처의 기존 문구(체크 켬/끔)는 무변경.

### Rule ID 매핑(리뷰 반영분)

- **VIEW-7·Q30(W-1)**: 수신 거부(상속 포함) 거래처의 청구는 발행 폼에 첫 안내 체크박스 대신 안내를 보이고 첫 안내(발행 안내·반복 청구 발행 안내)를 예약하지 않는다 — PRD v0.50 VIEW-7 문언 그대로. 컨트롤러·반복 청구 서비스 양쪽 진입점에서 인큐를 건너뛰고, `SendService` REFUSED 가드는 유지(이중 방어).
- **W-3**: 콜백 동작 유지(리뷰 판정 준수), 주석·테스트만 실제 동작(모든 저장)과 정합화.
- **W-4**: 번호 비교 SQL·Ruby 정규화를 `Client.same_phone_digits` 스코프 + `#phone_digits`(delete)로 단일화.

### 실행한 검증

- `mkdir -p tmp/parallel/T2` 후 전용 DB 격리 실행:
  `DATABASE_URL=sqlite3:tmp/parallel/T2/test.sqlite3 bin/rails test test/models/client_test.rb test/services/promises/register_service_test.rb test/controllers/app/clients_controller_test.rb test/controllers/app/invoices_controller_test.rb test/services/recurring_invoices test/services/reminders/send_service_test.rb`
  → **174 runs, 1,059 assertions, 0 failures, 0 errors, 0 skips** (신규 5건 포함 — send_service_test는 회귀 확인용)
- `bin/rubocop` (소유 10파일) → **10 files inspected, no offenses detected**
- `bin/rails zeitwerk:check` → 통과("all is good")
- 내 실행 범위 밖 회귀 정적 확인 — `invoices_reminders_test.rb`의 SHARE-6 3건·`payments_controller_test.rb`의 발행 건은 전부 미거부 거래처라 기존 경로(무변경), 거부 시스템 테스트 3건(`app_invoice_reminders_test.rb`·`viewer_refusal_test.rb`)은 발행 계열 초안 폼을 쓰지 않아 무영향.

### 남은 우려

- 발행 폼의 거부 안내는 `@invoice.client.refused?` 시점 판정이라, 상세 열람 뒤 거래처가 거부하면(다른 청구의 refusal 전파) 발행 시점에는 안내 없이 폼이 나올 수 있다 — 이때도 컨트롤러가 인큐를 건너뛰고 flash로 거부 안내를 주므로 발송은 나가지 않는다(422 재렌더가 아니라 303 redirect라 재렌더 화면에는 거부 배너가 이미 존재).
- W-6(기존 행 단위 시절 데이터 소급)은 배포 시점 운영 확인 과제로 그대로 남는다.
