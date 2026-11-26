# FIX3 — 병렬 배치 리뷰 반영 수정(경고 6건)

날짜: 2026-11-26 · 모드: 절약(badeuldon-developer-lite) · 리뷰 4건 모두 APPROVED, WARNING만 수정

## 1. T2 W-1 — 헬퍼 이중 제거 (`test/models/client_test.rb`)
- 파일 로컬 private `mark_refused!`(기본값 `2026-10-12 09:00`) 삭제, 9곳 호출을 전역 `RefusalTestHelper#mark_refused`로 교체.
- 로컬 기본 시각에 의존하던 3곳(157·238·301행 부근)은 `at: Time.zone.parse("2026-10-12 09:00")`을 명시해 동작 변화 없음.
- `grep -n "mark_refused!"` → 0건 확인.

## 2. T4 W-2 — 불가능 날짜 리터럴 크래시 제거 (`test/fixtures_no_future_date_test.rb`)
- `future_date_literals`의 `Date.parse`를 begin/rescue로 감쌈 — 파싱 실패 시(형식은 맞으나 존재하지 않는 날짜) 해당 리터럴을 오탐자로 offenders에 포함(줄 텍스트에 "(존재하지 않는 날짜 리터럴)" 부기).
- 자체 테스트 1건 추가: "가드 판정 — 불가능한 날짜 리터럴(2099-02-30)은 보고되고 예외가 나지 않는다"(2099-02-30·2099-02-29 2리터럴 보고 단언).

## 3. T3 W-1 — 주석 교정(주석만)
- `app/models/withdrawn_payment_record.rb`: archive! 위 주석을 실제 메커니즘으로 교정 — "enum 컬럼은 read_attribute로 라벨 문자열을 읽어 복사하며, insert_all이 보관 모델의 enum 매핑으로 Order와 같은 정수로 직렬화한다 — 매핑 드리프트는 모델 테스트 ①이 잡는다. attribute_before_type_cast로 바꾸지 않는다(enum 재매핑 시 과거 행의 의미가 깨진다)". 코드 변경 없음.
- `db/migrate/20261126090000_create_withdrawn_payment_records.rb` 8행 주석도 동일 메커니즘 서술로 교정.

## 4. T3 관찰 ③ — 테스트 이름 정정 (`test/models/withdrawn_payment_record_test.rb`)
- 테스트 ⑥ 이름 "4년 364일 유지" → "4년 1일 전 행은 유지"(`4.years.ago - 1.day`와 일치). 단언은 그대로.

## 5. T3 W-2 — 관리자 삭제 경로 보관 단언 (`test/services/admins/account_purge_service_test.rb`)
- 신규 테스트 1건: paid 주문(Order.create! — product: collection_pass·amount 4,000·pg_order_id "purge-test-order-1")을 테스트 안에서 직접 생성 → purge 성공 뒤 `Order.where(user_id:)` 0건 + `WithdrawnPaymentRecord` 1건(pg_order_id·amount·status "paid"·product "collection_pass" 대조).
- 참고: insert_all은 타입 캐스팅을 우회해 반환 라벨이 문자열("paid")로 온다 — 단언을 문자열로 고정.

## 6. T3 W-3 — 탈퇴 화면 보존 안내 1줄
- `app/views/app/profiles/edit.html.erb` — "필요한 내역은 탈퇴 전에 미리 저장해 주세요." 바로 뒤 같은 서식(`<p class="mt-2 text-xs font-medium text-stone-600">`)으로 추가. 최종 문단 전문:

```erb
<p class="mt-2 text-xs font-medium text-stone-600">필요한 내역은 탈퇴 전에 미리 저장해 주세요.</p>
<p class="mt-2 text-xs font-medium text-stone-600">결제 기록은 관계 법령에 따라 회원과 연결되지 않는 형태로 5년간 보관됩니다 (개인정보처리방침 §3).</p>
```

- `test/controllers/app/profiles_controller_test.rb` GET edit 테스트에 `assert_includes response.body, "결제 기록은 … 5년간 보관됩니다 (개인정보처리방침 §3)."` 단언 1건 추가.

## 검증 결과
- 전용 DB `DATABASE_URL=sqlite3:tmp/parallel/FIX3/test.sqlite3` 대상 테스트: **95 runs, 691 assertions, 0 failures, 0 errors, 0 skips**(client_test·fixtures_no_future_date_test·withdrawn_payment_record_test·account_purge_service_test·profiles_controller_test·test/services/users).
- `bin/rubocop <소유 7파일>`: no offenses.
- `git status --short`: 소유 파일 외 추가 변경 없음(워크트리의 기존 다른 배치 변경은 그대로).

## 남은 우려
- 없음. 보관 enum 단언이 라벨 문자열 기준이라는 점(모델 테스트 ①이 정수 대조를 담당)은 주석으로 명시됨.
