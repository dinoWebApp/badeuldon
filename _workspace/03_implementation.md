# 03_implementation — F-LEGAL/REF 3-S 결선 통합 (2026-11-11, 절약 모드)

T-F1(LEGAL 내용증명+과금)·T-F2(REF 추심 소개) 병렬 fan-out의 공유 파일 결선·마이그레이션 확인·
인수 검증·스모크·컨트롤러 최초 HTTP 검증을 수행했다. fan-out 산출물: `_workspace/parallel/T-F1/03_implementation.md`·`_workspace/parallel/T-F2/03_implementation.md`.

## 1. 변경 파일 목록

| 파일 | 내용 |
|---|---|
| `config/routes.rb` | app namespace에 `resources :legal_documents, only: %i[index new create show]` + `member { get :download }`(LEGAL-1~4·Q5 — download는 paid 한정 자원 상태라 member GET 정당화)·`resources :referrals, only: :index`(REF-1~4·P5·Q13 — 소개 단일 진입) 주석 포함. 라우트 실측: `download_app_legal_document`·`app_legal_documents`(GET/POST)·`new_app_legal_document`·`app_legal_document`·`app_referrals` 전부 생성 확인 |
| `app/helpers/app/base_helper.rb` | 사이드바 메뉴 2건 추가 — "내용증명"(app_legal_documents_path·LEGAL-1~4)·"추심 안내"(app_referrals_path·REF-1~4). 기존 `app_nav_items` 문법 준용(active 판정 start_with?) |
| `app/views/app/invoices/_legal_banner.html.erb` | 하드코딩 2곳 → `new_app_legal_document_path(invoice_id: @invoice.id)`·`app_referrals_path` 헬퍼 교체 + 3-S 인계 주석 제거 |
| `app/views/app/invoices/_referral_banner.html.erb` | 하드코딩 1곳 → `app_referrals_path` 헬퍼 교체 + 인계 주석 제거 |
| `app/views/app/referrals/index.html.erb` | 하드코딩 2곳 → `app_invoices_path`·`app_invoice_path(invoice)` 교체 + 인계 주석 제거 |
| `app/views/app/legal_documents/{index,new,show}.html.erb` | **T-F1 원본 유실로 재작성**(사유 §5.1) — 하드코딩 헬퍼 교체를 포함해 최종본 반영(`app_legal_documents_path` form·`new_app_legal_document_path`·`app_legal_document_path(order)`·`download_app_legal_document_path(@order)`) |
| `app/controllers/app/legal_documents_controller.rb` | create/download 리다이렉트 하드코딩 → `app_legal_document_path(@order)` 교체 + 인계 주석 제거. **결함 수정 1건 — download 미결제 가드 신설**(§4.②) |
| `app/controllers/app/orders_controller.rb` | `post_payment_redirect_path`의 legal_doc 착지점 문자열 → `app_legal_document_path(order)` 교체 + 인계 주석 제거(승인 로직 무변경) |
| `test/controllers/app/referrals_controller_test.rb` | **결선 활성화로 드러난 결함 수정 1건**(§4.③) — `assigns` 3건을 응답 본문 기반 검증으로 교체 + 헬퍼에 유니크 issue_number 추가 |
| `test/integration/tmp_3s_finalization_test.rb` | 임시 최초 HTTP 검증 7건 — **실행 후 삭제 완료**(§3) |

마이그레이션: 신규 없음 — T-F1 `20261111032743_add_item_type_to_orders.rb` 재확인(dev `orders.item_type` INTEGER default 0 null:false + `[user_id, item_type]` 인덱스 · schema.rb 반영 · `Order::LEGAL_DOC_PRICE`=5000·`Order.legal_docs` 스코프 runner 실측). 3-S 신규 마이그레이션 0건(단일 마이그레이션 원칙 — 01_plan 계약 준수).

## 2. 라우트 최종 (config/routes.rb app 블록)

```ruby
resources :legal_documents, only: %i[ index new create show ] do
  member { get :download }   # LEGAL-2 — 결제 완료(paid) 주문 한정 PDF 자원 상태
end
resources :referrals, only: :index   # REF-1~4 — 소개 화면 단일 진입(P5)
```

## 3. 스모크 + 컨트롤러 최초 HTTP 검증

### 비인증 curl(dev 3002·pid 분리)
| 경로 | 결과 |
|---|---|
| `/up` | **200** |
| `/app/legal_documents` | **302 → /session/new**(U1 가드) |
| `/app/legal_documents/new` | 302(가드) |
| `/app/legal_documents/999999` | 302(가드) |
| `/app/referrals` | **302 → /session/new**(U1 가드) |

※ 지시서의 "303"은 폼 성공 규약(POST) 기준이며 GET 인증 가드는 프로젝트 기존 세션 가드의 302(리다이렉트) 그대로 — 기존 /app 표면과 동일 동작.

### U1 Integration(임시 파일 — 7테스트 41 assertion 전부 통과 · 실행 후 파일 삭제 · 레코드는 트랜잭션 롤백 무잔존)
1. legal_documents **index 200**(사이드바 "내용증명" 메뉴 active 렌더 실측)
2. legal_documents **new 200** — LEGAL-3 고지문("법률 자문")·LEGAL-4("우체국") 렌더
3. legal_documents **create 303** — `Order.legal_docs` +1건·`amount=5000`·`item_type="legal_doc"`·`metadata.invoice_id` 실측·`app_legal_document_path(order)` 착지
4. legal_documents **download 미결제 → 303 redirect + flash**(결함 수정 후 — §4.②)
5. referrals **index 200** — P5 고지문 + delta_overdue(D+30 41일 경과) 목록 노출
6. invoices show **D+30 대상 건**(delta_overdue) — legal 배너("내용증명·추심 안내")·referral 배너("장기 미수금 안내") 동시 노출 + 배너 내 결선 헬퍼 URL 실측
7. invoices show **비대상 건**(delta_issued — travel_to 2026-10-12 기준 11일 경과) — 양 배너 미노출

### 결선 확인 테스트(Phase 7 금지 예외 — 특정 파일 결선 확인, T-C3 선례)
`referrals_controller_test`(6)·`order_item_type_test`(6)·`content_proof_pdf_service_test`(7)·`invoices_controller_test`(배너 회귀)·`orders_controller_test` — **64 runs, 0 failures**.

## 4. T-F1 화이트리스트 외 분기 4곳 인수 검증 + 결함 수정 내역

| # | 분기 | 판정 |
|---|---|---|
| ① | `FulfillPassService` `issue_pass! unless @order.legal_doc?` | **정상 유지** — runner 실측: legal_doc 주문 paid 전환 only·PaymentPass 미발급 / 기존 pass 주문은 패스 발급·paid 유지(무영향). `legal_target?` D+40 true·미만료 false 실측 |
| ② | `Webhooks::PortOneController#settle_paid` `order.collection_pass? \|\| order.legal_doc?` | **정상 유지** — legal_doc가 구독 갱신(UpgradeService) else 분기로 유입되지 않는 판정식 확인. 웹훅 실호출은 테스트 stub으로 커버(외부 호출 금지 원칙) |
| ③ | `App::OrdersController#callback` `post_payment_redirect_path` | **수정(최소)** — 착지점 문자열 `"/app/legal_documents/#{order.id}"` → `app_legal_document_path(order)` 헬퍼 교체(라우트 결선 헬퍼 정렬 — 동작 동일·URL 하드코딩 금지 컨벤션 정합) |
| ④ | `portone_payment_controller.js` `orderName` 기본값 "수금 패스 10건권" | **정상 유지** — 기본값 유지 확인(기존 _checkout 무전달 무영향). legal show 뷰(재작성본)는 `data-portone-payment-order-name-value="내용증명 양식"`으로 오버라이드 |

### 발견·수정한 결함(총 3건)
1. **[CRITICAL] `download` 미결제 가드 부재** — T-F1 문서("결제 완료(paid) 주문 한정 다운로드")와 달리 컨트롤러가 상태를 검증하지 않아 **pending 주문에서 GET /download 시 PDF가 생성·제공됨**(통합 테스트로 최초 재현 — 200 OK). 무료 제공 방지(LEGAL-2·01_plan 리스크 5) 위반. 수정: download 선두에 `unless @order.paid? → 303 redirect + "결제가 완료된 후 내려받을 수 있습니다."` 가드 신설. show 뷰(재작성)는 paid/pending/실패 3분기 상태 안내 유지.
2. **[CRITICAL — 자작 사고] legal_documents 뷰 3파일 유실** — perl 치환 명령 오류(s{PAT} 치환 블록 누락 + 빈 파일명 인자)로 index/new/show가 0바이트화(untracked라 git 복구 불가). T-F1 문서·컨트롤러 계약·`billings/_checkout` 선례·`ContentProofPdfService::LEGAL_NOTICE/DIRECT_SEND_NOTICE` 상수를 근거로 재작성하고 결선 헬퍼를 반영했다. 재작성본은 통합 테스트 7건 + 기존 테스트 64건으로 동작 실측. **수정 대상 파일이 T-F1 소유였으므로 reviewer가 원본과의 문구·마크업 차이를 집중 검토할 것**(특히 new의 select 문구·show의 3분기 상태 카드).
3. **[CRITICAL] T-F2 테스트 `assigns` 3건** — routes 결선으로 skip이 풀리며 Rails 8에서 제거된 `assigns` 사용이 에러화. 응답 본문(유니크 issue_number assert_match/no_match) 기반 검증으로 교체 — 검증 의미(경계·제외·격리) 동일 유지.

## 5. 게이트·기타

- `bin/rails zeitwerk:check` — 통과(all is good)
- `bin/rubocop` — **313 files, no offenses**(파일 지정 직접 호출 시의 Lint/Syntax는 ERB 직접 파싱 아티팩트로 기존 전 ERB 공통 — 프로젝트 설정 실행 기준 0)
- 문서(PRD/AGENTS) 미수정 — 지시 준수
- 임시 산출물 정리: `test/integration/tmp_3s_finalization_test.rb`·`/tmp/smoke_3s.rb` 삭제, dev 서버(pid /tmp/badeuldon_3002*) 종료, runner 레코드는 transaction Rollback 무잔존
- dev 서버 재부팅 후 비인증 스모크 재실측(§3) — 재작성 뷰 컴파일 포함

## 6. Rule ID 매핑(결선 기여분)

| Rule | 결선 내용 |
|---|---|
| LEGAL-1~4·Q5 | 라우트 결선(index/new/create/show + member download)·사이드바 "내용증명"·배너 링크 헬퍼화·download 미결제 가드(LEGAL-2 무료 제공 방지) |
| REF-1~4·P5 | 라우트 결선(index)·사이드바 "추심 안내"·배너/뷰 링크 헬퍼화 |
| PLAN-5 | 결제 위젯·callback·웹훅 분기 인수 검증 유지(legal_doc는 FulfillPassService가 item_type 분기) |
| SEC-5/멱등 | create pending 재사용·웹훅 apply_status 회복 — 인수 검증으로 무손상 확인 |

## 7. Phase 6 — 리뷰 통합 수정 (2026-11-11, `05_review.md` 전건)

Status: CHANGES_REQUESTED(B-1·C-1·C-2·W-1~W-5) → 전건 수정 완료.

### 수정 내역

| 이슈 | 수정 |
|---|---|
| B-1 | metadata 3개 쓰기 지점 전부 병합 전환: `FulfillPassService#merged_metadata`(기존 metadata 보존 + 결제 응답 병합)·`PurchaseService#keep_pending_for_webhook_recovery!`·`#record_failure!`(동일 병합). 회귀 테스트: 서비스 3건(모호 실패 보존·명확 실패 보존·확정 병합) + 컨트롤러 전 체인 1건(create→웹훅 Transaction.Paid 확정→metadata.invoice_id 보존→download %PDF 200·패스 미발급) |
| C-1 | 구현으로 정합화(오케스트레이터 결정): `ContentProofPdfService`에 `watermark:` 옵션 — Prawn create_stamp + rotate(38°) + transparent(0.22) "미리보기 — 미결제" 대각 워터마크를 전 페이지에 적용. download 액션: 미결제 주문 → 워터마크 미리보기 PDF 200, paid 주문 → 정식 PDF 200. show(대기) 뷰에 미리보기 다운로드 링크 추가 |
| C-2 | create에 `find_paid_legal_order` 가드 — 동일 청구 paid legal_doc 주문 존 시 재주문 차단, 기존 주문 show로 303 리다이렉트 + 안내 notice("이미 결제가 완료되었습니다…"). 가드 순서: paid 차단 → pending 재사용 → 신규 생성. 주석·테스트 실제 동작과 일치 |
| W-3 | 정책 확정(허용 유지): download의 서비스 호출에 `enforce_target: !@order.paid?` — paid 주문 재다운로드는 청구 마감 후에도 대상 재검증 없이 스냅샷 제공(PAY-6 회계 보관용 취지). 테스트 1건으로 명시 |
| W-4 | 기록 불요 판정 문서화: download 액션 주석 + 본 절 — P4는 "발신 기록" 대상이며 문서 다운로드는 발신 아님. 주문 레코드 자체가 발급 이력(P4) — 별도 감사 기록 불요 |
| W-5 | new의 미사용 `@invoice` 제거. `?payment_failed=1`는 show에서 소비 — flash.now alert "결제가 승인되지 않았습니다. 다시 시도해 주세요." |

### 변경 파일 (Phase 6)

- `app/services/orders/fulfill_pass_service.rb` — merged_metadata 병합
- `app/services/orders/purchase_service.rb` — keep_pending/record_failure 병합
- `app/services/legal_documents/content_proof_pdf_service.rb` — watermark·enforce_target 옵션 + stamp_watermark
- `app/controllers/app/legal_documents_controller.rb` — C-1/C-2/W-1/W-3/W-4/W-5 반영
- `app/views/app/legal_documents/index.html.erb` — W-2 total_amount 통일
- `app/views/app/legal_documents/show.html.erb` — 미리보기 링크
- `test/controllers/app/legal_documents_controller_test.rb` — 신설(8건, HTTP 재현)
- `test/services/orders/purchase_service_test.rb` — B-1 회귀 3건 추가

### Phase 6 게이트

- 컨트롤러·Integration 경유 재검증: legal_documents_controller_test 8건(paid 체인 %PDF 200·미결제 워터마크 PDF vs 정식 PDF 비교·C-2 재주문 차단·마감 후 재다운로드 허용·타인 404·비인증 302) 전부 통과
- 관련 스위트: purchase_service 14 · webhook portone 10 · purchase_service_concurrency · content_proof 7 · order_item_type 6 · referrals 6 · orders_controller = **49 runs 286 assertions 0 failures**
- `bin/rubocop`(수정 6 files) 0 offenses · `bin/rails zeitwerk:check` OK — 전체 테스트는 Phase 7 Tester 대상(실행하지 않음)
