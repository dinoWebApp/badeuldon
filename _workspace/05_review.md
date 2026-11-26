# 05_review — 병렬 배치(절약): 남은 후속 — 판단 위임 (2026-11-26, Reviewer 3명·정적 리뷰·reviewer-lite GLM-5.3-Flash/max)

리뷰어 프로필에 쓰기 도구가 없어 최종 답변으로 돌려준 산출물을 오케스트레이터가 옮겨 적었다(내용 무변경·HTML 엔티티만 복원).
리뷰어는 모두 지정 파일만 실행했다(통합 게이트 결과는 오케스트레이터가 기록).

## 진행

| 태스크 | status | BLOCKER | CRITICAL | WARNING |
|:---|:---|---:|---:|---:|
| T1 감사 IP — 서비스 계층 | APPROVED | 0 | 0 | 1 (nil 호환 테스트 1건 — Tester) |
| T3 결제 기록 비식별 보관 | APPROVED | 0 | 0 | 3 (주석 교정·관리자 삭제 경로 단언·탈퇴 화면 보존 안내) |
| T2 수신 거부 폴백 제거 | APPROVED | 0 | 0 | 1 (헬퍼 이중 통일) |
| T4 기술 부채 | APPROVED | 0 | 0 | 1 (가드의 불가능 날짜 예외 처리) |

---

## T1 — 감사 로그 IP 서비스 계층 12곳 (ADMIN-2·Q32)

### 1. 결론

**APPROVED**

### 2. 심각도 집계

**B 0 · C 0 · W 1**

### 3. 이슈 목록

| # | 심각도 | 파일:줄 | 문제 | 제안 |
|:--|:--|:--|:--|:--|
| W-1 | WARNING | `test/services/admins/member_admin_service_test.rb`(신규 블록) | 5개 서비스 테스트 중 유일하게 **"ip를 넘기지 않으면 감사 ip가 nil"** 하위호환 테스트가 없다(payments·role·purge·refund 4개 스위트에는 있음). 지시서의 테스트 행렬 ②항이 member 스위트에서만 빠져 있다. 구조상 `@ip` 기본 nil이라 깨질 위험은 낮으나 매트릭스 대칭성이 깨진다 | Tester 보강 단계에서 `toggle_suspension!`(또는 `change_plan!`) 무인자 호출 → `member_suspend`(또는 `member_plan_change`) 감사 `ip` nil 단언 1건 추가 |

**관찰(이슈로 계산하지 않음 — T1 코드 결함 아님):**
- 작업 트리에 T1 소유권 밖 변경이 섞여 있다: `test/fixtures/payment_passes.yml`(고정 만료 2026-12-30 → `90.days.from_now` 상대값), `test/fixtures/invoices.yml`(상대 만료일), 그리고 C-1/X-1 "usable 의존 제거" 수정이 `test/controllers/app/profiles_controller_test.rb`·`billings_controller_test.rb`·`test/system/*` 등 T1 소유 밖 파일에도 존재. T1의 03 보고는 `payment_passes.yml`를 변경 파일로 주장하지 않는다. 병렬 공유 트리라 T1 귀속을 단정할 수 없으므로 **오케스트레이터 확인 요청** — 통합 단계(3-S)에서 픽스처 변경 태스크가 귀속·정합화를 해야 하며, T2 보고에 이미 invoices.yml 상대값화로 `invoices_controller_test` SHARE-2 고정날짜 테스트가 깨진다는 충돌이 기록돼 있다. T1 자체 테스트는 이 픽스처와 무관함을 검증했다(환불 성공은 패스 가용성과 무관 — `PLAN-9②` "모자라면 0에서 종료" — T1의 환불 IP 테스트는 날짜 폭탄 패턴이 아님).
- `users/withdrawal_service.rb`의 감사 1곳은 이미 `ip: ip`를 받고 있음 확인(전수표 13/13 완결 — T1 미수정이 맞는 판단).

### 4. 항목별 판정표

| 확인 항목 | 판정 | 근거 |
|:---|:---|:---|
| 1. 누락 0 (서비스 감사 전수) | **충족** | `app/services` 내 `AuditLogs::RecordService.call` 13곳 전수 grep — 13/13에 `ip:` 전달. T1의 12곳(payments 1·role 5[change_role/unlock/create_admin/record_denied!/record_denial]·member 2·purge 1·refund 3) + withdrawal 1(기존). 03 보고의 전수표와 1:1 일치 |
| 2. IP 전달 경로 완결성 | **충족** | `Admins::RoleService`: 클래스 메서드 4종 모두 `new(ip:)`로 **호출마다 새 인스턴스** — 인스턴스 재사용·스레드 안전성 문제 없음, 내부 `denial`→`record_denial`까지 `@ip` 상속 확인. `Orders::RefundService`: attempt(:87)·failed(:245)·refund(:326) 3경로 모두 `@ip`. `AccountPurgeService`: `self.call(ip:)`→`new.call(..., ip:)` 지역 인자로 온전 전달 |
| 3. 하위 호환 | **충족** | `ip:`가 전부 기본값 `nil` 키워드 인자. 무인자 호출처 전수: `RefundService.new` 테스트 6곳(`revenue_stats_query_test:81`·`webhooks/portone:167,201`·`legal_documents:259`·`sales/monthly_settlement:202`·`admin/orders_controller_test:332`)·`RecordService.new` 기존 테스트 5곳 — 모두 무변경 동작. 프로덕션 호출처는 컨트롤러 5곳뿐(전부 갱신됨) |
| 4. 컨트롤러 5곳 | **충족** | 전부 `ip: ClientIp.of(request)` 전달. 액션 구조 변경 없음(서비스 호출 줄에 키워드 추가만 — 최대 +2줄 포매팅). T1 변경으로 10줄을 초과하게 된 액션 없음(`admins#create` 13줄은 선존재 — T1 무관) |
| 5. 규약(§4.2) | **충족** | 서비스 5개에 `params`·`Current`·`request` 직접 읽기 없음(grep 검증 — `plan_params:`는 컨트롤러가 `params.expect`로 추출해 넘긴 해시의 인자명, 기존 설계 유지). `AuditLogs::RecordService` 시그니처의 `ip:` 키워드와 정확히 일치. 컨트롤러가 값을 풀어 전달하는 규정 방식 |
| 6. 테스트 품질 | **충족(W-1 1건)** | ① `ip:` 전달 → 감사 행 `ip` 값 비교: 5개 스위트 전부 커버. ② 무전달 → nil: 4/5(W-1). ③ 컨트롤러 `CF-Connecting-IP` 헤더 → 감사 `ip`: members(정지)·orders(환불) 2건. 공허 단언 없음 — 전부 `AuditLog` 행을 실제 조회해 비교. 환불 경로는 `ok_client`(FakePortOneClient 스텁)·`with_portone_client` 대역 안에서만 실행 확인 |
| 7. 실행 검증 | **통과** | 아래 명령 참조 |

**Rule ID 준수 매핑**: ADMIN-2(서비스 계층 감사 IP — 2026-11-26 확정 문단의 열거 12행위와 구현 12곳이 정확히 대응) ✓ · Q32(`ClientIp.of` 단일 출처 — 서비스는 값만 전달, 헤더 판정은 컨트롤러 한 곳) ✓ · 규약 §4.2 ✓ · SURF-3/기타 무영향(마이그레이션·라우트 변경 없음).

### 5. Tester 중점 제안

1. **member_admin nil 호환**(W-1) — 무인자 호출 시 `member_suspend`·`member_plan_change` 감사 `ip` nil 단언.
2. **컨트롤러 CF 헤더 E2E 미커버 호출처**: `admins_controller`(create=관리자 생성·change_role·unlock), `base_controller#require_owner` 거부 경로(staff가 PATCH refund → `admin_console_denied` 감사 ip), `app/payments_controller`(과다입금 → `payment_over_recorded` ip) — 서비스 단위 테스트는 있으나 헤더→감사 단언은 members·orders 2곳만 존재.
3. **RoleService 내부 denial 경로**: 테스트된 것은 클래스 메서드 `record_denied!`뿐 — staff가 `change_role!`/`unlock!`/`create_admin!`을 직접 호출할 때의 인스턴스 `denial`→`record_denial` `@ip` 경로(`admin_role_denied` 등)는 미커버.
4. **refund `fail_with_audit` 경로의 ip** — 신규 테스트는 attempt+refund 성공만 커버, `order_refund_failed` 감사의 ip는 미단언.
5. **픽스처 충돌 정합**(통합 단계) — invoices.yml 상대값화로 깨진다는 T2 보고의 `invoices_controller_test` SHARE-2 테스트 재실행.

### 6. 테스트 실행 결과

```
DATABASE_URL=sqlite3:tmp/parallel/RV1/test.sqlite3 bin/rails test \
  test/services/{payments/record_service,admins/{role_service,member_admin_service,account_purge_service},orders/refund_service}_test.rb
→ 73 runs, 410 assertions, 0 failures, 0 errors, 0 skips

DATABASE_URL=sqlite3:tmp/parallel/RV1/test.sqlite3 bin/rails test \
  test/controllers/admin/{members,orders}_controller_test.rb
→ 34 runs, 309 assertions, 0 failures, 0 errors, 0 skips
```

환불 관련 테스트는 전부 포트원 스텁 대역 내에서 실행됐고 외부 실호출은 없다.

---

### 오케스트레이터 처리 결정 (T1)

- **W-1(member_admin nil 호환 테스트)**: Phase 7 Tester에 지시.
- **관찰(T1 소유 밖 변경)**: 확인 결과 **이번 T1의 변경이 아니다** — 픽스처 상대값화·C-1/X-1 수정은 오후·오전 배치의 산출물이다(미커밋이라 리뷰어가 배치를 구분할 수 없었던 것). T2 보고의 "SHARE-2 고정 날짜 테스트가 깨진다"는 **T2 Developer의 HEAD 덮어쓰기 사고**가 원인이었다(그 테스트는 오후에 상대 travel로 고쳐져 있었다) → 사고 복구로 원복됨(08_run_report 사고 항목 참조).
- **Tester 중점 제안 1~4**: Phase 7 Tester 지시서에 포함.

---

## T3 — 회원 삭제 시 결제 기록 비식별 보관 5년 (AUTH-1.5·ADMIN-3·Q33)

### 1. 결론

**APPROVED** — BLOCKER·CRITICAL 0건. 데이터 무결성·개인정보 화이트리스트·콜백 확실성 모두 검증 통과. W 3건은 후속 반영 가능한 수준(문구·테스트 보강·주석 교정)이며 기능 정합성에 영향 없음.

### 2. 심각도 집계

**B 0 · C 0 · W 3**

### 3. 이슈 목록

| # | 심각도 | 위치 | 문제 | 제안 |
|:--|:--|:--|:--|:--|
| W-1 | WARNING | `app/models/withdrawn_payment_record.rb:30-33` 주석·`db/migrate/20261126090000_create_withdrawn_payment_records.rb:8` 주석·`_workspace/parallel/T3/03_implementation.md:83` | "`read_attribute`로 **정수값**을 직접 복사" 주석은 사실과 다르다. Rails 8.1의 `EnumType#cast`는 라벨 **문자열**을 돌려주고(activerecord-8.1.4.1 `enum.rb:181-189`), 정수 직렬화는 `insert_all`이 **보관 모델의** attribute type으로 수행한다(`insert_all.rb:247`). 동작은 정확하다(DB에는 Order와 같은 정수가 저장됨 — 오히려 라벨 복사가 enum 재번호 매핑에 더 유연) — 그러나 "정수 직접 복사"라는 거짓 근거가 남으면 추후 `attribute_before_type_cast`로의 "교정"이 유혹하고 그때는 enum 재매핑 시 의미가 깨진다. 직렬화 매핑의 실제 출처는 WithdrawnPaymentRecord 쪽이므로 "Order 단일 출처"는 주석·테스트 ①의 대조 단언으로만 담보된다 | 주석을 실제 메커니즘으로 교정 — "enum 라벨을 복사하며 insert_all이 양 모델의 동일 EnumType 매핑으로 같은 정수로 직렬화한다. 매핑 드리프트는 모델 테스트 ①이 잡는다" |
| W-2 | WARNING | `test/services/admins/account_purge_service_test.rb` | 관리자 계정 삭제 경로의 보관이 테스트되지 않았다. Q33 결정 문언("`User` 콜백으로 두 삭제 경로가 공통으로 보장")의 관리자 측 담보가 코드 독해뿐이다 — `WithdrawnPaymentRecord` 참조가 이 파일에 전혀 없음(회원 탈퇴 경로는 `withdrawal_service_test.rb:66-76`에 단언됨) | 기존 purge 서비스 테스트에 paid 주문 1건 추가 → `user.destroy!` 뒤 `assert_equal 1, WithdrawnPaymentRecord.count` 단언 1줄이면 닫힌다 |
| W-3 | WARNING | `app/views/app/profiles/edit.html.erb:179-190` | 탈퇴 화면 "삭제되는 항목"에 "결제·환불 내역"이 삭제 목록으로만 보인다. 방침 §3(privacy.html.erb:72-77)과 **모순은 아니다**(목록은 사용자가 잃는 접근성 기준으로 정확하고, 보관 사본은 회원과 연결 불가) — 그러나 "법정 보존 사본이 남는다"는 안내가 화면에 없어 방침과 화면 사이 투명성 공백이 있다. 사용자 관점 답변: 자기 계정에서 보던 내역은 전부 삭제되고 식별 불가 사본만 5년 남으며, 그 사실이 방침 §3에만 있다 | 탈퇴 안내에 1줄 보강 — "결제 기록은 관계 법령에 따라 회원과 연결되지 않는 형태로 일정 기간 보관될 수 있습니다(개인정보처리방침 §3)". profiles 뷰는 T3 소유 파일 밖이므로 오케스트레이터 후속 위임 대상 |

관찰(이슈 아님): ① `archive_payment_records` 콜백이 `false`를 반환하는 경로가 없어(`0`·Integer 반환) destroy 체인 오중단 위험 없음 ② 보관 모델의 `default: :pending`·`default: :pass`는 모든 insert가 명시값을 넣어 무해 ③ 모델 테스트 ⑥ 이름("4년 364일")과 실제 값(`4.years.ago - 1.day` = 4y1d)이 미세하게 어긋남 — 경계 ±1초는 잡 테스트 ②가 실측 커버 ④ `user.rb` status 주석 블록 갱신은 구현 보고의 "콜백 1개만" 선언을 살짝 벗어나나 낡은 문언의 정확한 교정이라 무해.

### 4. 항목별 판정표

#### A. 콜백의 확실성 (최우선) — 모두 PASS

| 확인 | 판정 | 근거 |
|:--|:--|:--|
| A1. `prepend: true` 콜백 순서 | **PASS** | `has_many :orders, dependent: :destroy`(user.rb:19)는 **선언 시점**에 :destroy 체인에 dependent 콜백을 등록하고, `before_destroy`(user.rb:37)의 `prepend: true`는 자신을 체인 **선두**로 삽입한다 — archive가 모든 dependent 파괴보다 먼저 실행된다. 모델 테스트 ①(주문 4건 → `assert_equal 4, WithdrawnPaymentRecord.count` + 건별 컬럼 대조)는 prepend를 빼면 `user.orders`가 빈 집합이 되어 즉시 실패하는 구조 — 실증 단언 |
| A2. 두 삭제 경로·우회 경로 부재 | **PASS** | `Users::WithdrawalService:37`·`Admins::AccountPurgeService:44` 모두 `user.destroy!`. app·lib 전수 grep 결과 `User.delete`·`users.delete_all`·`user.delete` 없음. Order를 cascade 밖에서 파괴하는 코드도 없음 |
| A3. 트랜잭션 원자성 | **PASS** | `destroy!`가 트랜잭션 안에서 콜백을 돌리고 `insert_all`이 같은 커넥션의 외부 트랜잭션에 합류 — 두 서비스가 추가로 `user.transaction`으로 감싼다. 테스트 ⑧(트랜잭션 내 destroy → 보관 1건 → Rollback → 회원·주문 생존·보관 0건)이 실측 고정. 삭제 실패 시 보관 행만 남는 경로 없음 |

#### B. 비식별성·화이트리스트 — PASS (판단 포함)

| 확인 | 판정 | 근거 |
|:--|:--|:--|
| B4. 컬럼 화이트리스트·번호 규식 | **PASS** | 스키마 실측: product·item_type·amount·status·pg_order_id(유니크)·pg_payment_id·order_created_at·paid_at·refunded_at·withdrawn_at·timestamps뿐 — `user_id`·FK·빌링키·metadata·refund_reason·연락처 컬럼 자체가 없다. `pg_order_id`는 `SecureRandom.uuid`(orders_controller.rb:17·legal_documents_controller.rb:120)로 서버 채번 — 회원 식별자 포함 없음. `pg_payment_id`도 우리 UUID와 동일값(upgrade_service.rb:186) 또는 PG 스냅샷 ID. 테스트 ②가 금지 컬럼 부재와 **모든 문자열 컬럼 값에 이메일·표시명 부재**까지 검사 |
| B5. 식별 불가능성 판단·방침 정합 | **PASS(한계 병기)** | 서비스 측 조인 경로가 구조적으로 없고(user_id 부재), 남는 유일한 역조회 가능성은 **PG 운영자가 포트원 콘솔에서 결제번호로 구매자를 역조회하는 것**뿐이다. 이는 사업자가 이미 계약 당사자로 보유한 정보 영역이라 개인정보처리방침 §3의 "탈퇴 시 즉시 파기 + 관계 법령 보존 예외(전자상거래법·국세기본법 5년)" 구조와 모순되지 않는다. **법률 자문 아님** — 보존 범위·식별 불가능성의 법적 충족 여부는 법무 확인 권고 대로 후속 |

#### C. 모델·멱등·파기 — PASS

| 확인 | 판정 | 근거 |
|:--|:--|:--|
| C6. archive! 멱등·경쟁·시점 | **PASS** | 사전 제외 + 유니크 인덱스 이중 방어, 모델 테스트 ⑤가 2회 호출 → 1·0·count 1 실측. 경쟁 상황: 같은 회원 동시 이중 탈퇴에서 늦은 쪽은 `destroy!`의 RecordNotFound로 끝나고, SQLite 단일 writer·동일 트랜잭션 재시도 시나리오에서 insert는 savepoint로 원자 흡수 — `RecordNotUnique`가 500으로 새는 실질 창은 사실상 없음(서비스의 `rescue RecordNotDestroyed`가 이 예외를 감싸지 않는 점은 알려진 한계 수준 — Tester 제안 2로 남김). 콜백은 dependent 파괴 전이라 전체 주문이 담긴다. `insert_all(record_timestamps: true)`로 timestamps null: false 충족 |
| C7. enum 정합 | **PASS** | product·status·item_type의 값·키가 Order와 정확히 동일. 메커니즘의 주석 오류만 W-1(값 저장 결과는 정확) |
| C8. RETENTION·expired·PurgeJob·recurring | **PASS** | `RETENTION = 5.years` 단일 출처, `scope :expired`는 호출 시점 평가. 무한 범위 `...` = 초과 만료 — 잡 테스트 ②가 ±1초 실측. PurgeJob은 expired 한정 `delete_all`·로그 건수만·`retry_on Deadlocked`. recurring.yml 양쪽 블록 등록 — 대조 테스트가 드리프트 방지 |
| C9. 마이그레이션 | **PASS** | `create_table` + 유니크 인덱스 + `withdrawn_at` 인덱스 + `null: false` 명시, `change`라 rollback 시 자동 제거(가역). 신규 테이블뿐이라 기존 테이블 lock 없음 |

#### D. 테스트 품질·운영

| 확인 | 판정 | 근거 |
|:--|:--|:--|
| D10. 8개 시나리오 고정 | **PASS(1개 공백 — W-2)** | ① 행 수·값 일치(상태 4종) ② 화이트리스트·문자열 값 전수 스캔 ③ 원본 연쇄 삭제 유지 ④ 0건 ⑤ 멱등 ⑥ 5년 경계(travel_to 고정 날짜 — 날짜 폭탄 없음) ⑦ 콜백 순서 ⑧ 롤백 — 공허 단언 없음. 공백은 관리자 경로(W-2)뿐 |
| D11. 운영 | **PASS** | 러너 조회 예시는 건수·집계만. 첫 파기 실행은 5년 내내 `purged=0`이 정상이므로 "삭제 0건이 고장이 아님"을 운영 노트에 명시하면 좋다 |

### 5. Tester 중점 제안

1. **관리자 계정 삭제 경로 E2E**: paid 주문 보유 회원을 관리자 계정 삭제로 삭제 → 보관 1건·주문 0건·감사 로그(account_purge) 1건 동시 확인(W-2 닫는 테스트).
2. **보관 실패 시 탈퇴 실패 전파**: `pg_order_id` 유니크 충돌을 유도해 destroy 실패가 회원·관리자에게 어떤 안내로 보이는지(RecordNotUnique가 rescue 밖임을 실측 — 인지 확인용).
3. **enum 매핑 드리프트 가드 실측**: 보관 모델의 매핑을 임시로 어긋나게 해 모델 테스트 ①이 실제로 잡는지 확인(파괴적 — 실행하지 말고 정적 판단).
4. **탈퇴 화면·방침 문구 대조**: W-3 보강 시 LP-12 톤과 방침 §3 문언이 서로 모순 없는지.
5. **파기 잡 첫 운영**: 등록 확인·`purged=0` 로그가 정상임을 인지.

### 6. 테스트 실행

```
DATABASE_URL=sqlite3:tmp/parallel/RV3/test.sqlite3 bin/rails test \
  test/models/withdrawn_payment_record_test.rb test/jobs/withdrawn_payment_records \
  test/services/users/withdrawal_service_test.rb
→ 27 runs, 237 assertions, 0 failures, 0 errors, 0 skips
```

---

### 오케스트레이터 처리 결정 (T3)

- **W-1(주석)**: 고친다 — 모델·마이그레이션 주석을 실제 메커니즘으로 교정.
- **W-2(관리자 삭제 경로 테스트)**: 고친다 — `account_purge_service_test`에 보관 단언 추가.
- **W-3(탈퇴 화면 보존 안내)**: 고친다 — 탈퇴 안내에 1줄 보강(방침 §3과 투명성 정합)·컨트롤러 테스트 단언.
- **관찰 ③(테스트 ⑥ 이름)**: 이름을 실제 값과 맞게 정정.
- **Tester 중점 제안 1·4·5**: Phase 7 Tester(1·4)와 운영 노트(5)에 반영. 2·3은 정적 판단으로 대체.

---

## T2 — 수신 거부 레거시 nil 폴백 제거·헬퍼 통일 · T4 — 픽스처 가드 강화·주석 정리

### 1. 결론

| 태스크 | 결론 |
|:---|:---|
| **T2** 수신 거부 레거시 nil 폴백 제거 + 마킹 헬퍼 통일(VIEW-7·Q30) | **APPROVED** |
| **T4** 픽스처 가드 강화 + 대시보드 서비스 주석 정리 | **APPROVED** |

### 2. 심각도 집계

- **T2**: B 0 · C 0 · **W 1**  /  **T4**: B 0 · C 0 · **W 1**

### 3. 이슈 목록

**W-1 (T2, WARNING) — `test/models/client_test.rb:384` — 파일 로컬 `mark_refused!`가 전역 `mark_refused`와 이중 존재(헬퍼 통일 미완)**
- 로컬 private 헬퍼 `mark_refused!(client, at:)`(384행)는 전역 `RefusalTestHelper#mark_refused`와 동일 본문이다. 같은 파일 안에서 전역 `mark_refused` 2곳(120·134행)과 로컬 `mark_refused!` 9곳이 혼재한다. "bang = 예외 던지는 변형"으로 오독할 여지가 있다.
- **제안**: 로컬 정의를 삭제하고 9곳을 전역 `mark_refused`로 교체(로컬 기본값 `Time.zone.parse("2026-10-12 09:00")`에 의존하던 2곳은 `at:` 명시). 동작 변화 없음.

**W-2 (T4, WARNING) — `test/fixtures_no_future_date_test.rb:126` — 불가능한 날짜 리터럴에서 `Date.parse`가 예외를 던져 가드 자체가 에러로 죽는다**
- `DATE_LITERAL_PATTERN`은 일을 `01..31`로만 제한하므로 `2026-02-30`·`2026-04-31`·`2026-02-29`(2026은 평년) 같은 "형식은 맞지만 존재하지 않는 날짜"를 매치한다. 이 값이 픽스처에 들어오면 — 가드가 잡아야 하는 바로 그 상황에 — `Date.parse`가 `Date::Error`를 던져 안내 메시지 대신 크래시가 난다. 현재 픽스처에 해당 리터럴 0건이라 증상은 없다.
- **제안**: `Date.parse` 실패 시 오탐자로 보고(또는 사유와 함께 제외). 자체 테스트에 불가능 날짜 1건 추가.

### 4. 항목별 판정표 — T2

| # | 확인 항목 | 판정 | 근거 |
|:--|:--|:--|:--|
| 1 | 폴백 제거 정합성 | **OK** | `client.rb:113` — `siblings.where(refused_phone: phone_digits)` 단일 기준. nil 거부 행은 상속 원천 제외, 자기 행은 `refused?`(행 단위)로 발송 계속 차단 — "더 적게 차단하는 안전한 방향" |
| 1b | 운영 nil 행 부재 전제 | **OK** | `refused_at` 쓰기 경로 전수 = 접수(`update_columns(refused_at, refused_phone)`)·전파(`update_all` 두 컬럼 동시)·상속(두 컬럼 동시) + 소급 마이그레이션. 신규 nil 행을 만드는 프로덕션 경로 없음. 테스트 DB는 `db:schema:load`라 소급 없음 → 헬퍼 도입이 정확한 보완 |
| 2 | 되돌림 없음·행 단위 판정·가드·전파 불변 | **OK** | `SendService:181` REFUSED 가드 = `client.refused?` 불변. 전파는 현재 번호 기준 그대로. 재개·재시작 거부·화면 문구 테스트 전부 기존 문언 유지·통과 |
| 3 | 헬퍼 | **OK** | `mark_refused(client, at: Time.current)` = 두 컬럼 동시 기록. `on_load(:active_support_test_case)` include — `AdminSessionTestHelper`와 동일 선례, 모델·컨트롤러·시스템 전역 사용 가능 |
| 4 | 복원 4파일 교체분(17곳) | **OK** | clients_controller 4·invoices_controller 4·clients_reminders 1·invoices_reminders 8 — 인자·시각 값 정확. 상속 기대 시나리오는 헬퍼가 `refused_phone`을 채워 1순위 경로로 정상 작동. 잔존 단독 마킹 7곳은 전부 행 단위 판정 전용이라 수정 불요 |
| 4b | 센서 테스트 반전 | **OK** | 단독 마킹 → 신규 등록 정상·원천 행은 여전히 거부 — 폴백 제거 후 올바른 동작을 정확히 고정 |
| 5 | `todays_sends_query_test.rb` 재작성본 | **OK** (커버리지 갭은 Tester 제안) | 쿼리 명세와 대조: 자격 게이트·기본 트랙 −17·+1·약속 트랙 오늘/−5·거부·보류·마감 제외·정렬·회원 격리 — 모두 일치. 경계 유래 주석과 테스트 값 정합 |

### 5. 항목별 판정표 — T4

| # | 확인 항목 | 판정 | 근거 |
|:--|:--|:--|:--|
| 7a | ERB 제거 텍스트 검사 | **OK** | `text_outside_erb` — 완결 쌍 gsub → 미완 `<%`는 행 끝까지 제거 → 유령 `%>`는 행두부터 제거. 혼합 줄을 잡는 것이 자체 테스트 1로 고정됨. 태그 **내부** 고정 날짜(`<%= Time.zone.parse("2099-12-31") %>`)는 구조적 사각지대(관찰) |
| 7b | `DATE_LITERAL_PATTERN` | **OK** | 월 01-12·일 01-31 범위 제한. 혼용 구분자도 탐지. 오탐 후보(`110-234-567890`·`010-3333-7777`·`BD-20260901-001`·`v1.2.2026`) 전수 불매치. 불가능 날짜가 패턴을 통과해 W-2의 크래시 경로 |
| 7c | 단언 6건 | **OK** | 판정 로직의 `future_date_literals(text)` 분리로 자체 고정. 경계값 2099/2020이라 wall-clock 안전 |
| 7d | 마커·실패 메시지 | **OK** | 인라인 마커 행 제외, 메시지에 파일:행·리터럴·ERB 제거 후 줄 텍스트 |
| 8 | reminder_actions_service 주석만 | **OK** | 직전 리뷰(T5)가 검증한 서비스 본문과 현재 코드가 일치, 주석 축소분의 포인터(`Reminders::SendSchedule.send_at_for`)가 정확 |

부가 관찰(이슈 아님): 가드의 `Dir[test/fixtures/*.yml]`은 비재귀 glob이지만 현재 하위 디렉터리에 yml이 0건.

### 6. Tester 중점 제안

1. **`todays_sends_query_test.rb` 빠진 약속 트랙 경계 2건** — `promised_on = 오늘−4`(포함 경계)와 `promised_on = 오늘+1`(promise_d1 nominal이 오늘) — 현 재작성본은 오늘(포함)·−5(제외)만 커버.
2. **`this_week` kind 약속 후보** — 테스트는 `date_selected`만 사용.
3. **링크 만료 제외** — 후보 범위 안 청구라도 `token_expires_at` 경과 시 제외됨을 쿼리 레벨에서 1건.
4. **시퀀스 종결 제외** — `sequence_finished_at` 마킹 청구의 쿼리 레벨 제외 1건.
5. **T2 시스템 테스트 2종 통합 실행** — 헬퍼가 시스템 케이스에서 실제 로드되는지 브라우저 E2E로 최종 확인.
6. (통합 단계에서 해소됨) 픽스처 상대 만료일 vs SHARE-2 고정 날짜 테스트 충돌 — 원인은 T2 Developer의 HEAD 덮어쓰기였고 복구로 원복됨.
7. **W-2 수정 후 회귀** — 불가능 날짜 리터럴이 픽스처에 들어왔을 때 가드가 에러가 아닌 보고로 실패하는지.

### 7. 테스트 실행

정적 리뷰 — 테스트 미실행(`refused_at` 쓰기 경로 전수 grep과 마킹 잔존 전수 grep은 실행).

---

### 오케스트레이터 처리 결정 (T2·T4)

- **T2 W-1(헬퍼 이중)**: 고친다 — `client_test.rb`의 로컬 `mark_refused!`를 전역 헬퍼로 통일.
- **T4 W-2(불가능 날짜 크래시)**: 고친다 — `Date.parse` 실패를 오탐자 보고로 처리 + 자체 테스트 1건.
- **Tester 중점 제안 1~4·7**: Phase 7 Tester에 포함. 5는 7-S 전체 시스템 테스트로 확인.

---

## 리뷰 총평 (오케스트레이터)

4건(리뷰어 3명) 모두 **APPROVED** — BLOCKER 0·CRITICAL 0·WARNING 6(T1 1·T2 1·T3 3·T4 1). 수정 라운드에서 모두 반영한다(주석 교정·헬퍼 통일·가드 예외 처리·관리자 삭제 경로 단언·탈퇴 화면 보존 안내 1줄). 재리뷰는 하지 않는다(경고 수준·변경면 작음 — 오케스트레이터가 diff·테스트로 직접 확인).
