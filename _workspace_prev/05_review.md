# 05_review — TAX-1/2 전자세금계산서 발행 (2026-11-16, Reviewer)

## Status: CHANGES_REQUESTED

- BLOCKER 0 · CRITICAL 4 · WARNING 7
- 보안·무결성·소유권 격리·웹훅 위조 방지·metadata 병합(B-1)은 모두 통과(아래 "정상 동작 확인 근거").
- CRITICAL 4건은 모두 결제-발행 플로우의 사용자 체감 결함·법정 문서 기재 정합성·계획서 대비 상태 머신 미완결이다.
  데이터 파탄·보안 취약(BLOCKER)은 없다 — CRITICAL 4건은 국소 수정 가능하다.

## 이슈 목록

| # | Severity | Rule ID | File:Line | 설명 | 수정 제안 |
|---|----------|---------|-----------|------|-----------|
| C-1 | CRITICAL | Q21·PLAN-5(선례 정합) | app/controllers/app/orders_controller.rb:26-27, 38-45 | tax_invoice 주문이 콜백(GET /app/orders/callback)을 타면 결제 성공 시 notice가 **"수금 패스(10건)가 발급되었습니다"**로 표시되고 app_billing_path(요금제 화면)로 리다이렉트된다. `post_payment_redirect_path`·notice 삼항식은 legal_doc 분기만 존재해 item_type tax_invoice가 패스 분기로 떨어진다. 발행 위젯의 callback URL이 callback_app_orders_url로 공유됨(app/views/app/tax_invoices/show.html.erb:75)이므로 **모든 세금계산서 결제자가 잘못된 안내·착지를 경험**한다. | `post_payment_redirect_path`에 tax_invoice 분기 추가(app_tax_invoice_path(order)) + notice 문구 분기("결제가 완료되었습니다. 발행 상태를 확인해 주세요." 등). legal_doc C-1·W-5 선례와 동일 패턴. |
| C-2 | CRITICAL | TAX-1(1건 1발행·과금 정합) | app/controllers/app/tax_invoices_controller.rb:27-39 | **paid 주문 가드(find_paid_*_order, C-2 선례) 누락 — 이중 결제 가능.** 결제 완료 후 SOAP 실패·콜백 도중 예외로 tax_invoices 레코드가 미생성되면(03 문서 알려진 한계 #5 — FulfillTaxInvoiceService가 ApiError·GuardFailed를 로그로만 흡수해 실제로 도달 가능한 상태) 청구 상세 패널은 다시 발행 버튼을 노출하고 create 가드는 `TaxInvoice.exists?`만 보므로 새 주문 생성·재결제가 그대로 허용된다 → 같은 청구에 300원 중복 과금. LEGAL 플로우는 정확히 이 시나리오를 `find_paid_legal_order`("이미 결제가 완료되었습니다" 유도)로 막았다(F-LEGAL 리뷰 C2 교정). | create에 `find_paid_tax_invoice_order` 가드 추가(Current.user.orders.paid.tax_invoices + metadata invoice_id) — paid 주문 존재 시 기존 주문 show로 안내하고 신규 주문 생성 금지. 패널 분기(@tax_invoice_guard)에 "결제 완료·발행 기록 미생성" 상태도 산출해 안내 권장. |
| C-3 | CRITICAL | TAX-1(정발행 기재 정합) | app/services/tax_invoices/issue_service.rb:91-99 | **부가세 포함(tax_mode: included) 청구의 품목 행 금액 오기재.** 행 Amount = quantity×unit_price(세포함 총액), Tax = 그 10%로 전송되는데, 포함 모드에서 invoice.subtotal = rows_sum×10/11, tax_amount = rows_sum−subtotal이다(app/models/invoice.rb:299-303). 즉 Σ품목.Amount ≠ AmountTotal, Σ품목.Tax ≠ TaxTotal이 ~9% 어긋난다. 바로빌은 항목 합계를 국세청 전송 기준으로 사용하므로 법정 문서 기재 오류 또는 검증 거부로 이어진다(별도 모드 기본이라 분기 노출 빈도도 높다). Tax 산식의 Float `* 0.1`도 정수 산식으로의 전환이 바람직하다. | tax_mode 분기: 포함 모드는 품목별 공급가액 = qty×price×10/11(사사오입)로 계산하고 마지막 행에 잔액 조정을 두어 Σ=invoice.subtotal·tax_amount와 정확히 일치시킨다(부동소수 대신 정수 연산). DASH-5 C-1(입금 행 가중 부호)·CLIENT-3/4(Q14 부분입금 방지)의 "모집단 일치" 교정 선례. |
| C-4 | CRITICAL | TAX-2(상태 머신)·01_plan §4 | app/jobs/tax_invoices/poll_state_job.rb:8, 35-36 | **최대 재시도 후 failed 전이 누락 — 영구 "발행 처리 중".** 01_plan §4는 "완료(NTSSendKey 캡처) **또는 최대 재시도 후 failed**"를 명시했으나 구현은 retry_on(attempts: 10) 소진 시 예외를 재발생시켜 잡만 실패로 끝나고 tax_invoices.status는 pending에 고정된다. 국세청 승인이 길어지거나(주말·지연) 바로빌 상태 조회가 반복 실패하면 U1에게는 무기한 "발행 처리 중"으로 보인다(재발행은 canceled/issued가 아니므로 가드에도 걸리지 않는다). | retry_on에 블록을 주어 executions >= attempts 시점에 `tax_invoice.update!(status: :failed)` 확정 후 재발생 종료하거나, ApiError 코드 "PENDING"과 실오류를 구분해 폴링 상용 건의 소진 시 failed 확정. failed 후 UI 안내(03 문서 한계 #5의 CS 재발행 경로와 접속). |
| W-1 | WARNING | 규약(외부 API·트랜잭션 경계) | app/services/tax_invoices/issue_service.rb:26-37 | RegistAndIssueTaxInvoice SOAP 호출(타임아웃 15s×2)이 `ActiveRecord::Base.transaction` 블록 내부에서 수행된다. 쓰기는 create! 단 하나라 트랜잭션 감싸기가 불요하고, 외부 API는 FulfillPassService가 정립한 "트랜잭션 밖 수행"(fulfill_pass_service.rb:29-30) 패턴과 정반대다. 콜백 요청 스레드가 DB 트랜잭션·커넥션을 장시간 점유한다. | create!(with_lock 포함)만 트랜잭션으로 감싸고 SOAP 호출은 트랜잭션 밖으로 이동. 순서: (검증·기록 commit) → SOAP 성공 → PollStateJob 인계(현행 유지). |
| W-2 | WARNING | 규약(컨트롤러 10줄) | app/controllers/app/tax_invoices_controller.rb:20-42 | create 액션 본문이 약 18줄(가드 3종·주문 생성·리다이렉트)으로 "컨트롤러 액션 본문 10줄 이내"를 초과한다. LegalDocumentsController#create(~28줄) 선례가 있으나 신규 코드는 규약 방향으로 갈 필요가 있다. | 가드(미리보기 대상 판정+문구 산출)를 서비스/헬퍼 단일 판정점으로 이관해 create를 축약. cancel(52-65)도 CancelService 호출부는 유지하되 분기 축소. |
| W-3 | WARNING | 규약 §4.2(Service→params 금지)·입력 하드닝 | app/controllers/app/tax_invoice_settings_controller.rb:10-14, 59-61 | `params.expect` 결과(ActionController::Parameters)를 RegisterCorpService에 그대로 주입한다 — 전수 확인 결과 타 컨트롤러는 서비스에 params를 주입한 선례가 없다(첫 사례). 또한 ① corp_num 자릿수를 로컬 검증 없이 RegistCorp 외부 호출부터 시도하고(users.rb:58의 10자리 검증은 save! 시점 — 외부 수용 시 RecordInvalid 500 여지) ② 조작된 POST의 tax_type 임의값은 enum 할당 시 ArgumentError → 500이 된다. | 컨트롤러 경계에서 `tax_invoice_setting_params.to_hash`로 변환해 전달. RegisterCorpService.validate_locally에 corp_num `/\A\d{10}\z`·tax_type enum 값 포함 검증을 추가해 외부 호출 전에 차단(422). |
| W-4 | WARNING | SEC-2(최소 데이터)·품질 | app/services/tax_invoices/register_corp_service.rb:55 | user.phone 미설정 시 가짜 연락처 "02-0000-0000"을 바로빌 회원사 가입(RegistCorp)에 전송한다. 03 문서 한계 #4로 인지돼 있으나 가짜 데이터의 외부 전송은 피할 수 있으면 피하는 것이 낫다. | 설정 폼 1단계에 연락처 선택 입력을 추가하거나, 미설정 시 안내로 저장을 유도(RegistCorp TEL 필수라면 placeholder 실제 번호 수집). |
| W-5 | WARNING | UX 정합 | app/services/tax_invoices/cancel_service.rb:21-22 | 취소 실패 시 SOAP 전송 실패(일시 네트워크 오류, code "SOAP")까지 "국세청 전송이 완료된 계산서는 수정세금계산서로 정정해야 합니다"로 단정한다. 재시도하면 성공할 수 있는 상태를 종결 문구로 안내한다. | e.code가 "SOAP"(전송 계열)이면 "일시적 오류 — 잠시 후 다시 시도해 주세요"로 분기, 바로빌 음수 코드(NotCancelable 규격)만 정정 안내 문구 사용. |
| W-6 | WARNING | TAX-2(조회 경로) | app/views/app/invoices/_tax_invoice_panel.html.erb:21-22 | 패널의 "발행 내역 보기" 링크가 app_tax_invoice_setting_path(발행 설정 온보딩 화면)를 가리킨다. TAX-2 발행 상태·취소·승인번호의 실제 조회 화면은 발행 주문 상세(app_tax_invoice_path(@tax_invoice.order_id))다. | link_to 대상을 app_tax_invoice_path(@tax_invoice.order_id)로 변경(order optional이므로 present 가드). |
| W-7 | WARNING | [INFERENCE] 기록(03 문서 #1·#2·#7) | app/services/baro_bill/client_service.rb:74-84, app/services/tax_invoices/issue_service.rb:96 | 문서 미기재 3종이 관행 기반 [INFERENCE]로 구현돼 있다: ① 공통 API asmx 파일명(BAROBILL.asmx) ② GetCorpStateEx 상태 코드(1 계속/2 휴업/3 폐업 — 폐업만 차단) ③ 품목 세액 round drift(별도 모드에서 Σ품목.Tax vs TaxTotal 수원 단위 어긋남 가능). 런 리스크 기록과 일치하나 TESTBED 실측 전까지 운영 판단이 이 값들에 의존한다. | TESTBED 실측 시 3종 확인 후 갱신(런 리스크 #2 계획 유지). 별도 모드 drift는 C-3 수정 시 마지막 행 잔액 조정으로 함께 해소 가능. |

## Rule ID 준수 매핑

| 항목 | 판정 | 근거 |
|---|---|---|
| TAX-1 ① paid 한정·1건 1발행 | **준수** | tax_invoices.invoice_id unique 인덱스(db/migrate/20261115224720) + IssueService 가드(#call·verify_guards!) + 컨트롤러 이중 가드 — DB 담보와 앱 가드의 적층 |
| TAX-1 ② 건당 300원·결제 완료 후 발행 | **준수** | TaxInvoice::ISSUE_FEE=300 단일 상수·서버 주문 생성(클라 금액 미신뢰)·IssueService `@order&.paid?` 가드·결제는 PurchaseService/웹훅 확정점에서만 paid |
| TAX-1 ③ 공동인증서 필수 | **준수** | User#tax_invoice_ready? 단일 판정점(corp 정보 5종+barobill_id+cert 마킹) — 컨트롤러 가드·패널 분기(settings_missing·버튼 비노출) 공유. CheckCERTIsValid 실측 검증 후 마킹(오표시 방지 — 문서 확인됨) |
| TAX-1 ④ 취소 과금 전제·오발행 방지 3종 | **준수** | 미리보기(new)·중복 가드·발행 전 GetCorpStateEx(폐업 차단). 취소 버튼 confirm 문구에 과금 고지(tax_invoices/show.html.erb:54) |
| TAX-1 ⑤ 정발행·영수·개인 비대상 | **준수** | IssueDirection=1·PurposeType=1·TaxInvoiceType=1(/tmp/barobill_ti.txt 1984-1987 일치)·거래처 corp_num blank 가드+비대상 안내(패널 client_missing) |
| TAX-1 ⑥~⑦ 고지 | **준수** | 설정·미리보기 화면에 세무 자문 아님 고지+바로빌((주)케이넷) 위탁·취소 과금 고지(P5·DASH-6 선례 문구) |
| TAX-2 승인번호 기록·조회 | **준수(C-4 단)** | nts_send_key·nts_send_state·write_date 기록 → 청구 상세 패널+발행 주문 show 조회. 폴링 멱등(종결 상태 no-op·인자 스칼라 id·retry_on 명시) |
| Q21 | **준수(C-1·C-2 단)** | 포트원 단건 플로우 재사용(주문→위젯→callback/webhook→재조회 검증)·ISSUE_FEE 상수·item_type enum 확장(pass 0·legal_doc 1 불변 — 기존 값 영향 없음) |
| SEC-5(멱등) | **준수** | FulfillPassService newly_paid 재판정 + FulfillTaxInvoiceService pending 재판정 + unique 인덱스 — 콜백·웹��� 경합에서도 발행 1회 |
| 보안(소유권·웹훅·noindex·이스케이프) | **준수** | Current.user.orders.tax_invoices.find / scoped_invoice(Current.user.invoices) 격리·웹훅 get_payment 재조회+pg_order_id 결합 확인(기존 패턴 유지)·/app prefix noindex(application_helper.rb:4)·raw/html_safe 0건 |
| P4(발행 요청·결과 전부 기록) | **준수(C-2 단)** | barobill_state 원값 보존·canceled 레코드 유지·metadata 병합(B-1 — 덮어쓰기 없음). SOAP 실패 시 레코드 미생성 경로는 C-2와 연동해 후속 보강 |
| P5·SEC-2·AUTH-1.3·PLAN-5·INV-4·TIME-1 | **준수** | 세무 자문 고지·거래처 정보 U1 입력(clients 폼 확장)·/app 로그인 가드+프로필 가드(BaseController 상속)·LEGAL 선례 인프라 재사용·paid? 단일 판정·write_date Date(KST 무관 일자) |
| 아키텍처(§4.2·§5) | **준수(W-1·W-3 단)** | Model→Service 없음·Service는 스칼라/AR 주입(#call·client 주입 stub 가능)·Job→Service만·zeitwerk 통과·Service 동사+목적어+Service 네이밍·params.expect 화이트리스트 |

## 정상 동작 확인 근거 (무결성·보안 통과 항목)

1. **1건 1발행의 DB 담보** — `t.references :invoice, null: false, foreign_key: true, index: { unique: true }`(마이그레이션) + `index_tax_invoices_on_mgt_num unique`. 앱 가드와의 경합에서도 최종 방어선이 동작한다.
2. **웹훅 위조 방지 기존 패턴 유지** — Webhooks::PortOneController는 get_payment 재조회 후 `payment[:id] == order.pg_order_id` 결합 확인으로 확정하며, settle 분기는 item_type 기준(tax_invoice 포함)이라 product=collection_pass 함정 값에 반응하지 않는다.
3. **metadata 병합(B-1 선례)** — FulfillTaxInvoiceService·FulfillPassService·PurchaseService 모두 `(metadata||{}).stringify_keys.merge(response)` — invoice_id 역참조 보존 확인.
4. **이중 settle 멱등** — 콜백(PurchaseService)·웹훅이 with_lock+pending 재판정으로 직렬화되고 tax_invoice 발행은 newly_paid에서만 1회 수행된다.
5. **계정 삭제 cascade 안전** — user.rb 연관 선언 순서(invoices 14행 < orders 19행 < tax_invoices 27행) + Invoice has_one :tax_invoice dependent: :destroy 조합으로 user.destroy! 시 tax_invoices가 orders 파괴 전 정리됨(B-1 교훈 적용 확인).
6. **ownership 격리** — cancel·show는 `Current.user.orders.tax_invoices.find(params[:id])`, new·create는 `Current.user.invoices.find_by` — 타 사용자 id 접근 차단. order_invoice의 Invoice 역참조는 서버 기록 metadata 한정이라 우회 불가.
7. **바로빌 사실관계 전수 일치** — 3014(발급완료)·5031(취소)·NTSSendState 4/5·ISSUE_CANCEL(국세청 전송 전만 가능)·CheckCERTIsValid 존재·GetBaroBillURL PWD 빈문자열+60초·-32000 기가입 흡수·TaxType 1/2/3(RegistAndIssueTaxInvoice 페이로드 규격)·TaxInvoiceTradeLineItem 필드명·MgtKey 인자명 — /tmp/barobill_*.txt 원문과 대조 확인.
8. **마이그레이션 품질** — null: false·default·인덱스 명시·금액 정수 컬럼·status 인덱스. schema.rb 반영 확인.
9. **뷰 품질** — ERB 이스케이프 기본·뷰 쿼리 없음(가드 분기는 컨트롤러 @tax_invoice_guard 산출)·DESIGN-2 딥 그린·min-h-11 터치 타깃·상태색(발행완료 녹색/처리중 주황)·P5 고지 2화면.
10. **nav 잠금 링크 카운트 선갱신** — dashboards_controller_test 11→12(+base_helper 메뉴 1건) 일치.

## Tester 중점 지시 (Phase 7 인계)

1. **콜백 착지(C-1 재현→회귀)**: tax_invoice 주문 결제 성공 → GET /app/orders/callback 도착 시 notice·리다이렉트가 발행 주문 show로 가는지. legal_doc·pass 주문은 기존 착지 유지(회귀 방지).
2. **이중 결제 차단(C-2)**: stub으로 SOAP 실패 → 주문 paid+tax_invoices 미생성 상태에서 create 재호출 — 신규 주문 생성이 차단되고 기존 paid 주문 안내로 유도되는지. LEGAL C-2 시나리오와 대칭 테스트.
3. **부가세 포함 페이로드(C-3)**: tax_mode included 청구 stub 발행 시 Σ품목.Amount == invoice.subtotal, Σ품목.Tax == invoice.tax_amount 일치 단정. 별도 모드 drift도 상단·하단 행 케이스로.
4. **폴링 상태 머신(C-4)**: NTS 진행중(1·2·3) 재시도 → issued(3014+NTS 4) 확정·NTS 5 → failed·재시도 소진(10회) → status failed 전이·이미 issued/canceled/failed 건 재실행 no-op(멱등).
5. **웹훅 중복 settle**: 같은 order에 Transaction.Paid 2회 수신 → TaxInvoice 1건·PollStateJob 인계 1회·패스 발급 없음(product=collection_pass 함정 확인).
6. **콜백·웹훅 경합**: PurchaseService와 웹훅 FulfillPassService 동시 실행 → paid 전환 1회·발행 1회.
7. **가드 사슬 5종**: 설정 미완료·거래처 사업자번호 없음(개인)·주문 미결제·이미 발행 요청됨·paid 아님 각각의 안내 문구와 303/422 응답.
8. **취소 경계**: pending → cancel 성공(canceled·barobill_state 5031)·issued 건 직접 PATCH cancel → NotCancelable 안내·재취소 차단("이미 취소된 발행입니다").
9. **소유권 격리**: 타 사용자 order id로 /app/tax_invoices/:id·cancel 접근 → 404, 타인 invoice_id로 new·create → 차단.
10. **설정 경계**: RegistCorp -32000 흡수(저장 계속)·9자리 corp_num(422)·조작된 tax_type POST(500 아님)·CheckCERTIsValid 실패 시 마킹 미변경.
11. **SURF-3**: /app/tax_invoice_setting·/app/tax_invoices 응답 noindex 메타 확인.
