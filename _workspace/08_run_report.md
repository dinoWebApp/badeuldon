# 08_run_report — F-EMAIL 실행 검증 (2026-11-20, Phase 8)

- 부트: 포트 3009 — Puma Listening·**WARN/deprecated/error 0건**
- 라우트: `GET /passwords/new` 200 ✓(재설정 요청 화면)·`GET /session/new` 200 ✓
- 배달 방식 등록: `ActionMailer::Base.delivery_methods[:outbound_mail_api]` ✓
- 폴백: 로컬 credentials `outbound_mail` 부재 → `configured? false` → 로그 발송 경로 유지 확인(무중단 전환 전제)
- 실발송 0건(stub만) — 첫 실발송은 운영 credentials 등록 후 사용자 요청 재설정 시점([INFERENCE] 5건 그때 해소)

| 게이트 | 결과 |
|---|---|
| 전체 테스트 | **1,438 runs·8,909 assertions·0 failures**(+39 — C-1 회귀[새 이벤트 새 키·실제 2회 발송] 포함) |
| rubocop | 406 files 0 offenses |
| 리뷰 루프 | CHANGES_REQUESTED(**C1** 내용 해시 키의 반복 통보 영구 흡수·W6) → Phase 6 잡 키 전환(DeliveryJob·retry_on retryable? 5회)+from 상수 폴백(3 errors 차단)+settings 접근자 방어 → CRITICAL 경계(재리뷰 면제) → Phase 7 통과 |
| [INFERENCE] | 오류 본문 형식·202 data 상세·null 수용·429 본문·한글 Display Name — 첫 실발송 시 |
