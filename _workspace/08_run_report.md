# 08_run_report — INV-7 반복 청구 + PAY-6 PDF 실행 검증 (2026-11-11, Phase 8)

- 부트: 포트 3002·pid 분리 — Puma 정상·**WARN/deprecated 0건**
- 라우트 실측(정정 — 최초 프로브가 단수 경로 착오, 복수 계약 경로로 재확인):
  | 경로 | 기대 | 실측 |
  |---|---|---|
  | `GET /up` | 200 | 200 ✓ |
  | `GET /app/recurring_invoices` | 302(가드) | 302 ✓ |
  | `GET /app/recurring_invoices/new` | 302(가드) | 302 ✓ |
  | `GET /app/invoices/1/payment_pdf` | 302(가드) | 302 ✓ |
  - 인증 후 동작(생성·PDF 본문·한글 렌더)은 Phase 7 시스템 테스트(app_invoice_pdf_test 등)로 검증
- 마이그레이션: recurring_invoices·recurring_invoice_items·subscriptions.coupon_id(선행) 적용 완료
- 검증 서버 정리 완료(포트 3002 free 실측)

| 게이트 | 결과 |
|---|---|
| 7-S 전체 테스트 | 1,008 runs·0 failures(+system 11 = 1,019) |
| rubocop | 283 files 0 offenses |
| zeitwerk·migrate | 통과 |
| Phase 5→6→재리뷰 | CHANGES_REQUESTED(B1 계정 삭제 FK 파탄·B2 PDF 텍스트 전무·C1 이중 발행·C2 스캔 고착·W3) → 수정(pdftotext 한글 추출 증거) → **재리뷰 APPROVED**(원 이슈 7건 독립 재증명) |
| 위임 실측 | T-D1·T-D2·리뷰·테스트·수선 전부 정의 일치(Flash/low·high) |
| 운영 참고 | recurring.yml 06:30 KST — Solid Queue 잡 프로세스(bin/jobs)에서 실행·NOTI-3 템플릿 솔라피 등록 전까지 알림톡은 skipped(NO_TEMPLATE) 기록 |
