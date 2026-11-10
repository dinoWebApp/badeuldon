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
