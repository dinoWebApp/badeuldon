# 08_run_report.md — Phase 8 실행 검증 (F-PLAN)

- **일자**: 2026-10-15 · 운영 버전 `b1c294c`

## 운영 실측 (https://badeuldon.kr)

| 검증 | 결과 |
|:---|:---|
| 랜딩 | ✅ 200 |
| `/up` | ✅ 200 |
| `/app/billing` 비인증 | ✅ 302 → 로그인 |
| 웹훅 `POST /webhooks/toss` | ✅ 200 (토스 규격) |
| 마이그레이션 | ✅ v20261015000002 (subscriptions·orders·payment_passes) |

## 로컬 러너·테스트 검증

- 체험→카드 등록→활성→해지→만료 전 생명주기 통과
- 병렬 갱신 with_lock 1회 차감 실측
- 수금 패스 10건 사용→11번째 차단
- 모호 실패 pending 유지·웹훅 회복 경로 확인

## 결론

실행 검증 **통과** — Phase 9 진행.
