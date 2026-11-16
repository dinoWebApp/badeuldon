# T-F1 03_implementation — LEGAL 내용증명 양식 PDF + 건당 5,000원 과금 (LEGAL-1/2/3/4·Q5)

날짜: 2026-11-11 · 절약 모드 · 작업 디렉터: /Users/gimgeonjun/products/badeuldon

## 1. 변경 파일 목록

### 신규 (소유 화이트리스트 내)
| 파일 | 내용 |
|---|---|
| `db/migrate/20261111032743_add_item_type_to_orders.rb` | orders.item_type integer(default 0, null: false) + 인덱스 [user_id, item_type] — **마이그레이션 실행 완료**(dev) |
| `app/services/legal_documents/content_proof_pdf_service.rb` | 내용증명 양식 PDF 생성(Prawn+Pretendard TTF — ReceiptPdfService Q17 패턴 준용). `legal_target?` 클래스 메서드가 D+30 초과·미수 판정의 단일 출처(REF 배너와 동일 조건: due_on+30 < 오늘) |
| `app/controllers/app/legal_documents_controller.rb` | U1 전용 — index/new/create/show/download. 소유권 격리(Current.user 스코프) |
| `app/views/app/legal_documents/index.html.erb` | 발급 가능 대상 + 발급 이력(주문 기준 P4) |
| `app/views/app/legal_documents/new.html.erb` | 대상 청구 select + **LEGAL-3 고지문** + LEGAL-4 직접 발송 안내 |
| `app/views/app/legal_documents/show.html.erb` | 결제 상태(대기=포트원 위젯 체크아웃 / 완료=다운로드 버튼 / 실패·취소=재주문 안내) |
| `app/views/app/invoices/_legal_banner.html.erb` | D+30 초과·미수 청구 상단 배너(내용증명 링크 + 추심 안내 링크 — T-F2 계약 경로 하드코딩+주석 인계) |
| `test/services/legal_documents/content_proof_pdf_service_test.rb` | PDF 생성·**pdftotext 한글 전문 추출 실측**(청구 내역·발송 이력·약속·부분입금·LEGAL-3 고지문·LEGAL-4 안내 전부 포함)·D+30 경계(travel_to: +30일 거부/+31일 허용)·unsettled 외 거부·발송 이력 상한 10건 |
| `test/models/order_item_type_test.rb` | item_type enum·기본값 pass 무영향·legal_doc 5,000원 생성·legal_docs 스코프·FulfillPassService legal_doc/pass 분기·멱등 |

### 수정 (소유 화이트리스트 내 — 최소)
| 파일 | 내용 |
|---|---|
| `app/models/order.rb` | `LEGAL_DOC_PRICE = 5_000`·enum item_type {pass:0, legal_doc:1}(default pass)·scope legal_docs |
| `app/views/app/invoices/show.html.erb` | `_legal_banner` 렌더 2줄(T-F2가 넣은 referral_banner 렌더 아래) |
| `app/controllers/app/invoices_controller.rb` | `before_action :set_legal_banner, only: :show` + private set_legal_banner(@legal_banner = legal_target? — 3줄) |

### 수정 (화이트리스트 외 — 결제 체인 재사용에 필연적 최소 분기 · 3-S/reviewer 인계)
| 파일 | 내용 | 사유 |
|---|---|---|
| `app/services/orders/fulfill_pass_service.rb` | `issue_pass! unless @order.legal_doc?` 1줄 가드 | 콜백(PurchaseService)·웹훅 공용 확정점이 legal_doc 주문에 패스를 발급하는 버그 예방 — LEGAL-2는 발급물 없이 paid 전환만 |
| `app/controllers/webhooks/portone_controller.rb` | settle_paid 분기 `order.collection_pass? \|\| order.legal_doc?`(주석 — item_type 우선 판정 사유) | 웹훅이 legal_doc 주문을 product enum 폴백 분기(구독 갱신 UpgradeService)로 보내는 것 차단 |
| `app/controllers/app/orders_controller.rb` | callback의 성공 notice·실패 alert 리다이렉트를 `post_payment_redirect_path`(신설 private)로 분기 — legal_doc 주문은 내용증명 상세(`/app/legal_documents/:id`)로 복귀, 기존 주문은 기존대로 app_billing | 라우트 계약에 legal 전용 callback 액션이 없어 기존 콜백을 재사용 — 성공 문구("수금 패스 N건 발급")·착지점 오류 수정. 리다이렉트만 분기, 승인 로직 무변경 |
| `app/javascript/controllers/portone_payment_controller.js` | `orderName` data value 신설(미전달 시 기본값 "수금 패스 10건권" — 기존 _checkout 무영향) | 결제창 상품명이 legal 주문에도 "수금 패스 10건권"으로 표시되는 오류 방지(5,000원 vs 4,000원 혼동·CS 리스크) |

## 2. 결제 체인 다이어그램 (수금 패스 플로우 대비)

```
[수금 패스(기존)]                              [내용증명(신규 — LEGAL-2)]
billings show "구매" 버튼                       invoices show 배너 /app/legal_documents/new
  → POST /app/orders (create)                    → POST /app/legal_documents (create)
    pending Order(product=collection_pass)         pending Order(product=collection_pass*,
    amount=4,000, item_type=pass(기본))                          item_type=legal_doc, amount=5,000,
    → redirect billings#show(checkout)                           metadata={invoice_id})
                                                   → redirect legal_documents#show
                                                   (같은 청구 pending 주문 재사용 — 연타 멱등)
                                                   (동일 청구 paid 주문 존재 시에도 pending 재사용
                                                    → 상세 화면이 paid로 표기 — 이중 결제 차단)
  위젯(portone-payment Stimulus)                 위젯(동일 Stimulus 재사용 — show 뷰에서 렌더)
    orderName="수금 패스 10건권"                   orderName="내용증명 양식"(data로 전달)
    callback_url=callback_app_orders_url           callback_url=callback_app_orders_url(동일)
         └──────────── 공통: GET /app/orders/callback ────────────┘
              App::OrdersController#callback
                → Orders::PurchaseService(승인 확정 — with_lock·멱등·웹훅 회복)
                    → Orders::FulfillPassService
                        pass 주문:  paid + 패스 발급 (기존 무영향 — 회귀 테스트 가드)
                        legal_doc:  paid 전환만(발급물 없음 — 신규 가드)
                → 리다이렉트: pass → /app/billing (기존)
                              legal_doc → /app/legal_documents/:id (신규 분기)
  웹훅(회복·경합 공용 경로): Webhooks::PortOneController#settle_paid
      collection_pass? || legal_doc? → FulfillPassService(item_type별 분기)
      (신규 가드 없으면 legal_doc가 else 분기 = 구독 갱신 UpgradeService 유입 — 버그 예방)
  다운로드: legal_documents#download — paid 주문 한정 ContentProofPdfService → send_data
      (미결제는 redirect+flash — 무료 제공 방지: LEGAL-2·01_plan 리스크 5)
```

*) legal_doc 주문도 product=collection_pass를 채운다 — product 컬럼 null: false 제약. 품목 판정은
전부 item_type 기준이며 승인 로직은 product을 읽지 않는다(Order 모델 주석에 명문화).

## 3. Rule ID 매핑

| Rule | 구현 |
|---|---|
| LEGAL-1 | `ContentProofPdfService` — D+30 초과 **미수(unsettled) 한정**(legal_target?·생성 가드), 청구 내역(품목·공급가액·부가세·총액·미수 잔액)·발송 이력(message_logs 최근 10건·템플릿 라벨)·약속 이력(Q14 판정)·부분입금 내역(payments)·Prawn+Pretendard TTF(Q17) |
| LEGAL-2 | 건당 5,000원(`Order::LEGAL_DOC_PRICE`·서버 원값 — 클라이언트 신뢰 금지)·orders.item_type 마이그레이션·**결제 완료(paid) 후에만 download 허용**·미결제는 상태 안내만(워터마크 미리보기 미제공 — 무료 제공 방지) |
| LEGAL-3 | 고지문("본 서비스는 법률 자문을 제공하지 않습니다…변호사 검토 권장") — new 화면·show 상시·PDF 본문 3중 포함(상수 `LEGAL_NOTICE` 단일 문언) |
| LEGAL-4 | 발송 대행 없음 고지 — index·new·show·배너·PDF 하단("우체국 등기 등 실제 발송은 직접 수행") |
| PLAN-5 | 포트원 단건 결제 플로우 재사용(위젯→callback→PurchaseService·웹훅 회복 — 승인·멱등·회복 로직 무변경) |
| INV-4 | unsettled 스코프 재사용(초안·수금완료·무효 제외 모집단) |
| REM-6 | 발송 이력 인용(message_logs — debtor·sent 한정·최근순 10건 상한) |
| Q14 | 약속 판정 2상태 표기 — 판정 중(도과 전)·미이행(도과 후 미수). paid 확정 분기는 본 양식 대상(미수)에서 발생하지 않아 제외(주석 — PromiseComplianceQuery 정의 준용) |
| TIME-1 | Date.current·Time.current(KST 고정) |

## 4. 자기 스코프 검증

- **게이트**: 자기 파일 RuboCop 0 위반 · zeitwerk:check 통과 · **전체 테스트 1,088건 통과(0 실패)** · 신규 13건(+81 assertion) · orders/orders_controller/webhook 회귀 28건 통과 — item_type 추가 무영향 실측
- **pdftotext 한글 전문 추출 실측 완료**(poppler) — 고지문·직접 발송 안내·청구·발송·약속·입금 전부 검출
- **ERB 컴파일 검증**(index/new/show/_legal_banner)·Stimulus JS `node --check` 통과
- **runner 스모크**(트랜잭션 롤백): legal_target? 가드·JSON_EXTRACT metadata 역참조·Invoice lookup — SMOKE OK
- **라우트 미결선 인계(3-S)**: `config/routes.rb` 미수정 — 컨트롤러는 라우트 계약 경로/헬퍼명 기준으로 작성했고 뷰·컨트롤러 리다이렉트는 `/app/legal_documents...` 문자열+주석. 3-S에서 `resources :legal_documents, only: %i[index new create show]` + `member { get :download }` 추가 시 `new_app_legal_document_path`·`app_legal_document_path`·`download_app_legal_document_path` 헬퍼로 치환 요망(주석으로 표기 완료). 사이드바 메뉴(선택)도 3-S 영역
- **경계**: D+30 "초과" = due_on+30 < 오늘(travel_to 테스트 — 01_plan 리스크 3)
- **임시 레코드**: runner 스모크는 transaction+Rollback으로 무잔존, 마이그레이션은 스키마만 변경

## 5. 설계 결정·모호 해석 (reviewer 확인 권고)

1. **주문-청구 결합을 orders.metadata(invoice_id)로** — 마이그레이션 화이트리스트가 item_type 1건으로 한정돼 invoice_id 컬럼·별도 테이블을 만들 수 없었다. JSON_EXTRACT 조회로 멱등(연타 주문 누적 방지)·이중 결제 가드를 구현. reviewer가 강타입 조인을 원하면 3-S에서 invoice_id 컬럼 추가 마이그레이션 제안 가능
2. **legal_doc 주문의 product=collection_pass 채움** — product null: false 제약. 품목 판정 전부 item_type 기준(Order 주석 명문화). webhook 분기 순서(legal_doc 우선)도 주석 고정
3. **paid 이행 확정(Q14 "이행") 표기 제외** — 양식이 unsettled 한정이라 paid 시점 판정은 도달 불가(죽은 분기 제거 — 주석에 근거 남김). Reviewer가 미수 중 발급 후 마감→재발급 상태 표기를 원하면 별도 논의
4. **화이트리스트 외 4파일 최소 분기**(§1 표) — 결제 체인 재사용 계약의 필연 결과. 각 1~6줄 이내·기존 pass·plus 주문 무영향(회귀 테스트로 실측)
5. **미결제 워터마크 미리보기 미구현** — 01_plan·PRD v0.38 LEGAL-2는 "미결제는 워터마크 미리보기만"을 언급하나 무료 제공 경계(리스크 5 — "결제 미완료 시 다운로드 차단이 정답")와 충돌 소지가 있어 **상태 안내만 제공**하는 보수 해석. 워터마크 미리보기가 요구되면 후속 요청 필요
