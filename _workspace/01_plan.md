# 01_plan — F-ADMIN Run C (2026-11-10, Full · 절약 모드)

## 범위 분할 (게이트 승인 대상)

| 런 | 범위 | 사유 |
|---|---|---|
| **Run C(이번)** | **공지(ADMIN-6/7)·티켓(ADMIN-8 + `noti_ticket_reply` 발송)·FAQ 선노출(ADMIN-9)** | U1·운영자 양측 가치 완결 — credentials 등록 완료 실측(19키) |
| 별도 후속 | ADMIN-10 콘텐츠 통합 — **블로그 자체(BLOG 도메인)가 미구현**이라 LP-11 콘텐츠 허브와 통합 검토가 정합 / 쿠폰·프로모션(결제 플로우 결선)·롤 부여/해제 콘솔·계정 삭제·데이터 파기(파급 범위) — 각 필요 시점 소규모 런 | Run B 이관 목록(03 문서) 유지 |

## 구현 범위

### 1. 공지 (ADMIN-6 관리 + ADMIN-7 노출)
- `notices` 테이블: title·body(text)·importance enum(general:0/important:1)·published_at·expires_at(게시 기간 — null 허용=무기한)·timestamps
- `notice_reads`(user_id·notice_id — **복합 유니크**): 사용자별 읽음 처리(ADMIN-7)
- Admin: CRUD + 발행/종료(publish·close member)·목록 필터
- U1 노출: ① /app 대시보드 상단 **일반 배너**(닫기=읽음 기록·게시 기간 내만) ② **중요 팝업**(확인 버튼 전까지 지속 노출 — 읽음 전 모든 /app 진입 시) ③ `/app/notices` 목록·상세 — noindex 유지(SURF-3 /app 전체)
- 읽음 기록: NoticeReads::MarkService(멱등 — find_or_create_by)

### 2. 티켓 (ADMIN-8)
- `tickets`: user_id FK·category enum(billing:0/support:1/bug:2/feature:3/etc:4 — PRD 5분류)·title·status enum(open:0 접수·answered:1 답변완료·closed:2 종료)·timestamps
- `ticket_messages`(스레드): ticket_id FK·sender enum(user:0/admin:1)·body(text — 2,000자 상한)·timestamps. **이미지 첨부: Active Storage 1장**(disk 저장 — storage 볼륨·5MB·jpg/png/webp 한정 — **프로젝트 첫 AS 도입**·Rails 8.1.4.1에서 AS 권고 전부 해소 상태)
- U1: `/app/tickets` 목록·작성(분류·제목·본문·이미지 선택 — **화면에 FAQ 선노출 ADMIN-9: 랜딩 `_faq` 파셜 재사용(데이터화 후속)**)·상세(스레드·추가 질문 폼 — answered 상태에서 질문 시 **open 복귀**·closed는 재문의 불가 안내)·rate_limit(작성 5회/시간 — 스팸 방지, 뷰어 패턴 준용)
- Admin: 목록(상태·분류 필터)·상세(스레드)·답변 등록(**`noti_ticket_reply` 알림톡 발송 — credentials `KA01TP261109000802333pyOjLfFH6J4` 실측**)·종료(close)
- **알림 발송 설계**: `Tickets::NotifyAnswerService` — Solapi 래퍼 직접 호출(청구 가드 불요 — 자격·상한·수신거부 개념 없음)·variables: `사용자명`=display_name·`문의제목`=title·`url`=`badeuldon.kr/app/tickets/{id}`·**phone 미등록 시 skipped 기록·U1 향 즉시 발송(PERF-1 성격)**·발송 성공/실패/skipped 모두 MessageLog 기록
- 리마인더 시퀀스와 무관 — PLAN-3 상한 집계 밖(message_logs에는 기록하되 SEQUENCE_TEMPLATE_KEYS 밖)

### 3. 설계 결정 (게이트 확정 대상 — 권고안)
1. **티켓 알림 기록(REM-6/P4)**: `message_logs.invoice_id` **nullable 완화 + ticket_id nullable 추가** — 티켓 알림도 발송 이력에 기록(P4 "모든 발신은 기록"). invoice 관련 기존 쿼리 무영향(null 제외 집계 없음 확인 필요 — 리뷰 기준)
2. **티켓 종료 주체**: 관리자만 종료·사용자 추가 질문 시 open 복귀(스레드 보존)
3. **공지 읽음 규칙**: 일반 배너 닫기=읽음(다시 노출 안 함)·중요 팝업 확인=읽음·미확인 중요는 전 /app 화면 진입 시 모달
4. **FAQ**: 랜딩 LP-8 파셜(`/app/tickets/new` 삽입 — ADMIN-9)·FAQ 데이터화는 후속
5. **Active Storage 첫 도입**: disk 서비스(Kamal storage 볼륨 재사용 — `config.active_storage.service = :local`·production 볼륨 내 storage/ 디렉터리)

## 대상 파일 (예상)

| 구분 | 파일 |
|---|---|
| DB | 마이그레이션 1건(notices·notice_reads·tickets·ticket_messages + message_logs 컬럼 조정) |
| 모델 | notice.rb·notice_read.rb·ticket.rb·ticket_message.rb(신규)·message_log.rb(invoice optional·ticket) |
| 서비스 | notice_reads/mark_service.rb·tickets/notify_answer_service.rb·tickets/create_service.rb(신규) |
| 컨트롤러 | admin/notices·admin/tickets(신규)·app/tickets·app/notices(신규) |
| 뷰 | admin 공지·티켓 화면·app 티켓·공지 화면·app 대시보드 배너/팝업·layouts/app(팝업) |
| 라우트 | admin(notices CRUD·tickets)·app(tickets·notices) |
| 솔라피 | credentials template_ids noti_ticket_reply(등록 완료 — 코드 참조만) |
| 테스트 | models·services·controllers(admin·app) — Phase 7 |

## 진행 (Full 순차 — Developer-lite 2회 분할로 리스크 저감)

2(문서 현행화) → 3-a(공지+FAQ+U1 노출) → 3-b(티켓+알림) → 4(게이트) → 5(Reviewer-lite — **컨트롤러 경유 재현 필수**) → 6? → 7(Tester-lite) → 8 → 9

## 리스크

- Active Storage 첫 도입 — 부트·마이그레이션(as associated tables) 영향. 프로덕션 볼륨 경로 확인(Phase 8)
- message_logs 스키마 완화의 기존 쿼리 영향 — Invoice 집계는 invoice_id null 행을 자연 배제(티켓 알림은 invoice_id nil)·리뷰에서 전수 확인
- 팝업 모달의 UX(모든 /app 진입 시 중요 미확인 노출) — Turbo 내비게이션에서의 렌더 타이밍
- 티켓 스팸 — rate_limit·본문 상한·분류 강제(enum)
- noti_ticket_reply 실발송 검증 — 4종 레거시 변수명 이슈와 달리 신규 템플릿(#{사용자명}·#{문의제목}·#{url}) — 라이브 검증은 배포 후(기술 부채 패턴 준용)

## 관련 Rule ID

ADMIN-6·7·8·9 · NOTI-1(운영 사본 참조)·REM-10(솔라피 공유)·REM-6/P4(발신 기록 — 티켓 확장)·SEC-5(읽음 멱등)·PERF-1·SURF-3(/app noindex)·LP-8/ADMIN-9(FAQ)·P5(운영 표면 분리)·TIME-1
