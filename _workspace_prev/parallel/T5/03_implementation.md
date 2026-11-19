# T5 — dunning(구독 결제 실패 재시도) 구현 내역 (PLAN-5 · 2026-11-16 확정 문장)

## 변경 파일

| 파일 | 구분 | 내용 |
|:---|:---|:---|
| `app/models/subscription.rb` | 수정 | 상수 `DUNNING_RETRY_DELAYS = [1, 3, 7]` · `DUNNING_MAX_STAGE = 3` · `dunning_active?` · `reset_dunning!` 추가 |
| `app/services/subscriptions/upgrade_service.rb` | 수정 | `retry_charge` 액션 신설 · `renew` dunning 가드 · `record_charge_failure!` 명확 실패 → dunning 진입 · `advance_dunning!`/`dunning_message` 신설 · `extend_period!` 성공 시 dunning 초기화 |
| `app/jobs/subscriptions/dunning_retry_job.rb` | 신규 | 재시도 실행 Job(스칼라 subscription_id · 멱등 · `discard_on ActiveJob::DeserializationError`) |
| `app/views/admin/members/show.html.erb` | 수정 | 구독 상태 줄에 dunning 현황(재시도 N/3회 · 다음 재시도 시각 · 소진 시 해지 확정) 표시 |
| `app/views/admin/orders/index.html.erb` | 수정 | failed plus_monthly 주문 행에 dunning 배지(`재시도 N/3`)· 하단 안내 문구 갱신(미구현 문구 제거) |

## 스키마 선언 (3-S 통합 마이그레이션용 — 마이그레이션 생성 금지 준수)

```
add_column :subscriptions, :dunning_stage, :integer, null: false, default: 0
add_column :subscriptions, :next_retry_at, :datetime
add_column :subscriptions, :last_payment_failed_at, :datetime
```

- `dunning_stage` — 완료된 재시도 실패 횟수(0=정상). 상한 3(`DUNNING_MAX_STAGE`).
- `next_retry_at` — 다음 재차감 예약 시각(KST, TIME-1 `Time.current` 기준). nil=재시도 없음.
- `last_payment_failed_at` — 마지막 명확 실패 시각(ADMIN-4 CS 추적 근거).
- 인덱스 불요 — 재시도 Job은 스케줄 예약(push) 방식이라 전수 스캔 쿼리가 없다.
- 로컬에서 컬럼 부재로 구독 차감 경로 테스트가 실패하는 것은 3-S 마이그레이션 적용 전까지 정상.

## 재시도 스케줄 명세 (PLAN-5)

1. **진입** — 자동 갱신(`SubscriptionRenewalJob` → `UpgradeService(action: :renew)`) 차감의
   **명확한 실패** 시(`record_charge_failure!`): 실패 주문 기록 + `dunning_stage` 1 진행 +
   `next_retry_at = 실패 시각 + DUNNING_RETRY_DELAYS[stage]` (D+1 → D+3 → D+7) +
   `Subscriptions::DunningRetryJob.set(wait: delay.days).perform_later(subscription.id)`.
2. **재차감** — `DunningRetryJob` → `UpgradeService(action: :retry_charge)` → with_lock 재판정
   후 기존 `charge_and_extend!` 경로 재사용(동일 빌링키 · PortOne 래퍼 `charge_billing_key` —
   새 API 호출 코드 없음). 성공 시 `extend_period!`가 `reset_dunning!`(stage 0 · next_retry_at nil).
3. **최종 실패** — stage 3 재시도까지 실패 시(advance_dunning!에서 stage 4 계산 시)
   `dunning_stage = 3` 고정 · `next_retry_at = nil` · `cancel!` 전환. 주기가 이미 종료됐으므로
   갱신 Job의 기존 cancelled 경로가 다음 일간 스윕에서 `expire!`로 Free 강등 — "기간 말 만료
   동일" 해지 정책과 동일 경로(PLAN-5). **만료 강등 임박 상태의 cancelled이므로 즉시 만료 아님을
   ADMIN-4에 "재시도 소진 — 해지 확정"으로 표시**.
4. **모호 실패(TIMEOUT/CONNECTION)** — 기존대로 pending 유지·웹훅 회복(`settle_renewal`) 대기.
   dunning 단계 진행 안 함(차감 성공일 수 있음).

## 경합·멱등 설계

- **갱신 Job과의 경합** — `UpgradeService#renew`가 `dunning_active?` 구독을 차감하지 않고
  무변경 통과(가드). 재차감은 재시도 Job 단일 소유 → 일간 갱신 스윕이 dunning 스케줄을
  우회하는 일이 없다(기존 `subscription_renewal_job.rb` 무수정 — 화이트리스트 외).
- **Job 멱등** — `perform` 진입 가드: 구독 부재/비-dunning(no-op) · `next_retry_at`이 미래면
  그 시각으로 Job 재예약 후 종료 · 이미 성공(reset)이면 no-op. `retry_on` 미사용 — dunning
  스케줄 자체가 재시도 계획이며 즉시 retry는 중복 차감 시도가 되므로 `discard_on
  ActiveJob::DeserializationError`만 둔다. 차감 실패는 `UpgradeError`로 로그만 남기고 종료
  (다음 단계는 `record_charge_failure!`가 이미 예약).
- **포트원 멱등** — 재차감 주문은 `prepare_renewal_order!`의 기존 패턴(pending 재사용 or 신규
  uuid)을 그대로 따른다. 실패 주문(failed)은 재사용 대상이 아니므로 재시도마다 새 paymentId로
  포트원이 중복 차감을 판단한다(기존 갱신 경로와 동일 안전성).

## ADMIN-4 표시 내용

- 회원 상세(admin/members/show): `결제 재시도 N/3회 · 다음 재시도 MM-DD HH:MM` / 소진 시
  `재시도 소진 — 해지 확정`(주황·빨강 상태색 — DESIGN 상태색 3종 준수).
- 결제 목록(admin/orders/index): `plus_monthly` + failed 주문의 사용자 구독이 dunning 중이면
  상태 셀에 `재시도 N/3` 배지. 컨트롤러 수정 불가(fan-out 제약)라 뷰에서 `order.user.subscription`
  연관 접근(기존 admin 뷰의 `log.admin&.email` 패턴과 동일한 수준) — 목록 페이징 범위 내 소규모.
- **ADMIN-5 매출 집계 제외**: dunning 중 주문은 pending/failed 상태이고 최종 실패 주문도 failed이므로
  paid 기반 매출 집계에 원래 포함되지 않는다 — 집계 Query 측 수정 불요(queries는 화이트리스트 외).
- 신규 라우트 불요(기존 ADMIN 경로 재사용 — routes.rb 무수정).

## PortOne 래퍼 재사용 지점

- 재차감: `Subscriptions::UpgradeService#charge_and_extend!` → `PortOne::ClientService#charge_billing_key`
  (신규 API 호출 코드 0줄). 실호출 없음 — 테스트는 Phase 7 stub 주입(`client:` 인자, 기존 체계).
- 자가 검증: `bin/rubocop`(수정 3 ruby 파일 0 offense) · `ruby -c` 3종 OK · `bin/rails zeitwerk:check` OK.
