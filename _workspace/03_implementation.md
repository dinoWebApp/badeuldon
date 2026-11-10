# 03_implementation — F-ADMIN Run C 3-a (공지 ADMIN-6/7 + FAQ 선노출 ADMIN-9)

작성: Developer(절약 모드) · 2026-11-10 · **3-b(티켓) 인계 포함**

## 1. 변경 파일 목록

### DB
- `db/migrate/20261110000004_create_notices.rb` — **2테이블 1마이그레이션**
  - `notices`: title string null:false · body text null:false · importance integer null:false default 0(general:0/important:1) · published_at datetime(nil=초안) · expires_at datetime(nil=무기한) · timestamps. 인덱스: published_at·importance
  - `notice_reads`: user_id FK(null:false, cascade) · notice_id FK(null:false, cascade) · timestamps + **복합 유니크 인덱스 [user_id, notice_id]**(SEC-5 성격 멱등)
  - `db/schema.rb` 동기화 완료. dev DB 마이그레이션 up/down 재검증 완료

### 모델/서비스
- `app/models/notice.rb`(신규) — importance enum · `published_now` 스코프(published_at ≤ Time.current ≤ expires_at 또는 무기한 — KST TIME-1) · `ordered` 스코프 · `draft?/live?/ended?` 상태 술어(ADMIN-6 목록 배지용 — 인스턴스 술어라 뷰 호출 가능) · 검증(title·body 필수, expires_at > published_at은 둘 다 있을 때만)
- `app/models/notice_read.rb`(신규) — belongs_to user/notice + 복합 유니크 검증
- `app/models/user.rb` — `has_many :notice_reads, dependent: :destroy` 추가(기존 연쇄 순서 영향 없음 — 자식 참조 없음)
- `app/services/notice_reads/mark_service.rb`(신규) — `call(user:, notice:)` find_or_create_by! 멱등(02 확정 해석 1) · Result Data 객체(created 플래그)

### Admin(ADMIN-6)
- `app/controllers/admin/notices_controller.rb`(신규) — index(최신순·중요도 필터·무효 enum 무시) · new/create · edit/update · `publish`(member PATCH — published_at=Time.current, 초안일 때만 = 멱등) · `close`(member PATCH — expires_at=현재, live일 때만) · destroy · 발행 전 초안도 목록 표시(상태 배지: 초안·게시 중·종료)
  - ⚠️ 배지 헬퍼를 `app/helpers/admin/notices_helper.rb`로 만들었다가 **zeitwerk 충돌 실측**(최상위 `Admin` = models/admin.rb 클래스)로 삭제 → 컨트롤러 `helper_method`로 이관. **3-b도 app/helpers/admin/ 디렉터리 사용 금지**
- 뷰: `app/views/admin/notices/{index,_form,new,edit}.html.erb` — Run B admin 톤(admin-card/admin-title · 필터 폼 · 상태 배지 · 발행/종료/삭제 button_to) · 이스케이프 기본 · @변수만

### U1 노출(ADMIN-7)
- `app/controllers/app/notices_controller.rb`(신규) — index(게시 중 전체·읽음 id 목록) · show(`published_now` 스코프 find — 미게시 404) · `mark_read`(member POST — NoticeReads::MarkService 경유 멱등 · 303 PRG)
- `app/controllers/app/base_controller.rb` — `load_active_notices` before_action 추가: 게시 중 중요/일반 각각 미읽음 필터(@unread_important_notices/@unread_general_notices) — /app 전 화면 대상이라 베이스에서 적재(노출 쿼리는 컨트롤러, 뷰는 @변수만)
- 뷰:
  - 배너 `app/views/app/notices/_banner.html.erb` + `dashboards/show.html.erb` 상단 render — 게시 중 **일반**·미읽음만. 닫기=POST mark_read(303 리다이렉트 후 재노출 없음)
  - 팝업 `app/views/app/notices/_popup.html.erb` + **`layouts/app.html.erb` 레이아웃 레벨 render**(미읽음 중요 최신 1건) — 확인(읽음 POST) 전까지 /app 전 화면 노출. Turbo 내비게이션에서도 레이아웃이 재평가되어 읽으면 사라짐(통합 테스트로 검증)
  - 목록/상세 `app/views/app/notices/{index,show}.html.erb` — 제목·중요도 배지·게시 기간·본문·미읽음 N 배지·상세 "확인했습니다" 버튼
- 라우트(`config/routes.rb`):
  - app: `resources :notices, only: %i[index show], path: "notice"` + `member { post :mark_read }` → **/app/notice·/app/notice/:id**(PRD 문언 준수) — 주석에 ADMIN-7 인용
  - admin: `resources :notices` + `member { patch :publish; patch :close }` — 주석에 ADMIN-6 인용
- 내비: `app/helpers/app/base_helper.rb` — "공지" 메뉴 추가(/app/notice, 프로필 미완료 시 locked)

### 기존 테스트 최소 수정 (내비 항목 추가의 직접 귀결만)
- `test/controllers/app/dashboards_controller_test.rb` — 잠금 내비 개수 6→7(공지 메뉴 추가)

## 2. Rule ID 매핑

| Rule | 구현 |
|---|---|
| ADMIN-6 | notices 테이블(중요도 enum·게시 기간) + Admin CRUD·publish/close·상태 배지·중요도 필터 |
| ADMIN-7 | notice_reads 복합 유니크·MarkService 멱등 · 일반 배너(닫기=읽음·재노출 없음) · 중요 팝업(레이아웃 레벨·확인 전 지속) · /app/notice 목록·상세(path: "notice" — PRD 문언) · noindex는 기존 /app 전체 robots(SURF-3)에 포함 |
| ADMIN-9 | 랜딩 `_faq` 파셜 재사용 준비 — 아래 §4 |

## 3. 배너/팝업 노출 규칙 구현 설명

- **노출 대상 산출**: App::BaseController `load_active_notices` — `Notice.published_now`(KST Time.current)를 중요/일반으로 분리, `where.not(id: user.notice_reads)`로 미읽음만. 뷰는 @변수만 소비(뷰 쿼리 금지).
- **일반 배너**: 대시보드 show.html.erb 상단에서 미읽음 일반 전건 렌더. "닫기" button_to → POST /app/notice/:id/mark_read → MarkService(find_or_create_by!) → 303 redirect_back → 배너 소재 로직이 미읽음에서 제외되어 재노출 없음.
- **중요 팝업**: layouts/app.html.erb에서 미읽음 중요 최신 1건을 모달 오버레이로 렌더(여러 건이면 확인 후 다음 화면에서 순차 노출). "확인" button_to → 동일 mark_read → 303 → 다음 렌더부터 제외. Turbo로 /app 내 이동해도 레이아웃 재평가로 미읽음이 없으면 렌더되지 않음(통합 테스트 "팝업 확인 후 다시 노출되지 않는다" 검증).
- **읽음 멱등(SEC-5)**: 복합 유니크 인덱스 + find_or_create_by! 이중 방어 — 재POST 303 유지·레코드 1건.

## 4. FAQ 선노출(ADMIN-9) — 3-b 인계 사항

- `app/views/landing/_faq.html.erb`는 **경로·루트 의존성 없이 자기완결**(faqs 로컬 변수 + details/summary, Tailwind 전역 클래스만 사용) — **app 레이아웃에서도 그대로 렌더 가능하며 수정 불요**로 확인했다(랜딩 index.html.erb:17은 `render "landing/faq"`로 사용 중).
- 3-b 삽입 제안: `render "landing/faq"`를 tickets 뷰에 그대로 사용(파셜은 컨트롤러 독립). 섹션 래퍼(bg-cream · py-16/24)가 앱 컨텍스트에서는 다소 크므로 원하면 카드 래퍼만 조정 — 파셜 자체는 건드리지 않는 것을 권장(랜딩 회귀 방지).

## 5. 기타 3-b 인계 사항

- **마이그레이션 번호**: 이번 건 = `20261110000004_create_notices.rb`. 3-b의 tickets/ticket_messages + message_logs 컬럼 조정은 `20261110000005_` 이후를 사용.
- **routes 현황**: app namespace에 `resources :notices, path: "notice"` 추가됨 — 3-b는 `resources :tickets`를 app namespace에 별도 추가(충돌 없음). admin namespace에 `resources :notices` 추가됨 — admin tickets도 별도 블록.
- **app/helpers/admin/ 금지** — Admin 모델 클래스와 최상위 네임스페이스 충돌(zeitwerk 실측, §1). 배지 등 표현 로직은 컨트롤러 helper_method 패턴 준용.
- `NoticesController` 컨트롤러명 vs `/app/notice` 경로: `path: "notice"` 해결 확인.

## 6. 자기 스코프 검증 결과

- **신규 테스트 32건 전부 통과**: `test/models/notice_test.rb`(11) · `test/services/notice_reads/mark_service_test.rb`(3) · `test/controllers/admin/notices_controller_test.rb`(8) · `test/controllers/app/notices_controller_test.rb`(10) — 배너/팝업 노출·닫기/확인 후 재노출 없음·mark_read 멱등 303·소유 유저 본인 기록·미게시 404·비인증/관리자 가드 포함(모두 컨트롤러 경유 HTTP 수준 재현)
- 마이그레이션 down/up 재검증 통과(dev)
- `bin/rubocop` 신규·수정 파일 29개 0 offense · `bin/rails zeitwerk:check` 통과
- 회귀: dashboards 3파일 23건 통과(1건은 내비 수 6→7 최소 갱신) · surf3_indexing · admin base_guard 통과
- dev DB 임시 레코드: 없음(테스트 레코드는 test DB) · PRD/AGENTS 문서 미수정(지시 준수)

---

## 3-b. 티켓(ADMIN-8) + `noti_ticket_reply` 알림톡 발송 — 구현 완료 (2026-11-10)

### 변경 파일

| 구분 | 파일 | 내용 |
|---|---|---|
| DB | `db/migrate/20261110000005_create_tickets.rb` | tickets·ticket_messages 생성 + message_logs nullability 완화·ticket_id 추가 / `20261110023150_create_active_storage_tables` (AS install 자동 생성) |
| Model | `app/models/ticket.rb` | 분류·상태 enum·title 100자 검증·`mark_answered!`·`reopen!`·`mark_closed!` (guard 명시) |
| Model | `app/models/ticket_message.rb` | sender enum·body 2,000자·`has_one_attached :image` (jpg/png/webp·5MB) |
| Model | `app/models/message_log.rb` | invoice `optional: true` 완화 + `belongs_to :ticket optional` + `single_subject` 검증(청구/티켓 정확히 하나) |
| Model | `app/models/user.rb` | `has_many :tickets, dependent: :destroy` 추가 |
| Service | `app/services/tickets/create_service.rb` | 티켓+첫 발화 트랜잭션 생성·Result(errors) |
| Service | `app/services/tickets/follow_up_service.rb` | 추가 질문 — closed 거부·answered → open 복귀·open 유지(PRD "종료 전까지 추가 질문 가능" 기준 — 지시문 "answered에서만"은 PRD 원문에 종료 전까지 허용이 명시돼 PRD 우선·주석 기록) |
| Service | `app/services/tickets/notify_answer_service.rb` | 티켓 전용 발송 경로(SendService 미재사용 — invoice 가드·sequence_step 결합 회피)·SolapiStubbing 주입 지점·NO_PHONE skip·실패 1회 종료 |
| Controller | `app/controllers/app/tickets_controller.rb` | index/new/create/show/follow_up · `rate_limit to: 5, within: 1.hour, by: -> { Current.user.id }, only: :create` · params.expect · helper_method 배지 |
| Controller | `app/controllers/admin/tickets_controller.rb` | index(상태·분류 필터·limit 100)/show/reply(transaction: 발화+answered 전환 후 NotifyAnswerService)/close(+`ticket_close` 감사) |
| View | `app/views/app/tickets/{index,new,show}.erb` | U1 톤 · new는 `render "landing/faq"` 선노출(ADMIN-9 — 인계 방식 준용, 파셜 무수정) |
| View | `app/views/admin/tickets/{index,show}.erb` | Run B admin 톤 · reply 폼(`ticket_message[body]`)·종료(confirm) |
| Route | `config/routes.rb` | app `resources :tickets` + member `post :follow_up` / admin `resources :tickets` + member `post :reply`, `patch :close` |
| Nav | `app/views/layouts/admin.html.erb`("티켓") · `app/helpers/app/base_helper.rb`("문의") | 3-S 결선 패턴 준용 |
| Test | `test/controllers/app/dashboards_controller_test.rb` | 잠금 내비 카운트 7→8 최소 갱신(3-a 선례 준용) |
| Test | `test/controllers/app/invoices_controller_test.rb` | Run C 팝업 button_to와의 충돌 소거 — INV-6 테스트에서 delta의 중요 공지를 사전 읽음 처리(주석 기록) |

### MessageLog optional 전환 영향 분석

- 기존 발송 경로(Reminders::SendService·DeliverJob·스캔 잡)는 `invoice_id`를 항상 채우므로 nil 허용만으로 무영향.
- 부분 유니크 인덱스(`recipient_role=debtor AND status=pending`)는 invoice_id가 채워진 채무자 행만 대상 — 티켓 알림은 `invoice_id NULL·recipient_role=user`로 인덱스 밖.
- `sent_sequence`·상한 집계(PLAN-3)는 invoice_id 조건 조회 — 티켓 행(null) 자연 배제.
- `single_subject` 검증으로 invoice·ticket 동시/동시없음 오기록 차단(P4 정합성). `user_must_own_invoice`는 invoice nil 시 return — 티켓 알림과 충돌 없음.
- 회귀: `bin/rails test test/models/message_log_test.rb test/services/reminders/send_service_test.rb` 통과.

### 알림 발송 설계 (Tickets::NotifyAnswerService)

- 템플릿 `noti_ticket_reply`(ALIMTALK_TEMPLATES.md B-4) — variables `사용자명`=display_name·`문의제목`=title·`url`=`badeuldon.kr/app/tickets/{id}`(스킴 없이 host부터 — 버튼 `https://#{url}` 규격).
- U1 향 즉시 발송(REM-3 창 제외·PERF-1 성격)·PLAN-3 상한 집계 밖(SEQUENCE_TEMPLATE_KEYS 밖·주석 명시)·재시도 불요(ApiError 시 failed 기록 후 종료)·phone blank → skipped+NO_PHONE. 성공/실패/스킵 전부 MessageLog 기록(P4).
- Solapi 호출은 컨트롤러 경유 자기검증에서 `with_solapi_client` fake로 차단 — 실호출 0회 확인.

### 자기 스코프 검증 결과 (컨트롤러 경유 HTTP)

임시 통합 테스트(실행 후 삭제 — Phase 7에서 정식화)로 전 시나리오 3시드 반복 통과: ① U1 작성 303+open·FAQ 선노출 ② 작성 6회차 429(실 스토어 주입 격리 프로세스 — test env NullStore 증분 nil 실측 반영) ③ 타인 티켓 404 ④ admin 답변 → answered + MessageLog 1건(sent·invoice nil·ticket_id·variables·원본 phone) ⑤ 추가 질문 open 복귀 → admin 종료 closed + `ticket_close` 감사 1건 → closed 후 follow_up 거부 ⑥ NO_PHONE skipped ⑦ Solapi 400 실패 → failed·303 ⑧ 이미지 첨부 경계(jpg OK·csv 422·5MB+ 초과 422).

- 전체 테스트 815건 통과(0 failure) · `bin/rubocop` 240파일 0 offense · zeitwerk 통과 · AS 마이그레이션 포함 dev migrate 완료
- rate_limit 실측 노트(Phase 7 인계): `config.action_controller.cache_store`는 test env에서 NullStore이고 `rate_limit`은 부팅 시 store을 캡처 — 429 동작 검증은 실 스토어 주입이 필요(격리 프로세스 방식).
- dev DB 임시 레코드 없음 · 문서(PRD/AGENTS) 미수정 · 솔라피 실호출 없음

## 8. Phase 6 — 리뷰 반영(05_review CHANGES_REQUESTED · 2026-11-10, 3-a+3-b 통합)

### C-1 (CRITICAL — 반영) mark_read 미게시 공지 우회 차단
- `app/controllers/app/notices_controller.rb` — `Notice.find` → **`Notice.where(published_at: ..Time.current).find`**(리뷰어 권고안 그대로). 초안(published_at nil)·미래 발행은 404 차단. **show의 `published_now`와의 차이 주석 명시**: 이미 종료된 공지는 허용(세션 도중 만료 클릭의 404 UX 유지).
- 컨트롤러 경유 재검증(`test/controllers/app/notices_controller_test.rb` 4건 추가): 초안 mark_read 404+NoticeRead 0건 · 미래 발행 404 · 종료 건 허용 303 · **초안 차단→발행 후 mark_read 정상** 회귀. Phase 7 Tester 인계 목록의 "C-1 회귀 최우선"은 위 4건으로 충족 가능.

### W-1 (반영 — app 측) 티켓 첨부 이미지 인증 서빙
- `app/controllers/app/tickets_controller.rb` — `image` 액션 신설: 소유 스코프 경유 404(타 U1·존재 프빙 차단) 후 **send_data 스트리밍**(inline·원본 content_type/filename).
- 라우트 1건(`config/routes.rb`): `GET /app/tickets/:ticket_id/messages/:message_id/image`(`app_ticket_message_image_path`).
- 뷰: `app/views/app/tickets/show.html.erb` 이미지 태그 교체 — 렌더 HTML에서 `/rails/active_storage/blobs/redirect/` 부재 단언 통과.
- 재검증(`test/controllers/app/tickets_image_serving_test.rb` 신설·유지): 소유자 200(image/png·바이트 일치) · 타 U1 404 · 비로그인 302 로그인 리다이렉트.
- **⚠️ admin 측 잔존(인계)**: `app/views/admin/tickets/show.html.erb`는 소유권 제한(지시: app 측만)으로 AS 리다이렉트 image_tag 유지. 완전 차단하려면 admin 전용 서빙 경로(admin 세션 가드) 또는 AS 커스텀 routes 제거(기술 부채) 필요.

### W-3 (반영) publish 무음 실패
- `app/controllers/admin/notices_controller.rb` — update 성공·이미 live일 때만 성공 플래시, 실패 시 **alert**(검증 문구 포함·303 유지). close는 검증상 실패 불가라 미변경(리뷰 판정 준용).
- 재검증: 만료가 과거인 초안 발행 → published_at nil 유지 + alert 단언(테스트 1건 추가).

### W-4 (반영 — app 측) 첨부 이미지 N+1
- `App::TicketsController#show` — `with_attached_image.ordered` 결합. admin 측(`admin/tickets_controller.rb`)은 소유권 밖 — 인계(W-1 잔존과 동일).

### W-2 (수용 — Tester 인계)
- 티켓 도메인 정식 테스트 → Phase 7 인계(리뷰어 §3 재현 16 시나리오 전환). 본 수정으로 추가된 C-1 4건·W-1 4건·W-3 1건은 기존 스위트에 유지 — 회귀 방어막 일부 선확보.

### 게이트 결과
- `bin/rubocop` 수정 rb 파일 7개 + views dir 0 offense · `bin/rails zeitwerk:check` 통과
- 재검증 실행: notices(app 14건·admin 9건) + tickets_image_serving 4건 + dashboards 회귀 — **42 runs 241 assertions 0 failures**
- Phase 6 잔존 해소(3-b admin 측 W-1·W-4): `Admin::TicketsController`에 `image` 액션 추가(admin 가드 하 send_data — app 측 패턴 준용)·admin 라우트 `GET tickets/:ticket_id/messages/:message_id/image` 결선·`show`에 `with_attached_image` 결합·`admin/tickets/show.html.erb`의 `image_tag(message.image)`를 인증 서빙 경로로 교체. 관리자 로그인 세션 Integration(임시·후 삭제)으로 이미지 200·AS 리다이렉트 URL 부재·비인증 리다이렉트 재현, `test/controllers/app/tickets_image_serving_test.rb` 회귀 없음(7건 통과), rubocop 전체 0 offense·zeitwerk 통과.

## 9. 수동 발송 스텝 선택 결함 수정 (2026-11-10 — Standard·운영 실측 버그)

**결함(운영 실측·사용자 제보)**: `Reminders::DispatchService#manual_step_key`가 만기 미도과 청구서에 무조건 `invoice_notice`를 반환. 이 템플릿은 솔라피 검수본에 "(내일)"이 박힌 만기 전날(D-1) 전용 문구라 만기 17일 남은 시점의 수동 발송("지금 1통 보내기")에서 "결제 예정일: 11월 27일(금) (내일)"로 발송됨(메시지 로그 확인). 약속 트랙도 동일 — `promised_on >= today`면 무조건 `promise_d1`("내일(약속일)" 박힘).

**수정**: 수동 선택 경계 재정의 — "(내일)" 문구 템플릿(`invoice_notice`·`promise_d1`)은 전날(D-1)에만 선택. 그 외 만기 전 구간(당일 포함)은 SHARE-6 발행 안내 `issue_notice`(날짜만 안내 — 어느 날 보내도 내용이 참)로 대체. 약속 트랙은 전날→`promise_d1`·도과→`promise_overdue`·그 외→`issue_notice`. 수동 `issue_notice`는 템플릿 키가 달라 자동 스캔의 `invoice_notice` 멱등(`step_sent?`)과 무관 — D-1 도래 시 자동 안내는 정상 발송된다. 수동 재발송 허용(origin=manual은 스텝 멱등 대상 밖 — 기존 C-1 설계 준용), 상한·수신거부·발송 창 가드는 SendService 유지. **자동 스캔(steps_for·nominal)은 전혀 변경 없음.**

**파일**:
- `app/services/reminders/dispatch_service.rb` — `manual_step_key` 재작성 + 사유 주석(당일 처리·자동 멱등 무관성 명시)
- `app/helpers/app/reminders_helper.rb` — 변경 없음(라벨 맵에 `issue_notice`="발행 안내" 기존 존재 확인, 경계 라벨 정합)
- `test/services/reminders/dispatch_service_test.rb` — manual_step_key 케이스를 새 경계로 갱신: 만기 17일 전→issue_notice·만기 전날→invoice_notice·만기 당일→issue_notice·약속일 10일 전→issue_notice·약속일 전날→promise_d1·약속일 도과→promise_overdue(도과 케이스는 Promise 검증 우회 위해 생성 후 update_column)
- `test/controllers/app/invoices_reminders_test.rb` — 컨트롤러 경유 재검증 테스트 신설(`with_solapi_client` stub 필수): U1 세션에서 `POST /app/invoices/:id/remind` → 만기 17일 전 MessageLog template_key=`issue_notice`·variables에 "(내일)" 없음, 만기 전날=`invoice_notice`

**게이트 결과**: `bin/rubocop`(수정 4파일) 0 offense · `bin/rails zeitwerk:check` 통과 · `bin/rails test test/services/reminders/ test/controllers/app/` — **274 runs, 1651 assertions, 0 failures, 0 errors**

### §9.1 Phase 6 — 리뷰 반영(CHANGES_REQUESTED C-1·C-2·W-1·W-2 · 2026-11-10)

**C-1 — 수동 issue_notice 상한 우회 차단(PLAN-3 하드리밋 복원)**: 본 수정(§9)으로 issue_notice가 수동 반복 선택 가능해져 "1회성" 전제가 깨짐(재현: 상한 도달 후 수동 issue_notice 7회 전부 sent·누계 12통). SendService 가드에 **수동(origin=manual)은 템플릿 무관 상한** 추가 — `manual_cap_reached?`는 채무자 향 sent 전체를 집계(시퀀스성·1회성 혼합 총량도 5통을 넘지 않게 한다 — 리뷰 재현 시나리오 "invoice_notice 3 + issue_notice 2 → 6통째 차단" 충족에 시퀀스 키 한정 집계로는 불충분). 자동 시퀀스성은 기존대로 `sequence_step?` 한정, 자동 1회성 3종은 기존대로 집계 밖. 근거: PLAN-3 "하드리밋(수동 포함)"·REM-8 "동일 템플릿 수동 발송·상한 내". Q10과의 긴장은 오케스트레이터가 PRD에 기록 예정.

**C-2 — 약속 트랙 폴백의 과거 날짜 발송 차단**: 폴백 issue_notice가 만기 도과 구간에서 과거 만기일을 안내(재현: 만기 11-27 도과 후 12-01 발송 → "11월 27일(금)"). **불변식 정정(W-2)**: 폴백 issue_notice는 `due >= today`일 때만 허용. 만기 도과 + 약속 전날 이전(당일 포함) 창은 18종 중 참인 템플릿이 없어 `manual_step_key`가 **nil 반환** → 컨트롤러 `remind` 액션이 안내 flash("지금 상황에서 보낼 수 있는 안내 문구가 없습니다. 약속일이 지나면 자동으로 안내됩니다.")로 수렴 — 발송·MessageLog 기록 없음(스킵도 아님 — 발송 시도가 아니다). 해당 창의 명세 공백은 오케스트레이터가 PRD에 기록 예정(인계).

**W-1**: 컨트롤러 테스트 판별력 보강 — C-1 혼합 총량 테스트(6통째 CAP_REACHED + template_key 단언)·C-2 nil 창 테스트(만기 도과+미래 약속·약속 당일 경계, 발송·기록 0건·flash 단언) 신설.
**W-2**: manual_step_key 주석·본 §9 서술을 실제 규칙(폴백 due>=today 한정·nil 창·수동 상한 템플릿 무관)으로 정정.

**파일**: `app/services/reminders/dispatch_service.rb`(폴백 due 한정·nil)·`app/services/reminders/send_service.rb`(수동 상한)·`app/controllers/app/invoices_controller.rb`(`redirect_no_template`)·test 2파일.

**게이트 결과**: `bin/rubocop` 5파일 0 offense · `bin/rails zeitwerk:check` 통과 · `bin/rails test test/services/reminders/ test/controllers/app/` — **276 runs, 1669 assertions, 0 failures, 0 errors**

**인계 노트**: `app/views/app/invoices/show.html.erb`의 "다음 안내:" 라벨은 `@manual_template_key`가 nil이면 빈 표기가 된다(message_template_label(nil) → 빈 문자열 폴백) — C-2 nil 창에서 버튼은 동작하되 라벨만 비어 보인다. 뷰 파일은 본 수정 소유권 밖이라 건드리지 않았으며, nil 시 라벨 숨김 처리를 후속 권고한다(Phase 7 Tester 인계).
