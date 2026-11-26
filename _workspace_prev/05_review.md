# 05_review — 병렬 배치(절약): 후속 과제 뭉치 (2026-11-26, Reviewer 4명 병렬·정적 리뷰·reviewer-lite GLM-5.3-Flash/max)

리뷰어 프로필에 쓰기 도구가 없어 최종 답변으로 돌려준 산출물을 오케스트레이터가 옮겨 적었다(내용 무변경·HTML 엔티티만 복원).
네 리뷰어 모두 테스트를 실행하지 않았다(테스트 결과는 오케스트레이터가 확인: 통합 1,699 runs 0 failures).

## 진행

| 태스크 | status | BLOCKER | CRITICAL | WARNING |
|:---|:---|---:|---:|---:|
| T2 클라이언트 IP 통일 | APPROVED | 0 | 0 | 3 (W-1 IPAddr 교체·W-2 감사 IP 누락 2곳 수정·W-3 운영 노트) |
| T4 수신 거부 번호 고정 | APPROVED | 0 | 0 | 2 (W-1 오전 배치 산출물로 확인·무조치 / W-2 주석 보정) |
| T5 사전통보 발송 시각 정합 | APPROVED | 0 | 0 | 2 (W-1 테스트 1건 보강 / W-2 PRD 문서 반영) |
| T1·T3 파기 잡·픽스처·가드 | APPROVED | 0 | 0 | 1 (T3 I-1 ERB 지역 변수 전환 — T1은 W0) |

---

## T2 — 클라이언트 IP 전역 통일 (ADMIN-2·Q32)

### 1. 결론

**APPROVED** — BLOCKER·CRITICAL 0건. WARNING 3건은 후속 반영 권고 수준이며 재리뷰를 요구하지 않는다. 헬퍼 판정 규칙은 PRD Q32·ADMIN-2 문언("CF-Connecting-IP 우선 — 없거나 단일 IP 형태가 아니면 request.remote_ip 폴백, 전역 헬퍼 단일 출처")과 정확히 일치하고, 적용처 전수·기존 동작 보존·테스트 보강 모두 정합한다.

### 2. 심각도 집계

B 0 · C 0 · W 3

### 3. 이슈 목록

**W-1** `app/controllers/concerns/client_ip.rb:10,12` — IPv6 정규식이 형태 소거용으로 느슨해 무의미한 값도 채택된다. 정적 대입 평가: `":"`(빈 그룹+콜론 1회·빈 꼬리)·`":::"`·`"1:::2"`(빈 그룹 연속)·`"::ffff:1.2.3"`(IPv4 꼬리 1~3옥텟 허용)이 모두 통과하고, IPV4는 `"999.999.999.999"`를 통과시킨다(코드 주석이 이 절충을 명시적으로 기록 — 의도된 설계). 반면 `IPAddr.new(값)` 기반 판정은 위 변형값을 전부 거부하면서 유효한 전체형(`0000:…:ffff:255.255.255.255` 45자 매핑형 포함)은 전부 수용하므로 더 엄밀하고 구현도 단순해진다(`require "ipaddr"` 필요). 영향은 비정상 문자열이 감사·세션·`last_login_ip`에 그대로 저장되는 정도로, 운영에서는 CF가 헤더를 엣지에서 덮어쓰고 직접 경로가 없어(공개 포트 0) 위조 경로가 없다 — CRITICAL이 아닌 WARNING. 제안: `begin; IPAddr.new(header); rescue ArgumentError; end` 성공 시 채택으로 교체하거나, 정규식 유지 시 IPV6 꼬리를 `{0,3}`→정확히 4옥텟(또는 없음)으로 강화. 기록값은 원문 헤더 문자열을 유지해 P4 원문성을 보존하는 것을 권한다.

**W-2** `app/controllers/admin/tickets_controller.rb:71` — 관리 행위 감사 `ticket_close`에 `ip:` 인자가 없어(nil) ADMIN-2 감사 로그 중 유일하게 IP가 기록되지 않는다. T2의 취지("감사 로그 ip 전역 통일")와 불일치하며, 플랜 적용처 목록(세션 5종·재설정·영업 4종·sales_reps·sales_commissions·가입·탈퇴)에 누락된 것으로 보인다. `ip: ClientIp.of(request)` 추가를 권한다. 같은 패턴으로 `app/controllers/app/subscriptions_controller.rb:50`(`coupon_redeemed` — admin nil의 사용자 행위)도 `ip:` 없음이나 우선순위는 낮다. 플랜 목록 밖 파일이므로 3-S 결선이나 후속 태스크 반영 제안.

**W-3** 배포 직후 운영 혼란 예방(코드 변경 불요) — 기존 `admins.last_login_ip`에는 터널 IP(예: 127.0.0.1)가 저장돼 있어 배포 후 각 관리자의 첫 로그인에서 `notify_new_ip`가 1회 발동한다(신규 IP 메일 1통 + `new_ip_login` 감사 1건, 이후 `last_login_ip`가 실방문자 IP로 갱신돼 재발 없음). 기능상 허용 가능한 일회성 오탐이지만 AGENTS.md 운영 노트에 1행 기록을 권한다.

### 4. A·B 항목별 판정표

| 항목 | 판정 | 근거 |
|---|---|---|
| A1 판정 규칙 구현 일치 | 적합 | `client_ip.rb:16-21` — strip 후 `IPV4/IPV6` 매치 시 채택, 그 외 `request.remote_ip` 폴백. PRD Q32·ADMIN-2 문언과 동일 |
| A2 형식 검증 엄밀성 | 조건부 적합(W-1) | 형태 소거 의도는 문서화됐으나 콜론 전용·부분 옥텟 꼬리 통과 — IPAddr 기반이 더 엄밀(상세는 W-1) |
| A3 신뢰 경계 | 성립 | Cloudflare는 엣지에서 `CF-Connecting-IP`를 클라이언트가 보낸 값과 무관하게 덮어쓰는 공개 스펙 동작. 운영 수신 경로는 CF 터널→kamal-proxy(127.0.0.1 바인딩)·공개 포트 0·관리면 Tailscale뿐이라 헤더 위조는 내부망(운영자 신뢰 영역)에서만 가능. 로컬·테스트의 위조 가능성은 운영 판단과 무관. 근거 주석이 `client_ip.rb:1-7`에 기록돼 있어 구성 변경 시 검토 단서가 남는 것도 적절 |
| A4 폴백 조건 전수 | 적합 | 무헤더(`nil.to_s=""`)·빈 값·공백(strip 후 빈 문자열)·쉼표 목록(공백 유무 무관·`.`이 정규식에 없거나 콜론 반복에 불일치)·형식 불일치(포트 접미 `1.2.3.4:8080`·zone id `fe80::1%eth0`·9그룹 IPv6) 모두 폴백 확인 |
| B5 적용처 24곳·람바·시그니처 | 적합 | diff 전수 대조 — 보고서 목록과 실제 변경 1:1 일치. `rate_limit by: -> { ClientIp.of(request) }`는 기존 `-> { request.remote_ip }`와 동일한 인자 없는 람바·동일 컨트롤러 인스턴스 문맥 평가. `AdminSession.issue_for!(admin, ip:)`·`SalesRepSession.issue_for!(rep, ip:)`·`AdminMailer.new_login(admin, ip)` 시그니처 불변. `notify_new_ip`의 비교·메일 인자·감사 3곳이 모두 같은 헬퍼로 통일됐고 C-2 선례 순서(발급→판정→기록) 보존. `ClientIp.of(request)`는 모듈 함수 직접 호출이라 include 불요·Zeitwerk 상수 해석 정상 |
| B6 잔존 `request.remote_ip` | 적합 | `grep -rn "request.remote_ip" app/` → `client_ip.rb:20`(폴백 본체)만 유일. 다른 CF 헤더 직접 참조도 0건 |
| B7 뷰어 위임 동등성 | 적합(+개선) | 헤더 있음→헤더, 없음→remote_ip 동일. 유일한 동작 차이는 비정상 비어있지 않은 값(쉼표 목록 등)이 기존엔 `presence` 통과로 ViewEvent.ip에 원문 기록됐으나 이제 폴백 — "동작 불변"에서 벗어나지만 Q32 규격이 오히려 이것을 요구하므로 개선이며 기존 viewer 테스트(채택/폴백/빈 값/45자 매핑형)와 충돌 없음 |
| B8 배포 직후 영향 | 허용(W-3) | 관리자당 신규 IP 알림·감사 1회 발생 후 수렴 — 상세는 W-3 |
| B9 기존 동일값 IP의 기능 영향 | 없음 | `AdminSession`·`SalesRepSession`은 TTL(절대+비활동)만으로 검증하고 IP 비교 로직이 없다 — 하이재킹 감지에 IP를 쓰지 않는 구조라 과거 동일값 잔존이 기능에 영향 없음. `last_login_ip` 비교는 직전 로그인 1회 기준(AUTH-7.4 최소 구현)이라 첫 로그인 후 자동 수렴 |
| 아키텍처 | 적합 | 계층: 컨트롤러→헬퍼 모듈(모델·Service 역전 없음)·Job·뷰 접촉 없음. `PortOne::ChannelKey`·`TaxInvoice` 선례와 같은 단일 판정 출처 모듈 패턴. 액션 본문 구조 변경 없음(표현식 교체만) |

### 5. Tester 중점 제안

1. **rate limit 버킷 분리**: 같은 `REMOTE_ADDR`에서 `CF-Connecting-IP`를 "1.2.3.4"와 "5.6.7.8"로 바꿔 `send_phone_code` 21회 — 헤더별로 별도 버킷(40회까지 통과)이고 헤더 없이는 기존 한도에 걸리는지 단언(AUTH-9 — 현재 미커버).
2. **새 IP 감지의 CF 헤더 경로**: `last_login_ip`가 "127.0.0.1"인 상태에서 CF 헤더 "203.0.113.7" 로그인 → `new_ip_login` 감사 1건 + `AdminMailer.new_login` 인자가 헤더 값인지(보강 테스트는 login_success·last_login_ip만 단언 — 분기 미경유).
3. **ViewEvent.ip 경계 보완**: 쉼표 목록 헤더가 원문 기록되지 않고 `REMOTE_ADDR`로 수렴하는지(기존 `.presence` 동작과 달라진 유일 지점이라 고정 가치 있음), W-1 해소 방향에 따라 `"::::"`·`"999.999.999.999"`의 채택/폴백 정책을 양성·음성으로 고정.
4. **W-2 반영 시**: `ticket_close` 감사 행의 `ip`에 헤더 값 기록 단언.

### 6. 테스트 실행

정적 리뷰 — 테스트 미실행(Developer 보고의 지정 10파일 134 runs·0 failures 신뢰, 파일·헬퍼·픽스처 정적 대조로 재현 불요 판단).

**리뷰 대상 파일**: `app/controllers/concerns/client_ip.rb`(신설) 외 교체 9파일 — 전부 `git diff`로 대조 완료. `profiles_controller.rb`의 탈퇴 기능·`clients/dashboards/invoices_controller.rb` 변경분은 타 태스크 소유로 T2 판정에서 제외(해당 파일 내 T2 변경은 `ip: ClientIp.of(request)` 1곳뿐임을 확인).

---

### 오케스트레이터 처리 결정 (T2)

- **W-1(IPv6 정규식 느슨)**: 고친다 — 표준 라이브러리 `IPAddr.new` 기반으로 교체(원문 헤더 문자열은 그대로 기록). 변형 값이 감사 로그에 섞일 여지를 없앤다.
- **W-2(감사 IP 누락 2곳)**: 고친다 — `admin/tickets_controller.rb` `ticket_close`·`app/subscriptions_controller.rb` `coupon_redeemed`에 `ip: ClientIp.of(request)` 추가(이번 배치의 다른 태스크가 두 파일을 건드리지 않으므로 수정 라운드 소유로 추가).
- **W-3(배포 후 일회성 신규 IP 알림)**: 코드 수정 없음 — AGENTS.md 운영 노트에 기록.
- **Tester 중점 제안 1~4**: Phase 7 Tester 지시서에 포함.

---

## T5 — 사전통보 실제 발송 시각 정합(REM-11) + SendSchedule 공용 객체 추출

### 1. 결론

**APPROVED** — 심각도 집계 **B 0 · C 0 · W 2**

추출된 `SendSchedule`은 직전 오전 배치(T3)에서 2차 리뷰까지 검증된 send_at 규칙(① pending 슬롯 우선·지나간 슬롯 폴백, ② `user.next_remind_slot(다음 스캔 시각)`)을 로직·경계 판정(`>=`, nil 가드, `Time.current < scan`)까지 그대로 옮겼고, 대시보드는 완전 위임으로 죽은 코드 없이 동작 불변이다. 사전통보 선별은 `steps_due_today` 단일 진입점 위에 "실제 발송일이 오늘" 필터만 얹었고 모집합·멱등·noti_due_soon 경로는 불변이다. 케이스 ①~⑥ 추적에서 통보가 실제 발송과 거짓으로 어긋나는(사실 아님 통보) 경로는 남지 않았다. W 2건은 막는 수준이 아니다.

### 2. 이슈 목록

| # | 심각도 | 파일:줄 | 문제 | 제안 |
|:--|:--|:--|:--|:--|
| W-1 | WARNING(테스트 정합성) | `test/services/reminders/prenotice_service_test.rb:198-211` | 「전날 재예약된 오늘 09시 슬롯은 통보한다」 테스트가 `travel_to`로 정확히 09:00:00.000에 고정돼 있다. 이 순간에만 `slot.scheduled_at >= Time.current`(send_schedule.rb:21)이 참이 되어 ① 경로로 통보한다. 운영에서는 사전통보 잡이 09:00:00+ε에 실행되므로 `>=`가 실패해 ② 폴백(내일 09시) → **통보 없음**이 지배적 결과다(슬롯이 먼저 sent가 돼도 `step_sent?`로 due_keys에서 빠져 통보 없음). 즉 테스트와 구현 문서의 케이스표("양성(① 경로)")는 운영에서 확률 ≈ 0인 정각 동률 분기만을 증명한다. 동작 자체는 안전 방향(거짓 "오늘 예정" 통보 없음, 발송은 슬롯이 그대로 실행, 자정~09시 대시보드 카드가 취소 창 제공)이라 CRITICAL이 아니다. | 정각 동률 테스트는 `>=` 경계 의미 기록용으로 유지하되, 운영 지배 분기를 고정하는 1건을 추가한다 — `travel_to("2026-11-10 09:05")` + 09:00 pending 슬롯 → `assert_empty u1_logs_for(invoice)`(DeliverJob 지연 상정). 또는 양성을 08:00(슬롯 미래)으로 재고정. `03_implementation.md` 케이스표의 ⑤ 행에 "운영 09:00+ε에서는 통보 생략(안전)"을 병기. |
| W-2 | WARNING(문서·PRD 정합) | `PRD.md` REM-11 문단, `app/services/reminders/prenotice_service.rb:38` | 시작 시각이 09시인 좁은 창 회원(예: 09~14)의 재예약 슬롯은 **항상 09:00**(remind_slot_on이 start_hour 사용)이라 사전통보 잡 실행 시각과 정확히 겹친다. 결과적으로 이 회원들은 알림톡 사전통보를 구조적으로 거의 받지 못한다(① 경계 실패 → ②가 다음 날을 내므로). REM-11의 "당일 아침 알림톡"은 이 모집단에 빈 곳이고, 취소 창은 DASH-2 카드(자정~09시)만이 제공한다. PRD의 신설 문장("실제 발송 예정 시각이 오늘인 청구만 통보")은 제한 조건이라 위반은 아니지만, 이 귀결이 문서에 없다. | PRD REM-11 문단에 한 줄 보강(코드 변경 불요): "재예약 슬롯이 09시(사전통보 실행 시각)와 일치하는 회원은 알림톡 통보 대신 대시보드 「오늘 발송 예정」 카드가 당일 취소 창을 제공한다(같은 SendSchedule 산정)". 오케스트레이터 문서 반영 대상. |

메모(집계 제외):
- `app/services/dashboards/reminder_actions_service.rb:11-24` — ①② 규칙 설명이 `SendSchedule` 헤더와 2중화됐다. 23~24행의 "추출됨·복제 금지" 포인터가 드리프트 위험을 흡수하므로 그대로 둬도 되나, 후속 정리 시 11~22행을 포인터로 축소해도 좋다.
- `today_send?`의 키별 MessageLog 조회 + 슬롯 계산은 사전통보 모집단(연체 도래분)이 작아 성능 영향 없음 — Developer 우려 2에 동의.
- 주말 소급분 테스트의 `MessageLog.delete_all`(prenotice_service_test.rb:223)은 travel 블록 내 전체 삭제라 넓지만, 단일 테스트 내 대조 전용이고 단언은 청구별 스코프라 수용.

### 3. A·B 항목별 판정표

#### A. 공용 객체 추출

| 항목 | 판정 | 근거 |
|:--|:--|:--|
| A1. 로직 이전 충실성 | **정합** | send_schedule.rb:18-37이 T3 03 문서·2차 리뷰가 확정한 규칙과 1:1 — ① `find_by(debtor×pending)` + `slot && slot.scheduled_at && slot.scheduled_at >= Time.current`(nil 가드·`>=` 경계 유지), ② `user.next_remind_slot(next_scan_time)`. next_scan_time은 `SCAN_WDAYS.include?(today.wday) && Time.current < scan` → 오늘 스캔, 아니면 다음 스캔 요일 — 오전 T3 2차가 승인한 "14:00:00 → 내일" 경계와 동일. `SCAN_HOUR`·`SCAN_WDAYS`는 DispatchService 상수 단일 출처 참조(recurring.yml `"0 14 * * 1-5"`와 대조 테스트가 드리프트를 잡음). |
| A2. 대시보드 위임 동작 불변 | **정합** | reminder_actions_service.rb:66-79 — `TodaysSendsQuery` → `scheduled_today_keys` → `SendSchedule.send_at_for` → `to_date == today` 필터 → `SendRow`, 절단 전 `sort_by.with_index { [send_at, invoice.id, index] }`(오전 정렬 그대로), `first(DASH_ACTION_LIMIT)`+`size`로 `*_total`. Free는 Query가 `Invoice.none`. 프라이빗 `send_at_for`·`next_scan_time` 소멸 확인(grep — app 전역에 잔존 참조 없음). 테스트 파일 무수정 실측 확인(mtime). |
| A3. 의존 방향(§4) | **정합** | `SendSchedule`은 `MessageLog`·`User`(모델)·`DispatchService` 상수(동일 Reminders 도메인)만 사용 — params·Current 없음, Service→Model 정방향. 대시보드 도메인 → 리마인더 도메인은 공개 진입점만 호출(§4.3). |

#### B. 사전통보 선별

| 항목 | 판정 | 근거 |
|:--|:--|:--|
| B4. 단일 진입점 위 구조 | **정합** | diff 대조 — `steps_due_today`(PRENOTICE_KEYS·상한 제외·소급 창) 호출부 불변, 그 뒤에 `today_send?` 필터만 추가. 가드 순서 `빈 due_keys → reminder_eligible? → today_send?`로 오늘 아닌 조회를 자격 없는 건에 실행하지 않는 최적화(결과 동일). `scheduled_at: today_at_9`·`noti_due_soon`·`dispatchable` 전부 불변. |
| B5-① 기본 창(09~18)·오늘 nominal | **정합** | 09시 실행 → `next_scan_time`=오늘 14:00 → `next_remind_slot(14:00)`=창 개방 → 오늘 14:00 → 통보. 실제 14시 스캔도 창 개방이라 즉시 발송 — 일치. |
| B5-② 종료 14시(09~14) | **정합** | `next_remind_slot(오늘 14:00)` → 14 < 14 실패·14 < 9(시작) 실패 → 다음 허용 요일 09:00 → 오늘 아님 → 통보 없음. 실제로 14시 스캔이 `reschedule!`→ 같은 값. 통보=실제 발송일. |
| B5-③ 시작 15시 | **정합** | `next_remind_slot(오늘 14:00)` → 허용 요일·14 < 15 → 오늘 15:00 → 통보. 실제 14시 스캔이 오늘 15시 슬롯으로 재예약 — 일치(6시간 취소 창). |
| B5-④ 오늘 비허용 요일 | **정합** | wday 불일치 → 다음 허용 요일 시작 시각 → 통보 없음. 실제도 14시 스캔이 같은 날로 재예약. |
| B5-⑤ 전날 재예약 오늘 09시 슬롯 | **정합(경계는 W-1)** | travel 동률에서는 ①로 오늘 09:00 반환 → 통보(테스트). 운영 09:00:00+ε에서는 `>=` 실패 → ② → 다음 날 → 통보 생략. 이때 실제 발송은 슬롯(DeliverJob)이 그날 실행하므로 "통보 없음+발송 있음"이 남지만, 09시 동시 발착에서는 알림톡이 발송에 앞설 수 없어(REM-11 취소 창 목적상 무의미) 안전 — 자정~09시 DASH-2 카드가 같은 판정으로 창 제공. 거짓 통보(사실 아님)는 발생하지 않는다. |
| B5-⑥ 주말 소급분 월요일 | **정합** | 토 만기→confirm_d1 nominal 일→창 종료 월. 월요일 09시: 기본 창은 ② 오늘 14:00 → 통보(월 14시 실발송과 일치), 종료 14시는 ② 화 09:00 → 통보 없음(실제 화 09시 슬롯 발송과 일치). |
| B6. 09:00 정각 경합 | **대책 불필요(관찰)** | 슬롯이 먼저 sent → `scheduled_today_keys`의 `step_sent?`가 due_keys에서 제외 → 통보 없음. 진행 중(pending·경과) → ② 폴백 → 좁은 창 회원은 생략(안전), 기본 창 회원의 레거시 슬롯은 "오늘" 통보가 여전히 사실. 추가 가드 불요. |
| B7. REM-11 취지 정합 | **위반 아님(W-2 문서화 권장)** | "전날 09시 통보가 오늘 발송 예정으로 맞히는가" — **아니다**: 통보는 일 단위 스코프(`to_date == Date.current`)라 전날의 `send_at=오늘` 건은 전날에도 통보하지 않는다. 좁은 창 회원의 알림톡 사전통보는 구조적으로 부재가 되지만, ① 09시 발송엔 어떤 알림톡도 앞설 수 없고 ② 취소 창은 DASH-2 카드로 보존되며 ③ PRD 문장은 "오늘인 건만 통보"의 제한 조건이다. P1~P5·REM-11 목적(오발송 차단 기회)은 화면 경로로 충족 — 코드 변경 불요, PRD 한 줄 보강만 권장. |

### 4. C. 테스트 품질

| 항목 | 판정 | 근거 |
|:--|:--|:--|
| SendSchedule 8건 | **양호** | 13:59:59→오늘/14:00:00→내일(양·음 경계)·토요일→월·금 저녁→월·슬롯 미래 ①(08:00)·경과 슬롯→② 폴백·nil pending→② 폴백·U1 향 미인식 — 양성·음성 모두 고정. `travel_to` 고정일+청구 고정 만기일 조합으로 날짜 폭탄 없음. |
| Prenotice 보강 5건 | **양호** | 5건 모두 `assert_prenotice_step_present`(steps_due_today 독립 선단언 — 공허 단언 방지) 후 통보 행 수를 양성 1건/음성 empty로 단언. FakeSolapiClient 주입으로 솔라피 실호출 차단 체계 유지. |

### 5. Tester 중점 제안

1. **09:05 지연 슬롯 케이스(W-1)** — 종료 14시 회원·오늘 09시 pending 슬롯·travel 09:05 → `run_prenotice` 후 통보 0건. 운영 지배 분기(② 폴백 생략)의 회귀 고정. 현재 스위트에는 이 결과를 단언하는 테스트가 없다.
2. **정각 경합 삼태계** — 같은 슬롯에 대해 ① sent 선점(슬롯 status sent + run → 0건) ② pending 진행 중(위 1번) ③ 동률(기존 테스트) — 세 결과가 모두 "거짓 양성 없음"으로 수렴하는지.
3. **두 스텝 갈라짐** — 한 청구의 due_keys 중 한 키는 오늘(② 14:00), 다른 키는 내일 슬롯 → `any?`로 통보 1건(오늘 스텝 기준).
4. **시작 10시·종료 14시 회원** — 슬롯이 10:00에 찍히는 변형 → 사전통보 09시에 ①로 통보하고 실제 10시 발송과 정합. W-2가 가리키는 공백이 "시작 09시" 특유임을 경계로 고정.
5. **noti_due_soon 병행 회귀** — 오늘 연체 스텝+내일 만기 청구에서 noti_prenotice와 noti_due_soon이 모두 나가는지.
6. **대시보드↔사전통보 동치** — 같은 (회원·청구·슬롯) 상태에서 DASH-2 카드 노출과 noti_prenotice 발생이 항상 동치임을 확인하는 시나리오.

### 6. 테스트 실행

정적 리뷰 — 테스트 미실행.

---

### 오케스트레이터 처리 결정 (T5)

- **W-1(09시 정각 동률 테스트)**: 운영 지배 분기(09:05 지연 슬롯 → 통보 없음) 고정 테스트 1건을 Phase 7 Tester에 지시.
- **W-2(PRD 문서)**: PRD REM-11에 "재예약 슬롯이 09시와 겹치는 회원은 알림톡 통보 생략·당일 취소 창은 대시보드 카드가 제공, 전날 통보는 후속 과제" 문장을 반영했다(코드 불변).
- **메모(대시보드 서비스 헤더 2중화)**: 후속 정리 과제로 기록.
- **Tester 중점 제안 1~6**: Phase 7 Tester 지시서에 포함.

---

## T4 — 수신 거부를 거부 시점 번호에 고정(VIEW-7·Q30)

### 1. 결론: **APPROVED**

BLOCKER 0 · CRITICAL 0 · WARNING 2. 구현은 PRD VIEW-7의 "알려진 한계 해소 구현 확정(2026-11-26)" 문단과 Q30 결정("같은 회원 안에서 번호 단위 — 접수 시 전파·등록·수정 시 상속. 다른 회원에는 영향 없음")에 정합하며, 행 단위 `refused?`·발송 가드·재개 불가·되돌림 없음 원칙은 불변이다.

### 2. 심각도 집계: B 0 · C 0 · W 2

### 3. 이슈 목록

**W-1 · 작업 보고 불일치 — `app/controllers/app/clients_controller.rb:78`(신설 `client_saved_notice`)·`test/controllers/app/clients_controller_test.rb:324~409`(신설 4테스트)**
HEAD(d658c78)에는 존재하지 않는 변경이 작업 트리에 있으나, Developer 보고는 컨트롤러를 변경 파일 표에 넣지 않았고 테스트 파일을 "무수정"이라 기술했다. 실제 diff는 +17행(고지 분기)·+84행(고지·배지 테스트)이다. 소유권상 두 파일 모두 T4 소유라 위반은 아니고, 내용도 PRD 요구("등록은 허용하고 안내 문구로 고지")의 정확한 구현이라 코드 결함이 아니다. → **확인 요청**: 이 변경의 소속을 확정하고 T4 보고서를 갱신하도록 Developer에 전달.

**W-2 · 폴백 상속 시 주석 부정확 — `app/models/client.rb:118`**
`self.refused_phone = phone_digits # = source.refused_phone` 주석은 1순위 경로에서만 참이다. 폴백 경로(refused_phone nil 원천)에서는 `source.refused_phone`이 nil이고, 실제 저장값은 자기 현재 번호 digits다. 동작 자체는 바람직하다(폴백으로 상속받은 행도 refused_phone이 채워져 이후 번호 변경에 한계가 재발하지 않는 자기 치유) — 주석만 보정 제안.

### 4. 항목별 판정표

| 항목 | 판정 | 근거 |
|:--|:--|:--|
| **A1 마이그레이션 안전성·가역성** | **적합** | `add_column`(SQLite 메타데이터 연산 — 테이블 재작성 없음) + 소급 UPDATE(운영 거부 행 0건 실측). `change`의 `execute`는 rollback 시 자동 되돌림이 없지만 `add_column`의 자동 되돌림이 컬럼째로 소급분을 제거해 결과적으로 무모순. `db:schema:load`(test DB 생성)는 마이그레이션을 거치지 않으므로 소급이 test DB에서 안 돈다 — 이것이 폴백의 필요성과 정확히 짝이다 |
| **A2 schema.rb 최소 변경** | **적합** | diff = `t.string "refused_phone"` 1행 + version 뿐 |
| **B3 접수 마킹** | **적합** | `unless client.refused?` 가드 유지(멱등), `update_columns(refused_at:, refused_phone:)` — 기존 의도적 우회 패턴과 일관. before_save 상속 콜백을 우회하는 것은 의도에 맞다 |
| **B4 전파** | **적합** | 같은 회원·같은 현재 번호·미거부 행에 `refused_at`·`refused_phone`을 같은 시각으로 `update_all` — 전파 행마다 refused_phone이 정확히 그 번호로 기록. `call`의 트랜잭션 안 — 강제 실패 롤백 테스트로 고정. `Client.where(user_id:)` 스칼라 — 규약 §4 준수 |
| **B5-a 거부 행 번호 변경** | **적합** | `return if refused_at.present?`로 콜백 조기 종료 → refused_at·refused_phone 불변. 테스트가 refused_phone 불변까지 단언 |
| **B5-b 옛/새 번호 등록** | **적합** | 원천 판정이 `refused_phone == phone_digits` 1순위 — B 등록 무상속·A 등록 상속. 테스트로 고정(옛 한계 고정 테스트의 올바른 교체) |
| **B5-c 정상 행 번호 이동** | **적합** | 이동 행 무상속·이동 번호 신규 등록분 무상속 — 테스트 고정 |
| **B5-d 재접수 전파(현재 번호 기준)** | **수용 가능 — 정합** | R(refused_phone=A, 현재 B)의 링크에서 재접수 → R 마킹 스킵(A 유지) → 전파는 `same_phone_digits(B)`만. 채무자가 B 링크에서 거부를 접수한 것이므로 B 차단은 VIEW-7에 정당하며, A는 전파 대상이 아니고 R의 refused_phone=A가 유지되므로 계속 차단 — 양쪽 번호 모두 논리 일관. 이 시나리오는 테스트 미고정 → Tester 중점 제안 1 |
| **B5-e 레거시 nil 폴백** | **유지 권고** | `.or` 구조: 양쪽 모두 동일 `siblings`에서 파생해 호환 — SQLite에서 올바른 SQL 생성, 실측 통과. 부활 여지: refused_phone nil 거부 행은 옛 한계가 그대로 적용된다. 판단: **유지** — 운영은 소급 UPDATE+단일 쓰기 지점으로 nil 행이 존재하지 않고, test DB는 `db:schema:load`라 소급이 없어 소유 밖 5파일의 기존 시나리오가 폴백에 의존한다. 폴백은 "우회 마킹이 옛 한계를 부활시켜도 조용히 통과시키는" 성격이라 기술 부채로 기록 — 후속 배치에서 5파일 마킹을 `mark_refused!` 형태로 보강한 뒤 제거하는 2단계가 깔끔하다 |
| **B6 `first` 비결정성** | **문제 없음** | Rails `first`는 PK 오름차순(결정적). 원천이 여럿이어도 상속 결과는 "거부 상태+원천 시각"으로 동일 |
| **C7 불변** | **적합** | `refused?`·`SendService` REFUSED 가드·`redirect_resume_refused`·배지 뷰 분기 — 전부 무변경. `same_phone_digits`·`phone_digits`의 소유 밖 호출처 0 |
| **C8 주석·스코프 용도** | **적합(W-2 제외)** | `same_phone_digits` 주석 "전파 전용"이 실제 호출처와 일치 |
| **D9 테스트 고정** | **적합** | 동작 표 a~c가 모델 테스트로 양성·음성 고정, 전파 행 전수 `refused_phone` 단언. 미고정은 5-d 재접수와 폴백의 명시적 모델 레벨 테스트 |

### 5. Tester 중점 제안

1. **재접수·번호 이동 시나리오(5-d)**: 거부 행 R(refused_phone=A)의 번호를 B로 바꾼 뒤 R의 청구 링크에서 refusal 재접수 → R의 refused_at·refused_phone 불변(A), 현재 번호 B를 가진 미거부 행만 B로 전파 마킹, A 번호 행은 무영향 — `RegisterService` 테스트 1건 신설 권장.
2. **폴백 의존 문서화**: `update_column(:refused_at)` 단독 마킹(레거시) 행의 상속 동작을 명시적 모델 테스트로 1건 고정 — 폴백 제거 시 깨지는 센서.
3. **전파 행의 발송 가드·기록(P4)**: 전파로 거부된 거래처의 다른 청구 발송이 REFUSED skip으로 기록되는지, 전파 직후 목록·상세 배지·재개 버튼 미노출.
4. **고지 문구 회귀**: 상속 등록·수정의 flash 문구가 `see_other` 리다이렉트 뒤에도 유지되는지.

### 6. 테스트 실행

```
DATABASE_URL=sqlite3:tmp/parallel/RV4/test.sqlite3 bin/rails test \
  test/models/client_test.rb test/services/promises/register_service_test.rb \
  test/controllers/app/clients_controller_test.rb
→ 80 runs, 439 assertions, 0 failures, 0 errors, 0 skips (전용 리뷰 DB)
```

---

### 오케스트레이터 처리 결정 (T4)

- **W-1(보고 불일치)**: 확인 결과 **이번 T4의 변경이 아니다** — `clients_controller.rb`의 `client_saved_notice`(+17행)과 `clients_controller_test.rb`의 고지·배지 테스트 4건(+84행)은 **오전 배치**(직전 런 T2 "수신 거부 번호 단위 — 등록 안내", 11:53 완료·오케스트레이터 diff 확인분)의 산출물이다. 작업 트리가 미커밋이라 리뷰어가 두 배치를 구분할 수 없었던 것. 이번 T4는 `clients_controller`를 건드리지 않았다(지시대로) — 조치 없음.
- **W-2(주석)**: 고친다 — `client.rb:118` 주석을 폴백 경로까지 정확하게 보정(수정 라운드).
- **폴백 유지 판단**: 받아들인다 — 기술 부채로 기록(후속: 소유 밖 테스트 5파일의 단독 마킹을 보강한 뒤 폴백 제거).
- **Tester 중점 제안 1~4**: Phase 7 Tester 지시서에 포함.

---

## T1 — 휴대폰 인증 기록 파기 잡(AUTH-9) · T3 — 픽스처 날짜 폭탄 근본 해소·가드

### 1. 결론

| 태스크 | 결론 |
|:--|:--|
| **T1** | **APPROVED** (B0·C0·W0 — 관찰 2건은 수정 불요) |
| **T3** | **APPROVED** (B0·C0·**W1** — I-1 반영 권고, 기능 무해) |

선례 파일(notices.yml)에서 이미 지역 변수 패턴(`<% now = Time.current %>`)이 사용 중임이 확인됐다 — I-1의 수정안 근거가 저장소 내 실측으로 확립된다.

### 2. 심각도 집계

- **T1**: BLOCKER 0 · CRITICAL 0 · WARNING 0 (관찰 O-1·O-2)
- **T3**: BLOCKER 0 · CRITICAL 0 · WARNING 1

### 3. 이슈 목록

**I-1 (T3, WARNING) — `test/fixtures/invoices.yml:14-19` — ERB 상수 정의가 "already initialized constant" 경고를 매 재렌더마다 낸다(실측 확인)**
- `ACTIVE_TOKEN_EXPIRES_AT`·`EXPIRED_TOKEN_EXPIRES_AT`는 `ActiveRecord::FixtureSet::RenderContext`의 상수 공간에 정의된다. 픽스처가 재렌더될 때마다 경고 출력 — 실측: `viewer_controller_test` 단독 실행에서만 2회, 통합 스위트에서는 픽스처 재선언 횟수에 비례해 늘어난다. 기능 무해(재할당되며 경고만 출력, 값은 매 로드 시점 평가)지만 테스트 출력의 신호 대 잡음을 해치고 렌더 컨텍스트 상수 공간을 프로세스 전역으로 오염시킨다.
- **제안**: 지역 변수로 전환 — 저장소에 이미 같은 문양의 선례가 있다(`test/fixtures/notices.yml:2`의 `<% now = Time.current %>` → 이후 행 `<%= now + 30.days %>`, 오랜 기간 스위트 통과로 동작 실측 확립). Rails 픽스처 ERB는 파일 전체를 RenderContext binding 하나에 단일 eval하므로 같은 템플릿 안 `<% %>` 지역 변수가 이후 행의 `<%= %>`에서 유효하다. 파일 간 공유는 없으므로 invoices.yml 내부 사용만으로 충분.

**관찰(수정 불요)**
- **O-1 (T1)** — `app/jobs/phone_verifications/purge_job.rb:11` `retry_on ActiveRecord::Deadlocked`: SQLite에서 데드락 감지는 실질 발동하지 않는다(잠금 경합은 `SQLite3::BusyException` → `StatementInvalid`). 무해하고 AGENTS 규약("retry_on 명시")·Rails 기본 문양과 정합하므로 유지가 맞다. 그 외 일시 오류 시 재시도 없이 실패해도 매일 04:30 반복이라 다음날 자연 재실행으로 복구되며, `delete_all`은 단일 문장이라 부분 삭제 후 실패 가능성도 없다.
- **O-2 (T3)** — 가드 `test/fixtures_no_future_date_test.rb:27` `next if was_in_block || opens.positive?`: 한 줄에 `<%`가 하나라도 있으면 그 줄 전체 미검사 → `값: <%= 상대 %> # 2027-01-01 고정` 같은 ERB 혼합 줄·슬래시(`2026/12/30`)·점(`2026.12.01`) 날짜는 미탐. 현재 관례(하이픈 ISO)와 전수 실측 0건이므로 수용 가능한 한계 — 문서화 수준으로 충분.

### 4. 항목별 판정표

#### T1

| # | 항목 | 판정 | 근거 |
|:--|:--|:--|:--|
| 1 | `purgeable` 창 침해 여부 | **OK** | 24h ≫ rate limit(1분·1시간)·이중 검증(30분·`consumed_recently`)·코드 유효(5분). `created_at: ...PURGE_AFTER.ago`(배제 범위 — 경계 행 유지). `SendService` rate limit(`sent_within`)·`VerifyService` 최근 행 조회·가입 `phone_verified?` 전부 영향 없음 |
| 2 | `delete_all` 멱등·로그·queue·retry | **OK** | 멱등(재실행 삭제 0건 테스트 고정). 로그는 `purged=N` 건수만 — 번호·코드 미기록(P4). `queue_as :default`는 기존 잡 전부와 동일 관례. O-1 참조 |
| 3 | recurring.yml 등록 | **OK** | production·development 각 블록 최상위 키(다른 잡 하위 아님), 들여쓰기 2칸, `"30 4 * * * Asia/Seoul"` fugit 접미사 문법 기존 잡과 동일, 기존 시간대와 04:30 미중복. **운영 확인 사항**: Solid Queue recurring은 프로세스 기동 시 로드 — `badeuldon-job` 재기동(배포) 후 유효, 첫 실행은 재기동 후 첫 04:30 KST. `purged=N` 로그로 확인 권장 |
| 4 | 테스트 3건·날짜 폭탄 | **OK** | 경계(24h±1초)·선별(25h/23h/방금/consumed 30분 창)·멱등 전부 고정. `travel_to Time.current` + 상대 생성이라 날짜 폭탄 없음 |

#### T3

| # | 항목 | 판정 | 근거 |
|:--|:--|:--|:--|
| 5 | ERB 평가 시점·Time 직렬화 | **OK** | 픽스처 로드 시점 KST(`config.time_zone = "Seoul"`) 평가. TimeWithZone 보간 결과 `"YYYY-MM-DD HH:MM:SS +0900"` — 오프셋 명시로 헤더 주석의 "KST 오프셋 명시" 규칙과 **충돌 없음**(무오프셋 UTC 저장 교훈 회피) |
| 6 | ERB 상수 경고 | **WARNING (I-1)** | 실측: "already initialized constant" 2회(viewer 단독). notices.yml 지역 변수 선례로 수정안 검증 완료 |
| 7 | 행별 전환 정합성 | **OK** | 활성 6행(issued·due_soon·viewed·promised·partially_paid·paid) 상대값 = travel 없는 시스템 테스트에서도·travel 2026-10-12 고정 테스트에서도 항상 유효(30일 뒤는 언제나 미래). `delta_overdue`(2026-10-31 고정 유지)는 travel 고정 경계 판정용이라 폭탄 아님 — 예외 타당. **패턴 2 위반 없음**: 만료 경계를 만드는 테스트는 전부 픽스처 파생 travel(`token_expires_at ±`) 또는 고정 travel+테스트 내 생성 조합. travel 없이 만료 404를 기대하는 잔존 사용처 0건 |
| 8 | 컨트롤러 테스트 상대화 | **OK** | 임박 `expires_at - 6.days`: 헬퍼 임박 구간 진입 확실. 경과 `+ 1.minute` → `expired?` 참. 정상 `- 20.days` → 표기 없음. 문구 보간 `%Y-%m-%d` == `display_date` 일치. 단언이 카운트만이라 연체 뱃지 등 타 표기와 충돌 없음 |
| 9 | 가드 테스트 | **OK** | 여러 줄 `<%…%>` 추적 견고. 오탐 없음: `BD-20260901-001`·전화번호 불일치, `"2026-12-01 09:00"`은 날짜 부분 매치로 탐지. `Date.current`는 wall-clock — travel 잔존 없음. 실패 메시지 `파일:라인 — 리터럴` 식별 가능. 인라인 마커 제외 방식 합리적 — 현재 0건. 한계는 O-2 |
| 10 | 잔존 고정 날짜 | **OK** | ERB 밖 미래 리터럴 전수 스캔 **0건**(최대 2026-11-11). `delta_draft`의 `due_on 2026-11-11`은 과거가 됐지만 draft는 `unsettled?` 밖 → `overdue?` 파생 없어 뱃지 의미 불변. 나머지는 전부 travel 2026-10-12 앵커·과거값 |

**Rule ID 정합 매핑**: T1 = PRD AUTH-9 "파기 잡 구현 확정(2026-11-26)" 문언과 1:1 — P4(기록)·개인정보 파기 정합. T3 = SHARE-2 유효기간 표기·VIEW-6 만료 안내 단언 불변·TIME-1(KST 오프셋 명시 유지) — 앱 코드 변경 0.

### 5. Tester 중점 제안

1. **I-1 반영 후**: 전체 스위트 출력에서 `already initialized constant` grep — 0건 확인.
2. **T1 운영 배포 후 첫 04:30 KST**: `[PhoneVerifications::PurgeJob] purged=N` 로그로 실행 확인 — 번호·코드가 로그에 없는 것도 함께 확인(P4).
3. **가입 E2E 회귀**: 파기 잡이 가입 플로우를 건드리지 않는지 — 발송→검증→가입 성공 경로 시스템 테스트 1회.
4. **delta_paid 토큰이 유효 링크로 바뀐 점**: 전체 스위트에서 viewer 계열 실패 여부 재확인 권장.
5. **가드의 미커버 형식**(슬래시·점 날짜, ERB 혼합 줄) — 픽스처 PR 리뷰 시 수동 확인 항목으로 제안.

### 6. 테스트 실행 기록 (격리 DB — 지정 파일만)

```
DATABASE_URL=sqlite3:tmp/parallel/RV13/test.sqlite3 bin/rails test \
  test/jobs/phone_verifications/purge_job_test.rb test/fixtures_no_future_date_test.rb
  → 4 runs, 11 assertions, 0 failures
DATABASE_URL=sqlite3:tmp/parallel/RV13/test.sqlite3 bin/rails test \
  test/controllers/viewer_controller_test.rb test/controllers/app/invoices_controller_test.rb
  → 65 runs, 487 assertions, 0 failures
경고 실측: "warning: already initialized constant … ACTIVE_TOKEN_EXPIRES_AT / EXPIRED_TOKEN_EXPIRES_AT (test/fixtures/invoices.yml:17·18)" 2회 확인 — I-1 근거
```

---

### 오케스트레이터 처리 결정 (T1·T3)

- **I-1(ERB 상수 경고)**: 고친다 — 지역 변수로 전환(FIX2 수정 위임). 통합 재확인에서 오케스트레이터도 같은 경고를 관찰했던 건.
- **O-1·O-2**: 수정 없음 — O-2(가드의 미커버 날짜 형식)는 08_run_report의 알려진 한계로 기록.
- **Tester 중점 제안 1~5**: Phase 7 Tester 지시서에 반영(1·3·4는 자동화, 2는 운영 확인 사항으로 AGENTS.md 운영 노트, 5는 문서).

---

## 리뷰 총평 (오케스트레이터)

4건 모두 **APPROVED**(BLOCKER 0·CRITICAL 0·WARNING 8 — T1 0·T2 3·T3 1·T4 2·T5 2). 수정 라운드에서 고치는 것: T2 W-1(IPAddr 교체)·W-2(감사 IP 2곳), T4 W-2(주석), T3 I-1(ERB 지역 변수). 문서로 처리: T5 W-2(PRD REM-11 — 반영 완료), T2 W-3(운영 노트). 테스트 보강은 Phase 7 Tester(T5 W-1 포함). 재리뷰는 하지 않는다(경고 수준 수정·변경면 작음 — 오케스트레이터가 diff·테스트로 직접 확인).
