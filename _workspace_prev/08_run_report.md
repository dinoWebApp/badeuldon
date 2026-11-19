# 08_run_report — 기능 잔여·기술 부채 병렬 배치 실행 검증 (2026-11-16, Phase 8)

- 부트: 포트 3004·rails server 직접 — **Puma Listening 확인·WARN/deprecated 0건**
- 마이그레이션: 3-S 통합 1건 적용(users 4컬럼·subscriptions 3컬럼·message_logs digest·view_events 복합 인덱스) — Phase 4/3-S에서 실측 완료
- 라우트 실측:

| 경로 | 기대 | 실측 |
|---|---|---|
| `PATCH /app/notification_settings` | 존재(T7 토글 저장) | ✓(GET 404는 update-only 정상) |
| `GET /app`·`GET /app/invoices` | 302(가드 — 회귀 없음) | 302 ✓ |

- 인증 후 화면(프로필 알림 설정 섹션·토글 파셜·dunning ADMIN 표시)은 Phase 7 통합 테스트로 검증
- 주간 다이제스트: NO_TEMPLATE skip 기록 실측(runner 실행 — MessageLog 기록·솔라피 호출 0)

| 게이트 | 결과 |
|---|---|
| 7-S 전체 테스트 | **1,241 runs·7,047 assertions·0 failures·0 errors**(기존 1,183 + 신규 58건 — 6태스크 시나리오+Q22·Q23) |
| rubocop | 354 files 0 offenses |
| 리뷰 루프 | CHANGES_REQUESTED(B1 결제 500·C3 dunning 3건·W7) → Phase 6 수정 → **재리뷰 APPROVED** → Phase 7 분기 코드 버그 BUG-1~4+파생 2건 수정 → 게이트 그린 |
| 병렬 충돌 | T6·T8 공동 편집 파일(send_service.rb) 마커 0·양 변경 공존 논리 정합(리뷰 특별 검증 통과) |
| 위임 실측 | Developer/Reviewer/Tester lite — model-io 로그 휘발·미기록 이례 지속(00_delegation_log 정직 기록) |
