# T-D2 — PAY-6 수금완료 증빙 PDF · 구현 산출물 (2026-11-11, 절약 모드 fan-out)

## 변경 파일 목록 (소유권 화이트리스트 내 전부)

| 파일 | 변경 | 내용 |
|---|---|---|
| `Gemfile` / `Gemfile.lock` | 수정 | `gem "prawn", "~> 2.5"` + `gem "prawn-table"` — 2.5가 최신 stable(3.0 미출시 실측). **prawn-table 필수**: Prawn 2.x부터 표 레이아웃은 별도 gem(지시문의 "prawn 내장"은 1.x까지 사실 — 실측 NoMethodError로 확인·추가). 둘 다 순수 Ruby, 네이티브 확장 없음, bundle install 로컬 성공 |
| `vendor/fonts/Pretendard-Regular.otf` · `Pretendard-Bold.otf` | 신규 | jsdelivr npm pretendard@1.3.9 `dist/public/static/*.otf` (지시 경로 `dist/otf/`는 404 → 패키지 파일 트리 조회로 실제 경로 확정). 각 1.57MB, `file` = OpenType font data, 바이트 검증 통과(>100KB·OTF 헤더) |
| `app/services/invoices/receipt_pdf_service.rb` | 신규 | `Invoices::ReceiptPdfService.call(invoice:)` → PDF 문자열 반환 |
| `app/controllers/app/invoices_controller.rb` | 수정 | `payment_pdf` member 액션 + `before_action :set_invoice`에 `payment_pdf` 추가(소유권 스코프 = `Current.user.invoices.find` — 타인 404). 액션 12줄(주석 제외 8줄) |
| `app/views/app/invoices/show.html.erb` | 수정 | paid 상태 녹색 확정 카드 안에 "수금완료 증빙 PDF" 보조 액션 버튼 1개(`link_to … download:` — 강조 없이 흰 배경+녹색 링·hover/focus 링) |
| `test/services/invoices/receipt_pdf_service_test.rb` | 신규 | 서비스 단위 테스트 6건 |

**하지 않음(계약대로)**: routes 추가 없음 — 3-S가 `resources :invoices` 내 `member { get :payment_pdf }`로 결선. 뷰는 계약명 `payment_pdf_app_invoice_path(invoice)` 참조(3-S 결선 전까지 show 렌더·컨트롤러 HTTP 불가 — 예정된 상태). PRD·AGENTS·recurring·nav 일체 미접촉.

## PDF 레이아웃 (A4 · margin 56pt · Pretendard)

1. 제목 "수금 완료 증빙"(Bold 22pt) + 청구번호(BD-YYYYMMDD-NNN, 회색 10pt) + 수평선
2. 요약 표 4행: 거래처명 · 청구번호 · 발행일(issued_at) · **입금일 = `payments.maximum(:paid_on)`** (PAY-1/2 — 마감 입금일, 다중 입금 시 최대값)
3. "품목 내역" 표: 품목명·수량·단가·합계(행별, `prawn-table`, 행 합계 = 수량×단가)
4. 금액 표: 공급가액 · 부가세 · (원천징수 옵션 건만) 원천징수 3.3% −실수령액 · **총액**(Bold, 완료 녹색 배경 — DESIGN-2)
5. 하단: 생성일시(KST `Time.current` — TIME-1) + "본 문서는 받을돈에서 생성된 수금 완료 증빙입니다"

가드: `paid?` 아님 → `Invoices::ReceiptPdfService::PdfNotAvailable` raise. 컨트롤러는 **404 대신 상세 redirect + alert 안내**로 변환(UX 판정 — 코드 주석에 명시, 서비스 가드와 이중 방어). 금액 포맷은 뷰 `won` 헬퍼와 동일 천단위 콤마+원(DESIGN-3, `ActiveSupport::NumberHelper` — 서비스 계층은 뷰 헬퍼 호출 불가라 재현). 컬럼은 `description`(InvoiceItem 실명) 사용. 마이그레이션 불요(기존 컬럼만 참조).

## 테스트 (6건 — `test/services/invoices/receipt_pdf_service_test.rb`)

paid 청구 PDF 생성(%PDF 헤더·바이트 >10KB — Prawn 내부 압축 스트림이라 한글 문자열 직접 검증 불가, "렌더 성공+바이트" 대체 검증·폰트 등록 실패 시 렌더 자체 실패) · 다중 입금 MAX paid_on · 미마감(draft/issued/partially_paid/voided) raise · 2행 품목 · 원천징수 옵션 · 마이그레이션 불요.

## 자기 스코프 검증 결과

- 신규 테스트: **6 runs, 23 assertions, 0 failures, 0 errors**
- `bin/rails zeitwerk:check`: 통과
- `bin/rubocop` (서비스·컨트롤러·테스트 3파일): **0 offenses** (ERB는 rubocop 파서 비지원 — Erubi 컴파일로 통과 확인)
- `bin/rails test test/models/invoice_test.rb`: **47 runs, 215 assertions 통과**(회귀 없음)
- 컨트롤러 HTTP·routes·nav·전체 테스트: 3-S 결선 영역 — 미수행(금지)
- 임시 파일 정리: /tmp 폰트 다운로드본 삭제 완료

## Phase 6 — 리뷰 수정 (2026-11-11, B-2 — 통합 수정 Developer-lite)

**B-2 (BLOCKER) — PAY-6 PDF 텍스트 전무: Pretendard OTF(CFF-outline) × Prawn TrueType 서브셋 비호환**

- 폰트 교체: `vendor/fonts/Pretendard-{Regular,Bold}.otf` 삭제 → `pretendard@1.3.9` npm 패키지의 `dist/public/static/alternative/Pretendard-{Regular,Bold}.ttf`(TrueType/glyf outline, `file` 실측 "TrueType Font data")로 교체(각 ~2.6MB)
- 서비스 갱신: `app/services/invoices/receipt_pdf_service.rb` — font.register 경로 .otf→.ttf + 헤더 주석에 B-2 원인(OTF=CFF는 Prawn 서브셋과 비호환·TTF만 허용) 문서화. 서비스 로직 자체는 무변경(리뷰어 실증과 동일 코드)
- **검증 강화(재발 방지 — "%PDF+바이트" 대체 검증 금지 반영)**:
  1. **pdftotext(poppler) 전문 추출 실측**(dev runner — paid 청구 1건 생성 후 `/tmp/td1_receipt.pdf`):
     `수금 완료 증빙 / 청구번호 BD-… / 거래처명 / 발행일 / 입금일 / 품목 내역 / 공급가액 300,000원 / 부가세 30,000원 / 원천징수(3.3%) -9,900원 / 실수령액 320,100원 / 총액 330,000원 / 생성일시: …` **전부 추출 성공**
  2. 테스트 2건 신설(receipt_pdf_service_test): ① 번들 폰트 **TrueType 매직바이트(0x00010000) 단정** + OTF("OTTO") 부재·디렉터리 내 ttf 2종 외 금지 ② PDF 내장 폰트가 `/Subtype /TrueType`이고 CFF(`CIDFontType0`) 혼입 부정 단정
- 부대 정리: /tmp 패키지·폰트 다운로드본 삭제

게이트: pdf 서비스 테스트 8건(기존 6+신규 2) 통과 · rubocop 수정 파일 0 offense · zeitwerk 통과. 뷰어 육안 확인(Preview·Chrome)은 Phase 7 Tester 권장 항목.
