# 07_test_report — 기능 잔여·기술 부채 병렬 배치(6태스크) (2026-11-16 · Tester)

**결론: 테스트 작성·실행 완료. 코드 버그 4건 발견(전부 본 배치 회귀 — Phase 6 분기 필요). 전체 스위트는 버그 4건 해소 전까지 67건 실패가 구조적으로 남는다.**

---

## 1. 실행 결과

| 항목 | 값 |
|---|---|
| 전체 `bin/rails test` | **1,241 runs / 6,631 assertions / 9 failures / 58 errors / 0 skips** |
| 실패 원인 분류 | **코드 버그 67건(전부 4건의 버그 파생) — 테스트 코드 오류 0건** |
| `bin/rubocop` | **354 files inspected, no offenses** (테스트 신규·수정분 포함) |
| 신규 테스트 파일 | 7종 (+테스트 내 통합 클래스 1) |
| 구 정책 기존 테스트 갱신 | 9건 (Q22·Q23·PLAN-5·T3 억제 기준 — 각각 근거 인용) |

개별 파일 기준(버그 파생 실패 제외): T3 하드닝·T6 모델/컨트롤러·T5 dunning·A·공통 회귀 전부 통과. T8 payments 정책 테스트 9건 중 7건 통과, 2건은 BUG-2 재현으로 실패(의도된 버그 고정 테스트).

## 2. 발견 코드 버그 (Phase 6 분기 — Tester 수정 불가 항목)

### BUG-1 (CRITICAL) — `User#tax_invoice_ready?`가 private이 됨 → TAX·paid 화면·AUTH 전역 500
- 위치: `app/models/user.rb:155`(`private` 신설 위치) — T6이 REM-3 블록을 삽입하며 기존 `private` 경계보다 **위에** 메서드군을 넣고 `tax_invoice_ready?`를 private 구간으로 밀어넣었다(git diff HEAD 확인 — `+  private` 1건).
- 파급: `App::InvoicesController#set_tax_invoice_context`(236행)·`TaxInvoices::IssueService#verify_guards!`(50행)·`App::TaxInvoicesController`(74행)가 public 호출 → NoMethodError. **paid 청구서 상세 렌더 전체·TAX 발행 전 경로·가입→프로필 리다이렉트 등 31건 실패.**
- 수정 제안: `tax_invoice_ready?` 정의를 `private` 위(또는 별도 `public` 구간)로 이동. 회귀 테스트는 이미 작성돼 있어 수정 즉시 녹색.

### BUG-2 (CRITICAL) — `Payments::RecordService#call`의 rescue가 nil Payment로 InvalidPayment를 만듦 → 금액·날짜 검증 실패 경로 전부 500
- 위치: `app/services/payments/record_service.rb:54-59` — `payment = nil` 후 `payment = record_payment!` 할당이 `save!` 예외로 완료되지 못한 상태에서 `rescue ActiveRecord::RecordInvalid → raise InvalidPayment, payment(nil)` → `InvalidPayment#initialize`의 `payment.errors`에서 NoMethodError.
- 파급: 0·음수·미래 입금일·마감 후 금액 미전송(원클릭·Q22 경계) 등 **모든 Payment 검증 실패 경로**가 422 대신 NoMethodError. 컨트롤러의 `@payment = e.payment` 계약도 파탄.
- 수정 제안: `record_payment!`를 예외 대신 실패 Payment 반환으로 바꾸거나, `call`에서 `payment = Payment.new(...)`를 with_lock 밖(또는 begin 전)에 확보해 rescue에서 nil이 아님을 보장.
- 고정 테스트: `test/controllers/app/payments_over_policy_test.rb` 2건(의도적으로 현재 실패 — 버그 회귀 표지)·`payments_controller_test` 3건 갱신분.

### BUG-3 (CRITICAL) — `app/views/app/profiles/edit.html.erb:126`이 뷰에서 헬퍼 상수 `REMIND_WDAY_OPTIONS`를 직접 참조 → 프로필 화면 전체 500
- 내용: ERB 컴파일 모듈에서 헬퍼 모듈 상수 lookup 불가(실측 — NameError). 기존 선례인 `bank_options` 메서드 감싸기(BANKS)를 따르지 않은 T6 회귀. **프로필 edit·저장 실패 재렌더·로그인 후 프로필 리다이렉트 등 25건 실패.**
- 수정 제안: 헬퍼에 `def remind_wday_options; REMIND_WDAY_OPTIONS; end` 추가 후 뷰에서 호출(선례 준용).
- 고정 테스트: `profiles_remind_settings_test` 2건(422 기대 — 현재 BUG-3으로 500) 실패로 회귀 표지.

### BUG-4 (CRITICAL) — `Noti::WeeklyDigestService#skip_no_template!`이 스코프 밖 지역변수 `variables` 참조 → NO_TEMPLATE 경로(현 상태의 유일 도달 경로) 전부 NameError
- 위치: `app/services/noti/weekly_digest_service.rb:79` — `variables = build_variables`는 `call` 지역변수인데 private 메서드 `skip_no_template!`에서 bare `variables` 사용. `failed` 분기(86행)의 `variables`도 동일 결함.
- 파급: 템플릿 미등록 상태(운영 현재 상태)에서 다이제스트 1호 발송 시도 즉시 NameError — 기록도 안 남고 잡 에러 로그만 남음(P4 위반). **4건 실패.**
- 수정 제안: `variables`를 인스턴스 변수(`@variables ||= build_variables`)로 승격 후 양쪽 분기에서 참조.
- 고정 테스트: `weekly_digest_test` NO_TEMPLATE·집계 4건(전부 BUG-4 재현으로 실패).

## 3. 구 정책 기존 테스트 갱신 (정책 변경에 따른 정당한 갱신 — 근거 기록)

| 파일·테스트 | 구 기대 | 신 기대 | 근거 |
|---|---|---|---|
| payments_controller_test — 이중 클릭(SEC 멱등) | 422 "이미 수금이 마감된" | 422 "입금 금액을 입력해 주세요"(금액 미전송 → 잔액 0 → 검증 실패) | Q22 — paid 본 기록만 추가 경로 신설·원클릭 0원은 검증 실패(T8 경계 정의) |
| payments_controller_test — 마감 본 재등록 | 422 차단 | **303 기록만 추가**(상태 paid 불변·DeliverJob 인큐 0건·플래시 상태 유지 안내) | Q22 |
| payments_controller_test — 잔액 초과(결정 #3) | 422 거부·잔액 불변 | **303 실입금액 기록·마감·AuditLog payment_over_recorded·"남은 잔액을 N원 초과" 플래시** | Q22·W-5 정정 문언 |
| payments_reminders_test — 마감 본 재등록 422 재렌더 | 422 + 발송 이력 렌더 | **303 + 알림 인큐 0건** | Q22(상태 불변·알림 없음) |
| payments_concurrency_test — 동시 원클릭 | [303,422] "이미 마감된" | [303,422] "입금 금액을 입력해 주세요"·기록 1건 유지 | Q22 + T8 경계(현재 BUG-2로 [0,303] — 버그 표지) |
| payments_concurrency_test — 동시 부분입금 초과 유도 | [303,422] 차단 | **[303,303]·2건 기록·누계 80,000·paid·초과분 감사 기록** | Q22 — 초과 차단 폐기 |
| upgrade_service_test — 명확 차감 실패 | "즉시 만료(dunning 없음)" | **dunning 1단계 진입(stage 1·D+1·빌링키 유지·active)** | PLAN-5 2026-11-16 확정 |
| upgrade_service_coupon_test — charge 실패 후 재시도 | renew 재갱신으로 재시도 | **retry_charge(D+1) 경로로 재시도**(스윕은 dunning 중 무변경)·dunning 리셋 검증 추가 | PLAN-5 — 갱신 Job 경합 방지 |
| track_service_test — 긴 UA·긴 IP | 절단만 하고 45자 저장 | 유효 IP 그대로·**형식 실패 IP는 "unknown"** | T3 하드닝(IPAddr 검증 신설) |
| viewer_controller_test — device 판별 | 동일 IP 연속 2요청 | **요청마다 다른 IP**(T3 30분 억제와 무관하게 device 검증) | T3 억제 정책 |

## 4. 시나리오 ↔ Rule ID 매핑 (본 배치 분 — TAX 제외)

| Rule/결정 | 시나리오(테스트 파일) | 커버 |
|---|---|---|
| REM-3(세부 지정) | 검증 정상·주말·야간·경계값 9·18·start<end(`user_remind_window_test`) / 컨트롤러 저장 303·주말 422·야간 422·서버 필터(`profiles_remind_settings_test`) / 이월 9시나리오·최악 7일 종료(`user_remind_window_test`) | ✅ |
| NOTI-2 | NO_TEMPLATE skip 기록·같은 주 duplicate·NO_PHONE·집계 3지표·타 사용자 미포함·기간 경계·토글 off/정지/번호 부재 제외·토글 303/422·AUTH 가드(`weekly_digest_test`) | ✅ (단, NO_TEMPLATE·집계 4건은 BUG-4로 현재 실패 — 버그 표지) |
| PLAN-5(dunning) | ① 진입 stage1·D+1·Job 예약 ② 재차감 성공 리셋·연장 ③ **해지 후 무차감(C-1 — Job·서비스 양쪽)** ④ **3회 소진→cancelled→갱신 스윕 expire!(C-2)** ⑤ 스윕 경합 무변경 ⑥ ADMIN 표기(표기·소진 해지 전환) ⑦ 모호 실패 미진입·settle_renewal 회복 리셋 ⑧ Job 멱등(비대상 no-op·미래 재예약)(`dunning_retry_test`) | ✅ 전부 통과 |
| PAY-2·Q22 | 정상 부분·정확 전액(비고 없음)·과다입금(잔액 0·paid·AuditLog·오프라인 안내)·누적 후 과다(잔액 기준 초과분)·마감 후 재입금(기록만·알림 0)·마감 후 원클릭 422·금액 무결성(`payments_over_policy_test` + 기존 갱신분) | ✅ 7/9 통과·2건 BUG-2 표지 |
| Q23 | 반복 부분입금 건마다 partial_paid 인큐·SEQUENCE_TEMPLATE_KEYS 집계 밖(`payments_over_policy_test`) | ✅ |
| SHARE-4·SEC-5(T3) | 첫 열람 기록+알림 인큐 불변·30분 내 동일 청구서+IP 억제(이벤트·알림 0)·31분 경과 기록·동일 IP 타 청구서 미억제·타 IP 미억제·IP unknown 폴백·절단·키 일관성·UA 512자·봇 무기록(`track_service_hardening_test`) | ✅ 전부 통과 |
| P4 | digest MessageLog 기록·마감 후 재입금 기록·AuditLog 초과분 비고 — 각 테스트에서 검증 | ✅ |
| Q10/PLAN-3 | partial_paid가 SEQUENCE_TEMPLATE_KEYS 밖(상한 집계 제외) — 회귀 고정 | ✅ |
| A(W-3·en.yml·JS) | deploy.yml CACHE_CONTROL·폰트 파일 존재·en.yml 한국어 0건·ko I18n 키 5샘플+한국어 해석·hello 제거·portone_shared 존재(`parallel_batch_3s_regression_test`) | ✅ 전부 통과 |
| 공통(3-S·SURF-3·AUTH) | 마이그레이션 컬럼 4+3+1·view_events 복합 인덱스·routes 결선·recurring.yml 양환경·/app noindex·신규 경로 비인증 302 | ✅ 전부 통과 |

리뷰 8블록 커버: 1(B-1 4케이스 303)✅ 2(C-1/C-2 ⑦종)✅ 3(T6 9시나리오+422)✅ 4(T7)✅(버그 제외) 5(T8 4케이스+동시)✅ 6(T3)✅ 7(en.yml 회귀 샘플)✅ 8(C-3 422)✅.

## 5. 게이트 판정

- **RuboCop: 통과(0 offense).** 외부 API 실호출 0건(FakePortOneClient·FakeSolapiClient·with_portone_client·with_solapi_client·NO_TEMPLATE fail-fast 경로만).
- **전체 테스트: BUG-1~4 해소 전까지 통과 불가** — 67건 전부 4개 버그의 직접 파생이며, 버그별 고정(회귀 표지) 테스트가 이미 깔려 있어 Phase 6에서 소스만 수정하면 즉시 녹색 수렴이 예상된다. 수정 후 `bin/rails test` 재실행 필수.
- 테스트 소스 미사용 정의 0건·들여쓰기 2칸·git 커밋 없음·PRD/AGENTS/01·02·03·05 무수정.

## 6. Phase 6 인계 요약

1. BUG-1: `user.rb` — `tax_invoice_ready?`를 public 영역으로 이동.
2. BUG-2: `record_service.rb` — rescue 시 nil이 아닌 Payment 전달.
3. BUG-3: `profiles_helper.rb`+`edit.html.erb:126` — 헬퍼 메서드 감싸기(bank_options 선례).
4. BUG-4: `weekly_digest_service.rb` — `variables`를 인스턴스 변수로.
5. W-1(message_logs 부분 유니크 인덱스)·W-2(NOTI-2 문언)는 재리뷰 인계 사항 그대로 — 본 배치에서 미접촉.

## 후속 보완 (2026-11-18)

- 시간 폭탄 누락 1건 보완: dunning_retry_test.rb 두 번째 테스트 GET에 travel_to(2026-11-16 12:40) 적용. 해당 파일 10 runs 통과, 전체 재실행 **1,241 runs / 7,047 assertions / 0 failures / 0 errors**, rubocop 0 offense.
