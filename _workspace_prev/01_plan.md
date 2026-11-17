# 01_plan — TAX TESTBED 실측·[INFERENCE] 검증 (2026-11-16, Standard · 절약 모드)

## 배경

TAX-1/2 런(prev workspace)은 stub 수준까지만 검증 — 실 SOAP 전송 계층은 TESTBED에서 0회. release_auth_key가 실키라 운영 발행 경로가 이미 활성 → 첫 실사용자가 실패 지점을 발견하기 전 TESTBED 실측으로 [INFERENCE]를 닫는다. TESTBED는 무료 테스트 포인트라 충전 불요.

## 검증 대상 (prev 03 문서 한계 목록 기준)

| # | 항목 | 실측 방법 | 판정 |
|---|---|---|---|
| I-1 | 공통 API WSDL 파일명(`BAROBILL.asmx` 추정) | WSDL 후보 URL GET → savon 클라이언트 생성 | 200+파싱 성공 |
| I-2 | SOAP 응답 파싱 구조(`{m}_response.{m}_result`) | 실제 호출 1회 이상 성공 | 응답값 도출 |
| I-3 | 공통 API 인증키·호출 규격(연동인증키 1번째 파라미터) | GetCorpState(바로빌 자체 BRN 416-81-38772 — 견적서 공개 정보·계속 영업 중) | 정상 응답 or 명확한 오류 코드 |
| I-4 | RegistCorp 규격(-32000·파라미터·고정값 수용) | 파트너 자신의 BRN으로 호출 → -32000(이미 가입) 기대 | 코드 확인 |
| I-5 | CheckCERTIsValid 호출 규격 | 파트너 BRN으로 호출 → 미등록 응답 기대 | 코드 확인 |
| I-6 | GetBaroBillURL("CERT") | URL 반환 확인 | URL 형식 |
| I-7 | CORPSTATE 서비스(GetCorpStateEx) 상태 코드 | GetCorpStateEx로 I-3 동일 BRN | State 값 기록 |
| I-8 | TI 서비스(문서 명시 `testws.baroservice.com/TI.asmx`) | GetTaxInvoiceState(더미 mgt_num) | "없음" 오류 코드 확인 |

- 실발행(RegistAndIssueTaxInvoice)은 TESTBED 회원사+공동인증서 등록이 선행 — 인증서 파일은 사용자 소유물이라 자동화 불가. **자동 실측은 I-1~I-8까지, 실발행 E2E는 사용자 협조(테스트 인증서) 후 별도**로 명시.
- 진단용 사업자번호: 바로빌((주)케이넷) 416-81-38772 — 견적서·문서에 공개된 정보로 읽기 전용 조회만 사용. RegistCorp 프로브는 -32000 기대라 레코드 생성 없음.

## 실행 방식 (Phase 3)

- **오케스트레이터가 직접 실행**(기계적 검증 성격 — `bin/rails runner`로 로컬 부트 + TESTBED 키 사용). 코드 수정이 필요해지면 그 시점에 Developer-lite 위임(Phase 3 분기).
- 엔드포인트 후보 탐색: 문서 재조사 + URL probe(`BAROBILL.asmx` 실패 시 대안 후보 순차 시도 — 결과를 모두 기록).

## 산출물

- `_workspace/03_verification.md` — [INFERENCE]별 실측 결과(요청·응답·판정)·수정 사항
- 코드 수정 시 `_workspace/03_implementation.md` 별도 + 테스트는 Phase 7(Tester) 영역
- Phase 2: PRD 버전 갱신(사유: TESTBED 실측 진행) — 실측 확정 문장은 결과 반영 후 동일 버전 내 갱신

## 리스크

1. WSDL 후보 전부 실패 가능 — 그 경우 바로빌 기술문의(070-4040-5711)에 문의할 질문 목록을 산출물로 남기고 사용자 보고(런은 여기서 종료)
2. TESTBED 포인트 소진 — 무료 포인트로 I-1~I-8 전부 커버 가능하나 실패 시 문의 항목에 추가
3. 실발행 E2E 미커버 — 사용자 협조 필요 항목으로 명시(숨기지 않음)

## Rule ID

TAX-1·TAX-2(구현 확정의 실측 보강)·SEC-5(멱등)·P4(호출·응답 전부 기록) — 신규 Rule ID 없음
