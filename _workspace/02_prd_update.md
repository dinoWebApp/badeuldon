# 02_prd_update — INV-7+PAY-6 병렬 배치 문서 현행화 (2026-11-11, Phase 2)

PRD v0.35 → **v0.36**. 배치 승인(T-D1·T-D2 + 3-S, Q15~Q17 확정) 반영.

## PRD.md 변경 내역

| 위치 | 변경 요지 |
|---|---|
| 문서 버전 | v0.36 (INV-7 반복 청구 + PAY-6 수금완료 PDF 구현 확정) |
| INV-7 | 구현 확정(Q16) — recurring_invoices+items·발행일 1~28 한정·issue! 플로우 재사용·issue_notice 자동·PLAN-1 한도 적용(skip+사유)·보류 사유 기록 |
| PAY-6 | 구현 확정(Q17) — Prawn+Pretendard OTF·paid 한정·마감 입금일(MAX paid_on)·VIEW-4 뷰어 PDF 별개 후속 명시 |
| NOTI-3 | 구현 확정(Q15) — noti_recurring_issued/held 초안(B-5)·등록 전 skipped(NO_TEMPLATE)·발행 정상·등록 후 자동 활성화 |
| 결정 기록 | Q15(템플릿 미등록 처리)·Q16(한도 적용)·Q17(PDF 기술·범위) 신설 |

## ALIMTALK_TEMPLATES.md

- B-5 절 신설: `noti_recurring_issued`(20번)·`noti_recurring_held`(21번) 초안 — 등록 전 상태 명시
- 헤더 갱신일 2026-11-11

## fan-out 전달 확정 해석

1. **라우트 계약(3-S 결선용)**: T-D1 `resources :recurring_invoices, only: %i[index new create show]` + `member { patch :pause; patch :resume; patch :cancel }` / T-D2 `resources :invoices` 내 `member { get :payment_pdf }`
2. **T-D1 발행 불변식**: 스케줄당 월 1회(next_issue_on==today)·보류·한도 skip은 **반복 스케줄 상태 필드에 사유 기록**(NOTI-3 통보 데이터)·발행은 기존 issue!(PLAN-1·토큰·수금 패스 상속)·발행 후 last/next 갱신은 발행 커밋 성공 후
3. **T-D2 불변식**: paid 아닌 청구 404·본인 소유·한글 OTF 렌더·파일명 한국어
4. **공유 파일**: routes·app nav — 3-S 전용·fan-out 금지
5. 컨트롤러 경유 검증 공백(Run A 교훈): fan-out은 runner 중심, 컨트롤러는 3-S 스모크+Phase 5 리뷰어 재현+Phase 7
