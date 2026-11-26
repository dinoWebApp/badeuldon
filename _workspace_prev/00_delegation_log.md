# 00_delegation_log — 병렬 배치(절약): 후속 과제 뭉치 (2026-11-26, lite 모드·parallel)

위임 실측 기록 (규약 §4.6·§8.1·§6.14) — 스폰 직후 `~/.zcode/cli/rollout/model-io-sess_subagent_agent_*.jsonl`의
`request.body.model`·`request.body.output_config.effort`를 읽어 프로필 정의(`.zcode/agents/`)와 대조한다.
판정은 프로필 정의 대비 일치 여부로만 한다.

실측 정정(2026-11-26 14:20): `badeuldon-reviewer-lite`의 `thoughtLevel: max` 상향(규약 v4.2.2)은 **같은 세션의 다음 스폰부터
바로 적용**됐다 — 리뷰어 4개 스폰 전부 `effort=max` 실측(아래 표). "세션 시작 스캔이라 새 세션부터"라는 사전 예상은 틀렸다
(에이전트 종류의 발견·등록만 세션 시작 스캔 — 기존 프로필의 frontmatter 값은 스폰 시점에 다시 읽힌다).

승인 게이트: 2026-11-26 14:00 AskUserQuestion multiSelect — 사용자가 T1~T5 전부 선택.

| Phase | 태스크 | 프로필 | 정의(모델/effort) | 실측(모델/effort) | 판정 |
|:---|:---|:---|:---|:---|:---|
| 3-P 웨이브1 | T1 인증 기록 파기 잡 | `badeuldon-developer-lite` | GLM-5.3-Flash / low | GLM-5.3-Flash / low | 일치 (14:03 실측) |
| 3-P 웨이브1 | T2 클라이언트 IP 통일 | `badeuldon-developer-lite` | GLM-5.3-Flash / low | GLM-5.3-Flash / low | 일치 (14:03 실측) |
| 3-P 웨이브1 | T3 픽스처 상대 만료일 | `badeuldon-developer-lite` | GLM-5.3-Flash / low | GLM-5.3-Flash / low | 일치 (14:03 실측) |
| 3-P 웨이브2 | T4 수신 거부 번호 고정 | `badeuldon-developer-lite` | GLM-5.3-Flash / low | GLM-5.3-Flash / low | 일치 (14:06 실측 — T1 완료로 빈 슬롯에 선스폰) |
| 3-P 웨이브2 | T5 사전통보 발송 시각 정합 | `badeuldon-developer-lite` | GLM-5.3-Flash / low | GLM-5.3-Flash / low | 일치 (14:09 실측 — T3 1차 완료로 빈 슬롯에 스폰) |
| 3-P 후속 | T3-2 delta_issued 픽스처 폭탄 해소 + 재발 방지 가드 테스트 (SendMessage 재개) | `badeuldon-developer-lite` | GLM-5.3-Flash / low | GLM-5.3-Flash / low | 일치 (14:10 재개분 실측) |
| 4 재확인 | T1·T2 수정분 오케스트레이터 직접 | — | — | 소스 diff 지시대로(PurgeJob·scope·recurring 2블록 / ClientIp.of 신설·적용처 교체·app/ 잔존 request.remote_ip 0건)·영향 테스트 8묶음 86 runs 610 assertions 0 failures(전용 DB tmp/parallel/orch) | |
| 5 리뷰 | T2 클라이언트 IP 통일 | `badeuldon-reviewer-lite` | GLM-5.3-Flash / max (v4.2.2) | GLM-5.3-Flash / max | 일치 (14:18 스폰 — max 상향 첫 실측) |
| 5 리뷰 | T4 수신 거부 번호 고정 | `badeuldon-reviewer-lite` | GLM-5.3-Flash / max | GLM-5.3-Flash / max | 일치 (14:18 스폰) |
| 5 리뷰 | T5 사전통보 정합·SendSchedule 추출 | `badeuldon-reviewer-lite` | GLM-5.3-Flash / max | GLM-5.3-Flash / max | 일치 (14:18 스폰) |
| 5 리뷰 | T1·T3 파기 잡·픽스처·가드 | `badeuldon-reviewer-lite` | GLM-5.3-Flash / max | GLM-5.3-Flash / max | 일치 (14:18 스폰) |
| 6 수정 | FIX1 리뷰 반영 — ClientIp IPAddr 교체·감사 IP 2곳·주석 보정 | `badeuldon-developer-lite` | GLM-5.3-Flash / low | GLM-5.3-Flash / low | 일치 (14:30 스폰 직후 실측) |
| 6 수정 | FIX2 리뷰 반영 — invoices.yml ERB 상수 → 지역 변수 | `badeuldon-developer-lite` | GLM-5.3-Flash / low | GLM-5.3-Flash / low | 일치 (14:30 스폰 직후 실측) |
| 7 테스트 | A분 — T5 사전통보·T4 수신 거부 번호 고정 (리뷰 Tester 중점 제안) | `badeuldon-tester-lite` | GLM-5.3-Flash / low | GLM-5.3-Flash / low | 일치 (14:33 스폰 직후 실측 — 실행 중) |
| 7 테스트 | B분 — T2 클라이언트 IP·T1 파기 잡·T3 회귀 (리뷰 Tester 중점 제안) | `badeuldon-tester-lite` | GLM-5.3-Flash / low | GLM-5.3-Flash / low | 일치 (14:33 스폰 직후 실측 — 실행 중) |
| 4 재확인 | FIX1·FIX2 수정분 오케스트레이터 직접 | — | — | ClientIp 최종 코드(IPAddr 기반·원문 반환·InvalidAddressError/ArgumentError 폴백)·감사 IP 2곳 추가(ticket_close·coupon_redeemed) diff 확인 / invoices.yml ERB 지역 변수 전환(Developer 보고 115 runs 0 failures·경고 0건) | |
