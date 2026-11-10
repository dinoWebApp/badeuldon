# 01_plan — INV-7 반복 청구 + PAY-6 수금완료 PDF 병렬 배치 (2026-11-11, §6.14 parallel · 절약 모드)

## §6.14 병렬 판정

**유리 — 2태스크 fan-out + 3-S 결선**:
- T-D1(INV-7) = recurring 도메인(마이그레이션·모델·잡·U1 UI) / T-D2(PAY-6) = PDF 도메인(gem·서비스·invoices member 액션) — **파일 소유권 분리 ✓**
- 상호 의존 없음(반복 청구는 PDF 미참조·PDF는 반복 청구 미참조) **✓**
- 공유 파일(routes·app nav)은 3-S 결선 **✓**

## T-D1 · INV-7 반복 청구 (REM-1 서비스 명의·NOTI-3)

- **스케줄 모델**: `recurring_invoices`(user·client FK·day_of_month 1~28 — 월말 말일 이슈 회피 권고·tax_mode·withholding_enabled·hold_if_unpaid boolean·status enum active:0/paused:1/cancelled:2·last_issued_on·next_issue_on·timestamps) + `recurring_invoice_items`(recurring_invoice FK·name·quantity·unit_price — 발행 시 스냅샷 소스)
- **자동 발행 잡** `RecurringInvoices::IssueJob`(매일 06:30 KST — recurring.yml): next_issue_on == today && active → 발행 플로우
  - **보류 규칙(INV-7)**: hold_if_unpaid && 직전 발행 청구가 미수(unsettled) → 발행 skip·보류 기록(schedules 상태 필드 last_skip_reason + skip 카운트 — NOTI-3 통보 대상)
  - **PLAN-1 한도 적용**(권고·게이트 확정): 월 한도 초과 시 skip+사유 기록 — 반복 청구도 Free 3건 한도 대상
  - 발행: Invoice 신규 생성(초안→`issue!` 재사용 — 채번·토큰·한도·수금패스 전부 기존 검증 재사용)→ **issue_notice 알림톡**(REM-1 서비스 명의 — 기존 DeliverJob enqueue 재사용·자격·가드 SendService 위임)
  - 발행 성공: last_issued_on·next_issue_on=다음 달 N일 갱신
- **NOTI-3 알림톡(결정 필요·Q15 제안)**: 발행 완료 통보·보류 사유 통보용 템플릿 `noti_recurring_issued`·`noti_recurring_held`가 **19종에 없음 → ALIMTALK_TEMPLATES.md B-5 초안 작성(사용자 검수 후 솔라피 등록)**·등록 전까지는 DeliverJob 수준에서 MISSING_TEMPLATE 예외를 **skipped(NO_TEMPLATE) 기록으로 흡수** — 발행 자체는 정상·템플릿 등록 후 자동 활성화. 대안(U1 대시보드 알림만)보다 이 방침 권고
- **U1 UI**: `/app/recurring` 리소스 — 목록·신규(거래처 select·품목 행 동적[CLIENT-2 items 재사용·직접 입력]·매월 N일·tax_mode·withholding·보류 설정)·상세(발행 이력)·**일시중지/재개·해지**(INV-7) — 사이드바 "반복 청구" 메뉴(3-S)
- 발행된 청구는 기존 Invoice로 — 상태·수금·리마인더 시퀀스 전부 기존 플로우 재사용
- 소유 파일: 마이그레이션 1건(2테이블)·`recurring_invoice.rb`·`recurring_invoice_item.rb`·`RecurringInvoices::IssueJob`·`RecurringInvoices::IssueService`(발행+보류 판정)·`app/controllers/app/recurring_invoices_controller.rb`+views·routes(3-S)·테스트

## T-D2 · PAY-6 수금완료 증빙 PDF

- **기술 결정(권고)**: `prawn` gem 추가(Gemfile — T-D2 단일 소유)·**한글 폰트 Pretendard OTF 번들**(npm pretendard dist/otf Regular+Bold — public/fonts 재사용 불가, PDF는 파일시스템 경로 필요 → `app/assets/pdfs/` 또는 lib/assets 다운로드 번들)
- **범위 한정(권고)**: PAY-6(발행자 회계 보관용)만 — VIEW-4 뷰어 PDF는 이번 범위 밖(후속 표기)
- **서비스** `Invoices::ReceiptPdfService` — paid 청구 한정(마감 상태 아님 → 생성 불가)·내용: 거래처명·청구번호·발행일·**품목 요약(행별 명·수량·단가·합계)**·공급가액·부가세·총액·**입금일(마감 입금일 = MAX paid_on)**·원천징수(옵션 건)
- **액션**: `GET /app/invoices/:id/payment_pdf`(member·paid 청구만 — 미마감 404/안내·본인 소유권) → send_data(파일명 `수금완료증빙_{청구번호}.pdf`)·청구서 상세(수금 완료 상태)에 다운로드 버튼
- 소유 파일: `Gemfile`·`Gemfile.lock`·폰트 파일 2·`app/services/invoices/receipt_pdf_service.rb`·`app/controllers/app/invoices_controller.rb`(member 액션 추가)·invoice show 뷰(버튼)·routes는 3-S(간단해도 결선 통일)·테스트(생성 바이트·한글 렌더·미마감 차단)
- 판정: ✓ 3조건(Gemfile 단일 소유·T-D1과 무관)

## 3-S 결선 (단일 Developer-lite)
- routes 결선(T-D1 recurring_invoices resources + T-D2 payment_pdf member)·app nav "반복 청구" 추가·전체 migrate·스모크(303 가드·PDF 404/200)·T-D1/T-D2 컨트롤러 테스트 실행(결선 후 최초 HTTP 검증 — Run A 교훈)

## 결정 기록 제안 (게이트 확정 → Phase 2 PRD 반영)

| # | 결정 | 권고 |
|---|---|---|
| Q15 | NOTI-3 알림톡 템플릿 미등록 처리 | 초안 작성(B-5)·등록 전 skipped(NO_TEMPLATE) 기록·발행 정상·등록 후 자동 활성화 |
| Q16 | PLAN-1 한도 적용 | 반복 청구도 월 3건 한도(Free) — 초과 시 skip+사유 기록·Plus 무제한 |
| Q17 | PDF 기술·범위 | Prawn+Pretendard OTF 번들·PAY-6(발행자용)만·VIEW-4 뷰어 PDF 후속 |
| — | day_of_month 1~28 | 월말(29~31) 말일 이슈 회피 — 등록 UI에서 1~28 한정 |

## 대상 파일 요약

T-D1: 마이그레이션·recurring 모델 2·잡 1·서비스 1·app/recurring 컨트롤러+뷰 4~5·테스트 / T-D2: Gemfile·폰트 2·PDF 서비스·invoices 컨트롤러·show 버튼·테스트 / 3-S: routes·nav

## 관련 Rule ID

INV-7·NOTI-3·REM-1(issue_notice)·PAY-1/2(마감 입금일)·PAY-6·PLAN-1·VIEW-4(범위 밖 표기)·TIME-1·SURF-3
