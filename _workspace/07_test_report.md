# 07_test_report — F-ADMIN Run C Phase 7 (테스트 정식화·실행)

작성: Tester(절약 모드) · 2026-11-10
대상: Run C 3-a(공지 ADMIN-6/7)·3-b(티켓 ADMIN-8/9) + Phase 6 수정(C-1·W-1·W-3·W-4)

## 최종 결과

- **전체 `bin/rails test`: 876 runs · 4,946 assertions · 0 failures · 0 errors · 0 skips**
- 기존 815건 회귀 0 + 신규 52건(34 tests + 기존 18건 파일 이동 없음 — 아래 대조표 기준 신규 파일 7개) 전부 통과
- `bin/rubocop test/` — 104 files inspected, **no offenses**
- 솔라피 실호출 0회 — `with_solapi_client` 방어선 경유(admin reply·notify 서비스·skipped는 호출 차단 객체로 실측)
- 코드 버그 0건 — Phase 6 수정(C-1·W-3·W-1)이 모두 테스트로 재확인됨

## 신규 파일(7개)

| 파일 | tests | 커버 |
|---|---|---|
| `test/models/notice_read_test.rb` | 3 | 복합 유니크·조합 허용·MarkService 2회 1건(SEC-5) |
| `test/models/ticket_test.rb` | 7 | category/status enum·title 100자·상태 전이 guard 3종(answered 멱등·closed reopen 거부·close 멱등)·종료 권한 경로·dependent 삭제 |
| `test/models/ticket_message_test.rb` | 7 | sender enum·body 2,000자·jpg/png/webp 수용·csv/gif 거부·HTML→png 위조 거부(Marcel)·5MB 초과 거부·첨부 선택 |
| `test/services/tickets/create_service_test.rb` | 5 | Result 성공/실패·첨부·트랜잭션 롤백(gif 실패 시 티켓 없음)·상한 |
| `test/services/tickets/follow_up_service_test.rb` | 6 | open 유지·answered→open 복귀·closed 거부·타인 404 경로·blank/2,001자 |
| `test/services/tickets/notify_answer_service_test.rb` | 5 | sent/failed/skipped 3분기·MessageLog(invoice nil·ticket_id·variables·phone 스냅샷)·PLAN-3 집계 밖 |
| `test/controllers/admin/tickets_controller_test.rb` | 9 | 비인증 303·U1 admin 접근 불가(세션 비공유)·필터·reply(sent 기록)·blank 거부·close+ticket_close 감사·강제 종료·close 멱등·admin 이미지 서빙 |
| `test/controllers/app/tickets_controller_test.rb` | 10 | 작성 303·422·FAQ 선노출(ADMIN-9)·상한 422·분류 etc 귀속·타인 404·follow_up/closed alert·비로그인 리다이렉트 |

合计 52 tests / 221 assertions(신규 파일 기준).

## 리뷰 16 시나리오(05_review §3) 테스트화 대조표

| 리뷰 시나리오 | 정식 테스트 | 상태 |
|---|---|---|
| 공지 ①~⑧(노출·닫기·확인·close·만료 경계·404·mark_read 멱등) | 기존 `app/notices_controller_test.rb`(14)·`admin/notices_controller_test.rb`(9) — 유지 | ✅ 기존 |
| 공지 ⑨ C-1 초안 선읽음 우회 | 기존 `app/notices_controller_test.rb` C-1 회귀 4건(초안 404·미래 404·종료 허용·발행 후 정상) — 유지 | ✅ Phase 6 |
| 티켓 ① 작성 303+open | `app/tickets_controller_test.rb` 작성 303 | ✅ |
| 티켓 ② FAQ 선노출 | 동일 파일 FAQ 테스트 | ✅ |
| 티켓 ③ 스레드·폼 | 상세 200 + 발화 노출 | ✅ |
| 티켓 ④ 타인 404(show·follow_up) | app 404 + FollowUpService 타인 nil | ✅ |
| 티켓 ⑤ admin 답변→answered+MessageLog | `admin/tickets_controller_test.rb` reply(sent·invoice nil·ticket_id) + NotifyAnswerService sent 전체 단언 | ✅ |
| 티켓 ⑥ 상태 필터 | admin index 필터(상태·분류) | ✅ |
| 티켓 ⑦ 추가 질문 open 복귀 | app follow_up + FollowUpService answered→open | ✅ |
| 티켓 ⑧ 종료+감사 1건 | admin close + AuditLog sole 단언 | ✅ |
| 티켓 ⑨ closed follow_up 거부 | app alert + FollowUpService 거부 | ✅ |
| 티켓 ⑩ NO_PHONE skipped | NotifyAnswerService skipped(NO_PHONE·호출 차단) | ✅ |
| 티켓 ⑪ Solapi 400→failed | NotifyAnswerService failed(E400·error_code/message) | ✅ |
| 티켓 ⑫ 답변 blank 거부 | admin blank reply alert | ✅ |
| 티켓 ⑬ 이미지(csv/gif/위조/5MB/정상) | `ticket_message_test.rb` 5건 + 기존 `tickets_image_serving_test.rb`(4) 유지 | ✅ |
| 티켓 ⑭ 본문 2,001·제목 101 | 모델·서비스·컨트롤러 3계층 | ✅ |
| 티켓 ⑮ rate_limit 429 | **미정식화** — test env NullStore·부팅 시 store 캡처로 실 스토어 주입(격리 프로세스) 필요. 05_review §4-2·03_implementation §3-b 노트 유지. 기술 부채로 기록 권장 | ⚠️ 인계 |
| 티켓 ⑯ single_subject | 기존 `message_log_test.rb` + NotifyAnswerService PLAN-3 밖 테스트 | ✅ |

W-3(publish 실패 alert)·W-1(인증 서빙)은 기존 테스트(admin notices 1건·tickets_image_serving 4건+admin 이미지 신규)로 커버. 시스템 테스트(Turbo 팝업)는 리뷰 §4-3 제안이나 통합 테스트가 레이아웃 재평가까지 커버 완료 상태라 본 라운드 생략 — 운영 판단 인계.

## 원인 분류

실패·에러 이력(자체 수정 — 테스트 오류 3건): ① `assert_predicate ... :include?(…)` 파서 오류(문법) ② NoticeRead 테스트가 fixture(gamma_read_general) 중복 생성 ③ `assert_no_difference` 블록 누락. **코드 버그 0건** — Developer 위임 불요.

## 잔존(기술 부채 인계)

1. rate_limit 429 실측(실 캐시 스토어 주입) — 05_review §4-2 유지
2. 시스템 테스트(Turbo 팝업 소멸·모바일 z-index·DESIGN-6) — 리뷰 §4-3·4-4
3. NOTICE: not applicable — dev/test DB 잔존 레코드 없음(트랜잭션 롤백), 스토리지 blob은 테스트 DB 정리 대상

---

# 07_test_report — 수동 발송 스텝 선택 결함 수정 Phase 7 (Standard 런 — 검증·보강·전체 게이트)

작성: Tester(절약 모드) · 2026-11-10
대상: 03_implementation §9·§9.1(수동 스텝 선택 재정의 + Phase 6 C-1·C-2 수정) — 리뷰(05_review §4 후반부) Tester 중점 제안 4건 중 미커버 보강

## 최종 결과

- **전체 `bin/rails test`: 883 runs · 5,003 assertions · 0 failures · 0 errors · 0 skips** (Phase 6 이후 기준 878건 회귀 0 + 신규 5건 통과)
- `bin/rubocop` — 변경 테스트 3파일 **no offenses**
- 솔라피 실호출 0회 — 신규 전 케이스 `with_solapi_client` 방어선 경유(IntegrationTest·시스템 테스트 포함)
- **코드 버그 0건** — C-1(수동 템플릿 무관 상한)·C-2(nil 창·라벨 nil 숨김)가 모두 테스트로 재확인됨

## 신규 테스트(5건 — 리뷰 §4 제안 커버 맵)

| 리뷰 제안 | 테스트 | 파일 | 결과 |
|---|---|---|---|
| ① 수동 issue_notice 후 자동 스캔 무결성 | "수동 issue_notice 발송 후에도 D-1 자동 스캔은 invoice_notice를 발송한다 (SEC-5 키 분리·무결성)" — 컨트롤러 수동 POST(만기 17일 전) → travel D-1 → `DispatchService.new.call` → `[issue_notice sent, invoice_notice sent]`·origin 구분 단언 | `test/controllers/app/invoices_reminders_test.rb` | ✅ |
| ① 약속 트랙 동일 무결성 | "수동 issue_notice 발송 후 약속 전날 자동 스캔은 promise_d1을 발송한다 (PROMISE-3·SEC-5 무결성)" — 수동 issue_notice(만기 전+약속 원격) → travel 약속 전날 → 자동 스캔 promise_d1 sent | 동일 | ✅ |
| ② 상한 혼합 시나리오 정식화(서비스 레벨) | "수동 상한은 시퀀스성·1회성 혼합 총량 5통에서 발동하고 6통째 manual 발송을 차단한다 (PLAN-3·Q11·C-1)" — 서로 다른 템플릿 5종(issue_notice·confirm_d1·requeue_d7·final_d14·promise_d1) 실발송 5통 → 6통째 skipped+CAP_REACHED·호출 0·**자동 1회성(partial_paid)은 무영향**(Q10 경계 동시 단언) | `test/services/reminders/send_service_test.rb` | ✅ |
| ③ 시스템 테스트(뷰 정합) | "만기 17일 전 청구서의 다음 안내 라벨과 발송 이력은 발행 안내로 표기된다 (REM-8·Q11)" — "다음 안내: 발행 안내" 라벨·invoice_notice 라벨("만기 예정 안내") 부재·발송 후 이력 행 "발행 안내"·fake 호출 template_key 단언 | `test/system/app_invoice_reminders_test.rb` | ✅ |
| ④ Q11 삼분 경계(4·5·6) | "수동 발송 총량 경계 — 4통째·5통째는 성공하고 6통째만 CAP_REACHED로 차단된다 (Q11 삼분 경계)" — 컨트롤러 경유 실 POST 6회: 4·5통째 성공 flash, 6통째 상한 안내 flash·skipped 1건·sent 5건·fake 호출 5회 | `test/controllers/app/invoices_reminders_test.rb` | ✅ |

## 기존 스위트 무충돌 확인

- Run C의 `message_stats`·PLAN-3 상한 테스트와의 충돌 없음 — 수동 집계(`manual_cap_reached?` — 채무자 sent 전체)와 시퀀스 집계(`sequence_sent_count` — SEQUENCE_TEMPLATE_KEYS 한정)가 분리돼 있어 기존 어설션(예: send_service_test "상한 도달에도 1회성 발송…"· tickets PLAN-3 밖) 전부 원치와 같이 통과. 티켓 알림(noti_ticket_reply·recipient_role=user)도 수동 총량 집합(invoice 스코프·debtor) 밖으로 자연 배제됨(전체 스위트 883건으로 실측).
- W-1 판별력 보강 — 기존 컨트롤러 테스트의 `variables "(내일)" 단언은 유지하되, 본 런의 시스템 테스트가 템플릿 본문·라벨 레벨의 판별 단언("만기 예정 안내" 부재)을 보강했다.

## 원인 분류 (실패·에러 이력 — 전부 테스트 오류, 자체 수정 후 재실행 통과)

1. 무결성 테스트를 gamma(Free)로 작성 → 자동 스캔 INELIGIBLE_PLAN skip — delta로 변경(자격 필요는 REM-8 기존 규칙, 코드 결함 아님)
2. D-1 travel일 착오(만기 11-27 기준 D-1=11-26) — 날짜 정정
3. 수동 issue_notice sent 후 **자동** issue_notice 재발송은 step_sent?(origin 무관)가 duplicate로 흡수하는 것이 SEC-5 정상 동작 — 단언을 partial_paid(미발송 1회성)로 교체하고 주석에 duplicate 정상 기록

## 잔존

- 없음(본 런 범위) — 리뷰 §4 제안 4건 전부 소화. test DB 잔존 레코드 없음(트랜잭션 롤백), 스토리지 blob 생성 없음
