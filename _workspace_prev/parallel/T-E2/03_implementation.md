# T-E2 구현 산출 — 무료 도구 3종(LP-11·P3 가입 없이)

2026-11-11 · 절약 모드 병렬 배치 · 소유권 화이트리스트 내에서만 변경

## 변경 파일 목록

| 파일 | 내용 |
|---|---|
| `app/controllers/tools_controller.rb` | 신규 — index·reminder_generator·tax_calculator·invoice_template·invoice_template_pdf(send_data) |
| `app/services/tools/reminder_text_library.rb` | 신규 — REM-2 4톤 × 3종 = 12종 문구 상수 + 변수 치환(순수 함수) |
| `app/services/tools/tax_calculator_service.rb` | 신규 — 3.3%·부가세 10%·실수령액 계산(원 단위 floor — INV-2 산식 동일) |
| `app/services/tools/template_pdf_service.rb` | 신규 — 청구서 양식 PDF(Prawn + Pretendard TTF — ReceiptPdfService 패턴 준용) |
| `app/helpers/tools_helper.rb` | 신규 — tools_won·tools_copy_button·tools_meta(도구별 title/description)·tools_cta |
| `app/views/layouts/tools.html.erb` | 신규 — 공개·크림 톤 크롬(blog 레이아웃 준용), _head 재사용 → noindex 미출력(색인 허용) |
| `app/views/tools/index.html.erb` | 도구 허브 3카드 |
| `app/views/tools/reminder_generator.html.erb` | 폼+결과 동일 페이지(GET params)·문구 카드 3종·복사 버튼 |
| `app/views/tools/tax_calculator.html.erb` | 폼+결과(GET params 공유 URL)·인라인 JS 즉시 계산 + 서버 계산 병행 |
| `app/views/tools/invoice_template.html.erb` | 입력 폼(선택) → `.pdf` GET 제출 |
| `app/views/tools/_copy_script.html.erb` | 복사 최소 JS(CSP nonce 적용) |
| `test/services/tools/reminder_text_library_test.rb` | 12종 존재·금지 표현 부재(LP-12·P5)·치환·기본 톤 |
| `test/services/tools/tax_calculator_service_test.rb` | 계산 정확성·콤마·부가세 포함 환산·절사·InvalidAmount |
| `test/services/tools/template_pdf_service_test.rb` | %PDF 헤더·입력 반영(pdftotext 존재 시)·샘플 대체·총액·발행일 |

## 라우트 계약(3-S 결선 대상 — routes.rb는 이번 스코프에서 미수정)

```
GET /tools                      → tools#index
GET /tools/reminder-generator   → tools#reminder_generator
GET /tools/tax-calculator       → tools#tax_calculator
GET /tools/invoice-template     → tools#invoice_template
GET /tools/invoice-template.pdf → tools#invoice_template_pdf
```

- 뷰·레이아웃은 **`/tools...` 리터럴 경로 + 주석**(3-S 결선 시 `tools_path` 계열 헬퍼로 교체) — T-E1 선례 준용.
- 컨트롤러는 `Tools::` 서비스 3종만 호출 — 라우트 결선 즉시 동작 가능 상태.

## Rule ID 매핑

- **LP-11**: 무료 도구 3종(/tools) + 각 도구 주 CTA(가입 유도, LP-12 준수 문구)
- **REM-2**: 독촉 문구 4단계 톤(부드럽게/정중하게/사실적으로/명확하게)×3종
- **INV-2**: 원천징수 3.3% 산식(원 단위 floor)
- **P3**: 세션·쿠키·DB 저장 없음 — 입력은 GET params만, PDF도 send_data 즉시 반환
- **P5·LP-12**: 문구 상수에 법적 조치·협박·내용증명 언급 없음(테스트로 검증)
- **SURF-3**: NOINDEX_PATH_PREFIXES 미포함 → 색인 허용(_head 공통 파셜 자동)
- **DESIGN-2/3/6**: 크림 배경·딥 그린 액센트·천단위 콤마 표기·min-h-11 터치 타깃
- **TIME-1**: PDF 발행일 `Time.current` KST

## 문구 12종 전문(검토용)

### soft(부드럽게)
1. 안녕하세요, {client} 담당자님. {due_date}에 안내드렸던 {amount}가 아직 입금 확인 전이라 여쭤봅니다. 혹시 일정에 차질이 있으시면 편하게 알려주세요.
2. {client} 담당자님, 바쁘신 와중에 죄송합니다. 청구한 {amount} 건이 확인 대기 중이라 가볍게 접어봅니다. 처리 일정만 한 줄 공유 주시면 감사하겠습니다.
3. 안녕하세요. {amount} 청구 건을 잊고 계실까 봐 다시 안내드립니다. 여유 되시는 때 입금 부탁드리며, 문의 사항이 있으면 언제든 말씀해 주세요.

### polite(정중하게 — 기본)
1. {client} 담당자님, {due_date} 만기의 {amount} 청구 건이 아직 입금 전입니다. 사정이 있으시다면 입금 예정일을 알려주시면 그에 맞춰 진행하겠습니다.
2. 안녕하세요, {client} 담당자님. 청구드린 {amount}가 만기({due_date})를 지나 확인 대기 중입니다. 입금 예정일을 회신 주시면 대단히 감사하겠습니다.
3. {client} 담당자님, {amount} 청구 건의 입금이 확인되지 않아 안내드립니다. 예정일 공유 부탁드리며, 영수증이 필요하시면 말씀해 주세요.

### factual(사실적으로)
1. {client} 담당자님, {due_date} 만기의 {amount} 청구 건이 만기일을 경과했습니다. 현재 상태를 확인 부탁드리며, 입금 예정일을 회신 주시면 일정을 갱신하겠습니다.
2. 안내드립니다 — {client} 담당자님. {amount} 청구 건({due_date} 만기)이 미입금 상태입니다. 처리 현황과 입금 예정일 확인 요청드립니다.
3. {client} 담당자님, {amount} 청구 건이 {due_date} 이후 미입금으로 남아 있습니다. 입금 예정일을 알려주시면 회계 정리에 반영하겠습니다.

### firm(명확하게)
1. {client} 담당자님, {due_date} 만기 {amount} 청구 건이 상당 기간 미입금 중입니다. 금주 내 입금 또는 입금 예정일 회신 부탁드립니다.
2. {client} 담당자님, {amount} 청구 건({due_date} 만기)이 계속 미입금 상태입니다. 이번 주까지 입금 여부를 명확히 알려주시기 바랍니다.
3. {client} 담당자님, {amount} 청구 건의 입금이 장기 지연되고 있습니다. 구체적인 입금 예정일을 회신 주시지 않으면 후속 조치 일정을 다시 안내드리게 됩니다.

변수: {client}=거래처명(미입력 시 빈 값)·{amount}=천단위 콤마+원(예: 1,000,000원)·{due_date}="11월 30일" 형식. 콤마 포함 금액·잘못된 날짜 입력도 안전 처리.

## 명시적 해석(레포트용)

1. 지시문의 `Invoices::TemplatePdfService` 네이밍 vs 화이트리스트 `app/services/tools/` 충돌 → **화이트리스트 우선으로 `Tools::TemplatePdfService`로 구현**(invoices 도메인 파일 수정 금지가 더 상위 제약). 3-S 결선 후 필요 시 리네임 가능(클래스명만 변경).
2. PDF 양식은 "받을돈 워터마크 없이 깔끔하게" 지시에 따라 하단 브랜딩 푸터 없음(입금 안내 자리만).

## 자기 스코프 검증 결과

- 변경 파일 = 화이트리스트 전부(그 외 파일 미수정 확인: git status로 models/routes/layouts 기존 파일 무변경)
- `bin/rubocop` (소유 8파일): **0 offenses**
- `bin/rails zeitwerk:check`: **good**
- `bin/rails test test/services/tools/`: **19 runs, 163 assertions, 0 failures** (전체 스위트 실행 금지 준수)
- 러너 검증: 서비스 3종 동작 + PDF `%PDF` 헤더(53,275 bytes) + ERB 5파일 `ActionView::Template#compile!` 통과(라우트 미결선이라 HTTP 테스트 불가 — 3-S 결선 시 컨트롤러 200·PDF 헤더 스모크 필요)
- 임시 레코드: 없음(테스트도 레코드 미생성)
