# 00_delegation_log — F-EMAIL 자체 메일 API 연동 (2026-11-20, 일반 모드)

- Phase 3·5·7 위임 실측 기록 예정
- Phase 3 Developer(일반, 2026-11-20): 신규 4(래퍼·ApiError·배달 방식·initializer)+수정 2(production.rb — 배달 방식·raise_errors·default_url_options badeuldon.kr 교정/application_mailer) — 메일러·호출부 0줄 수정·message_id nil 실측→렌더 SHA-256 멱등 키로 교체(편차 사유 03 문서)·스모크 26항목 PASS.
- Phase 5 Reviewer(일반, 2026-11-20): CHANGES_REQUESTED — C1(내용 해시 키가 반복 이벤트[신규 IP·재잠금]를 영구 흡수 — AUTH-7.4 즉시 통보 무음 위반·잡 ID 키 승격 권고)·W6. 통과: 폴백 안전·부트 순서·재설정 링크 재발송=새 메일(AUTH-8 무위반) 판정.
- Phase 6 Developer(일반, 2026-11-20): C-1 잡 키 전환(DeliveryJob 신규·retry_on retryable? 5회·헤더 우선→내용 해시 폴백)+W3/4/6·PRD W-1 문구 갱신(오케스트레이터)·from 상수 폴백(3 errors 근본 차단 — 1,399 runs 0 failures).
- Phase 7b Developer(재개): settings 접근자 방어 1행 — bang 경로 stub 재현 검증·39 runs 유지.
- Phase 8/9(오케스트레이터): 부트·배달 방식 등록·폴백 확인·08_run_report·AGENTS(완료 항목·예정·병렬 후보)·progress 리셋.
- 커밋 전 게이트 실패 3건(2026-11-20): 사용자가 로컬 credentials에 outbound_mail 블록 등록 → "부재 전제" 테스트 3건이 환경 의존 실패(테스트 결함·코드 무관) — Tester에 밀봉 수정 위임.
