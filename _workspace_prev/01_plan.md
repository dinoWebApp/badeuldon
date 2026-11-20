# 01_plan — 정책 문서 갱신·인프라·기술 부채 병렬 배치 (2026-11-20, §6.14 · 일반 모드)

## Phase 0 조사 결과

- 약관 3종(/terms·/privacy·/refund)은 **기 구현**(2026-10-15 시행본·F-PLAN 시대) → 태스크는 신기능 반영 **갱신**
- payments.note·message_logs 인덱스·routes destroy 등 기술 부채 4건 확인

## 태스크 분해 (§6.14 3조건 판정)

| 태스크 | 내용 | 소유 파일 | 판정 |
|---|---|---|---|
| **T1 정책 문서 갱신** | ① 개인정보처리방침: **수집 항목 표 갱신** — 휴대폰번호(필수·AUTH-9 인증)·이메일(재설정)·추천 코드 어트리뷰션·**바로빌 제3자 제공**(회원사 가입 정보·공동인증서 등록 안내·발행 이력) ② 이용약관: 유료 부가서비스 조항 갱신 — 내용증명 건당 5,000원(LEGAL-2)·전자세금계산서 건당 300원(Q21)·추천 코드 할인 20%(Q24)·세금계산서는 세무 자문 아님(TAX 고지) ③ 환불: 유지(월 구독 특성) — 수정일 갱신 | `app/views/pages/{terms,privacy,refund}.html.erb` | ✓ 독립 |
| **T2 운영 인프라(오케스트레이터 직접)** | ① **SQLite 백업 자동화**: 서버 systemd timer + `.backup` 스크립트(일 1회·30일 보존·/home/kgj/backups) 설치·실측 ② CF 터널 토큰 로테이션·HSTS 절차 문서화(사용자 수동 — CF 대시보드) | 서버 파일(저장소 비침범) | ✓ 파일 무충돌 |
| **T3 기술 부채-DB** | ① `payments.note`(Q22 — 과다입금 초과분 비고 구조화·RecordService 저장·감사 기록 병행) ② `message_logs` digest 멱등 부분 유니크 인덱스(리뷰 W-1) ③ routes `except: :destroy`(sales_reps — 관찰⑤) | `db/migrate/*(1건 통합)`·`app/models/payment.rb`·`app/services/payments/record_service.rb`·과다입금 뷰·`config/routes.rb` | ✓ (routes는 T3 단독) |
| **T4 솔라피 잔액 모니터링** | 래퍼 `get_balance`(Cash API — 잔액· Points) + ADMIN-5 대시보드 표시·임계치(예: 5만원 미만 주황) — **라이브 읽기 전용 실측 포함**(무료·안전) | `app/services/solapi/client_service.rb`·`app/controllers/admin/dashboards_controller.rb`·admin 대시보드 뷰 | ✓ |

- Phase 2(오케스트레이터): PRD v0.44 — NOTI-2 집계 기간 문언 확정(구현=직전 7일 기준·W-2 해소)·정책 문서 갱신 명시·Q 신규 없음
- 파이프라인: 0✓→1-P✓→✋multiSelect→2→3-P(상한 3·T1/T3/T4 → T2는 오케스트레이터 병행)→3-S(마이그레이션 T3 단독 확정)→4→5→6?→7→8→9

## 리스크

1. T1 법률 검토 — 그룹 리소스가 아닌 **법무 검토는 사용자 별도 확인 필요**(안내 문구 유지·기존 양식 수준에서 갱신)
2. T4 라이브 잔액 API 스펙 [INFERENCE] — 실측 실패 시 표시 숨김 처리로 방어
3. T2 백업 — 서버 직접 조작(SSH)·타이머 상태 실측까지 검증
