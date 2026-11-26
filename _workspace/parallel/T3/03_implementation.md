# 03_implementation — T3: 회원 삭제 시 결제 기록 비식별 보관 5년 (AUTH-1.5·ADMIN-3·Q33)

작성: badeuldon-developer-lite (병렬 배치 웨이브 1) · 2026-11-26

## 변경 파일 (소유 파일만)

| 파일 | 변경 |
|:--|:--|
| `db/migrate/20261126090000_create_withdrawn_payment_records.rb` | 신설 |
| `db/schema.rb` | 이 마이그레이션 반영(전용 dev DB에서 적용 — 아래 주의 참조) |
| `app/models/withdrawn_payment_record.rb` | 신설 |
| `app/models/user.rb` | 콜백 1개 + private 메서드 1개만 추가(연관 선언·기존 코드 무변경) |
| `app/jobs/withdrawn_payment_records/purge_job.rb` | 신설 |
| `config/recurring.yml` | production·development 1잡씩 2블록 추가 |
| `test/models/withdrawn_payment_record_test.rb` | 신설 (7테스트) |
| `test/jobs/withdrawn_payment_records/purge_job_test.rb` | 신설 (4테스트) |
| `test/jobs/withdrawn_payment_records/recurring_registration_test.rb` | 신설 (1테스트) |
| `test/services/users/withdrawal_service_test.rb` | "정상 탈퇴" 테스트에 주문 1건 추가 + 보관 단언 추가(기존 단언 유지) |

**주의(db/schema.rb)**: 작업 시점에 T2의 마이그레이션(`20261126050721_add_refused_phone_to_clients`)이
이미 워크트리에 pending 상태로 있어, 전용 dev DB 마이그레이션 시 `db/schema.rb` diff에
T2 분(`refused_phone` 컬럼)이 함께 포함된다. T3 신설분은 `withdrawn_payment_records` 테이블
+ `version: 2026_11_26_090000` 승격뿐이다 — 통합 단계(3-S)에서 자연 해소.

## 마이그레이션 전문

```ruby
class CreateWithdrawnPaymentRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :withdrawn_payment_records do |t|
      # Order의 enum 정수값을 그대로 복사한다(값 의미는 Order 모델 단일 출처).
      t.integer :product, null: false
      t.integer :item_type, null: false
      t.integer :amount, null: false
      t.integer :status, null: false
      # 보관 멱등 키 — 원본 주문의 PG 주문번호(식별자가 아닌 주문번호).
      t.string :pg_order_id, null: false
      t.string :pg_payment_id
      t.datetime :order_created_at
      t.datetime :paid_at
      t.datetime :refunded_at
      # 보존 기준일(탈퇴 시각) — 5년 경과분 파기 범위 조회 인덱스.
      t.datetime :withdrawn_at, null: false

      t.timestamps null: false
    end

    add_index :withdrawn_payment_records, :pg_order_id, unique: true
    add_index :withdrawn_payment_records, :withdrawn_at
  end
end
```

## 콜백 위치와 prepend 근거

`app/models/user.rb` — `belongs_to :referred_by_sales_rep` 직후(Association 블록 끝):

```ruby
before_destroy :archive_payment_records, prepend: true
```

`prepend: true`가 없으면 `has_many :orders, dependent: :destroy`가 먼저 실행돼 주문이 이미
지워진 뒤 콜백이 돌고 사본이 0건이 된다. `User.destroy!` 경로는 2개 — 회원 탈퇴
(`Users::WithdrawalService`, 수정 금지·무변경)와 관리자 계정 삭제(`Admins::AccountPurgeService`,
수정 금지·무변경)이며 콜백 한 곳으로 두 경로가 공통 보장된다. private
`archive_payment_records` → `WithdrawnPaymentRecord.archive!(self)` — Model→Model 참조만
(서비스 호출 없음, §4.2 준수). 같은 트랜잭션 안에서 실행되므로 destroy 실패·롤백 시 보관 행도
원복된다(테스트 ⑧로 고정).

## 멱등 구현 방식 (테스트 근거)

`insert_all(..., unique_by:)`의 SQLite 지원 여부에 의존하지 않고 **사전 제외 방식**을 택했다:

```ruby
already_archived = where(pg_order_id: user.orders.select(:pg_order_id)).pluck(:pg_order_id)
rows = user.orders.where.not(pg_order_id: already_archived).map { ... }
return 0 if rows.empty?
insert_all(rows, record_timestamps: true)
```

- 유니크 인덱스가 이중 방어(경합 시 `ActiveRecord::RecordNotUnique` — 재시도해도 유니크로 흡수).
- 테스트: `WithdrawnPaymentRecord.archive!(user)` 두 번 호출 → 두 번째 0건·count 1(모델 테스트 ⑤).
- 원본 enum 값은 `order.read_attribute(:product)` 등으로 **정수값**을 직접 복사(enum 문자열
  매핑에 의존하지 않음).

## 컬럼 화이트리스트 대조표 (Q33)

| Order 컬럼 | 보관 테이블 | 비고 |
|:--|:--|:--|
| product / item_type / amount / status | O (int) | enum 정수값 그대로 |
| pg_order_id | O (유니크) | 주문번호 — 멱등 키·식별자 아님 |
| pg_payment_id | O | PG 결제번호 |
| created_at | O → order_created_at | |
| paid_at / refunded_at | O | |
| withdrawn_at | O (not null) | 보존 기준일 = 탈퇴 시각 |
| **user_id** | **X** | 회원 식별자 — 테스트로 부재 단언 |
| **pg_billing_key** | **X** | 빌링키 |
| **metadata** | **X** | 구매자 정보(invoice_id 등) 포함 가능 |
| **refund_reason** | **X** | 자유 텍스트 |
| 이메일·이름·전화번호 등 User 컬럼 | **X** | 테스트로 보관 행 문자열 컬럼에 개인정보 문자열 부재 단언 |

## enum 공유 방식

Order의 enum 리터럴을 동일 값으로 선언하고 주석으로 "Order 모델이 단일 출처 — 값 변경 시
양쪽 동기화 필수"를 명시했다(`Order.products` 해시 참조 공유보다 autoload·마샬링 이슈가 없는
단순한 방식). 접두어 충돌 없음(`product`·`status`·`item_type`).

## 테스트 결과

```
DATABASE_URL=sqlite3:tmp/parallel/T3/test.sqlite3 bin/rails test \
  test/models/withdrawn_payment_record_test.rb \
  test/jobs/withdrawn_payment_records test/services/users
→ 27 runs, 237 assertions, 0 failures, 0 errors, 0 skips
```

- 모델 7: ① 상태 4종(paid·pending·failed·cancelled) 섞은 주문 N건 → N건 보관·전 컬럼 일치
  (prepend 누락 시 이 테스트가 깨진다 — 주석 명시) ② 컬럼 화이트리스트 + 개인정보 문자열 부재
  ③ 원본 Order 연쇄 삭제 유지 ④ 주문 0건 → 보관 0건 ⑤ 멱등 ⑥ expired 경계(4y364d 유지·
  5y+1s 만료, travel_to) ⑧ 트랜잭션 롤백 원복
- 잡 4: 5년 경과만 삭제·경계 ±1초·재실행 멱등·로그 건수만(주문번호 값 부재)
- recurring 등록 대조 1: production·development 04:35 KST
- 서비스: 탈퇴 뒤 Order 0건 + 보관 사본 2건(product·item_type·amount·status·withdrawn_at 일치,
  화이트리스트 컬럼 부재) — 기존 단언 전부 유지

**교훈(재현 방지)**: 디버그용 runner가 전용 test.sqlite3에 커밋한 잔여 행이 테스트를 오염시킨
실측이 있었다(깨끗한 DB에서는 전부 통과). 병렬 전용 DB 재생성은 파일 삭제 후 `db:create db:migrate`.
또한 이 minitest에서 `assert_equal(nil, nil)`이 "Use assert_nil" 힌트 예외로 실패 처리되므로
nullable 비교는 nil 분기로 작성했다.

## 정적 검증

- `bin/rubocop <소유 ruby 파일 8개>` → 8 files inspected, no offenses
  (`config/recurring.yml`을 rubocop에 직접 넘기면 Ruby 파서로 구문 오류가 나는데 이는 yml
  강제 파싱의 오탐 — `bin/ci` 전체 스캔 대상이 아니어도 무해)
- `bin/rails zeitwerk:check` → Otherwise, all is good!
- `git status --short`: 소유 파일 + 다른 태스크(T1·T2·공유 문서) 변경만 확인 — 타인 소유 파일 무수정

## 운영 조회 예시 (runner — 건수·집계만)

```bash
bin/rails runner 'puts WithdrawnPaymentRecord.count'                          # 보관 총 건수
bin/rails runner 'puts WithdrawnPaymentRecord.expired.count'                  # 5년 경과(파기 예정)
bin/rails runner 'puts WithdrawnPaymentRecord.group(:item_type).count'        # 품목별 집계
bin/rails runner 'WithdrawnPaymentRecords::PurgeJob.perform_now'              # 수동 파기(건수 반환)
```

개별 건 조회는 pg_order_id로만 가능하다(회원 역참조 불가 — 비식별 설계).

## 남은 우려 (법무·후속)

1. **보존 범위·식별 불가능성의 법적 충분성은 법무 확인 권장**(Q33 원문과 동일 — 코드·방침 정합만 보장).
   티켓(분쟁 3년)·발송 기록 보존은 미구현(PRD AUTH-1.5 "알려진 한계" ⑤⑥).
2. 탈퇴 뒤에는 원본 주문이 없으므로 관리자 환불 실행·재발급 불가 — PG 콘솔 수동(이미 방침에 고지).
3. 보관 테이블의 `pg_payment_id`는 PG 조사 시 결제 건 역조회 키다(개인정보 아님으로 판단 — 법무 확인 여지).
4. SALES 월 정산·재가입 혜택 등 AUTH-1.5 "알려진 한계" ①②는 본 태스크 범위 밖(PRD 기록됨).
