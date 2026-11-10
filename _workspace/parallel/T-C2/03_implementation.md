# T-C2 03_implementation — 쿠폰·프로모션(ADMIN-4·Q12, 2026-11-10)

## 1. 변경 파일 목록

### 신규
| 파일 | 내용 |
|---|---|
| `db/migrate/20261110040001_create_coupons.rb` | coupons 테이블(code unique 인덱스) + `subscriptions.coupon_id`(FK) + `audit_logs.admin_id` null 허용 완화 — 지시서의 "신규 1건"을 단일 마이그레이션으로 통합 |
| `app/models/coupon.rb` | 쿠폰 모델 — enum percent:0/amount:1·검증 매트릭스·`redeemable?`(단일 판정점)·`final_price_for`(percent 절사)·`consume!`(원자 증가) |
| `app/controllers/admin/coupons_controller.rb` | 표준 CRUD + helper_method `coupon_discount_label`(notices 패턴)·used_count>0 쿠폰 삭제 차단(P4 이력 보존) |
| `app/views/admin/coupons/{index,new,edit,show,_form}.html.erb` | Run B admin 톤(admin-card·admin-title·emerald 버튼) — 목록에 used_count/max·잔여·활성/만료/비활성 배지 |
| `test/models/coupon_test.rb` | 검증 매트릭스 12건 |
| `test/services/subscriptions/upgrade_service_coupon_test.rb` | 결제 시나리오 7건(FakePortOneClient 주입 — 실호출 없음) |
| `test/controllers/app/subscriptions_coupon_test.rb` | 쿠폰 적용 HTTP 7건(PortOneStubbing 경유) |
| `test/fixtures/coupons.yml` | active/amount/depleted/expired/inactive 5종 |

### 기존 파일 수정(파일별 사유 — 화이트리스트 "쿠폰 적용 설계 최소 파일")
| 파일 | 변경·사유 |
|---|---|
| `app/models/subscription.rb` | `belongs_to :coupon, optional: true` 3줄 — 첫 차감 쿠폰 **예약** 상태. 첫 차감 성공 트랜잭션에서 nil 환원되어 "적용 1회·재과금 정상가"가 상태로 보장됨 |
| `app/services/subscriptions/upgrade_service.rb` | `charge_and_extend!` 첫 차감 할인 결선 + `resolve_first_charge_coupon!`/`consume_first_charge_coupon!`/`coupon_metadata`/`prepare_renewal_order!`에 금액 인자. 갱신(renew)·웹훅 회복 경로 외 무변경 — **자동 갱신 Job의 재과금은 쿠폰 nil 상태라 항상 정상가** |
| `app/controllers/app/subscriptions_controller.rb` | update의 `coupon_code` 분기(신규 라우트 없이 기존 PATCH 엔드포인트 재사용 — 라우트 3-S 소유·금지 대응) + `record_coupon_redeemed_audit` + issue_token 메모이제이션 |
| `app/controllers/app/billings_controller.rb` | `@has_paid_plus_order` 1행 — 뷰 쿼리 금지 대응 |
| `app/views/app/billings/show.html.erb` | 쿠폰 섹션(코드 입력 폼·적용 중 배너) — DESIGN-2 emerald 톤 |
| `app/services/audit_logs/record_service.rb` | `admin:` 기본값 nil — coupon_redeemed는 U1 행위라 admin 부재 |
| `app/models/audit_log.rb` | `belongs_to :admin, optional: true` — 위와 동일 근거. admin 행위 로그는 전부 admin_id를 유지(기존 기록 무영향) |
| `db/schema.rb` | 마이그레이션 반영(커밋 필수 항목) |

### 소유권 준수 확인
routes·layouts·members/admins·PRD/AGENTS·다른 태스크 파일 — **수정 없음**. admin nav 링크는 3-S 소유.

## 2. 결제 플로우 다이어그램

### 할인 적용(첫 차감)
```
/app/billing 쿠폰 코드 입력
  → PATCH /app/subscription (coupon_code, issue_token 없음)
  → 서버 검증: 존재→이미 paid Plus 결제?→redeemable?(활성·만료·한도·0원)
  → 통과: subscriptions.coupon_id = coupon  (예약 — 아직 미소비)
[카드 등록: 위젯 → card_callback/수동 PATCH issue_token → register_card → activate!
  → 컨트롤러: coupon 예약 존재 시 감사 로그 action=coupon_redeemed(admin nil)]
… 첫 주기 종료 → SubscriptionRenewalJob → renew → charge_and_extend!
  → resolve_first_charge_coupon!: coupon 있음 + paid plus 주문 없음 → 적용
     · coupon 무효(만료·한도·비활성·0원) → UpgradeError "결제가 중단되었습니다" (정가 폴백 금지)
  → charge_billing_key(amount = 할인가)   ← 포트원 첫 차감
  → 트랜잭션: order paid(amount=할인가, metadata.coupon{code,type,value})
              + coupon.consume!(used_count+1, 원자) + subscriptions.coupon_id=nil
```

### 할인 미적용/재과금
```
쿠폰 미예약 → charge amount = 9,900 정가 (기존 경로 그대로)
첫 차감 성공 후(coupon_id=nil) → 두 번째 이후 모든 차감 amount = 9,900 정가
charge 실패(ApiError) → 주문 failed/모호 보류·만료 처리(기존 이슈 #4 로직) — used_count 불변·예약 유지
  → 재등록 후 재시도: 잔존 pending 주문 재사용 + 금액을 할인가로 재설정해 동일 할인 적용
```

## 3. 불변식 6건 자기 점검 표 (02 확정 해석 2)

| # | 불변식 | 구현 | 자기 점검(테스트) |
|---|---|---|---|
| 1 | 코드 검증은 서버(존재·만료·활성·한도) | `apply_coupon` 서버 판정 + `redeemable?` 단일 판정점 + `unavailability_reason` 사유 flash | coupon_test 4건 + subscriptions_coupon_test 거부 3건 ✅ |
| 2 | 적용 1회 | 예약→첫 차감 성공 트랜잭션에서 `coupon_id=nil` 환원 + 이미 paid Plus 주문 존재 시 예약 무효화·적용 거부 | service "재과금 정상가"·"중복 적용 차단" ✅ |
| 3 | used_count는 결제 성공 시점만 증가(멱등) | `consume!`가 성공 트랜잭션 내 원자 증가 — charge 실패 시 미증가·예약 유지 | service "실패 미소비" + "성공 시점 1회" ✅ |
| 4 | 첫 차감 orders.amount=할인가·metadata coupon_code | order.amount=할인가·`metadata.coupon{code,discount_type,discount_value}`(P4 응답 원문 보존) | service 2건(amount·metadata 검증) ✅ |
| 5 | 재과금 정상가 | 첫 차감 후 coupon_id nil — 갱신 경로 항상 PLUS_MONTHLY_PRICE | service `[7,900, 9,900]` 시퀀스 ✅ (upgrade_service_test 기존 9,900 회귀도 통과) |
| 6 | amount 상한 9,900(0원 방지) | amount 1..9,900·percent 1..100 검증 + `final_price_for` 0원 이하 시 redeemable? 거부 | coupon_test 범위 6건 + "정가 전액 0원 거부" ✅ |

## 4. 자기 스코프·게이트 결과

- 마이그레이션 up/down 검증: `db:migrate:up/down VERSION=20261110040001` 양방향 성공(3회 왕복)
- 테스트: 신규 26건 + 회귀(subscription·upgrade_service·order·subscriptions_controller·billings) — **91 runs, 0 failures, 0 errors**
- `bin/rails zeitwerk:check` 통과 · `bin/rubocop` 자기 12파일 **0 offenses**
- 임시 레코드 정리: dev DB 디버그 쿠폰(AAAAAAAA·DEBUGXYZ1) destroy 완료
- 미수(3-S 의존): `resources :coupons`(admin namespace) 라우트·admin nav 링크 — 라우트 미결선으로 admin 컨트롤러 HTTP 테스트 불가 → Phase 5 리뷰어 재현 대상. 컨트롤러 로직은 notices CRUD와 동일 패턴·파라미터 화이트리스트(expect) 적용

## 5. 리뷰어 주의 사항(설계 판단 공개)

1. **audit admin_id null 완화** — 지시서("coupon_redeemed 감사")에 필요한 최소 스키마 완화. AuditLog.admin_id null 허용 + RecordService `admin:` 옵셔널. coupon_redeemed는 **카드 등록(구독 활성) 성공 시점·컨트롤러 경유**로 기록(지시 문언 준수) — 실제 used_count 소비(첫 차감)는 Job 경유라 감사 없고 order metadata로 P4 추적된다. 이미 활성+카드 등록 상태에서 쿠폰을 예약하는 사용자의 감사는 기록되지 않는 한계(문서화).
2. **쿠폰 적용 엔드포인트** — 신규 라우트 금지에 따라 기존 `PATCH /app/subscription`을 재사용(coupon_code 파라미터 분기). "구독 자원의 갱신(예약 추가)"로 REST 정당화 가능하나, 3-S가 `resource :coupons` 등 신설을 원하면 이관 가능(컨트롤러 로직 그대로).
3. **만료일 당일까지 유효** — `expires_at < Date.current` (date 경계, TIME-1 KST).
4. **percent 절사** — 9,900×20%=1,980원 할인(원 단위 미만 절삭).
5. **위젯 콜백 경로와 쿠폰** — 위젯 GET 콜백에는 coupon_code를 실을 수 없으므로 **쿠폰을 먼저 예약→카드 등록** 순서가 정상 UX다. 예약은 서버에 남아 위젯 경로에도 그대로 적용된다.
6. **폴백 정책** — 첫 차감 시점에 쿠폰 무효 시 정가 폴백 대신 **결제 중단**(01_plan 리스크 1 권고안): 사용자가 안내받지 못한 금액 차감(금액 불일치) 방지.
