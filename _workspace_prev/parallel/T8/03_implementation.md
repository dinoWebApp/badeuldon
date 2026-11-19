# T8 — 부분입금 정책 코드 정합(Q22·Q23) — 구현 문서

PRD v0.41 PAY-2(Q22 오기록 정책·Q23 partial_paid 반복 재발송)를 코드에 정합. §6.14 병렬 fan-out 제약 준수 — 마이그레이션·routes·테스트·전체 테스트/부트 미수행.

## 1. 현행 동작 조사표 (수정 전, 4케이스)

| 케이스 | 수정 전 동작 | 근거 위치 | Q22/Q23 판정 |
|:---|:---|:---|:---|
| ① 일반 부분입금 | 잔액 이하 금액 기록 → `mark_partially_paid!` → partial_paid 인큐 | `app/services/payments/record_service.rb` transition!·enqueue | 정합(시퀀스 잔액 기준 — `remaining_amount` 그대로 사용) |
| ② 과다입금(금액 > 잔액) | **차단** — `guard_within_remain`이 InvalidPayment(422, "잔액보다 큽니다") | record_service.rb 구 guard_within_remain(구 결정 #3) | **부정합(Q22 위반)** — PRD는 잔액 0 처리·마감·초과분 비고·오프라인 환불 안내 |
| ③ 마감(paid) 후 재입금 | **차단** — `guard_payable!`이 InvalidPayment(422, "이미 수금이 마감된") | record_service.rb 구 guard_payable! | **부정합(Q22 위반)** — PRD는 payments 기록만 추가(상태 불변·알림 없음) |
| ④ 반복 부분입금 시 partial_paid | **첫 1회만 발송, 이후 :duplicate** — `claim_log`의 `step_sent?`(SEC-5 sent 판정)이 debtor×partial_paid sent 이력 존재 시 재생성 차단 | `app/services/reminders/send_service.rb` claim_log·step_sent? | **부정합(Q23 위반)** — PRD는 추가 부분입금마다 재발송(상한 집계 밖 유지) |

## 2. Q22/Q23 정합 수정 내역 (파일:라인)

### Q22 — 과다입금·마감 후 재입금

- `app/models/invoice.rb` (remaining_amount, ~285): `remaining_amount`를 0 하한 클램프 `[total_amount - payments_total, 0].max` — 과다입금·마감 후 재입금에서 음수 잔액 노출·DASH 집계 왜곡 방지("잔액 0 처리"). `payments_total`·transition! 산식은 실합계 유지.
- `app/services/payments/record_service.rb` (전면 정합):
  - `guard_recordable!`: 차단 대상을 void·draft로 한정. paid는 통과(기록만 추가 경로).
  - `record_payment!`: 잔액 초과 차단 폐기(구 결정 #3 폐기) — **payments에는 실제 입력 금액 기록**. `@over_amount = paid? ? 0 : [amount - remain, 0].max`(마감 후 재입금은 초과분 개념 부적용).
  - `call`: with_lock 내 `@post_paid_record = @invoice.paid?` 판정 → paid면 전이·알림 모두 스킵(상태 불변·알림 없음). 커밋 후 `note_over_record`(over_amount > 0 시).
  - **초과분 비고 기록 위치**: `AuditLogs::RecordService.call(action: "payment_over_recorded", target: invoice, detail: "과다입금 초과분 N원 — 잔액 0 처리·수금 마감. 환불은 오프라인 안내")` — 기존 감사 구조(F-ADMIN Run C에서 admin_id nullable로 U1 행위 감사 선례 — coupon_redeemed) 재사용. Service→Service 호출(규약 §4.2 허용).
  - `over_amount`·`post_paid_record?` 공개 리더 추가(컨트롤러 플래시 분기용).
- `app/controllers/app/payments_controller.rb` (success_notice, ~38): 마감 플래시에 초과분 문구 덧붙임 — "입금액이 청구액을 N원 초과해 초과분은 마감 기록 비고에 남겼습니다. 환불은 거래처와 직접 조율해 주세요."(오프라인 환불 안내). 마감 후 재입금은 "수금 상태는 수금완료로 유지됩니다" 안내.

### Q23 — partial_paid 반복 재발송

- `app/services/reminders/send_service.rb`:
  - `claim_log`: `per_event_debtor_notice?`(debtor × partial_paid)를 `new_log!` 직행 조건에 추가 — 건마다 새 MessageLog 이력(U1 향 이벤트 알림과 동일 패턴). 구 `step_sent?` 1회 차단 해소.
  - `per_event_debtor_notice?` 헬퍼 신설(auto_sequence_step? 뒤).
  - 상한 집계 밖 유지 확인: `sequence_step?`·`manual_cap_reached?`는 partial_paid를 집계하지 않음(1회성 — Q10 확정 그대로). 변경 없음.
  - 경계 안전: 동시 2건 partial_paid → DB 부분 유니크 인덱스(debtor×pending) + `new_log!`의 RecordNotUnique rescue가 기존대로 흡수(:duplicate).
- 시퀀스 잔액 기준: partial_paid 문구 변수 "잔액"은 `remaining_amount`(`send_service.rb` ~261) — 클램프만 적용되고 최신 잔액 기준 계속(기존 동작 유지).

## 3. 스키마 선언 (마이그레이션 금지에 따른 후속 과제)

- **선언**: `payments.note` (text, nullable) — "마감 기록 비고"를 payments 행에 직접 남기는 1순위 설계. 현 스키마에 컬럼 부재 + 마이그레이션 생성 금지로 본 태스크에서는 **AuditLog(action "payment_over_recorded")로 대체 기록**하고 컬럼 추가 시 `note_over_record`를 payments.note 기록으로 전환 권장.

## 4. 경계 동작 정의

| 경계 | 동작 |
|:---|:---|
| 정확히 잔액과 같은 금액 | 기존 마감 경로 유지 — over_amount 0, mark_paid!, paid_thanks(PAY-4 옵션) |
| PAY-1 원클릭(amount nil) | 남은 잔액 서버 계산 — 기존 동작 유지 |
| void·draft에 대한 기록 | 기존과 동일 422("입금을 기록할 수 없는 상태") |
| 마감 후 재입금 | payments 기록만 추가, 상태 paid 불변, 알림 없음, 잔액 표기 0(클램프) |
| 마감 후 재입금 amount nil | remain=0 → Payment 검증("입금 금액 미입력") 422 |

## 5. 소유권 준수

수정 파일 4개 — `app/models/invoice.rb`(잔액 메서드만)·`app/services/payments/record_service.rb`·`app/controllers/app/payments_controller.rb`·`app/services/reminders/send_service.rb`(claim_log 가드만). users·reminders 스케줄·주간 다이제스트·recurring·subscription·routes·마이그레이션 미접근. 솔라피 실호출 구조 변경 없음(발송은 기존 SendService·DeliverJob 재사용).

## 6. 자가 검증

- `bin/rubocop` 대상 4파일: **0 offenses**
- `ruby -c` 4파일: 모두 Syntax OK
- 전체 테스트·부트: 금지(3-S 이후) — 미수행
- 참고: 기존 테스트 중 `test/controllers/app/payments_controller_test.rb`·`test/integration/payments_concurrency_test.rb`·partial_paid 관련 테스트는 구 정책(초과 차단·마감 후 차단·1회 발송)을 전제로 할 가능성이 높다 — 3-S Tester 단계에서 Q22/Q23 시나리오로 갱신 필요.
