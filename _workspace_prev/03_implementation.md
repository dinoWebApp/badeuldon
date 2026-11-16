# 03_implementation — TAX-1/2 전자세금계산서 발행 (2026-11-16, Developer)

## 자가 검증 결과

- `bin/rails zeitwerk:check` — 통과("all is good!")
- `bin/rails db:migrate` — 3건 마이그레이션 적용 완료(db:migrate:status up 확인)
- `bin/rubocop`(전체 328파일) — 0 offense
- `bin/rails runner` 부팅 스모크(신규 클래스 전부 로드) — BOOT_OK
- 전체 테스트는 미실행(Phase 7 Tester 담당). 테스트 파일 미작성(하드 제약) — 단,
  `test/controllers/app/dashboards_controller_test.rb` nav 카운트만 11→12 선갱신(위임 지시 8번 예외).

## 변경 파일 목록

### 신규 (14)

| 파일 | 내용 |
|---|---|
| `db/migrate/20261115224716_add_tax_invoice_settings_to_users.rb` | users 확장 — corp_num·corp_name·ceo_name·corp_addr·contact_name·tax_type(default 0)·barobill_id(unique)·barobill_cert_registered(default false, null: false) |
| `db/migrate/20261115224718_add_tax_invoice_fields_to_clients.rb` | clients 확장 — ceo_name·corp_addr(상호=name·사업자번호=business_number·담당자=contact_name·email 기존 컬럼 재사용 — 마이그레이션 최소화) |
| `db/migrate/20261115224720_create_tax_invoices.rb` | tax_invoices — invoice_id(fk null: false + **unique 인덱스 — 1건 1발행**)·user_id(fk)·mgt_num(unique)·status(default 0)·barobill_state·nts_send_state·nts_send_key·write_date·supply/tax/grand_total·order_id(fk nullable)·status 인덱스 |
| `app/services/baro_bill/client_service.rb` | 바로빌 SOAP 래퍼(savon) — register_corp·certificate_register_url(CERT)·check_cert_is_valid·get_corp_state·regist_and_issue_tax_invoice·get_tax_invoice_state·cancel_tax_invoice. 솔라피 래퍼 패턴(credentials 기본값·stub 주입 가능 savon_factory·fail-fast ApiError) |
| `app/models/tax_invoice.rb` | status enum(pending/issued/canceled/failed)·ISSUE_FEE=300(Q21)·검증·status_label |
| `app/services/tax_invoices/register_corp_service.rb` | 발행 설정 1단계 — 사업자 정보 저장+RegistCorp(-32000 흡수)·barobill_id 채번 |
| `app/services/tax_invoices/issue_service.rb` | 발행 — 가드 사슬→휴폐업 조회→RegistAndIssueTaxInvoice→tax_invoices 기록→PollStateJob 인계 |
| `app/services/tax_invoices/cancel_service.rb` | 발급 취소 — ProcTaxInvoice(ISSUE_CANCEL)→status:canceled(barobill_state 5031) |
| `app/services/orders/fulfill_tax_invoice_service.rb` | 웹훅/콜백 결제 확정점 — metadata 병합(B-1 선례)→IssueService |
| `app/jobs/tax_invoices/poll_state_job.rb` | GetTaxInvoiceStateEX 폴링 — retry_on(polynomially_longer·10회)·멱등·3014+NTS=4 확정 |
| `app/controllers/app/tax_invoice_settings_controller.rb` | show·update·register_certificate·confirm_certificate(CheckCERTIsValid 검증 후 마킹) |
| `app/controllers/app/tax_invoices_controller.rb` | new(미리보기)·create(주문)·show(위젯/발행상태)·cancel(member PATCH) |
| `app/views/app/tax_invoice_settings/` | show.html.erb(2단계 온보딩·고지 2종)·register_certificate.html.erb(팝업 안내) |
| `app/views/app/tax_invoices/` | new.html.erb(미리보기)·show.html.erb(체크아웃·TAX-2 상태·취소) |
| `app/views/app/invoices/_tax_invoice_panel.html.erb` | paid 청구 상세 패널(기존 발행 기록·발행 버튼·설정 안내·개인 거래처 안내 4분기) |

### 수정 (14)

| 파일 | 내용 |
|---|---|
| `Gemfile`·`Gemfile.lock` | savon 추가(bundle 완료) |
| `app/models/user.rb` | has_many :tax_invoices·tax_type enum(general/simplified/exempt)·corp_num 10자리 검증·tax_invoice_ready? 단일 판정점 |
| `app/models/client.rb` | normalizes 확장(ceo_name·corp_addr)·corp_num 헬퍼(business_number 하이픈 제외 파생) |
| `app/models/invoice.rb` | has_one :tax_invoice·settled_paid_on(마지막 입금일 — WriteDate 근거) |
| `app/models/order.rb` | item_type enum 확장 tax_invoice: 2(pass 0·legal_doc 1 불변)·scope :tax_invoices |
| `app/services/orders/fulfill_pass_service.rb` | tax_invoice 주문은 패스 발급 제외 + 트랜잭션 밖에서 FulfillTaxInvoiceService 위임(콜백·웹훅 양 경로 단일 확정점) |
| `app/controllers/webhooks/portone_controller.rb` | settle 분기에 tax_invoice 추가(FulfillPassService 경유 위임) |
| `app/controllers/app/invoices_controller.rb` | set_tax_invoice_context before_action(@tax_invoice·@tax_invoice_guard 산출 — 뷰 쿼리 금지 규칙) |
| `app/controllers/app/clients_controller.rb` | strong params에 ceo_name·corp_addr 추가 |
| `app/views/app/invoices/show.html.erb` | _tax_invoice_panel 렌더 1줄 |
| `app/views/app/clients/_form.html.erb` | 대표자명·사업장 주소 필드 추가(TAX-1 안내 문구) |
| `config/routes.rb` | `resource :tax_invoice_setting`(show/update + collection POST register/confirm_certificate)·`resources :tax_invoices`(new/create/show + member PATCH cancel) — URL 동사 없음 |
| `app/helpers/app/base_helper.rb` | app_nav_items에 "전자세금계산서" 메뉴(설정 근처) |
| `test/controllers/app/dashboards_controller_test.rb` | nav 잠금 링크 카운트 11→12(위임 지시 예외 — Phase 7 충돌 방지 선갱신) |
| `db/schema.rb` | 마이그레이션 반영 |

## Rule ID 구현 매핑

| Rule ID | 구현 |
|---|---|
| **TAX-1** | paid 한정 1건 1발행(tax_invoices.invoice_id unique + IssueService 가드)·건당 300원(Q21)·공동인증서 필수 2단계 설정(user.tax_invoice_ready? — 미완료 시 발행 버튼 비활성·settings_missing 안내)·오발행 방지 3종(미리보기 new·중복 차단 가드·발행 전 GetCorpStateEx 휴폐업 조회 — 폐업(3) 차단)·PurposeType=1(영수)·IssueDirection=1(정발행)·개인 거래처 비대안(client_missing)·TESTBED 기본(운영 전환 계약 후 RELEASE) |
| **TAX-2** | NTSSendKey(승인번호)·NTSSendState·write_date(수금 마감일=마지막 입금일) 기록 → 청구서 상세 패널·발행 주문 show에서 조회. 폴링 Job 멱등(인자 스칼라 id·완료 상태 no-op) |
| **Q21** | TaxInvoice::ISSUE_FEE=300 상수 단일 출처·orders.item_type tax_invoice·포트원 단건 위젯 재사용(portone_payment Stimulus)·결제 완료(paid) 후에만 IssueService 수행 |
| **PLAN-5** | LegalDocuments 선례의 포트원 단건 플로우 재사용(주문→위젯→callback/webhook→재조회 검증·FulfillPassService 확정점) |
| **SEC-2** | 거래처 사업자·대표자·주소는 U1이 직접 입력(clients 폼 확정)·검증은 corp_num 정규화(하이픈 제외)·10자리 포맷 |
| **AUTH-1.3** | 발행 설정은 로그인 U1 전용(/app 가드)·user.tax_invoice_ready? 단일 판정점(컨트롤러 가드·뷰 분기 공유) |
| **P4** | 발행 요청·결과 전부 기록 — tax_invoices(barobill_state 원값 보존)·orders(metadata 병합)·취소도 레코드 유지(status:canceled) |
| **P5** | 설정·미리보기 화면에 세무 자문 아님 고지 + 바로빌((주)케이넷) 위탁·취소 과금 고지 명시 |

## 설계 결정 사항

1. **엔드포인트**: TESTBED `https://testws.baroservice.com/{BAROBILL,TI,CORPSTATE}.asmx?WSDL` / RELEASE `https://ws.baroservice.com/...`. release 판정 = `Rails.env.production? && credentials.dig(:barobill, :release_auth_key).present?`(명시 인자 override 최우선).
2. **관리번호(mgt_num) 채번**: `"TI{user_id}I{invoice_id}"` — 24자 이내·user 단위 결정적 유니크. 바로빌 규격상 취소된 관리번호는 재사용 불가이므로 **재발행 스코프 진입 시(후속) 별도 접미 채번 필요** — canceled 후에는 발행 버튼 자체를 비노출(재발행은 이번 런 스코프 밖, 위임 지시 확정).
3. **바로빌 아이디 채번**: `"bd" + user_id 18자리 0패딩`(=20자, RegistCorp ID 규격 6~20자)·users.barobill_id unique. 비밀번호는 GetBaroBillURL이 PWD를 요구하지 않으므로(빈 문자열 허용 — 문서) 난수 채번 후 비보존.
4. **취소 처리**: ProcTaxInvoice ProcType=ISSUE_CANCEL(국세청 전송 전에만 가능 — 문서). 성공 시 status:canceled·barobill_state=5031. 실패(전송 완료 건 등)는 NotCancelable 예외로 U1 안내("수정세금계산서 정정 필요"). canceled 레코드 유지 — invoice_id unique와 조합 제약 만들지 않음(위임 지시 확정).
5. **인증서 등록 완료 판정**: 공통 API에 CheckCERTIsValid가 존재함을 문서 재조사에서 확인(런 리스크 #1 해소) — confirm_certificate가 이 API로 실제 등록 여부를 검증한 뒤에만 `barobill_cert_registered` 마킹(오표시 방지). 전용 등록완료 콜백은 바로빌에 없음.
6. **결제-발행 원자성**: 결제 확정(with_lock + pending 재판정)과 발행(SOAP)을 분리 — 발행은 트랜잭션 밖에서 수행하며 실패해도 paid를 되돌리지 않음(로그 추적, 뷰에서 "발행 기록 미생성" 안내). metadata는 항상 병합(B-1).
7. **PriceType 세금 매핑**: user.tax_type(general/simplified/exempt) → TaxType 1/2/3. 품목 세액은 항목별 10% 라운드(invoice.tax_amount 총액과의 차이는 바로빌 합계 기준 AmountTotal/TaxTotal이 우선).

## 알려진 한계·Developer가 발견한 스펙 불명 지점

1. **[INFERENCE] 공통 API WSDL 파일명** — 문서의 엔드포인트 표에 공통 API asmx가 미기재. 바로빌 표준 구성 `BAROBILL.asmx`로 구현 — TESTBED 실측 시 확인 필요.
2. **[INFERENCE] GetCorpStateEx 상태 코드** — State 1 계속/2 휴업/3 폐업은 바로빌 표준 휴폐업 코드 관행에 근거(문서 본문에 코드표 미검출). IssueService는 폐업(3)만 차단.
3. **RegistCorp 업태/업종(BizType/BizClass 필수)** — 받을돈이 보유하지 않는 정보라 고정값("서비스"/"프리랜서 서비스")으로 채번. 향후 설정 폼 확장 후보.
4. **RegistCorp TEL 필수** — user.phone 미설정 시 "02-0000-0000" 폴백(바로빌 계정 연락처 실용성은 낮음 — UI 안내 후보).
5. **발행 실패 재시도 경로 부재** — 결제 완료 후 SOAP 실패 시 failed 처리는 PollStateJob이 담보하지만, 가드 위반·SOAP 거부(주문은 paid, tax_invoices 레코드 없음)의 CS 재발행은 후속 스코프(수동 재시도 or 환불 절차).
6. **SOAP 실측 미수행** — savon 응답 파싱 구조(`{메서드}_response.{메서드}_result`)는 WSDL 문서 규격 기준 코드 완성. TESTBED 실발행 실측은 운영 전환 후(런 리스크 #2 — 계획서 확정 사항). 테스트는 savon_factory·client 주입으로 stub 가능한 구조.
7. **InstaMax 품목 세액 계산** — invoice 세금계산은 withholding이 있는 경우 총액 세액과 항목 합이 미세하게 어긋날 수 있음(바로빌은 항목 합계를 국세청 전송 기준으로 사용 — TaxTotal 상위 필드와의 정합은 실측 검증 항목).
8. **대량(99개 초과) 품목** — invoice items가 99개 초과면 RegistAndIssueTaxInvoice 규격 위반. 현재 받을돈 청구서 실사용 규모(소액·소량)에서 비현실적이라 상한 가드를 두지 않았다 — IssueService 상한 가드 추가는 Reviewer 판단 대상.

## 비고

- dashboards nav 카운트 외 테스트 코드는 일절 미작성·미수정(Phase 7 영역).
- `db/schema.rb`는 마이그레이션 반영 상태로 커밋 대상(커밋은 하지 않음 — 하드 제약).
- `_workspace/01_plan.md`·PRD.md·AGENTS.md 미수정.

## Phase 6 수정(2026-11-16)

05_review.md(CHANGES_REQUESTED — CRITICAL 4·WARNING 7)의 최소 수정 결과. 테스트 파일 미작성(하드 제약)·PRD/plan/review 문서 미수정·커밋 없음.

### CRITICAL

| # | 수정 내용 | 파일:위치 |
|---|---|---|
| C-1 | `post_payment_redirect_path`에 tax_invoice 분기 추가(발행 주문 show `app_tax_invoice_path(order)`로 착지 — legal_doc 선례 패턴)·notice 삼항식을 `payment_notice` 품목별 문구 분기 메서드로 전환("전자세금계산서 발행 결제가 완료되었습니다. 발행 상태를 확인해 주세요."). legal_doc·pass 착지·문구는 기존 그대로(회귀 없음) | app/controllers/app/orders_controller.rb:24-25, 39-66 |
| C-2 | create에 paid 주문 가드 추가 — `Order.tax_invoice_order_for(@invoice, paid: true)`로 해당 청구의 paid tax_invoice 주문 존재 시 기존 주문 show로 리다이렉트+안내("이미 결제가 완료되었습니다…"), 신규 주문 생성 차단(LEGAL find_paid_legal_order 선례). 부수: Order에 공용 역참조 메서드 `tax_invoice_order_for` 신설(가드·패널 공용, invoice.user_id 스코프로 소유권 격리)·청구 상세 패널에 `:paid_pending` 가드 분기 신설(결제 완료·발행 기록 미생성 시 재결제 버튼 대신 "발행 주문 확인" 안내 — @tax_invoice_order 컨트롤러 산출) | app/controllers/app/tax_invoices_controller.rb:24-38, 88-103 · app/models/order.rb:57-64 · app/controllers/app/invoices_controller.rb:227-247 · app/views/app/invoices/_tax_invoice_panel.html.erb:26-35 |
| C-3 | 품목 행 금액을 tax_mode 분기·정수 연산으로 재구성 — 별건 모드: 행 공급가액=qty×price·세액=(qty×price)×10/11 사사오입 정수식 `(x*10+5)/10` / 포함 모드: 행 공급가액=총액×10/11 사사오입 `(x*10+5)/11`·세액=총액−공급가액(Invoice.compute_amounts 산식과 동일 근사). `adjust_last_row!`로 마지막 행에 반올림 잔액 반영 → Σ품목.Amount=AmountTotal(invoice.subtotal)·Σ품목.Tax=TaxTotal(invoice.tax_amount) 정확 일치. Float `* 0.1` 제거 | app/services/tax_invoices/issue_service.rb:100-139 |
| C-4 | retry_on에 소진 블록 추가 — executions 소진 시점(10회)에 `tax_invoice.update!(status: :failed)` 확정 후 예외 재발생(잡 실패 기록 유지). 멱등 유지(issued/canceled/failed는 no-op) | app/jobs/tax_invoices/poll_state_job.rb:9-15 |

### WARNING

| # | 수정 내용 | 파일:위치 |
|---|---|---|
| W-1 | RegistAndIssueTaxInvoice SOAP 호출을 AR 트랜잭션 밖으로 이동 — 쓰기(create!+with_lock)만 트랜잭션으로 감싸고 SOAP 성공 후 PollStateJob 인계(순서 유지). fulfill_pass_service 트랜잭션-외부호출 분리 패턴 준수 | app/services/tax_invoices/issue_service.rb:25-37 |
| W-2 | create 액션 축약(가드 조기 리턴 3종+생성 위임) — 주문 생성(멱등 pending 재사용 포함)을 신규 `TaxInvoices::CreateOrderService.call`로 이관. 컨트롤러 본문 10줄 이내 | app/controllers/app/tax_invoices_controller.rb:24-38 · app/services/tax_invoices/create_order_service.rb(신규) |
| W-3 | 컨트롤러가 서비스에 `params.expect(...).to_hash.symbolize_keys`로 전환(params 직접 주입 제거 — 규약 §4.2). RegisterCorpService에 `validate_input`(enum 할당 전 tax_type 화이트리스트 검증 — 조작값 500 방지)·`validate_corp_num_format`(RegistCorp 외부 호출 전 `/\A\d{10}\z` 검증 — RecordInvalid 500 여지 제거) 추가, 위반은 422 재렌더 | app/controllers/app/tax_invoice_settings_controller.rb:11-14, 62-64 · app/services/tax_invoices/register_corp_service.rb:22-31, 38-70 |
| W-4 | 가짜 연락처 "02-0000-0000" 폴백 제거 — `tel: @user.phone`(실제 보유 데이터)로 전환하고 phone을 RegistCorp 필수 세트에 추가(미설정 시 422 안내). 설정 폼 1단계에 연락처 필드 신설(부수 조정 — 실제 번호 수집이 전제라 폼 없이는 가드만으로 저장 불가) | app/services/tax_invoices/register_corp_service.rb:78 · app/views/app/tax_invoice_settings/show.html.erb:74-84 |
| W-5 | 취소 실패 문구 상태별 분리 — code "SOAP"(전송 계열·일시 오류)는 재시도 안내 문구, 그 외(바로빌 음수 코드)는 기존 수정세금계산서 정정 안내 유지 | app/services/tax_invoices/cancel_service.rb:21-28 |
| W-6 | 패널 "발행 내역 보기" 링크를 app_tax_invoice_setting_path(온보딩 화면)에서 발행 주문 상세 `app_tax_invoice_path(@tax_invoice.order_id)`로 수정(order optional — present 가드) | app/views/app/invoices/_tax_invoice_panel.html.erb:21-25 |
| W-7 | 코드 변경 없음 — TESTBED 실측 후속(03 문서 한계 #1·#2·#7 유지). 단, 별도 모드 drift(#7·③)는 C-3의 마지막 행 잔액 조정으로 함께 해소됨 | — |

### 부수 조정(사유 기록)

- `app/models/order.rb` — `tax_invoice_order_for` 공용 메서드 신설(C-2 가드와 패널 `:paid_pending` 분기가 동일 역참조 조회를 필요로 하며, 중복 구현 대신 단일 출처로 둠).
- 리뷰 지적 외 코드는 변경하지 않았다. `bin/rubocop` 0 offense(329파일)·`bin/rails zeitwerk:check` 통과·`bin/rails db:migrate`(신규 마이그레이션 없음 — up 확인)·runner 부팅 스모크 BOOT_OK. 전체 테스트는 미실행(Phase 7 영역).

### Phase 7 분기 수정(B-1)

- app/views/app/invoices/show.html.erb:36 — `render "tax_invoice_panel"`(컨트롤러 상대 경로)을 절대 경로 `render "app/invoices/tax_invoice_panel"`로 수정(뷰 루트 기준 — App 네임스페이스 경유). 타 컨트롤러(payments·promises 등) 422 재렌더 시 Missing partial 크래시 해소. 검증: 지적 4파일 34 runs 0실패·전체 스위트 1,183 runs 0실패·`bin/rubocop` 0 offense(342파일).
