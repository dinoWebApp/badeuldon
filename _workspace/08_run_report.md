# 08_run_report — F-REM 실행 검증 (2026-11-04, Phase 8 — 오케스트레이터 직접)

## 부트

- 환경 특이: 월요일 세션의 stale Puma(pid 85135·포트 3999)가 `tmp/pids/server.pid`를 점유해
  `bin/dev`(포트 3000) 부팅 거부됨 — 사용자 프로세스이므로 **건드리지 않고** 검증 전용 인스턴스를
  `bin/rails server -p 3001 -P tmp/pids/server_3001.pid`(pid 파일 분리)로 기동해 우회.
- 부트 로그: Puma 정상 기동·Rails 8.1.4 development — **WARN/deprecated 0건** [허용/수정/주의 분류 대상 없음]
- 마이그레이션 3종(20261104000001~3) 개발 DB 적용 완료(db:prepare·db:migrate:status up 확인 — Phase 4)

## 경로 실측 (curl)

| 경로 | 기대 | 실측 | 판정 |
|---|---|---|---|
| `GET /`(랜딩) | 200 | 200 | 통과 |
| `GET /up`(헬스) | 200 | 200 | 통과 |
| `GET /app`(대시보드) | 302 로그인 리다이렉트 | 302 | 통과 |
| `GET /b/nonexistent-token-123`(뷰어) | 404(VIEW-6 수렴) | 404 | 통과 |
| `GET /terms`(공개 정적) | 200 | 200 | 통과 |

## 신규 라우트 등록 확인 (`bin/rails routes`)

- `PATCH /app/invoices/:id/suspend_reminders`·`resume_reminders`, `POST /app/invoices/:id/remind`·`restart_reminders`
- `PATCH /app/clients/:id/suspend_reminders`·`resume_reminders`
- `GET /b/:token/refusal_thanks`

전부 의도 라우팅·컨트롤러 액션과 일치.

## 정리

- 검증 서버 정상 종료·pid 파일 제거. stale 서버(3999)는 원상 유지(사용자 프로세스 — 필요 시 사용자가 직접 종료)
- 시스템 테스트(브라우저 E2E — 뷰어 수신거부·/app 발송 이력)는 Phase 7 Tester가 Selenium으로 검증 완료(628건 0실패)
