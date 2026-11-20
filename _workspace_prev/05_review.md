# 병렬 배치 T1·T3·T4 — 통합 리뷰 (05_review)

일자: 2026-11-20 · 리뷰어: badeuldon-reviewer (일반 모드 · 리뷰+테스트 통합 런)
대상: git working tree — `_workspace/parallel/{T1,T3,T4}/03_implementation.md` 산출물 (T2 인프라·코드 리뷰 대상 아님)

## 총평

- **BLOCKER 0 · CRITICAL 1(테스트 인프라 — 본 배치 내 해소) · WARNING 3 · NOTE 4**
- 상태: **APPROVED** — C-1은 Tester(본 런)가 테스트 stub화로 해소 완료, W-1·W-2는 주석 1줄 정정 수준의 후속 청산 항목, W-3은 법무 검토 위임 항목(기능 결함 없음). 기능 정합성·보안·데이터 무결성 위반 0.
- T2(서버 백업 스크립트·crontab)는 워킹트리 무관 인프라 — `server-backup` 스크립트·crontab 등록본은 리뷰 대상 명세에서 제외(지시 확인).

---

## 이슈 목록

### C-1 (CRITICAL — 테스트 실호출, 본 런에서 해소) T4 — 대시보드 렌더 경로 외부 API 무방어

- `severity`: CRITICAL · `rule_id`: AGENTS 테스트 전략("외부 API(솔라피·포트원)는 테스트에서 stub/wrapper 주입 — 실 호출 금지")·REM-10
- `file:line`: `app/controllers/admin/dashboards_controller.rb:38` (`Solapi::ClientService.new.get_balance`)
- 내용: `load_solapi_balance`가 컨트롤러에서 래퍼를 직접 생성한다. **RAILS_ENV=test에서도 credentials에 유효한 솔라피 키가 로드된다**(`test/test_helpers/solapi_stubbing.rb` 주석 실측 명시 — 본 리뷰에서 `RAILS_ENV=test bin/rails runner`로 재확인: api_key present true)·테스트 캐시는 NullStore라 캐시 방어선도 작동하지 않는다. 결과적으로 기존 테스트가 전부 **api.solapi.com 실호출**을 수행한다 — `test/controllers/admin/dashboards_controller_test.rb`(GET admin_root_path 7회·전부 200 렌더), `test/controllers/admin/sessions_controller_test.rb` "12시간 절대 만료 전까지 세션 유지"(렌더 11회). 네트워크 차단 환경에선 CONNECTION→rescue로 우연히 통과하고, 개방 환경에선 실호출+레이트리밋·플레이크 위험이다.
- 조치: 소스 수정 불가 제약으로 **Tester가 테스트 측 방어선으로 해소**(본 런). 실행 중 실측으로 200 렌더 지점 4곳을 특정해 전부 `SolapiStubbing.with_solapi_client`로 감쌌다 — `test/controllers/admin/dashboards_controller_test.rb`(7회 GET)·`test/controllers/admin/sessions_controller_test.rb`(12h 세션 테스트 11회)·`test/controllers/admin/base_guard_test.rb`(잠금 경계 렌더)·`test/controllers/sales/session_isolation_test.rb`(관리자 세션 유지 렌더 2곳). 신규 T4 컨트롤러 테스트도 전부 stub 주입. 소스 측 근본 대안(래퍼 주입점·`Rails.env.test?` 가드)은 후속 기술 부채 후보로만 기록한다 — 컨트롤러 직접 생성은 PortOne 계열 기존 패턴과 동일해 컨벤션 위반은 아니다.
- 상태: **해소(테스트 갱신)**

### W-1 (WARNING) T4 — 잔액 [INFERENCE] 잔존: message_stats_query 헤더 주석 미청산

- `severity`: WARNING · `rule_id`: ADMIN-5·REM-10
- `file:line`: `app/queries/admins/message_stats_query.rb:4`
- 내용: "솔라피 크레딧 잔액 API는 [INFERENCE] — 기술 부채로 로컬 집계만 제공한다" 주석이 잔존한다. T4 라이브 실측·대시보드 표시로 이 명제는 소멸했다(검증: `grep -rn INFERENCE app/` — 잔액 관련 잔존은 이 1건. `client_service.rb`의 send_sms·응답 식별자 마커는 본 태스크 범위 밖 항목). 해당 파일은 T4 화이트리스트 밖이라 개발자가 수정하지 않은 것—— 지시 기준 "[INFERENCE] 잔존 0" 대비 미달.
- 제안: 주석 1줄 정정("잔액은 T4 get_balance·대시보드 표시로 제공") — 오케스트레이터 후속 반영.

### W-2 (WARNING) T4 — 헬퍼 주석과 코드의 임계 경계 부등호 불일치

- `severity`: WARNING · `rule_id`: ADMIN-5
- `file:line`: `app/helpers/admin/dashboards_helper.rb:5-6`
- 내용: 주석은 "임계치 — **이하면** 발송 중단 임박으로 간주"라 했으나 코드는 `< LOW_BALANCE_THRESHOLD`(**미만**)다. 동작 자체는 명세(T4 문서 "경계값(=50,000)은 정상 판정"·뷰 각주 "50,000원 미만 주황 경고")과 정합 — 49,999 주황·50,000 정상. 주석만 오기다.
- 제안: 주석 "이하면"→"미만이면" 1단어 정정.

### W-3 (WARNING) T1 — 개정일 표기 방식의 문서군 불일치 + 당일 개정·시행

- `severity`: WARNING · `rule_id`: AUTH-9(공지 요건 관점)·전자상거래법 표시광고(법무 검토 영역)
- `file:line`: `app/views/pages/privacy.html.erb:13`(공고·시행일 전부 11-20 갱신) vs `terms.html.erb:14·178`·`refund.html.erb:12·68`(원 시행일 유지 + 부칙 개정일 병기)
- 내용: ① 3문서가 서로 다른 개정일 표기 방식을 쓴다 ② privacy 공고일=시행일=같은 날(선공지 없는 당일 개정). T1 문서 §4.7이 스스로 기록한 의도된 선택이나, 약관 중요 변경의 30일 전 공지 관행과의 정합은 법무 판단 영역이다.
- 제안: 법무 검토 후 표기 방식 통일(권장: terms/refund 방식—— 원 시행일 보존+부칙 개정일). 기능 결함 아님.

### N-1 (NOTE) T4 — get_balance의 credentials 검증이 sender_number까지 요구

- `file:line`: `app/services/solapi/client_service.rb:128-129` (`ensure_credentials!(require_pf_id: false)`)
- 잔액 조회에 발신번호는 불요하나 `required` 목록이 공유라 `@sender_number` 누락 시 MISSING_CREDENTIALS로 실패한다. 현재 credentials는 발송 성분과 항상 동시 구성이라 동작 영향 없음·오류 메시지에 누락 변수명이 명시돼 진단 가능. 후순위 정리 여지만 기록.

### N-2 (NOTE) T1 — terms 제5조에 "사업자 유형 회원 한정" 명시 부재

- `file:line`: `app/views/pages/terms.html.erb:83`
- PRD TAX-1은 "사업자 유형 사용자에 한해"로 한정한다. 구현은 `User#tax_invoice_ready?`(corp_num·barobill_id 등 필수 — `app/models/user.rb:142`)로 발행 설정 단계에서 실효 차단되나, 약관 문언에는 발행 주체 한정이 없다(거래처 개인 비대상만 명시). 문서 보강 후보.

### N-3 (NOTE) T1 — terms 제4조(회원가입)에 AUTH-9 휴대폰 인증 미반영

- T1 문서 §5 자체 기록(범위 밖 처리 정당). 제4조는 "이메일과 비밀번호로 계정을 만들고"에 머물러 있다. 후속 약관 갱신 시 반영.

### N-4 (NOTE) T3 — schema.rb 갱신 주체

- T3 문서는 "schema.rb 미수정(3-S 결선에서 갱신)"이라 했으나 워킹트리 schema.rb가 이미 갱신돼 있다(버전 2026_11_20_000000·`t.string "note"`·`idx_message_logs_digest_period_uniq where: digest = 1` 반영 — 마이그레이션과 정합 확인 완료). 3-S에서 마이그레이션을 실행한 것으로 보며 정합 문제 없음.

---

## 검증 관찰 (이슈 아님 — 준수 확인)

1. **T1 가격·수치 전수 대조** — 300원=`TaxInvoice::ISSUE_FEE`(tax_invoice.rb:6)·5,000원=`Order::LEGAL_DOC_PRICE`(order.rb:15)·20%=`Sales::AttachFirstChargeCouponService::DISCOUNT_PERCENT`·Free 3건/5거래처=`Invoice::FREE_MONTHLY_INVOICE_LIMIT`/`Client::FREE_CLIENT_LIMIT`·Plus 9,900원(부가세 포함)·수금 패스 10건 4,000원 90일 — 전부 코드 상수·PRD(PLAN-1/2·Q5·Q21·Q24)와 일치. "부가세 포함"은 PRD 명시 항목(구독·패스)에만 붙고 건당 요금은 제7조 포괄 조항으로 위임 — 정합.
2. **T1 LP-12 금지 표현** — 신규 문구에서 보장형("100%")·압박·'추심 대행' 오인 표현 0. 기존 "추심" 2건은 모두 "추심 서비스가 아니다" 부정형 고지(P5 경계 명시). 취소 과금("발행 취소 시에도 수수료가 과금됩니다")·20% 할인은 사실 고지로 압박 표현 아님.
3. **T1 SURF-3** — /terms·/privacy·/refund는 `NOINDEX_PATH_PREFIXES`(application_helper.rb:4 — /app·/b/·/admin·/sales) 밖이다. PRD SURF-3 "표면 ①과 그 하위 공개 콘텐츠는 색인 허용" — 법적 고지 페이지의 색인 허용은 **정합**(PagesController 주석·surf3_indexing_test 선례와 동일).
4. **T1 제3자 제공 정합** — 바로빌=(주)케이넷 표기는 PRD §EXT 의존성 표와 동일. 제공 항목(사업자 정보·청구 내역·발행 이력)·공동인증서 바로빌 서버 보관(당사 미보관)·제5조 위탁 이중 기재(제공 vs 위탁 구분)는 TAX-1 구현(GetBaroBillURL 팝업 등록 구조)과 정합. AUTH-9(휴대폰 필수·유일성 검증·알림톡 우선·5분 만료 1회용)·AUTH-8(이메일=재설정 링크) 반영 확인.
5. **T3 인덱스-쿼리 1:1** — `Noti::WeeklyDigestService#already_sent_this_week?`(71-73행)는 `MessageLog.exists?(user_id:, template_key:, scheduled_at: period_start)`이고 인덱스는 `[user_id, template_key, scheduled_at] where digest = 1` — 완전 대응(SEC-5 debtor pending 슬롯 인덱스와 동일한 "애플리케이션 판정 + DB 최후 방어선" 2중 구조). digest 열은 `boolean default false null: false`(schema)라 `where: "digest = 1"`(SQLite 정수 표현)은 기존 `idx_message_logs_debtor_pending_uniq` 선례와 동일.
6. **T3 dedup 안전성** — MAX(id) 1행 보존·`id NOT IN` 삭제 쿼리는 SQLite 정상 동작·digest 행은 WeeklyDigestService 단일 진입점이라 scheduled_at NULL 경로 없음(NULL은 유니크 판정 제외되나 도달 불가). up/down 분리로 rollback 시 비가역 삭제 재실행 없음 — 마이그레이션 컨벤션(명시적 name·up/down) 준수. payments.note의 null 허용은 "선택 표기·서비스만 기록" 근거가 모델 헤더에 명시돼 정당.
7. **T3 Q22 note 기록 시점** — `@payment.update!(note:)`는 `@invoice.with_lock` 트랜잭션 내부(record_payment! 안)에서 수행 — 기록·전이·비고가 함께 확정/롤백된다(P4). 초과분 산정은 `@invoice.paid?`(전이 전) 기준이라 마감 후 재입금 경로는 note 없음(Q22 정합). 감사 로그(`payment_over_recorded`·target=청구서·detail 문언) 불변 유지 — 내부 메서드명만 `audit_over_record`로 변경(공개 인터페이스 아님).
8. **T3 뷰·라우트** — 비고 표시는 `payment.note.present?` 조건·`<%= %>` 기본 이스케이프(raw 무사용)·뷰 쿼리 없음(@payments 순회만). `except: :destroy`는 컨트롤러에 destroy 액션이 실제 없음을 확인(8액션만 존재)·member PATCH 3종(toggle_suspension·rotate_code·unlock) 불변 — `bin/rails routes` 실측 DELETE 미노출 확인.
9. **T4 GET 전용·발송 무호출** — `get_balance`는 `method: :get`·`BALANCE_PATH = "/cash/v1/balance"`·바디 없음. 발송 API(SEND_PATH POST) 호출 경로 없음(SEC-5·PLAN-3·MessageLog 비개입 — P4 무관성 주석 명시).
10. **T4 캐시·경계·fail-fast** — 성공 5분·실패 1분(`:unavailable` 센티널로 nil 구분) — 장애 낙수 방지 설계 정합. 임계는 `< 50_000`(49,999 주황·50,000 정상)으로 뷰 각주 문언과 정합(W-2는 주석만 오기). 응답 파싱은 balance 누락·null·비숫자 → `UNEXPECTED_BALANCE_RESPONSE` fail-fast("잘못된 잔액을 정상처럼 표시" 차단), 콤마 문자열·Float는 관대 정규화 — 명세(라이브 실측 Integer) 대비 방어 적정. 컨트롤러 액션은 1줄 위임·헬퍼가 표현 로직 담당(뷰 직접 비교 금지 준수)·`Admin::DashboardsHelper` zeitwerk 상수 정상(부트 확인).
11. **T4 통화 포맷 실측(ko locale)** — `number_to_currency(unit: "₩")`는 ko locale에서 접미사로 렌더된다("120,000₩" — 대시보드 기존 매출 카드 "9,900₩"와 동일 규격). 표기 일관성 문제 없음(테스트가 이 형식을 계약화).
12. **공통 팬아웃 소유권** — 3태스크 파일 소유권 교차 0 확인(git diff 스팬 검증 — T1 views/pages 3종·T3 마이그레이션/payment/record_service/invoices show/routes·T4 solapi 래퍼/dashboards 3종+헬퍼 신설). PRD·AGENTS 미수정·커밋 없음.

---

## Rule ID 준수 매핑

| Rule ID | 태스크 | 준수 | 근거 |
|:---|:---|:---|:---|
| TAX-1 | T1 | ✅ | paid 한정·1건 1발행·거래처 개인 비대상·취소 과금·미리보기·공동인증서 바로빌 보관·세무 자문 아님 고지 — PRD 문언 전 항 반영 |
| TAX-1/Q21 | T1 | ✅ | 건당 300원 — `TaxInvoice::ISSUE_FEE = 300` 대조 일치 |
| LEGAL-2/Q5 | T1 | ✅ | 건당 5,000원·플랜 무관·결제 완료 후 다운로드 — `Order::LEGAL_DOC_PRICE = 5_000` 대조 일치 |
| Q24/SALES-4 | T1 | ✅ | Plus 첫 결제 20%·다음 달 정상가 — `DISCOUNT_PERCENT = 20`·PRD Q24 문언 일치 |
| AUTH-9 | T1 | ✅ | 휴대폰 필수 수집·유일성 검증·인증번호 알림톡(SMS 대체)·5분 만료 1회용·솔라피 제3자 제공에 인증번호 발송 포함 |
| AUTH-8 | T1 | ✅ | 이메일 수집 목적에 재설정 링크 발송 명시 |
| PLAN-1/2 | T1 | ✅ | Free 3건/5거래처·Plus 9,900원(부가세 포함)·14일 체험 — 코드 상수 일치 |
| LP-12 | T1 | ✅ | 신규 문구 금지 표현(보장형·압박·추심 오인) 0 — 스캔 완료 |
| SURF-3 | T1 | ✅ | 공개 법적 문서 색인 허용 — NOINDEX_PATH_PREFIXES 미포함 정합 |
| Q22 | T3 | ✅ | 초과분 note 구조화(트랜잭션 내)·마감 후 재입금 note 없음·환불 오프라인 문구 |
| P4 | T3 | ✅ | 감사 로그 병행 유지(payment_over_recorded)·기록 무결성 |
| SEC-5/NOTI-2(W-1 전번) | T3 | ✅ | digest 부분 유니크 인덱스 — 멱등 판정 쿼리와 1:1·dedup 선행 |
| 관찰⑤(routes) | T3 | ✅ | except: :destroy — 라우팅 404 흡수·member 불변 |
| ADMIN-5 | T4 | ✅ | 잔액 표시·임계 경고·fallback(단, W-1·W-2 주석 잔존) |
| REM-10 | T4 | ✅ | 선불 크레딧 모니터링 API 계층 — GET 전용·발송 무호출 |
| AGENTS 테스트 전략 | T4 | ⚠️→✅ | C-1 실호출 무방어 — Tester가 stub화로 해소(본 런) |

## Tester 중점 테스트 제안 (07_test_report에서 실행)

1. **T4 실호출 차단 최우선** — 기존 dashboards·sessions 테스트의 stub화(C-1 해소 검증: 전 테스트 실행에서 외부 호출 0)·컨트롤러 캐시 히트(5분 내 재요청 외부 호출 0)·실패 센티널(1분 내 재요청 외부 호출 0)은 MemoryStore 스왑으로 검증.
2. T4 단위 — get_balance(GET 메서드·경로·무바디·HMAC 헤더)·콤마 문자열 정규화·스키마 이탈 fail-fast·헬퍼 경계(49,999/50,000/nil).
3. T3 — 과다입금 note 저장 문구·일반/부분/마감 후 재입금 note nil·감사 병행·digest 2행째 RecordNotUnique·일반 message_logs 동일 키 영향 0·과다입금 후 상세 페이지 비고 표시·DELETE 라우트 부재(recognize_path).
4. T1 — 3문서 라우트 200·noindex 미출력(공개 허용)·핵심 문구 포함(300원·5,000원·20%·세무 자문 아님·바로빌·취소 과금).
