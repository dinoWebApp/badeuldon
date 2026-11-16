# 01_plan — TAX-1/2 전자세금계산서 발행 (2026-11-13, Full · 절약 모드 · Sequential)

## §6.14 판정

**불리 → Sequential 단일 사슬.** 이유: 바로빌 SOAP 래퍼가 발행 설정·발행 플로우·폴링 잡 전부의 선행 의존이고, users/clients 마이그레이션 체인·`config/routes.rb`·`orders.item_type` enum 확장·PRD/AGENTS 결선이 겹침(3조건 전부 미충족).

## 규모 판별 — Full (Phase 0→1→✋→2→3→4→5→6?→7→8→9)

새 도메인(`tax_invoices` 테이블·신규 화면 2종)·외부 API 래퍼(SOAP)·마이그레이션 2건·신규 라우트·Job — 3개+ 파일 변경 대규모.

## 사용자 확정 전제 (2026-11-13 — 설계 단일 소스)

1. **공동인증서 등록 필수** — 발행 설정 2단계(RegistCorp 사업자 정보 → GetBaroBillURL(CERT) 팝업) 완료 전까지 발행 버튼 비활성
2. **취소도 100원/건 과금 전제** — 오발행 방지 3종(발행 전 미리보기·중복 발행 차단·발행 전 휴폐업 조회)을 필수 스코프로

## 게이트 확정 대상 — Q21 전가 가격 (권장안 제시)

| 안 | 내용 | 근거 |
|---|---|---|
| **A 권장** | **건당 300원** — 포트원 단건 결제 재사용(orders.item_type :tax_invoice 추가·LEGAL 건당 5,000원 선례의 인프라), 결제 완료 후에만 발행 요청 | 원가 100원+취소율+마진·홈택스 무료 대안이 있어 저가 유지·구현 검증된 플로우 |
| B | Plus 구독 혜택(월 N건 포함)+초과 건당 | 구독 가치 강화 — 월 한도 추적 로직 추가로 스코프 확대 |

권장 A로 진행하고 B는 PRD 후속 후보로 기록.

## 구현 범위 (TAX-1·TAX-2·사용자 전제 반영)

### 1. 바로빌 래퍼 (선행 의존 — 全 스코프의 기반)
- `Gemfile` — `savon` 추가 (SOAP/WSDL 클라이언트 — 바로빌은 ws.baroservice.com SOAP·Ruby SDK 부재)
- `app/services/baro_bill/client_service.rb` — 솔라피 래퍼 선례(credentials.dig 기본값 + stub 주입 + fail-fast):
  - `RegistCorp`(회원사 가입 — 프리랜서, 바로빌 아이디는 받을돈 채번 `badeuldon_` prefix + user_id)
  - `GetBaroBillURL(toGo: "CERT")` — 인증서 등록 URL 반환
  - `RegistAndIssueTaxInvoice`(간편발급 — 관리번호 24자리·회원사 단위 유니크)
  - `GetTaxInvoiceState`(상태·NTSSendKey=국세청 승인번호)
  - `GetCorpState`(휴폐업·과세유형 — 발행 전 검증, 10원/호출)
- env 스위치: `test_auth_key`(TESTBED) / `release_auth_key`(운영 — 계약 후) · credentials 이미 등록됨
- 테스트베드 실측은 운영 배포 후 후속(이번 런은 stub 기반 코드 완성)

### 2. 마이그레이션 2건 + 신규 테이블
- `users` 확장: `corp_num`·`corp_name`·`ceo_name`·`corp_addr`·`contact_name`·`tax_type`(enum: general/simplified/exempt)·`barobill_id`·`barobill_cert_registered`(boolean, default false)
- `clients` 확장: `corp_num`·`ceo_name`·`corp_addr`·`contact_name`·(상호는 기존 name 재사용·email 기존 필드 확인)
- `tax_invoices` 신규: `invoice_id`(fk, unique — 1건 1발행)·`user_id`·`mgt_num`(24자리, unique)·`status`(enum: pending/issued/canceled/failed)·`barobill_state`·`nts_send_state`·`nts_send_key`(승인번호 TAX-2)·`write_date`·`supply_total`·`tax_total`·`grand_total`·`issued_at` — `null: false`·인덱스 명시

### 3. 발행 설정 온보딩 (U1)
- 설정(프로필)에 사업자 정보 폼 확장 + `/app/tax_invoice_setting` 단일 화면: ① 사업자 정보 저장(=RegistCorp) ② 인증서 등록(팝업 URL) ③ 등록 상태 표시
- 인증서 등록 완료 판정: 발급 API 오류코드 기반 갱신 + "등록 완료" 자체 갱신 버튼(전용 상태조회 API 문서 미확인 — Developer가 문서 재조사 후 최선 구현, 리스크 명시)
- 세무 자문 아님 고지(DASH-6 LEGAL-3 선례 문구) + 바로빌 회원사 가입·인증서 위탁 동의 고지

### 4. 발행 플로우 (수금 마감 건당)
- `invoices#show`(paid)에 "전자세금계산서 발행" 버튼 — 가드: ① 발행 설정 완료(인증서 포함) ② 거래처 corp_num 보유(개인 거래처는 비대상 안내) ③ 결제 완료(Q21-A) ④ 기존 tax_invoices 레코드 없음(1건 1발행)
- 발행 전 확인 미리보기(공급자/공급받는자/품목/금액) → 발행 전 휴폐업 조회 → 결제 → RegistAndIssueTaxInvoice
- 멱등: tax_invoices.invoice_id unique + 결제·발행 원자성(포트원 웹훅 선례 — 결제 재조회 검증)
- 폴링: `TaxInvoices::PollStateJob`(Solid Queue — 인자 스칼라 id·retry_on·완료(NTSSendKey 캡처) 또는 최대 재시도 후 failed)
- 취소: 발급 취소(5031 계열) — status:canceled·취소도 과금 전제(재발행은 별도 결제)
- TAX-2: invoices show에 발행 이력·승인번호·발행일 표시

### 5. 라우트·결선
- `resource :tax_invoice_setting, only: [:show, :update]` + `post :register_certificate`(member 개념) + invoices 하위 tax_invoices or member `issue_tax_invoice`·`cancel_tax_invoice` — URL 동사 금지 원칙 준수해 Developer가 세안
- 사이드바/설정 메뉴 링크 + dashboards_controller_test nav 카운트 갱신(반복 실측 결함 — 필수 점검)

## 대상 파일 (예상)

- 신규: `app/services/baro_bill/client_service.rb`·`app/models/tax_invoice.rb`·`app/controllers/app/tax_invoice_settings_controller.rb`·`app/controllers/app/tax_invoices_controller.rb`(또는 invoices member 확장)·`app/jobs/tax_invoices/poll_state_job.rb`·`app/views/app/tax_invoice_settings/`·`app/views/app/tax_invoices/`(또는 파셜)·테스트 다수
- 수정: `Gemfile`·`app/models/user.rb`·`app/models/client.rb`·`app/models/order.rb`(item_type enum)·`app/controllers/app/invoices_controller.rb`(show)·`app/views/app/invoices/show.html.erb`·`app/views/app/clients/_form*.erb`·`config/routes.rb`·`db/schema.rb`·PRD/AGENTS
- 주의: `orders.item_type` enum 확장 시 기존 pass/legal_doc 값 불변(0·1 → tax_invoice는 신규 값)

## 관련 Rule ID

TAX-1(제휴 발행·수수료 사용자 부담)·TAX-2(승인번호 기록·조회)·Q13(런 분리)·Q21(신규 — 전가 가격·건당 과금)·PLAN-5(포트원 단건 재사용)·INV-4(paid 판정)·SEC-2(거래처 정보 입력 책임 U1)·AUTH-1.3(프로필 가드)·TIME-1·P4(발행 요청·결과 전부 기록)·P5(세무 자문 아님 고지)·NOTI-3 선례(알림톡 템플릿 미등록 시 skip — **이번 런 알림톡은 제외·후속**)

## 리스크·모호점

1. **인증서 등록 상태 조회 API 미확인** — 문서에 전용 조회 메서드 미검출 → 오류코드 기반 갱신+사용자 자체 갱신 버튼으로 구현, 바로빌 계약 협의 시 문의 항목
2. **SOAP/WSDL 세부 스펙** — savon 실측 필요·TESTBED 계정(파트너 등록)은 사용자가 개발자센터에서 확보한 상태(테스트 인증키 credentials 등록 완료) — 코드 완성 기준, 실발행 실측은 운영 전환 후
3. **취소 API·오류코드 세부** — ModifyCode 6종·상태코드 11종 문서 확인은 Developer 몫
4. **결제-발행 원자성** — 결제 완료(웹훅/콜백)와 발행 요청 사이 유실 방지: LEGAL metadata 병합 선례(B-1) 준수
5. **거래처 사업자번호 미보유 다수** — 기존 clients 데이터엔 corp_num 없음 → 발행 시 안내로 유도(마이그레이션 백필 없음)

## Git 사전 점검 (Phase 0)

미커밋 8파일 — 하네스 v4.2.0 동기화 7파일 + `config/credentials.yml.enc`(암호화 본문·커밋 안전). **계획 승인 시 커밋 먼저 진행**(하네스 동기화 1커밋 + credentials 1커밋 또는 통합 1커밋) 후 런 산출물과 분리 유지.
