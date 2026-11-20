# 08_run_report — 랜딩 전면 재구성 LP-16 (2026-11-19, Phase 8)

- 부트·렌더: 13섹션 순서 확인(hero→pain→how_it_works→features(앵커)→scenarios→**all_features(신규)**→**sales_program(신규)**→message_samples→control→pricing→LP-14 커버→faq(12문)→final CTA) — 전 섹션 렌더 통과
- 라우트 실측:

| 경로 | 기대 | 실측 |
|---|---|---|
| `/` | 200 + 신규 2섹션·FAQ 12문 | 200 ✓ (_all_features 12카드·_sales_program·hero 배지 렌더) |

- 구현 범위 판정(Phase 3): 카드는 수금 워크플로 한정 — dunning(PLAN-5)·이메일(AUTH-8)은 운영 장치라 랜딩 제외. SEC-4 내보내기는 미구현 → "예정" 배지 사실 표기. 수치는 PRD 확정치만(300원·5,000원·4,000원/10건·90일·최대 5통).
- uibowl 관찰 반영: 아이콘+혜택 체크리스트·신규/예정 수치 배지·섹션 끝 CTA 재노출(SURF-4 가입 단일 진입 유지)·정적 마크업(뷰 DB 쿼리 금지).

| 게이트 | 결과 |
|---|---|
| 전체 테스트 | **1,477 runs·0 failures**(+10 — 기존 갱신 3건+신규 10건, landing 41 runs 0실패) |
| rubocop | 변경 .rb 파일 0 offenses |
| 리뷰 | APPROVED(B0·C0·W2 — W-1 헤드라인 완화 "전부입니다"→"한눈에", W-2 알림톡 문구 운영 전제는 02 문서 기록) |
| LP-12 금지 표현 스캔 | 0건 |

- 남음: 커밋·배포(배치 3 산출물과 함께 미커밋 상태) — 사용자 지시 대기.
