# 02_prd_update — F-ADMIN Run C 문서 현행화 (2026-11-10, Phase 2)

PRD v0.31 → **v0.32**. Run C(공지·티켓·FAQ) 승인에 따른 구현 확정 반영.

## PRD.md 변경 내역 요약

| 위치 | 변경 요지 |
|---|---|
| 문서 버전 | v0.32 (F-ADMIN Run C 구현 확정) |
| ADMIN-6 | notices 테이블(중요도 enum·게시 기간)·관리자 CRUD+발행/종료 |
| ADMIN-7 | notice_reads(복합 유니크·멱등)·일반 배너 닫기=읽음·중요 팝업 확인 전 지속·경로 `/app/notice`(PRD 문언 준수 — path: "notice") |
| ADMIN-8 | tickets+ticket_messages 스레드·AS 이미지 1장(5MB·jpg/png/webp)·rate_limit 5회/시간·본문 2,000자·관리자 종료·사용자 추가 질문 open 복귀·`noti_ticket_reply` 발송 연동(등록 완료 전환)·REM-6 확장(message_logs.invoice_id nullable+ticket_id) |
| ADMIN-9 | LP-8 파셜 재사용(데이터화 후속) |
| ADMIN-10 | 후속 분리 — LP-11 블로그와 통합 검토·쿠폰·롤 콘솔·계정 삭제도 범위 밖 명시 |

## Developer 지시서 전달 해석

1. **공지 읽음**: `NoticeReads::MarkService` — find_or_create_by 멱등(SEC-5 성격). 배너 닫기/팝업 확인/Turbo POST 읽음 endpoint
2. **티켓 알림**: `Tickets::NotifyAnswerService` — Solapi 래퍼 직접(청구 가드 불요)·variables `사용자명`·`문의제목`·`url=badeuldon.kr/app/tickets/{id}`·phone blank → skipped+NO_PHONE·모든 시도 MessageLog 기록(invoice_id: nil·ticket_id 세팅)
3. **message_logs 완화**: 기존 Invoice 기반 집계·스코프는 invoice_id null 행 자연 배제 — 리뷰에서 전수 확인
4. **AS 첫 도입**: `bin/rails active_storage:install` — disk service(config storage yml)·Kamal storage 볼륨 경로 확인은 Phase 8
5. **티켓 rate_limit**: 뷰어 rate_limit 패턴 준용(to: 5, within: 1.hour, by: Current.user)
