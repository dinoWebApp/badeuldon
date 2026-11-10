# 05_review — F-ADMIN Run C(공지 ADMIN-6/7·티켓 ADMIN-8/9) Phase 5

- 리뷰어: Reviewer(절약 모드) · 2026-11-10
- 리뷰 대상: Run C 3-a(공지)·3-b(티켓) 미커밋 분 — Run A/B는 기존 APPROVED 유지
- 방법: 전 파일 정독 + **컨트롤러 경유 HTTP 통합 재현 16 시나리오**(IntegrationTest·관리자 2FA 실로그인·U1 실로그인 — 임시 테스트로 실행 후 삭제, test DB만 사용·dev 레코드 없음·솔라피 실호출 0회 — with_solapi_client 방어선 실측)
- 전체 테스트 815건·rubocop 240 files는 오케스트레이터 확인치(재실행 생략 — 지시 준수)

---

## 종판: `status: CHANGES_REQUESTED`

- CRITICAL 1(C-1 — mark_read 미게시 공지 우회, HTTP 실측 확정) 수정 후 재리뷰 필요.
- 나머지는 WARNING 4건(운영·테스트·성능)으로 진행 가능하나 W-2(티켓 정식 테스트 부재)는 Phase 7 진입 전제.

---

## 1. 이슈 목록

### C-1 · CRITICAL · ADMIN-7 — `mark_read`가 미게시(초안·미래 발행) 공지에도 성공한다(우회 경로)
- 위치: `app/controllers/app/notices_controller.rb:17` — `notice = Notice.find(params[:id])`
- 재현(HTTP 실측, 컨트롤러 경유):
  1. U1이 `POST /app/notice/{초안 id}/mark_read` → **303 성공 + NoticeRead 생성**(404 아님)
  2. 관리자가 해당 공지를 **이후 발행** → 이 사용자에게 배너·팝업이 **영구 미노출**(재현 단언 통과)
  3. 부수: 존재하지 않는 id는 404 → **초안·예정 공지의 존재 프빙**(id는 자동증가로 열거 가능)
- 근거: ADMIN-7 "중요 공지는 확인 버튼 클릭 전까지 미확인 사용자에게 지속 노출" — 초안 단계 선읽음으로 이 보장이 우회된다. `show`는 `published_now` 스코프인데 `mark_read`만 무스코프라 경로 간 비대칭.
- 권고: `Notice.where(published_at: ..Time.current).find(params[:id])` — 초안(published_at nil)·미래 발행 모두 차단(우회 원천 봉쇄), 이미 종료된 공지는 허용해 세션 도중 만료 클릭의 404 UX를 유지. 대안으로 `published_now` 스코프도 가능(만료 직후 클릭 404 트레이드오프). 컨트롤러 테스트에 "초안 mark_read 404"·"미래 발행 mark_read 404" 2건 추가.

### W-1 · WARNING · SEC(이미지 접근) — 티켓 첨부 이미지가 비인증 다운로드 가능(AS 기본 구조)
- 위치: `app/views/app/tickets/show.html.erb:27`·`app/views/admin/tickets/show.html.erb:27` — `image_tag message.image`(AS redirect 서명 URL)
- 재현(HTTP 실측): 첨부 이미지의 `/rails/active_storage/blobs/redirect/{signed_id}/...` URL을 **비로그인 GET → 302 → 최종 200(image/jpeg 본문 다운로드 성공)**. 타 U1 로그인 세션으로도 200. `X-Content-Type-Options: nosniff`는 확인됨.
- 판정: BLOCKER로 보지 않은 근거 — signed_id는 HMAC 서명 비추측성이며 Rails Active Storage 기본 포스트처리라 "URL 보유자"로 한정된다. 다만 티켓 첨부는 CS 증빙(개인정보·화면 캡처 가능)이고 서명 URL은 만료 없어 Referer·브라우저 이력·프록시 로그 유출 시 영구 유효다.
- 권고: 티켓 이미지를 인증 서빙으로 전환(App::BaseController 상속 서빙 컨트롤러에서 소유자·관리자만 stream) — AS 커스텀 routes는 기술 부채 목록에 기록 권장. 최소한은 Tester 시나리오에 URL 유출 경로 점검 추가.

### W-2 · WARNING · 테스트 — ADMIN-8 티켓 도메인 정식 테스트가 전무하다
- 위치: `test/models/ticket*_test.rb`·`test/services/tickets/`·`test/controllers/{app,admin}/tickets_controller_test.rb` 모두 부재(03_implementation 3-b "임시 통합 테스트 실행 후 삭제 — Phase 7에서 정식화" 인계).
- 판정: 현재 전체 815건은 티켓 회귀 방어막 없음 — 본 리뷰 A절 재현이 임시 대체일 뿐이다. 게이트(테스트 통과)는 통과했으나 커버리지 결여는 WARNING.
- 권고: Phase 7 정식화 필수 — 모델(상태 전이 open→answered→open→closed·guard·제목/본문 상한·single_subject)·서비스 3종(Create/FollowUp/NotifyAnswer — sent/failed/skipped·NO_PHONE·variables)·컨트롤러(격리 404·rate_limit 실 스토어 주입·ticket_close 감사)·이미지 검증(spoof 포함). 본 리뷰 재현 시나리오 목록(§3)을 그대로 테스트 케이스로 전환 가능.

### W-3 · WARNING · ADMIN-6 — `publish`가 update 실패에도 "발행되었습니다" 플래시(무음 실패)
- 위치: `app/controllers/admin/notices_controller.rb:57` — `@notice.update(published_at: Time.current) if @notice.draft?`
- 시나리오: expires_at이 이미 과거로 설정된 초안(발행 지연 후)을 발행 → `expires_at_after_published_at` 검증 실패 → **저장 안 됐는데 성공 플래시**. 데이터 무결성은 검증이 지켜지만 운영자가 발행됐다고 오인.
- 권고: `if @notice.update(...)` 분기로 실패 시 alert 플래시(또는 폼 재렌더). close는 만료=현재라 검증상 실패 불가라 해당 없음.

### W-4 · WARNING · PERF(경미) — 티켓 스레드 뷰의 첨부 이미지 N+1
- 위치: `app/controllers/app/tickets_controller.rb:55` / `admin/tickets_controller.rb:35` — `ticket_messages.ordered`에 attachment 미프리로드, 뷰의 `message.image.attached?`가 메시지마다 exists? 쿼리.
- 권고: `with_attached_image`(Rails 제공 프리로드 스코프) 결합. 스레드가 길어질수록 선형 증가 — 경미하나 수정 1줄.

### 관찰(이슈 아님 — 운영 노트)
- `Tickets::NotifyAnswerService`는 TIMEOUT/CONNECTION(모호 실패)도 failed 기록 후 종료한다. SendService는 `retryable?` 시 잡 재시도로 넘기는 것과 대비되나, 티켓 알림은 1회성·요청 컨텍스트라 재시도 부적합 — 03_implementation의 "ADMIN-8 확정 해석"으로 문서화된 의도적 설계. 실제 발송됐을 가능성이 있는데 failed로 남을 수 있음은 P4 이력 정확도 관점 운영 노트로 유지 권장.
- `Admin::TicketsController#close` 감사에 `ip:` 미전달 — Run B `order_refund`와 동일 패턴(로그인 계열만 ip 기록)이라 컨벤션 정합.
- `message_logs` FK `on_delete: :cascade`(ticket)는 기존 invoice FK와 동일 관행 — Run C 신규 리스크 아님(향후 계정 삭제 런에서 P4 영향 일괄 검토 대상).

---

## 2. Rule ID 준수 매핑

| Rule | 요구(PRD v0.32) | 구현·검증 | 판정 |
|---|---|---|---|
| ADMIN-6 | 제목·본문·중요도·게시 기간 설정 발행 | notices 테이블(enum·published_at/expires_at nil=무기한)·CRUD·publish/close 멱등·상태 배지·중요도 필터(화이트리스트) | ✅ (W-3 경계) |
| ADMIN-7 | 배너(일반)·팝업(중요·전 화면·확인 전 지속)·/app/notice·사용자별 읽음 | notice_reads 복합 유니크·MarkService 멱등·레이아웃 팝업(/app 타 화면 노출 실측)·배너 닫기=읽음 재노출 없음 실측·path "notice"·SURF-3 noindex 자동 적용 | ✅ (C-1 예외 — 수정 필요) |
| ADMIN-8 | 5분류·AS 1장 5MB jpg/png/webp·rate_limit 5회/시간·본문 2,000자·관리자만 종료·재질문 open 복귀·REM-6 확장(message_logs invoice nullable+ticket_id)·skipped(NO_PHONE) | 전 항목 HTTP 실측 통과(§3 B1~B9·C2·C3) — 분류 화이트리스트 밖은 etc 귀속·종료는 admin 전용 경로(사용자 종료 권한 없음 — PROMISE-7 준용)·감사 ticket_close 1건 실측 | ✅ |
| ADMIN-9 | 문의 작성 화면에 FAQ(LP-8) 선노출 | `render "landing/faq"`(파셜 무수정 — 랜딩 회귀 방지)·/app/tickets/new 렌더 실측("자주 묻는 질문") | ✅ |
| REM-6 확장·P4 | 티켓 알림도 발신 이력 영구 기록 | MessageLog.sent/failed/skipped 전부 기록 실측·single_subject(invoice·ticket 정확히 하나) 검증 실측·variables 스냅샷(사용자명·문의제목·url=badeuldon.kr/app/tickets/{id}) 실측 | ✅ |
| SEC-5(성격) | 발송·읽음 멱등 | mark_read 2회 POST → 레코드 1건·303 실측 / 티켓 알림은 이벤트성 — debtor×pending 부분 유니크 인덱스 밖(recipient_role=user) 설계 문서화·sent 생성 성공 실측 | ✅ |
| PLAN-3 | 청구 건당 5통 상한 집계 | noti_ticket_reply는 SEQUENCE_TEMPLATE_KEYS 밖·sent_sequence invoice 스코프 — 티켓 행 자연 배제(코드 확인) | ✅ |
| REM-3 | 발송 창은 채무자 향만 | 티켓·U1 향 즉시 발송 — NotifyUserService와 동일 해석 | ✅ |
| AUTH-7·ADMIN-2 | 관리자 세션·감사 | 2FA 실로그인 경유 검증·ticket_close AuditLog 1건 실측 | ✅ |
| SURF-2/3/4 | 표면 분리·noindex | /app 프리픽스 noindex 자동 적용(head partial)·뷰어 규칙 대상 아님 | ✅ |
| TIME-1 | KST 고정 | Time.current 기준·만료 경계(== 포함) 동결 실측 | ✅ |
| §4 아키텍처 | 의존 방향·컨트롤러 10줄·뷰 쿼리 금지 | Model→Service 없음(상태 전이 메서드만)·감사는 컨트롤러 경유·Service는 params/Current 미참조·뷰 @변수+인스턴스 술어·액션 본문 10문장 이내·routes member 정당화·Zeitwerk(Admin 헬퍼 회피) | ✅ |
| DESIGN/UI | 톤·접근성·이스케이프 | Run B admin 톤 준용·min-h-11 터치 타깃·aria(role=dialog/region·aria-modal·labelledby)·사용자 입력 전부 `<%= %>` 이스케이프·whitespace-pre-line·금지 표현 없는 문구 | ✅ |

---

## 3. 통과 커버리지 — 컨트롤러 경유 HTTP 재현 16/16(159 assertions)

공지: ① 관리자 생성→초안→발행→U1 배너·팝업 노출 ② 팝업 /app 타 화면(공지·티켓·청구서) 커버 ③ 닫기=읽음→재노출 없음 ④ 팝업 확인→재노출 없음 ⑤ close 후 노출 중단 ⑥ 만료 경계(== 포함·과거 제외) ⑦ 목록·상세·미게시 404 ⑧ mark_read 멱등 2회 1건 ⑨ (C-1 실측 — 초안 선읽음 우회 확정)
티켓: ① U1 작성(이미지 첨부)→303·open ② FAQ 선노출 ③ 상세 스레드·추가 질문 폼 ④ 타인 티켓 404(show·follow_up) ⑤ admin 답변→answered+MessageLog 1건(sent·invoice nil·variables 정확·phone 스냅샷)·SolapiStubbing 실호출 차단 확인(fake 1회) ⑥ 목록 상태 필터 ⑦ U1 추가 질문→open 복귀 ⑧ admin 종료→closed+ticket_close 감사 1건 ⑨ closed follow_up 거부(메시지 불변) ⑩ NO_PHONE skipped ⑪ Solapi 400→failed·답변 자체는 303 ⑫ 답변 blank 거부 ⑬ csv 422·HTML→png 위조 422(Marcel 매직바이트 방어 실측)·5MB 초과 422·정상 png 성공 ⑭ 본문 2,001자·제목 101자 422 ⑮ rate_limit 실 스토어 주입 6회차 429 ⑯ single_subject(양쪽 지정·양쪽 공백) 검증 실패
무결성: message_logs 완화 영향 전수 — sent_sequence·PLAN-3 상한(invoice 스코프)·부분 유니크 인덱스(debtor×pending 밖)·reports 쿼리 3종(MessageLog 미사용)·admin members 뷰(nil invoice 컬럼 미렌더)·message_stats(티켓도 실발송이라 정반영)·reminders_context(invoice 스코프) — 오염 0건 확인

리뷰 재현 방식: 임시 IntegrationTest(실행 후 삭제 완료) — test DB 트랜잭션 롤백, dev DB·스토리지 잔존 레코드 없음, 솔라피 실호출 0회(with_solapi_client 생성자 차단 경유 확인)

---

## 4. Tester 중점 테스트 제안(Phase 7)

1. **C-1 회귀**: 초안·미래 발행 mark_read 404 단언 + 정상 mark_read 플로우 회귀(수정 후 최우선)
2. **티켓 정식 스위트**(W-2): §3 시나리오 16건을 models/services/controllers 계층으로 정식화 — rate_limit은 실 캐시 스토어 주입(test NullStore 무시 실측 반영)
3. **시스템 테스트(Turbo 클라이언트)**: 팝업 확인→Turbo 내비 후 소멸·배너 닫기 303 후 재노출 없음·여러 중요 공지 순차 노출(HTTP 재현은 레이아웃 재평가까지만 커버)
4. **모바일 뷰**: 팝업 z-50 vs 사이드바 드로어 z-40 겹침·모달 스크롤 잠금(DESIGN-6 터치)
5. **이미지**(W-1 전환 시): 인증 서빙 컨트롤러의 소유자·관리자만 200/타인 404·만료/무효 signed URL 404
6. **집계 회귀**: 티켓 알림 다수 발생 후 admin message_stats·members 발송 이력 오염 없음

---
---

# 05_review — 수동 발송 스텝 선택 결함 수정 Phase 5 (2026-11-10 — Standard 런)

- 리뷰어: Reviewer(절약 모드) · 2026-11-10
- 리뷰 대상: `app/services/reminders/dispatch_service.rb`(manual_step_key 재설계)·`test/services/reminders/dispatch_service_test.rb`(10케이스 재작성)·`test/controllers/app/invoices_reminders_test.rb`(컨트롤러 재검증 신설)·`_workspace/03_implementation.md` §9
- 방법: 전 파일 정독 + diff 대조(자동 스캔 무변경 확인) + **runner 재현 4종**(PLAN-3 상한 대조·SEC-5 키 분리·월말/연말/당일 경계·약속 트랙 변수 정합 — RAILS_ENV=test·fake client 주입·실호출 0회·재현 후 test DB drop/re-prepare·/tmp 스크립트 삭제) + 컨트롤러 경유는 신설 IntegrationTest로 실측
- 전체 테스트(876건)·전체 rubocop은 오케스트레이터 확인치 — 변경 3파일 rubocop 0 offense·관련 테스트 31건(129 assertions)은 리뷰 환경에서 직접 재실행 통과

---

## 종판: `status: CHANGES_REQUESTED`

- 보고된 결함 자체(만기 전 구간 수동 발송이 "(내일)" 박힌 invoice_notice 선택·약속 트랙 promise_d1 동일)는 수정됐고, 기본 트랙 경계·SEC-5·자동 스캔 회귀는 전부 정상 확인.
- 단, **CRITICAL 2건**이 신설됐다: ① 수동 issue_notice가 PLAN-3 상한 밖으로 빠져 "무상한 반복 발송" 우회로가 됨(runner 실측 — 같은 청구서 12통 발송) ② 약속 트랙의 issue_notice 폴백이 만기 도과 구간에서 과거 날짜("결제 예정일: 만기일")를 발송 — 이번 런이 고치는 결함과 동일 종류의 거짓 문구가 약속 분기에 잔존.
- 2건 모두 manual_step_key 주변 소폭 수정으로 해소 가능한 범위. 수정 후 재리뷰 대상.

---

## 1. 이슈 목록

### C-1 (CRITICAL · PLAN-3·REM-8·P1) — 수동 issue_notice 반복 발송이 상한 우회로가 됨
- `app/services/reminders/send_service.rb:116` — `CAP_REACHED if sequence_step? && cap_reached?`: 가드가 `SEQUENCE_TEMPLATE_KEYS`에만 적용되고 issue_notice는 1회성 3종이라 집계·가드 모두 밖(Q10). 그런데 이번 수정으로 issue_notice가 **수동 버튼으로 매일 선택 가능한 반복 템플릿**이 됐다 — Q10의 "1회성(발행 즉시 1회)" 전제가 깨졌는데 가드는 그대로다.
- **runner 재현**: (대조1) 같은 청구서 수동 `confirm_d1` 7회 → `sent 5 + skipped 2(CAP_REACHED)` — 시퀀스 키 가드 정상. (대조2) **같은 청구서, 상한 5 도달 후** 수동 `issue_notice` 7회 → **7/7 sent**, 채무자 sent 누계 12통(이후 무한). PLAN-3 "하드리밋(수동 발송 포함)"·REM-8 "수동은 상한 내" 기준 미충족. 수정 전에는 만기 전 수동 발송이 invoice_notice(집계 대상)라 5통에 걸렸으므로, 이번 수정이 만든 보호 후퇴다.
- 제안: SendService 가드에 `return "CAP_REACHED" if @origin == "manual" && cap_reached?` 추가(수동은 템플릿 무관 상한 적용 — 자동 1회성 3종은 Q10대로 무영향). 또는 manual_step_key가 상한 도달 시 nil 반환 + 컨트롤러 flash 안내. 어느 쪽이든 Q10 문언("집계 제외")과의 긴장이므로 02_prd_update에 결정 기록 1줄 병행 권고.

### C-2 (CRITICAL · REM-2·PROMISE-3) — 약속 트랙의 issue_notice 폴백이 만기 도과 구간에서 과거 날짜를 발송
- `app/services/reminders/dispatch_service.rb:75-77` — 약속 분기: 전날→promise_d1·도과→promise_overdue·**그 외→issue_notice**. 그런데 issue_notice 본문은 "결제 예정일: #{만기일}"이고 변수는 `invoice.due_on`(send_service.rb:238) — 만기가 지나고 약속일만 미래인 청구서(재약속 표준 시나리오)에서 "그 외" 창이 만기 도과 구간을 포함한다.
- **runner 재현**: 만기 11-27·약속 12-05 청구서, 12-01 수동 발송 → template `issue_notice`, `variables["만기일"]="11월 27일(금)"`(과거), `variables["약속일"]="12월 5일(토)"`(본문 미사용). **약속 당일(12-05)도 issue_notice**. 채무자에게 "지났는데 예정일 11월 27일" 발송 — 이번 런이 고치는 결함과 동일 종류의 거짓 문구. 주석·03 문서의 불변식("어느 날 보내도 내용이 참")은 기본 트랙(`due >= today` 보장)에서만 성립하고 약속 분기에서는 위반된다.
- 제안: 약속 분기 issue_notice 폴백을 `due >= today`인 경우로 한정. 만기 도과+약속 전날 이전(및 약속 당일) 창은 현 18종 중 참인 템플릿이 없으므로(promise_d1 "(내일)"·promise_overdue "도과" 모두 부적절) ① manual_step_key가 nil 반환 + 컨트롤러/뷰에서 "약속일 전날 자동 안내 예정" 안내(버튼 비노출 또는 flash) — 최소 변경, ② PRD 차원 신규 템플릿 결정 — 중 하나를 02_prd_update에 기록 후 구현.

### W-1 (WARNING · 테스트 품질) — C-2를 포착하는 테스트 부재·경계 1건 누락·판별력 없는 단언
- 서비스 테스트에 ① 만기 도과+미래 약속(전날 제외) 케이스의 **변수 정합 단언** ② 약속 당일(`promised_on == today`) 케이스가 없다 — 있었다면 C-2는 구현 단계에서 잡혔다.
- 컨트롤러 테스트의 `assert_not far_log.variables.values.join.include?("(내일)")`는 어느 템플릿이든 variables에 "(내일)"이 없어 판별력이 없다(문구는 템플릿 본문에 박혀 있음). 부하 단언은 `template_key` 동일성이므로 기능 검증에는 문제 없으나, 단언 의도(거짓 문구 0)를 본문 검증으로 옮기면 더 명시적이다.
- 제안: C-2 수정 테스트에 "모든 수동 발송 variables['만기일'] >= today" 성격의 단언·약속 당일 경계 추가.

### W-2 (WARNING · 주석·문서 정합) — "어느 날 보내도 내용이 참" 서술이 약속 트랙에서 부정확
- `dispatch_service.rb:66-68` 주석과 `03_implementation.md` §9의 issue_notice 근거 서술이 C-2와 충돌한다. C-2 수정 시 두 서술을 함께 정정할 것(주석이 다음 리뷰어·유지보수자에게 잘못된 불변식을 심는 것을 방지).

---

## 2. Rule ID 준수 매핑

| Rule ID | 판정 | 근거 |
|---|---|---|
| REM-2(단계·톤) | 부분 미충족(C-2) | 기본 트랙 D-1/D-2/당일 경계 전수 정확(runner). 약속 트랙 폴백이 거짓 문구 창 포함 |
| REM-8(수동) | 부분 미충족(C-1) | "현재 상황에 맞는 다음 1통"은 개선됐으나 상한 내 원칙이 issue_notice에서 공백 |
| PLAN-3(상한 5 하드리밋) | 미충족(C-1) | runner 실측 — 수동 issue_notice 무한, 같은 청구서 12통 실측 |
| SEC-5(멱등) | 충족 | runner — 수동 issue_notice(sent·manual) 후 D-1 자동 invoice_notice 정상 sent. step_sent?·claim_log 키 분리 실측. 수동은 멱등 밖(재발송 허용) 기존 설계 유지 |
| PROMISE-3(트랙 대체) | 충족(구조)·부분(C-2) | 약속 D-1→promise_d1·도과→promise_overdue 정확(runner·테스트). 기본 트랙 템플릿 폴백의 문구 정합만 미달 |
| REM-3(발송 창) | 충족 | 가드 SendService 유지 — 컨트롤러 테스트 10:00 발송·토요일 재예약 실측(P4 기록 포함) |
| REM-12/13(종결·재개) | 충족(무변경) | steps_for·steps_due_today·restartable? diff 0 — 소급 창·종결 훅 영향 없음 |
| P4(모든 발신 기록) | 충족 | 수동 issue_notice도 MessageLog 기록(runner 실측)·skip 사유 기록 경로 유지 |
| 아키텍처(§4.3·W-1) | 충족 | 단일 출처(DispatchService#manual_step_key) 유지·컨트롤러는 소비만·뷰는 라벨 헬퍼만 |

## 3. 통과 커버리지 — 재현 실측 요약

- **경계(runner, travel_to)**: 연말 12-31 D-1=invoice_notice·12-30(D-2)=issue_notice·15일 전=issue_notice·당일(1-1)=issue_notice·D+1=confirm_d1 / 월말 10-31(D-30)=issue_notice·11-29(D-1)=invoice_notice — Date 산수로 월·연 경계 안전
- **약속 트랙(runner)**: 전날→promise_d1·도과→promise_overdue(테스트에서 update_column 우회)·전날 이전→issue_notice — 판정 자체는 정확, 문구 정합만 C-2
- **컨트롤러 경유(IntegrationTest — with_solapi_client stub 실측)**: 만기 17일 전 `POST /app/invoices/:id/remind` → MessageLog template_key=issue_notice·303, 만기 전날 → invoice_notice. 수정 전 결함(17일 전 invoice_notice) 미재발 확인
- **회귀**: diff는 manual_step_key+주석 한정 — 자동 스캔(steps_for·nominal·소급 창·종결 훅) 0변경. 소비처(RemindersContext→remind 액션→show 뷰 "다음 안내" 라벨)·TEMPLATE_LABELS["issue_notice"]="발행 안내" 정합. 기존 시스템 테스트 라벨 단언("최종 안내(만기 14일 후)")는 D+14 건이라 영향 없음. Free 수동 허용(INELIGIBLE_PLAN 밖) 기존 유지
- **게이트(변경 3파일)**: rubocop 0 offense · 관련 테스트 31 runs/129 assertions 0 fail(클린 test DB에서 2회 — 재현 전후)

## 4. Tester 중점 테스트 제안(Phase 7)

1. **C-1 회귀(최우선)**: 상한 5 도달 청구서에서 수동 발송 → skipped+CAP_REACHED·flash 안내. 수정 방식(SendService 가드 vs manual_step_key nil)에 맞춰 컨트롤러 경유로 검증
2. **C-2 회귀**: 만기 도과+미래 약속 청구서 수동 발송 — 거짓 날짜 0건 단언(발송되지 않는 설계라면 skipped/비노출, 발송된다면 variables["만기일"] 과거 아님)·약속 당일 경계 포함
3. **무결성 회귀**: 수동 issue_notice 다수 후 자동 스캔 — D-1 invoice_notice·약속 전날 promise_d1·D+1 분기 무변경(키 분리 SEC-5)
4. **실측 보강**: "지금 1통 보내기" 라벨이 만기 17일 전 청구서에서 "발행 안내"로 표기되는지 시스템 테스트 1건(뷰 정합 — 현재 컨트롤러 테스트는 API 레벨만)
