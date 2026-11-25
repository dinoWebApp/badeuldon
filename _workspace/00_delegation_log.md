# 00_delegation_log — 관리자 환불 실행 (2026-11-24, 일반 모드)

위임 실측 기록 (규약 §4.6·§8.1) — 스폰 직후 `~/.zcode/cli/rollout/model-io-sess_subagent_agent_*.jsonl`의
`request.body.model`·`request.body.output_config.effort`를 읽어 프로필 정의(`.zcode/agents/`)와 대조했다.
판정은 프로필 정의 대비 일치 여부로만 한다.

| Phase | 프로필 | 정의(모델/effort) | 실측(모델/effort) | 판정 |
|:---|:---|:---|:---|:---|
| 3 구현 | `badeuldon-developer` | GLM-5.3-Flash / high | GLM-5.3-Flash / high | 일치 |
| 5 리뷰 | `badeuldon-reviewer` | GLM-5.4 / high | GLM-5.4 / high | 일치 |
| 6 수정 | `badeuldon-developer` | GLM-5.3-Flash / high | GLM-5.3-Flash / high | 일치 |
| 7 테스트 | `badeuldon-tester` | GLM-5.3-Flash / high | GLM-5.3-Flash / high | 일치 — 1차 호출은 리딩 단계에서 5시간 사용량 한도로 실패(위임 실측은 일치). 규약 에러 대응으로 신규 호출 1회 재시도(2026-11-25) — 재시도도 GLM-5.3-Flash / high 일치 |

## 사고 기록 (2026-11-24 — Phase 5 리뷰 중 포트원 운영 API 실요청)

- **경위**: Reviewer가 임시 재현 테스트에서 `DunningRetryJob.perform_now`를 대역 없이 실행 → 포트원 운영 호스트로
  빌링키 차감 요청 1회(가짜 빌링키 → `BILLING_KEY_NOT_FOUND` 거부, 금전 이동 없음). 별도로 가드 자가검사 중
  `api.portone.io:443` TCP 연결 2회(본문·인증 헤더 없음).
- **오케스트레이터 확인**: 이 Mac의 test 환경은 `config/credentials.yml.enc` + `config/master.key`를 읽어
  **운영과 같은 포트원 API 시크릿**이 로드된다(존재 여부·길이만 확인, 값 미열람). `log/test.log`에 인증 헤더
  0건(시크릿 미노출). 같은 거부 응답이 당일 로그에 3회(어느 실행이었는지는 미구분).
- **기존 결함(이번 변경 밖)**: `test/services/subscriptions/dunning_retry_test.rb:135`가 갱신 잡을 대역 없이
  실행 — 로컬 전체 테스트 1회마다 실요청 1회. 포트원에는 test 환경 실호출 차단 장치가 없었다(솔라피·메일은 있음).
- **대응(Phase 6에 포함 — 승인 계획 밖 안전장치, 사용자에게 즉시 보고)**: `PortOne::ClientService` test 환경
  실호출 차단 가드(솔라피 선례 동일 방식) + `with_http_transport` 플래그 + R3 테스트 대역 감싸기.
- **교훈**: 서브에이전트 지시서에 "실호출 금지·기존 테스트만 실행"을 적어도 임시 테스트로 위반될 수 있다 —
  차단 장치가 없는 외부 서비스에 대해서는 가드를 먼저 갖춘 뒤 서브에이전트에 테스트 실행 권한을 준다.
