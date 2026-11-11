# 08_run_report — F-LEGAL/REF 병렬 배치 실행 검증 (2026-11-11, Phase 8)

- 부트: 포트 3002·pid 분리 — Puma 정상·**WARN/deprecated 0건**
- 라우트 실측(전 화면 통합 확인):
  | 경로 | 기대 | 실측 |
  |---|---|---|
  | `GET /up` | 200 | 200 ✓ |
  | `GET /app/legal_documents` | 302(가드) | 302 ✓ |
  | `GET /app/referrals` | 302(가드) | 302 ✓ |
  | `GET /app/recurring_invoices` | 302(가드 — 이전 배치 회귀 없음) | 302 ✓ |
  | `GET /blog` | 200(공개 허브 — 이전 배치) | 200 ✓ |
  | `GET /tools` | 200(공개 도구 — 이전 배치) | 200 ✓ |
- 마이그레이션: orders.item_type(T-F1) 적용 완료 — schema 동기
- 인증 후 화면(LEGAL 과금 체인·REF 소개 화면)은 Phase 7 컨트롤러·Integration 테스트로 검증(0실패)
- 검증 서버 정리 완료

| 게이트 | 결과 |
|---|---|
| 7-S 전체 테스트 | 1,103 runs·0 failures(+15) |
| rubocop | 313 files 0 offenses |
| zeitwerk·migrate | 통과 |
| Phase 5→6→재리뷰 | CHANGES_REQUESTED(B1 metadata 덮어쓰기·C1 워터마크 미구현·C2 중복 결제·W5) → 통합 수정 → **재리뷰 APPROVED**(원 이슈 8건 전건 해소) |
| 위임 실측 | T-F1·T-F2·리뷰·수선·테스트 전부 정의 일치(Flash/low·high) |
