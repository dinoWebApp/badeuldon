## B분 — T2·T1·T3

2026-11-26 · Tester(절약 모드) · 격리 DB `DATABASE_URL=sqlite3:tmp/parallel/TSTB/test.sqlite3` · 시스템 테스트·전체 스위트 미실행(오케스트레이터 게이트 대상)

### 실행 명령·결과

```
DATABASE_URL=sqlite3:tmp/parallel/TSTB/test.sqlite3 bin/rails test \
  test/controllers/concerns/client_ip_test.rb \
  test/controllers/registrations_ip_rate_limit_test.rb \
  test/controllers/admin/sessions_controller_test.rb \
  test/controllers/viewer_controller_test.rb \
  test/jobs/phone_verifications/purge_job_test.rb \
  test/jobs/phone_verifications/recurring_registration_test.rb \
  test/controllers/admin/tickets_controller_test.rb \
  test/controllers/app/subscriptions_coupon_test.rb
  → 74 runs, 514 assertions, 0 failures, 0 errors, 0 skips

DATABASE_URL=sqlite3:tmp/parallel/TSTB/test.sqlite3 bin/rails test \
  test/controllers/viewer_controller_test.rb test/controllers/viewer_refusal_test.rb \
  test/controllers/viewer_promises_test.rb test/controllers/viewer_promises_rate_limit_test.rb \
  test/controllers/app/invoices_controller_test.rb test/models/invoice_test.rb \
  test/fixtures_no_future_date_test.rb
  → 145 runs, 935 assertions, 0 failures, 0 errors, 0 skips (T3 회귀)

DATABASE_URL=sqlite3:tmp/parallel/TSTB/test.sqlite3 bin/rails test \
  test/controllers/registrations_controller_test.rb
  → 14 runs, 87 assertions, 0 failures (가입 플로우 AUTH-9 회귀 — 파기 잡 무영향)

bin/rubocop (수정·신규 5파일) → no offenses
```

### 신규·수정 테스트 목록

| 파일:테스트 | Rule ID |
|:--|:--|
| `test/controllers/registrations_ip_rate_limit_test.rb` — "인증번호 발송 IP 한도는 CF-Connecting-IP별로 버킷이 분리된다"(20회 초과 429 → 다른 헤더 IP는 별도 버킷 통과) | AUTH-9·Q32 |
| `test/controllers/registrations_ip_rate_limit_test.rb` — "헤더 없는 요청은 remote_ip 버킷에 묶여 같은 한도가 적용된다" | AUTH-9·Q32 |
| `test/controllers/admin/sessions_controller_test.rb` — "CF-Connecting-IP 헤더의 새 IP는 new_ip_login 감사·new_login 메일(헤더 IP 인자)을 유발하고 재로그인은 무통보다" | AUTH-7.4·Q32 |
| `test/controllers/viewer_controller_test.rb` — "단일 IPv6 CF-Connecting-IP는 원문 그대로 기록된다" | SHARE-3·Q32 |
| `test/controllers/viewer_controller_test.rb` — "쉼표 목록 CF-Connecting-IP는 채택되지 않고 remote_ip로 수렴한다" | SHARE-3·Q32 |
| `test/controllers/viewer_controller_test.rb` — "콜론만 있는 값·옥텟 이탈 값 CF-Connecting-IP도 remote_ip로 수렴한다" | SHARE-3·Q32 |
| `test/jobs/phone_verifications/purge_job_test.rb` — "perform 뒤에도 방금 생성·consumed 행이 남아 가입 이중 검증(consumed_recently)이 통과한다" | AUTH-9 |
| `test/jobs/phone_verifications/recurring_registration_test.rb` — "recurring.yml에 파기 잡이 production·development 양쪽에 04:30 KST로 등록돼 있다"(신설 파일 — reminder_actions 선례 대조 방식) | AUTH-9 |

### FIX1 추가분 확인 (있으면 확인만 — 통과)

- `test/controllers/admin/tickets_controller_test.rb` CF 헤더(203.0.113.51) → `ticket_close` 감사 ip 단언 — 통과
- `test/controllers/app/subscriptions_coupon_test.rb` CF 헤더(203.0.113.42) → `coupon_redeemed` 감사 ip 단언(with_portone_client 스텁) — 통과

### 감사 호출 `ip:` 누락 전수 스캔 결과 (보고 전용 — 수정 없음)

컨트롤러 계층 `AuditLogs::RecordService.call`은 전부 `ip:` 보유(registrations·subscriptions·sales_reps 5곳·sales/sessions 3곳·tickets·sales_commissions·passwords·profiles·admin/sessions). 다만 **Service 계층 호출 11곳은 `ip:` 인자가 없다**(컨트롤러가 아닌 곳이라 request 접근이 없는 구조 — `Service→Current/params 금지` 규약상 컨트롤러에서 ip를 넘겨야 하나 미구현):

- `app/services/payments/record_service.rb:101`
- `app/services/admins/member_admin_service.rb:45`, `:98`
- `app/services/admins/role_service.rb:33`, `:47`, `:63`, `:81`, `:100`
- `app/services/admins/account_purge_service.rb:38`
- `app/services/orders/refund_service.rb:82`, `:240`, `:322`

(단, `users/withdrawal_service.rb:33`은 ip를 인자로 받아 기록함 — 서비스 경유도 구현 가능함을 보이는 선례.) ADMIN-2 완전 커버를 위한 후속 과제 후보 — 결함 아님(요구 범위는 컨트롤러 진입점).

### 앱 결함 후보

**없음.** 모든 보강 시나리오가 현재 구현과 일치해 통과했다(FAIL 테스트 0건 — 결함 재현 없음).

### 확인된 현재 동작 (결함 아님 — 정책 고정)

- `fe80::1%eth0`(zone id)은 IPAddr이 유효 주소로 파싱해 헤더에서 채택된다 — FIX1 실측표와 동일(FIX1 테스트가 고정).
- 쉼표 목록·`:`·`999.999.999.999`는 원문 기록 없이 `REMOTE_ADDR`로 수렴 — 기존 `.presence`와 달라진 유일 지점이 의도대로 동작함을 고정.
- 헤더 없는 등록 rate limit은 기존대로 remote_ip 버킷(127.0.0.1) 20회/1h.
- 파기 잡은 consumed(30분 창)·방금 생성 행을 유지해 `consumed_recently` 가입 이중 검증이 무영향.

### 플레이크 관찰

- 없음. 3회 실행 구간(단독/회귀/가입)에서 재현 불안정 0건.
- T3 지시 사항: `already initialized constant` 경고 — 회귀 실행 출력에서 **0건**(grep -c = 0, FIX2의 I-1 ERB 지역 변수 전환 반영 확인).

---

## A분 — T5·T4

2026-11-26 · Tester(절약 모드) · 격리 DB `DATABASE_URL=sqlite3:tmp/parallel/TSTA/test.sqlite3` · 시스템 테스트·전체 스위트 미실행(오케스트레이터 게이트 대상)

### 실행 명령·결과

```
DATABASE_URL=sqlite3:tmp/parallel/TSTA/test.sqlite3 bin/rails test \
  test/services/reminders test/services/dashboards test/models/client_test.rb \
  test/services/promises test/controllers/app/clients_controller_test.rb \
  test/controllers/app/clients_reminders_test.rb test/controllers/app/invoices_reminders_test.rb
→ 253 runs, 1392 assertions, 0 failures, 0 errors, 0 skips

bin/rubocop (신규·수정 테스트 5파일) → no offenses
```

솔라피 실호출 0건 — 발송 경로는 기존 주입 체계(FakeSolapiClient 생성자 주입·SendService client: 인자)만 사용.

### 신규 테스트 목록 (12건)

T5 — 사전통보 실제 발송 시각 정합(`test/services/reminders/prenotice_service_test.rb`):

| 테스트 | Rule ID |
|:--|:--|
| 「09:05 실행에서 오늘 09시 pending 슬롯은 경과로 보아 통보하지 않는다 — 운영 지배 분기」(② 폴백=수 09:00까지 단언 — 리뷰 W-1 필수분) | REM-11 |
| 「오늘 09시 슬롯이 이미 sent면 예정이 소멸해 통보하지 않는다 — 정각 경합 삼태계 ①」(②=위 테스트·③=기존 동률 테스트 — 주석 상호 참조) | REM-11 |
| 「due 키가 내일 슬롯에 미뤄져 있으면 통보하지 않는다 — 슬롯 시각이 우선한다」 | REM-11 |
| 「다른 키의 pending 슬롯은 사전통보 판정에 흘러들지 않는다 — due 키만 산정한다」 | REM-11 |
| 「시작 10시·종료 14시 회원은 오늘 10시 슬롯을 ①로 통보한다 — 09시 겹침은 시작 09시 회원 특유」(리뷰 W-2 경계) | REM-11 |
| 「기본 창 회원의 noti_prenotice와 noti_due_soon은 병행한다」 | NOTI-1 |
| 「종료 14시 회원은 prenotice는 생략돼도 noti_due_soon은 나간다」 | NOTI-1·REM-11 |
| 「대시보드 오늘 발송 예정 카드와 사전통보는 같은 상태에서 함께 갈린다 — 기본 창·종료 14시·시작 15시」(카드 send_at 14:00/15:00까지 단언) | DASH-2·REM-11 동치 |

T4 — 수신 거부 번호 고정:

| 파일:테스트 | Rule ID |
|:--|:--|
| `test/services/promises/register_service_test.rb` — 「번호를 바꾼 거부 행의 재접수는 현재 번호만 전파하고 거부 시점 번호는 불변이다」(R 불변=A·B 전파·A 행 무영향) | VIEW-7·Q30 — 리뷰 Tester 1(5-d) |
| `test/services/promises/register_service_test.rb` — 「refusal 전파로 거부된 거래처의 다른 청구 발송은 REFUSED skip으로 기록된다」(skip 이력 1건·실발송 0) | VIEW-7·Q30·P4 |
| `test/models/client_test.rb` — 「레거시 단독 마킹(refused_phone nil) 행도 현재 번호로 상속하며 상속 행은 자기 치유된다」(**폴백 제거 시 깨지는 의도된 센서** — 주석 명시) | VIEW-7·Q30 |
| `test/controllers/app/clients_controller_test.rb` — 「refused_phone이 채워진 원천의 상속 등록도 고지 문구로 303 안내된다」(1순위 경로 — 기존 4테스트는 폴백 경로) | VIEW-7·Q30 |
| `test/controllers/app/clients_reminders_test.rb` — 「refusal 전파로 거부된 거래처의 목록·상세에는 수신 거부 배지가 보이고 재개 버튼이 없다」(실제 RegisterService 접수 경로의 전파) | VIEW-7·Q30 |

### 앱 결함 후보

**없음.** 추가한 12건이 모두 현재 구현대로 통과했다(코드 수정 0건·실패 재현 테스트 0건).

### 확인된 현재 동작 (결함 아님 — 설계 공간의 기록)

- **한 청구의 steps_due_today에 사전통보 키 2개가 같은 날 도래하는 조합은 구조적으로 불가능** — base 트랙 키 간격 6일(confirm_d1↔requeue_d7·final_d14)·약속 트랙의 사전통보 키는 promise_overdue 하나뿐이고 소급 창(공칭일~다음 평일)이 절대 겹치지 않는다. 리뷰 중점 3의 "두 스텝 갈라짐"은 (a) due 키가 내일 슬롯으로 미뤄지면 통보 0 (b) due_keys 밖 키의 슬롯은 무영향으로 통보 1 — 키 격리 단언으로 대체했고 `today_send?`의 `any?` 의미는 이 조합으로 검증된다.
- 정각 경합 삼태계: sent 선점 → 0·pending 경과(09:05) → 0·동률(09:00:00) → 1 — 거짓 양성 없음으로 수렴.
- 전파는 "지금 그 번호를 가진 미거부 행"만 대상이며, 거부 행의 번호 이동 뒤 재접수는 refused_phone(거부 시점 번호)을 갱신하지 않는다 — 이동 전·후 번호 양쪽의 차단 논리가 일관.

### 플레이크 관찰

- 없음. 동일 스위트 2회 반복 실행에서 편차 0.
- 대시보드 동치 테스트는 3개 창을 한 테스트에서 순회하며 `MessageLog.where(invoice_id:).delete_all`로 상태 초기화(기존 주말 소급분 테스트와 같은 travel 블록 내 대조 패턴).
- SendRow는 invoice 객체 비교를 쓴다(`row.invoice == invoice` — Struct에 invoice_id 접근자 없음).
- 기존 테스트 무수정 — 전건 기존 선례 헬퍼(`run_prenotice`·`assert_prenotice_step_present`·`ReminderFactories`) 재사용.
