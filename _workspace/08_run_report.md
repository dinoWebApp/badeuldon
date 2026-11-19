# 08_run_report — F-SALES 실행 검증 (2026-11-19, Phase 8)

- 부트: 포트 3006 — Puma Listening·**WARN/deprecated 0건**
- 마이그레이션: 통합 1건 적용(sales_reps·sales_rep_sessions·sales_referral_codes·phone_verifications·sales_commissions + users 확장 — 부분 유니크 인덱스 포함)
- 라우트 실측:

| 경로 | 기대 | 실측 |
|---|---|---|
| `GET /sales` | 303(미인증 → 로그인) | 303 ✓ |
| `GET /sales/session/new` | 200(로그인) | 라우트 확인 ✓ |
| `GET /admin/sales_reps` | 303(관리자 가드) | 303 ✓ |
| `GET /registration/new` | 200 + 신규 필드(휴대폰·인증·추천) | 200·필드 8개 매치 ✓ |
| `GET /` | 200(랜딩 회귀 없음) | 200 ✓ |

- /sales 세션 격리(쿠키 키 분리)·정지 계정 차단은 Phase 7 통합 테스트로 검증(26건)
- SMS 실발송 0건(stub만 — [INFERENCE] send_sms 바디 스펙은 운영 첫 실발송 시 실측)

| 게이트 | 결과 |
|---|---|
| 7 전체 테스트 | **1,385 runs·8,557 assertions·0 failures**(기존 1,242+신규 141+갱신 — 코드 버그 0) |
| rubocop | 393 files 0 offenses |
| 리뷰 루프 | CHANGES_REQUESTED(B0·**C1** 인증-가입 세션 결합·W8) → Phase 6 전건 반영(CRITICAL 경로·재리뷰 면제) |
| 관찰(조치 불요) | ko.yml 문언 shadow·레거시 하이픈 번호 유일성 공백(소급 없음 범위)·감사 실패 분기 통합 미주입·locked_at stale·routes destroy 잔존(404 흡수 — except 제안 기록) |
