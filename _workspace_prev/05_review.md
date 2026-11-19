# 05_review — 기능 잔여·기술 부채 병렬 배치(6태스크) (2026-11-16 · Reviewer)

**status: APPROVED** (2026-11-16 재리뷰 — Phase 6 수정 후 · 재리뷰 범위 B-1·C-1/C-2·C-3 + W 부수)

---

# 재리뷰 결과 (Phase 6 수정 재검증 — 2026-11-16)

초차 리뷰(CHANGES_REQUESTED — B1·C3·W7)의 재검토. 수정 내역 `_workspace/parallel/phase6/03_implementation.md`, 실제 코드 기준 재검증 완료. **BLOCKER·CRITICAL 전부 해소 — APPROVED 전환.**

## 이슈별 재검증

**B-1 (BLOCKER) — 해소 [재검증: 제거 확인]**
- `app/controllers/app/payments_controller.rb:11-19` — create가 `@record_service = Payments::RecordService.new(...)` 인스턴스를 유지하고 `@payment = @record_service.call`로 반환(Payment 모델 — 뷰·load_invoice_show 계약 유지).
- `success_notice`(L45,49)·`over_notice`(L58) — `@record_service.post_paid_record?`·`@record_service.over_amount`로 서비스 리더 호출 교체. Payment 모델에는 해당 리더가 없으므로(B-1 루트) NoMethodError 경로 소멸 — **모든 입금 성공 경로(원클릭·부분·과다·마감 후 재입금) 정상 303 복원**.
- 뷰 참조 0건 재확인: `grep -rn "@record_service" app/views/` 매치 없음 — 컨트롤러 플래시 전용.
- 422 경로 `@payment = e.payment`(Payment 인스턴스)는 success_notice를 호출하지 않아 영향 없음 — 기존 동작 유지.

**C-1 (CRITICAL) — 해소 [재검증: 흐름 닫힘]**
- `app/models/subscription.rb:62-64` — `def dunning_active? = active? && (dunning_stage.positive? || next_retry_at.present?)`. 주석에 C-1·C-2·W-7 근거 기록.
- 흐름 추적: 갱신 실패(stage=1·next_retry_at=D+1·status active) → 사용자 cancel!(cancelled) → D+1 `DunningRetryJob#perform` L20 첫 가드 `!dunning_active?` → active?=false → **return — 재차감 없음**. retry_charge로 직접 진입해도 upgrade_service.rb 첫 분기·elsif 모두 `dunning_active?` false → no-op. **해지 사용자 무단 청구 경로 소멸.** 수동 해지 후 주기 종료 전까지는 기존 PLAN-5 정책(기간 말 유지)대로.

**C-2 (CRITICAL) — 해소 [재검증: 흐름 닫힘]**
- 3회 소진 `advance_dunning!`(stage=3·next_retry_at=nil·cancel!) → 다음 일간 `SubscriptionRenewalJob`(due_subscriptions cancelled 포함) → renew: 첫 분기 `dunning_active?` **false**(active? 한정) → `elsif active? && billing_key` false → `elsif active? || renewal_due?` → renewal_due?(주기 종료) true → **expire! 도달 복원** → plan: free·빌링키 폐기. plan: plus·cancelled 영구 잔존(무료 Plus) 소멸 — PLAN-5 "기간 말 만료" 문언 정합 복원.
- ADMIN 뷰: 소진 후 `dunning_active?` false로 "재시도 소진" 배지는 사라지고 기존 해지 표기로 전환 — 수용(초차 리뷰 인정 범위).
- 부대 정합: `app/jobs/subscription_renewal_job.rb:3-5` 헤더 문언을 PLAN-5 확정(dunning 스케줄·3회 소진 cancelled·만료는 본 Job 해지 경로)으로 갱신 — 초차 리뷰 권장 반영.

**C-3 (CRITICAL) — 해소 [재검증: 확인]**
- `app/controllers/app/notification_settings_controller.rb:10-13` — `render :update` → `head :unprocessable_entity` (초차 리뷰 권장안 ①). MissingTemplate 500 경로 제거·규약 422 준수. 토글 폼 1개 부분 갱신 특성상 뷰 재렌더 불요 판정 타당.

**W 부수 반영 확인**
| 항목 | 판정 |
|:---|:---|
| W-3 | 해소 — `admin/orders_controller.rb:9` `includes(user: :subscription)` |
| W-4 | 해소 — `.gitignore` `config/locales/*.bak` |
| W-5 | 해소 — payments_controller.rb:58 "청구액을"→"남은 잔액을" (over_amount=잔액 초과 기준과 문언 일치) |
| W-6 | 해소 — payment.rb 헤더 Q22 문언 갱신·`audit_logs/record_service.rb` action 목록에 `payment_over_recorded` 추가 |
| W-7 | 해소 — dunning_retry_job.rb:22·upgrade_service.rb(retry_charge) `next_retry_at.present?` 가드. active+stage>0+nil 조합은 advance_dunning!의 원자 갱신으로 발생 불가 — 방어선으로 충분 |
| W-1 | **미반영 — 인계 승인**: message_logs 부분 유니크 인덱스는 스키마 과제(마이그레이션 금지 제약)로 3-S 후속 런 인계. 주 1회·단일 스케줄러로 중복 실위험 낮아 APPROVED 판정에 불포함(인계 기록 필수) |
| W-2 | **미반영 — 인계 승인**: "직전 7일" vs PRD "당주" 문언 판정은 오케스트레이터 사항(Phase 7 인계). 코드 정합 훼손 아님 — 파셜 문구는 구현과 이미 일치 |

## 재리뷰 결론

- 재리뷰 범위 외 코드(T3·T6·T7·T8 본문·A·공통)는 초차 리뷰 판정(통과) 유지 — Phase 6에서 미접촉 확인(수정 파일 목록 상호 배타).
- 공유 판정점(dunning_active?) 1줄 수정이 renew·retry_charge·DunningRetryJob·ADMIN 뷰 전체에 파급되는 구조라 회귀 표면이 넓다 — **Phase 7 Tester는 아래 초차 리뷰의 T5 시나리오(2번 블록)를 최우선 실행**할 것. 특히 ③ 해지 후 D+1 무차감·⑥ 소진 후 갱신 스윕 expire!는 C-1/C-2의 직접 회귀 테스트다.
- B-1 회귀 테스트(입금 4케이스 전부 303·플래시 정상)도 Phase 7 필수 — 초차 리뷰 지시 1번 블록 그대로.

---

# 초차 리뷰 (2026-11-16 — CHANGES_REQUESTED 이력 보존)

## 이슈 목록

### BLOCKER

**B-1 (T8) — 입금 기록 성공 경로 전체가 NoMethodError 500으로 파탄 — [Phase 6 해소]**
- 위치: `app/controllers/app/payments_controller.rb:42,46` · `app/services/payments/record_service.rb:47-60`
- 내용: 컨트롤러의 `@payment`는 `Payments::RecordService#call`의 반환값(`payment` — **Payment 모델 인스턴스**, record_service.rb:57)이다. 그러나 `success_notice`가 `@payment.post_paid_record?`·`@payment.over_amount`를 호출한다. 두 리더는 **RecordService에** 추가됐고 Payment 모델에는 존재하지 않는다(grep 확인 — app/models/payment.rb 매치 0건). → PAY-1 원클릭·부분입금·과다입금·마감 후 재입금 **모든 입금 성공 경로에서 NoMethodError**. T8 문서의 "공개 리더 추가(컨트롤러 플래시 분기용)" 선언과 실제 연결이 어긋난 런타임 에러.
- PRD 근거: PAY-1·PAY-2 원클릭 마감·부분입금(Q22) — 정상 동작 전제 룰 전반이 파탄.
- 수정 방향: 컨트롤러가 서비스 인스턴스를 유지하도록 교체 —
  `service = Payments::RecordService.new(...); @payment = service.call` 후 `success_notice`에서 `service.post_paid_record?`·`service.over_amount` 사용(컨트롤러 10줄 규약 유지). 컨트롤러 수정 최소안이며 서비스 계약은 그대로.

### CRITICAL

**C-1 (T5) — 해지된 구독이 dunning 재차감으로 자동 청구됨(무단 차감 경로) — [Phase 6 해소]**
- 위치: `app/models/subscription.rb:59-61` · `app/services/subscriptions/upgrade_service.rb:109-124,118` · `app/jobs/subscriptions/dunning_retry_job.rb:18-30`
- 재현: ① 갱신 차감 명확 실패 → dunning_stage=1·D+1 DunningRetryJob 예약 ② 사용자가 /app/billing에서 해지(cancel — active이므로 가드 통과. ADMIN 플랜 수동 변경 해지도 cancel!로 동일) ③ D+1에 Job 실행 → `dunning_active?`는 **status를 보지 않음**(dunning_stage.positive? || next_retry_at.present?) → retry_charge → with_lock 내 `elsif subscription.dunning_active? && pg_billing_key.present?` → **charge_and_extend!로 카드 재차감 + 주기 연장**. 해지 의사를 표명한 사용자에게 자동 청구 — 결제 정합·PLAN-5("해지 시 결제 기간 말까지 이용" — 해지 후 신규 과금 규정 없음) 위반.
- 수정 방향: `dunning_active?`를 이용 중 상태로 한정 — `def dunning_active? = active? && (dunning_stage.positive? || next_retry_at.present?)`. 이 한 줄로 C-1·C-2·W-7이 동시 해소된다(renew·retry_charge·DunningRetryJob·ADMIN 뷰가 모두 이 판정점 공유).

**C-2 (T5) — 3회 소진 cancel! 후 만료 강등이 영구 미발동(무료 Plus 잔존) — [Phase 6 해소]**
- 위치: `app/services/subscriptions/upgrade_service.rb:88-102(renew)` · `app/jobs/subscription_renewal_job.rb(due_subscriptions)` · `app/models/subscription.rb:105-108(expire!)`
- 재현: 소진 시 `advance_dunning!` 최종 경로는 `dunning_stage=3·next_retry_at=nil·cancel!`(stage 잔존). 다음 일간 갱신 스윕(due_subscriptions는 cancelled 포함) → renew → 첫 분기 `if subscription.dunning_active?`가 **true(stage=3)** → 무변경 통과 → 기존 `elsif active? || renewal_due?` → `expire!`에 절대 도달 불가. plan: plus·status: cancelled 영구 잔존 → `reminder_eligible?`(subscription&.plus?) true·Plus 한도 무제한을 무료로 사용. PRD PLAN-5 문언 위반: "3회 모두 실패 시 구독 **cancelled(기간 말 만료** — PLAN-5 해지 정책 동일)" — 기간 말 만료가 발동하지 않음. T5 03 문서의 "갱신 Job의 기존 cancelled 경로가 다음 일간 스윕에서 expire!" 주장은 dunning 가드 분기와 모순.
- 수정 방향: C-1과 동일 수정(dunning_active? status 한정)으로 해소 — cancelled는 dunning 비대상이 되어 기존 `elsif active? || renewal_due?` → expire! 경로가 복원된다. `SubscriptionRenewalJob` 헤더 주석의 "차감 실패 → 즉시 만료 강등(dunning 미실시)"도 PLAN-5 확정 문언으로 갱신 권장.

**C-3 (T7) — 다이제스트 토글 저장 실패 시 렌더 템플릿 부재로 500 — [Phase 6 해소]**
- 위치: `app/controllers/app/notification_settings_controller.rb:10` — `render :update, status: :unprocessable_entity`
- 내용: `app/views/app/notification_settings/` 디렉터리 자체가 없다(ls 확인 — 파일 0건). 검증 실패 시 ActionView::MissingTemplate → 500. 토글은 boolean 단일 필드라 정상 데이터에서 실패 빈도가 낮지만, User 전역 검증(remind_* 검증 — context 없음·이번 배치 신설)이 모든 update save에 발동하므로 이상 데이터에서 도달 가능한 미구현 에러 경로다.
- PRD 규약: 응답 전략 — 실패 재렌더 `422`(ARCHITECTURE_CONVENTION). 422를 응답하려다 뷰 부재로 500 — 규약 자체 위반.
- 수정 방향(택1): ① `head :unprocessable_entity`(부분 갱신 대상이 토글 폼 하나뿐이라 충분) ② redirect with alert. `render :edit`은 @user 파셜 계약(app/shared/_noti_digest_setting이 user: @user 전제)과 불일치 — 권장하지 않음.

### WARNING

**W-1 (T7) — 주간 다이제스트 멱등의 동시 실행 DB 방어선 부재 — [3-S 후속 스키마 과제로 인계 승인]**
- `app/services/noti/weekly_digest_service.rb:72-75` — 결정적 키 `(user_id, template_key, scheduled_at)` exists?→create!는 재실행은 흡수하나 **동시 실행 경합에서 중복 MessageLog 2개·중복 발송 가능**. Reminders 선례(debtor×pending 부분 유니크 인덱스 — SEC-5 DB 방어선)와 격차. T7 03 문서의 "동시 실행 모두 중복 발송·이력 누적 없다"는 과잉 주장. 주 1회·단일 스케줄러라 확률은 낮다.
- 수정 방향: `message_logs`에 `(user_id, template_key, scheduled_at)` 부분 유니크 인덱스(digest=true 한정) 추가 또는 RecordNotUnique rescue 흡수. 후속 스키마 과제(payments.note와 함께 3-S 후속 런)로 명시 가능.

**W-2 (T7) — 집계 기간 "직전 7일" vs PRD 문언 "당주" 갭 (확인 요청) — [오케스트레이터 판정 인계]**
- PRD v0.41 NOTI-2: "집계: **당주** 만기·약속·수금 완료 건수/금액" / 구현: `[지난주 월 00:00, 실행 시각)` 직전 7일(`weekly_digest_service.rb:84-90`). 월요일 아침 기준 당주 집계는 9시간치 데이터뿐이라 구현 해석이 실용적으로 타당하나, PRD가 단일 소스 — PRD 문언 갱신(「직전 7일」 확정 문장) 또는 구현 정합 중 오케스트레이터 결정 필요. 파셜 문구는 이미 "지난 7일간"으로 구현과 일치.

**W-3 (T5) — admin orders/index 뷰의 행별 연관 접근(N+1) — [Phase 6 해소]**
- `app/views/admin/orders/index.html.erb:76-78` — 행마다 `order.user.subscription`(컨트롤러 수정 불가 제약 인정). 기존 `order.user.email` N+1 패턴 준용·페이징 범위 소규모라 수용하나, 컨트롤러 후속 정리 시 `includes(:user => :subscription)` 권장. 뷰어가 ADMIN 한정이라 정보 노출 문제는 없음(dunning 상태·시각만 표기).

**W-4 (A) — en.yml.bak이 .gitignore 미등록 — [Phase 6 해소]**
- `config/locales/en.yml.bak` untracked·.gitignore 규칙 없음(grep 확인). A 03 문서 자체가 ".gitignore 추가 권장"을 명시했으나 미반영 — 커밋 시 백업 파일 유입 리스크. 다음 커밋 전 `config/locales/*.bak` 추가 권장.

**W-5 (T8) — Q22 플래시 문구 "청구액을 N원 초과" 부정확 — [Phase 6 해소]**
- `app/controllers/app/payments_controller.rb:55` — over_amount는 **잔액** 초과 기준(`[amount - remain, 0].max`)인데 문구는 "청구액을 N원 초과". 부분입금 후 과다입금(누계가 총액을 넘지 않는 케이스)에서 사실과 어긋난다. "남은 잔액을 N원 초과했습니다"로 정정 권장. AuditLog detail("과다입금 초과분")은 중립이라 무해.

**W-6 (T8) — stale 주석 2건(구 결정 #3·감사 action 목록) — [Phase 6 해소]**
- `app/models/payment.rb:2-3` "잔액 초과 등록은 서비스 계층에서 차단한다(결정 #3)" — Q22로 폐기된 결정. `app/services/audit_logs/record_service.rb:3` action 확정 목록에 `payment_over_recorded` 미추가. 동작 무영향·P4 기록 자체는 정상 — 문서 단일 소스 정합 차원 정정.

**W-7 (T5) — next_retry_at nil 비교 방어 부재 — [Phase 6 해소]**
- `app/jobs/subscriptions/dunning_retry_job.rb:22`·`upgrade_service.rb:114` — `next_retry_at > Time.current`에 nil 방어 없음(소진 상태 stage=3·nil에서 Job이 실행되면 NoMethodError). C-1 수정(dunning_active? status 한정)으로 소진 상태가 dunning 비대상이 되어 도달 불가해지므로 별도 수정 불요 — C-1 수정 후 회귀 테스트로만 고정 권장.

## 공유 파일 특별 검증 — T6+T8(send_service.rb) 공존 정합: **통과**

지시서 요구사항(논리 충돌 검증) 코드 흐름 결과:

1. **partial_paid가 윈도우 게이트를 우회하지 않는다** — `call` 첫 줄 `return reschedule! if debtor? && outside_window?`(send_service.rb:38)은 recipient_role=debtor이면 template 무관 적용 → partial_paid(채무자 향)도 REM-3 창 밖이면 `reschedule!` → 다음 허용 슬롯 예약. 창 게이트 우회 없음.
2. **윈도우 이월이 partial_paid를 무한 지연시키지 않는다** — `User#next_remind_slot`은 허용 요일 최소 1개 보장(검증 `remind_wdays_within_fixed_boundary`)으로 루핑 반드시 종료(user.rb:130-140). 최악 이월 7일.
3. **예약→실행 흡수 정합** — 창 밖 부분입금: `reschedule!`가 pending 예약 로그 생성(scheduled_at=다음 슬롯) → 슬롯 실행 시 `claim_log` → `per_event_debtor_notice?` → `new_log!` → 기존 pending 예약과 부분 유니크(debtor×pending) 충돌 → RecordNotUnique rescue → `find_existing_log` → in_flight 해제(예약 시점 경과) 후 **그 로그를 갱신해 1통만 발송**. 이력 누적·이중 발송 없음.
4. **Q23 재발송 정합** — `per_event_debtor_notice?`(149-151)가 `step_sent?`·갱신 경로를 우회해 건마다 새 이력. 상한 집계는 `sequence_step?`(SEQUENCE_TEMPLATE_KEYS 밖)·`manual_cap_reached?` 모두 partial_paid 미포함 — Q10 "1회성 3종 상한 집계 제외" 유지. PLAN-3 문언과 정합.
5. **T6 위임 정합** — `outside_window?`→`User#remind_window_open?`·`next_window_at`→`User#next_remind_slot` 단일 출처 위임, U1 향(noti_opened 등)은 창 무관 즉시 기존 유지. WINDOW 상수는 문서화용 유지로 고정 경계 소스 이중화 아님(판정은 User 검증이 담당).
6. 마커 충돌 0건 — T6(226·256행 근방)과 T8(claim_log 61-62·146-151행)이 서로 다른 영역을 편집, 양쪽 변경 공존.

## Rule ID 준수 매핑

| Rule | 판정 | 근거 |
|:---|:---|:---|
| REM-3(세부 지정 — 고정 경계 내 축소만) | 통과 | 확장 3중 차단(모델 검증 user.rb:102-109 + 컨트롤러 서버 필터 profiles_controller + 헬퍼 선택지 9~18 범위). 기본값이 고정 경계 전체라 기존 사용자 무중단 |
| REM-3·시퀀스 스케줄링 반영 | 통과 | next_remind_slot 이월 — D+1/D+7 의미 불변·PLAN-3 상한·REM-12 종결 로직 무영향(발송 횟수 불변) |
| NOTI-2(월요일 아침·토글·NO_TEMPLATE) | 통과(W-2 문언 갭) | recurring `0 9 * * 1 Asia/Seoul` 기존 항목과 형식 일치·토글 기본 on·skipped(NO_TEMPLATE) 기록 — NOTI-3 선례 정합 |
| PLAN-5(dunning D+1·3·7·3회 cancelled) | 통과(재리뷰 — 초차 위반 해소) | dunning_active? active? 한정으로 해지 후 무차단 재차감·소진 후 만료 데드락 모두 해소. 재시도 스케줄·소진 cancel!·기간 말 만료 전 경로 PLAN-5 문언 정합 |
| PAY-2·Q22(과다입금/마감 후 재입금) | 통과(B-1 재리뷰 해소) | 초과 차단 폐기·실입금액 기록·마감·AuditLog 비고·기록만/알림 없음 — 문언 정합. remaining_amount 0 하한 클램프로 DASH-1 미수 집계·솔라피 "잔액" 변수 정합 |
| PAY-2·Q23(partial_paid 재발송·상한 제외) | 통과 | per_event 경로·Q10 산정 유지 — 위 특별 검증 4번 |
| SEC-5(멱등) | 통과(단 W-1 인계) | T7 주 단위 결정적 키(재실행 안전)·T3 첫열람 억제 면제·T8 부분 유니크 선점 유지 |
| SHARE-4·PERF-1 | 통과 | 기록 0건(첫 열람)은 억제 판정 없이 기록+mark_viewed!+noti_opened 인큐 — track_service.rb:23-38 |
| P4 | 통과 | digest 발송도 MessageLog 기록·partial_paid 건마다 이력·AuditLog 초과분 비고 |
| VIEW-8·SURF-3 | 통과 | 뷰어·랜딩 미수정 — T7 url은 U1 향 /app 링크로 뷰어(③)와 무관 |
| 소유권 격리 | 통과 | notification_settings=Current.user만·T7 집계는 @user.invoices 서브쿼리 스코프(누출 없음)·payments_controller set_invoice 기존 유지 |

## 통과 근거 (무결성·보안 확인 항목)

- **T3**: 억제 키 = invoice_id+정제 IP — 공유 오피스 IP에서 타 청구서 열람은 억제되지 않음(청구서 스코프). IP 정제(45자 절단·IPAddr 형식 검증·unknown 폴백)는 CF-Connecting-IP 원본 보존과 양립(개인정보 회귀 없음). 봇 UA 필터·HeadlessChrome 제외 의도 유지. 복합 인덱스 schema.rb:433 반영 확인.
- **T6**: 주말(0·6)·야간(<9·>18)은 서버 검증+서버 필터로 설정 자체가 저장 불가 — "고정 경계 침범 불가" 충족. csv 빈값 제출 → 검증 실패(최소 1일 강제).
- **T7**: suspended·phone 미보유·토글 off 사용자 제외. 집계 3지표 모두 사용자 스코프(due_within=unsettled 한정 재사용 — draft/voided 제외 확인). recurring.yml production/development 양쪽 동기화.
- **T8**: with_lock 직렬화·조건부 UPDATE 전이(INV-4) 유지. Payment amount>0 DB check constraint+모델 검증 이중 — 마감 후 amount 0·nil은 422로 흡수(schema.rb:280 확인). 마감 후 재입금은 상태 불변·알림 스킵 — PROMISE-7·INV-5와 무충돌.
- **A**: Thruster CACHE_CONTROL은 실제 지원 키(정적 서빙 Cache-Control) — public/fonts 셀프호스팅 폰트가 대상. portone_shared 추출은 두 컨트롤러의 customer 키 집합을 보존(billing=email 무조건(requireEmail)·payment=email 조건부 — 동등 확인), node 계약 유지. hello 잔존 참조 0건(grep). 제거 키의 ko.yml 이식 샘플 5키 확인(email/display_name/business_type/account_number/total_amount_must_be_positive) + default_locale=:ko라 t()는 ko.yml 단일 경로.
- **공통**: 3-S 단일 마이그레이션(컬럼명 vs 코드 참조 전수 일치 — users 3+1·subscriptions 3·message_logs.digest·view_events 인덱스), routes 1줄 결선(PATCH /app/notification_settings — 파셜 전제 헬퍼와 일치), 기존 라우트 무손상.

## Tester 중점 지시 (7-S 게이트 — 태스크별 경계 시나리오)

1. **B-1 회귀(최우선)** — 입금 4케이스(정상 부분/정확 전액/과다입금/마감 후 재입금) 모두 성공 303·플래시 정상. 수정 전 코드로는 전부 500임을 먼저 재현·고정하는 테스트 권장.
2. **C-1/C-2 회귀(T5) — 재리뷰 최우선** — ① 갱신 실패→stage1·D+1 예약 ② D+1·D+3·D+7 연속 실패→소진 cancel!→**다음 갱신 스윕에서 expire!·Free 강등 확인** ③ **dunning 중 수동 해지 후 D+1에 차감이 없음** 확인(가짜 차감 stub) ④ dunning 중 재차감 성공→reset_dunning!·주기 연장 정확 1회 ⑤ 모호 실패(TIMEOUT)는 dunning 진입 없음·웹훅 settle_renewal 시 reset ⑥ ADMIN members 표기(stage·다음 재시도·소진 문구) ⑦ cancel 후 기간 종료 전 구독 유지(해지 정책)·종료 후 Free 강등.
3. **T6 슬롯 이월 9시나리오** — 기본 설정: 금 18:00→월 09:00 / 토 10:00→월 09:00 / 월 07:30→당일 09:00 / 월 17:59→즉시 / 화·목 13~16: 월 14:00→화 13:00·화 16:00→목 13:00 / 창 내 임의 시각→즉시 / 비허용 요일→다음 허용일 start. + 주말·야간(start<9·end>18·wdays 0/6 포함·빈 배열) 설정 저장 422 / 시퀀스 5통 상한 불변(지연 후에도 CAP 5 초과 없음) / U1 향 noti_opened는 창 무관 즉시 유지.
4. **T7** — 같은 주 재실행 :duplicate / 템플릿 미등록 → skipped(NO_TEMPLATE)·주 1회만 기록 / 집계에 타 사용자 청구 미포함 / digest=true 단일_subject 면제·기존 청구·티켓 경로 검증 불변 / 토글 off·suspended·phone 빈값 제외 / NO_PHONE skip 경로.
5. **T8 4케이스** — 정상 부분(잔액 재계산·partial_paid) / 과다입금(remaining 0·paid·AuditLog "payment_over_recorded"·초과분 플래시) / 마감 후 재입금(payments 기록 추가·status paid 불변·알림 0·플래시 상태 유지 문구) / 반복 부분입금(sent partial_paid 이력 건마다 증가·수동 포함 총량 5통 불변). + 동시 2건 partial_paid 1통 / amount 0·nil·음수 422 / 기존 테스트 중 구 정책(초과 차단·마감 후 차단·1회 발송) 전제분 Q22/Q23 시나리오로 갱신 필드 확인.
6. **T3** — 첫 열람 기록+noti_opened 인큐 / 30분 내 동일 청구서+동일 IP 재열람 억제(이벤트 0·알림 0) / 31분 경과 재열람 기록 / 동일 IP·타 청구서는 억제 안 됨 / 잘못된 IP 헤더→ip="unknown" 기록 / UA 512자 초과 절단·device 판별 유지 / 봇 UA 무기록.
7. **en.yml 회귀 샘플** — 모델 검증 메시지 ko 노출(가입 blank·청구 폼 blank·금액 양수 위반) + 뷰 t() 샘플 + `en: ~` 파싱(부트·테스트 전수 통과가 실질 검증).
8. **C-3 확인** — 토글 저장 실패 강제(remind_* 이상 데이터 선주입) 시 422 응답·500 아님.

## 재리뷰 범위

B-1(컨트롤러-서비스 계약)·C-1/C-2(dunning_active? 상태 한정 — 수정 시 upgrade_service·subscription·관련 주석 포함 전후 diff)·C-3(422 경로)만 재검토. WARNING은 다음 런 통합 반영 허용. → **재리뷰 완료(상단). W-1은 3-S 후속 스키마 과제, W-2는 PRD 문언 판정으로 각각 인계 — APPROVED 판정에 불포함.**
