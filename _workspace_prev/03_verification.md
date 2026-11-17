# 03_verification — 바로빌 엔드포인트 [INFERENCE] 오답 최소 수정

## 실측 결과(2026-11-16)

- **I-1 판정**: [INFERENCE] 오답 확정 — `https://testws.baroservice.com/BAROBILL.asmx?WSDL`은 **404**(존재하지 않음).
- **공통 API 위치 확정**: RegistCorp·GetBaroBillURL·CheckCERTIsValid·GetCorpMemberContacts 등 공통 오퍼레이션은 전용 asmx가 없고 **각 서비스 asmx WSDL에 포함**된다 — TI.asmx·CORPSTATE.asmx 양쪽 WSDL에서 14회씩 검출 확인.
- **서비스 asmx 실측**: CORPSTATE.asmx — GetCorpStateEx·GetCorpState 존재 / TI.asmx — RegistAndIssueTaxInvoice·GetTaxInvoiceStateEX·ProcTaxInvoice 존재.
- **I-2 SOAP 응답 파싱** — Savon::Response는 `.body` 경유 필요(실측 발견 B-2·수정 완료): `get_corp_state`·`get_tax_invoice_state`의 `response.dig(...)` → `response.body.dig(...)`로 1단계 추가(Savon::Response에 dig 없음 — 실측 에러 `undefined method 'dig' for an instance of Savon::Response`). `soap_result`는 이미 `response.body[...]`라 수정 불요. 참고: GetCorpStateEx 호출 자체는 TESTBED 성공(전송·WSDL·인증키 정상) — 파싱만 실패.
- **대응**: 공통 호출(`call_common`·`call_common_returning_url`)의 WSDL을 BAROBILL.asmx → **TI.asmx**로 변경.

## 수정 내역 (최소 수정 — 로직 변경 없음)

1. `app/services/baro_bill/client_service.rb`
   - `call_common`: `soap_result(wsdl("BAROBILL"), ...)` → `soap_result(wsdl("TI"), ...)`
   - `call_common_returning_url`: `soap_result(wsdl("BAROBILL"), ...)` → `soap_result(wsdl("TI"), ...)`
   - 상단 주석 블록: 엔드포인트 설명에서 BAROBILL.asmx 제거, [INFERENCE] 제거 — 공통 API는 각 서비스 asmx에 포함(2026-11-16 TESTBED 실측 — BAROBILL.asmx는 404)·공통 호출은 TI.asmx 사용으로 갱신
2. `test/services/baro_bill/client_service_test.rb` — 기대 WSDL 문자열만 수정(3곳: register_corp·check_cert_is_valid·release 환경 전환 → TI.asmx)

변경 외 파일·로직 수정 없음. 커밋 안 함(지시).

## 자가 검증

- `bin/rubocop` (대상 2파일): 2 files inspected, no offenses
- `bin/rails zeitwerk:check`: Otherwise, all is good!
- `bin/rails test test/services/baro_bill/client_service_test.rb`: 8 runs, 29 assertions, 0 failures, 0 errors (B-2 수정 후 재검증 포함 — 스텁이 body 경유 dig를 이미 충족해 테스트 수정 불요)

## I-3~I-8 실측 결과 (2026-11-16 — B-1·B-2 수정 후 rails runner 라이브 프로브 P1~P6)

| 프로브 | 대상 | 결과 | 판정 |
|---|---|---|---|
| P1 | GetCorpState(더미 CorpNum) | ApiError code=**-10001** | ✓ 전송·파싱·오류 정규화 정상 |
| P2 | RegistCorp(가공 BRN 9999999999) | ApiError code=**-32001** | ✓ 엔드포인트 도달·서버측 파라미터 검증 작동 |
| P3 | GetCorpState(생성 시도 회원) | ApiError code=-10001 | ✓ (회원 미생성 상태라 동일) |
| P4 | CheckCERTIsValid(미등록 회원) | ApiError code=-10001 | ✓ 호출 규격 도달 |
| P5 | GetBaroBillURL(CERT) | ApiError code=-10001 | ✓ URL 반환 경로 도달 |
| P6 | GetTaxInvoiceState(더미 mgt_num) | ApiError code=-10001 | ✓ TI.asmx 전송·파싱 정상 |

- **오류코드 실측 확정**(공식 오류코드 레퍼런스 대조): `-10001` = "해당 인증키와 연결된 연계사가 아님"(더미·미연결 회원이라 기대 동작)·`-32001` = "사업자번호가 유효하지 않음"(가공 BRN 거부 — RegistCorp 파라미터 검증이 서버에서 작동하는 증거)·`-32000` = "이미 가입된 연계사업자"(문서 일치).
- **판정**: TESTBED 전송 계층(엔드포인트·WSDL 파싱·인증키 수용·요청 직렬화·응답 파싱·오류 정규화) **전부 실측 검증 완료**. 호출당 오류 코드가 정규화되어 반환되는 것까지 확인 — 코드 결함 0 잔여.
- **잔여 갭(코드 불요 — 사용자 데이터 의존)**: ① 실제 사업자번호(벨로루프)로 RegistCorp 성공 경로 ② 실제 공동인증서 등록 후 CheckCERTIsValid=1·RegistAndIssueTaxInvoice 실발행 ③ GetCorpStateEx State 값 실측(연결 회원 필요). 운영 포인트 충전 전에는 RELEASE 호출도 어차피 거부되므로, 실서비스 개시 순서: 포인트 충전 → (권장) 실 BRN으로 RegistCorp+GetCorpState 1회 스모크 → 서비스 오픈.
- **전체 회귀**: rubocop 342파일 0 offense·zeitwerk 통과·**전체 테스트 1,183 runs 0 failures**(수정 2건 반영 확인).
