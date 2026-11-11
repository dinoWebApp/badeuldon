# 05_review — INV-7 반복 청구 + PAY-6 수금완료 PDF 병렬 배치 (2026-11-11, Reviewer)

## Status: APPROVED (재리뷰 루프 1/2 — 2026-11-11)

초차 리뷰 CHANGES_REQUESTED(BLOCKER 2·CRITICAL 2·WARNING 3) → Phase 6 통합 수정 → **7건 전부 해소 확인·신규 이슈 0**. 전체 스위트 1008 runs 0 failures 0 errors 0 skips(리뷰어 재실행 실측)·변경 18파일 rubocop 0 offenses.

| # | 원 Severity | 위치(수정 후) | 판정 | 재증명 방법(리뷰어 독립 재현) |
|---|---|---|---|---|
| B-1 | BLOCKER | user.rb(선언 이동+주석)·AccountPurgeService(InvalidForeignKey 방어)·purge 테스트 | **해소** | 완납 청구+last_invoice 보유 스케줄 사용자 purge → success·user/schedule/invoice 전부 0건. 초차의 InvalidForeignKey 재현이 사라짐. developer 재발 테스트(동일 시나리오)도 통과 |
| B-2 | BLOCKER | vendor/fonts/*.ttf(OTF 삭제)·receipt_pdf_service(.ttf 경로)·재발 테스트 2건 | **해소** | HTTP로 PDF 수령 → pdftotext **에러 0개·전문 추출**: 수금 완료 증빙·청구번호·거래처명·발행일·입금일(MAX paid_on)·품목 2행(수량×단가=합계)·공급가액 100,000원·부가세 10,000원·총액 110,000원·생성일시 KST·푸터. 초차엔 0바이트+Syntax Error 수십 개였음. pdftoppm 렌더 육안도 정상(한글 타이포·우측 정렬·총액 녹색). 폰트 `file` 실측 TrueType |
| C-1 | CRITICAL | IssueService(call을 schedule.with_lock 감쌈+인큐 커밋 후 분리)·C-1 테스트 | **해소** | advance! 강제 실패 → 예외 상승·**Invoice 0건(롤백)**·커서 유지·**인큐 0건**·소비된 수금 패스까지 롤백(with_lock×issue! 내부 트랜잭션×PLAN-4 consume_collection_pass! 중첩 실측) → 재실행 시 정확히 1회 발행+패스 1건 소비. 초차의 이중 발행(11→12) 재현이 소멸 |
| C-2 | CRITICAL | RecurringInvoice(due_or_overdue 스코프+가드 <=+advance!/hold! 커서 구값 기준)·IssueJob 갱신 | **해소** | 커서 3일 고착(11-07·day 7) → 1회 발행·커서 **구값 기준 12-07**(드리프트 0)·last_issued_on=today. paused/cancelled는 여전히 스캔 제외. 초차의 영구 정지 재현이 소멸 |
| W-1 | WARNING | Controller(pause=active만·resume=paused만·render_invalid_transition 303+alert)·transitions 테스트 4건 | **해소** | HTTP 매트릭스: cancelled→resume 거부(alert 문언 정확·상태 유지)·paused→pause 거부·active→resume 거부·정상 전이 체인 전부 통과 |
| W-2 | WARNING | 방침 (b) 채택 — SendService(MISSING_TEMPLATE→skipped(NO_TEMPLATE))·IssueService(U1 통보 2종 커밋 후 인큐·보류사유 변수·held 버튼 url 분기)·no_template_skip 테스트 | **해소** | ① MISSING_TEMPLATE → :skipped·MessageLog `skipped/NO_TEMPLATE`(invoice 스코프·recipient_role user — NotifyUserService 선례와 동일 규약)·예외 상승 없음 ② 정상 응답 → :sent 무영향 ③ HTTP_400(타오류) → 기존대로 :failed ④ 인큐 계약: issued=2건(issue_notice debtor+noti_recurring_issued user)·held+last_invoice=1건(noti_recurring_held user)·한도 skip 등 last_invoice 없는 held=0건(스케줄 사유 기록으로 대체) ⑤ held 변수 맵에 `보류사유` 전달 실측. 템플릿 조회는 credentials template_ids라 등록 후 코드 변경 없이 자동 활성화 — Q15 원문 부합 |
| W-3 | WARNING | Controller(reject_forged_items before_action 추출) | **해소** | create 본문 8줄(≤10)·위조 품목 id 422 가드 유지(초차 재현 시나리오 재통과) |

---

## 재리뷰 검증 방법 (2026-11-11 — 컨트롤러 경유 통합 재현 유지)

1. **수정 diff 전수 정독**: user.rb·AccountPurgeService·IssueService·RecurringInvoice(스코프·커서)·IssueJob·Controller·SendService·ReceiptPdfService·Gemfile 폰트 — 7건 대응 전부 확인
2. **리뷰어 독립 재현 테스트 8건 작성·실행(67 assertions 통과)** — 위 표의 재증명 열. developer 테스트(동일 시나리오)와 별도 설계로 이중 검증. 실행 후 파일·/tmp·레코드 전부 삭제(잔여 0건 실측)
3. **B-2 독립 추증**: HTTP 응답 본체를 poppler pdftotext(에러 0)·pdftoppm 렌더로 이중 검증 — developer의 매직바이트·/Subtype /TrueType 단정 테스트와 별개
4. **회귀(지시 2)**: ① with_lock 중첩 — C-1 재현에 PLAN-4 수금 패스 소비 경로를 포함해 롤백 원자성까지 실측 + payments_concurrency·payment_pass_concurrency·subscription·payment_pass·subscriptions 서비스 57 runs 통과 ② SendService 변경 — reminders 서비스 5종 전체(dispatch·notify_user·prenotice·send·no_template) 통과 ③ user.rb 선언 이동 — user_test·account_purge_service_test 통과
4. **전체 스위트**: `bin/rails test` → **1008 runs, 5688 assertions, 0 failures, 0 errors, 0 skips**(리뷰어 실측) · `bin/rubocop` 변경 18파일 0 offenses
5. **W-2 규약 확인(지시 3)**: skipped MessageLog는 invoice 스코프+recipient_role user(기존 U1 향 이벤트 알림 선례와 동일)·P4 발신 시도 기록 충족·held는 last_invoice 존재 시에만 인큐되어 invoice 문맥 보장·claim_log의 U1 이벤트 경로(user_role·scheduled_at nil)는 이벤트마다 1통 정상 — REM-6/P4 정합

## 관찰 사항 (이슈 아님 — 기록 목적)

1. **한도 skip(held)의 last_invoice 미보유 케이스**: MessageLog가 invoice 스코프라 첫 달 한도 도달(직전 발행 없음) 시 U1 알림톡은 인큐되지 않고 스케줄 last_skip_reason+show 배너가 대체한다. Q15 취지(발행 무영향·사유 기록)에는 부합 — 솔라피 등록 후 통보 커버를 넓히려면 그때 별도 검토
2. **잔존 명칭**: issue_service_test.rb:153 테스트명·recurring_invoice_test.rb 헤더 주석에 "due_today" 잔존(동작은 due_or_overdue) — 코스메틱
3. **NOTI-3 등록 전 운영 절차**: credentials에 noti_recurring_issued·noti_recurring_held 코드 추가가 곧 자동 활성화 — ALIMTALK_TEMPLATES.md B-5(20·21번) 검수·등록 후 credentials 반영 필요(기존 기술 부채 절차와 동일)

## 최초 리뷰 이슈 아카이브 (초차 리뷰 2026-11-11 — 전부 해소)

<details>
<summary>초차 CHANGES_REQUESTED 이슈 목록(클릭해 펼치기)</summary>

| # | Severity | Rule ID | 위치 | 요지 |
|---|----------|---------|------|------|
| B-1 | BLOCKER | ADMIN-3·Q13·INV-7·AUTH-1.5 | user.rb:7·19 + 마이그레이션 | 발행 이력 있는 스케줄 보유 사용자 계정 삭제가 FK restrict로 파탄(purge 500) — `FOREIGN KEY constraint failed` 실측 |
| B-2 | BLOCKER | PAY-6·Q17 | vendor/fonts/*.otf | PDF 텍스트 전무(OTF CFF × Prawn 서브셋 비호환 — poppler·CoreGraphics 양쪽 실측) |
| C-1 | CRITICAL | INV-7·SEC-5 | IssueService | 발행→advance! 비원자 창 — 재실행 이중 발행 실증(Invoice.count 11→12)·무통지 청구·보류 판정 상실 |
| C-2 | CRITICAL | INV-7·TIME-1 | RecurringInvoice.due_today | 커서 equality 스캔 — 잡 미실행일 영구 정지(다음 달에도 부활 0 실측) |
| W-1 | WARNING | INV-7 | Controller | cancelled resume 재활성 가능(active 전이 실측) |
| W-2 | WARNING | NOTI-3·Q15 | IssueService | skipped(NO_TEMPLATE) 기록 부재·등록 후 코드 수정 필요 |
| W-3 | WARNING | 컨벤션 | Controller | create 19줄(가이드 10줄 초과) |

</details>

### 초차 Rule ID 준수 매핑·통과 커버리지 (판정 유효 — 수정으로 약화된 항목 없음)

초차 리뷰에서 정합 판정한 항목은 수정 후 재검증에서 모두 유지됐다: INV-7 등록 요소·발행일 1~28·일시중지/해지(W-1 가드로 더 강화)·보류 설정(unsettled DB 판정)·자동 발행(issue! 재사용 — 이제 with_lock 원자)·Q16·PLAN-1(count basis 일치)·SHARE-6/REM-1(동일 경로+커밋 후 인큐로 강화)·PAY-6 본문(TTF로 완성)·Q17·TIME-1(06:30 fugit 실측 유지)·소유권 격리·아키텍처 §4(잡→서비스→모델·컨트롤러 얇음)·UI 품질(터치 타깃·상태색·focus 링)·SURF/표면. 상세 근거는 초차 리뷰 본문(git 이력) 참조.

### Tester에게 제안하는 중점 테스트 영역 (수정 후 갱신)

1. **B-1**: 완납+last_invoice 스케줄 purge — developer 테스트 존재. 시스템 테스트(관리자 콘솔 경유)는 Phase 7 선택
2. **B-2**: 실기·실뷰어 1회 육안 권장(Preview·Chrome) — 자동 테스트는 매직바이트+/Subtype으로 고정됨. PDF 파일명 한글(Content-Disposition filename*)은 브라우저별 표기 차이 확인
3. **C-1·C-2**: travel_to 기반 시나리오 테스트 존재 — Solid Queue 실제 환경에서의 06:30 실행·배포 중첩은 운영 관측 항목으로 남긴다(첫 운영 월 로그 확인 권장)
4. **W-2**: 솔라피 템플릿 등록 후 credentials 반영 → 반복 청구 발행 → noti_recurring_issued 실발송 E2E(기존 기술 부채 "솔라피 라이브 실측" 절차와 동일 흐름)
5. **INV-7 전체 수금 루프**: 발행→열람→리마인더→약속→입금→다음 달 반복의 시스템 테스트(뷰어 인앱 브라우저 포함) — 신규 스케줄이 기존 INV/PAY/REM 체인과 간섭 없음을 E2E로 한 번 더
