# 02_prd_update — F-REM 문서 현행화 (2026-11-04, Phase 2 — 구현 선행)

승인 게이트에서 확정된 설계 결정 2건(①promise_overdue 종결 ②REM-9 폐기)과 파생 산정 해석을
명세에 반영했다. PRD v0.25 → **v0.26**.

## PRD.md 변경 내역

| 위치 | 변경 | 근거 |
|---|---|---|
| 문서 버전 | v0.26 (F-REM 명세 확정 — REM-9 폐기·REM-13 신설·VIEW-8 보강·PLAN-3 산정 확정, Q9/Q10) | Phase 2 필수 갱신 |
| REM-3 | "초기 구현은 고정값 제공, 세부 지정 UI 후속 구현(기술 부채)" 명시 | 이번 범위 결정 — REM-3 세부 지정 폐기가 아닌 후순위임을 명확히 |
| REM-9 | **폐기**(취소선 처리 — 결정 기록 Q9). 알림톡 사전검수 제약으로 직접 편집 구조적으로 불가. 승인 18종 템플릿 + 청구서별 변수 반영으로 대체. ID 재사용 금지 | 승인 결정 ② — AUTH-1.1 폐기 형식 준용 |
| REM-13 | **신규 등재** — 약속 파기(promise_overdue 1통) 후 시퀀스 자동 종결, final_d14 재개 없음. 재개는 U1 수동 재요청으로만(REM-12 준용) | 승인 결정 ① — 마지막 미확정 설계 항목 해소 |
| VIEW-8 | 표시 가능 요소에 "추가 안내 수신 거부 진입(VIEW-7)" 명시 | 뷰어에 수신거부 링크 추가를 위한 화이트리스트 보강 |
| NOTI-2 | 전용 템플릿 미등록으로 후속 구현(기술 부채) 명시 | 18종에 주간 다이제스트 없음 — 범위 밖 명시 |
| PLAN-3 | **상한 산정 대상 확정**: 시퀀스성 자동 발송(기본·약속 트랙 6종) + 수동 발송(REM-8)만 집계. issue_notice·partial_paid·paid_thanks는 시퀀스 외 1회성으로 제외. 최악 경로 invoice_notice+confirm_d1+requeue_d7+promise_d1+promise_overdue = 5통 정합 | 승인 결정 ① 파생 — ALIMTALK_TEMPLATES 종전 "기본 2통+약속 2통+마무리 1통" 해석 모호성 해소 |
| §10 결정 기록 | Q9(REM-9 폐기)·Q10(promise_overdue 종결 + PLAN-3 산정) 추가 | Rule ID 재사용 금지·결정 근거 문서화 |

## ALIMTALK_TEMPLATES.md 변경 내역

- "발송 트랙" 절: 미확정 설계 항목(promise_overdue 이후 final_d14 재개 여부) → **확정 분으로 교체**(REM-13·Q10 인용)
- 최악 경로 표기를 확정된 산정(시퀀스성 발송 기준 5통, 1회성 3종 제외)으로 갱신

## AGENTS.md

- Phase 9(완료 보고)에서 "구현 진행 상황" 갱신 예정 — 이 단계에서는 미변경(하네스 규약상 구현 완료 후 갱신)

## 구현에 전달하는 확정 해석 (Developer 지시서에 첨부)

1. **상한(PLAN-3)**: `message_logs` 중 recipient_role=debtor·시퀀스성 step·manual origin의 sent
   카운트 ≥ 5 → skip + 사유 기록. issue_notice·partial_paid·paid_thanks는 상한 검사 대상 밖
   (각각 발행·입금기록·마감 이벤트에서 정확히 1회).
2. **멱등(SEC-5)**: 자동 발송은 [invoice_id, step, origin=auto] 1회. 수동(REM-8)은 동일 스텝
   재발송 허용(origin=manual — 상한 내).
3. **REM-3 창**: 채무자 향 발송만 창(평일 09~18) 준수 + 다음 평일 09시 이연. U1 향 noti_*는
   즉시 발송(PERF-1 60초 충돌 회피).
4. **취소 창(REM-11)**: 09:00 사전통보 → 14:00 발송 직전 마감·보류·수신거부 재확인.
5. **overdue 저장화**: 매일 07:00 KST. settled·promised 제외 조건부 UPDATE.
