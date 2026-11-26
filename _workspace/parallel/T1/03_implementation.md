# T1 구현 산출물 — 감사 로그 IP 서비스 계층 12곳 (ADMIN-2·Q32)

## 변경 파일
- 서비스: `app/services/payments/record_service.rb` · `app/services/admins/role_service.rb` · `app/services/admins/member_admin_service.rb` · `app/services/admins/account_purge_service.rb` · `app/services/orders/refund_service.rb`
- 컨트롤러: `app/controllers/app/payments_controller.rb` · `app/controllers/admin/base_controller.rb` · `app/controllers/admin/admins_controller.rb` · `app/controllers/admin/members_controller.rb` · `app/controllers/admin/orders_controller.rb`
- 테스트: 위 서비스 테스트 5파일 + `test/controllers/admin/{members,orders}_controller_test.rb`

## 서비스 시그니처 (전 → 후)
| 서비스 | 전 | 후 |
|:--|:--|:--|
| Payments::RecordService | `new(invoice:, amount:, paid_on:, notify_thanks: true)` | `…, ip: nil` (@ip → 과다입금 감사) |
| Admins::RoleService | 클래스 메서드 `change_role!/unlock!/create_admin!/record_denied!` | 각각 `ip: nil` 추가, 인스턴스 `initialize(ip: nil)` — `denial`→`record_denial` 내부 경로까지 @ip 전달 |
| Admins::MemberAdminService | `change_plan!/toggle_suspension!` | 각각 `ip: nil`, `initialize(ip: nil)` — member_suspend/unsuspend·member_plan_change(3종 private 경유)에 @ip |
| Admins::AccountPurgeService | `call(admin:, user:, confirm_email:)` | `…, ip: nil` — account_purge 감사에 전달 |
| Orders::RefundService | `new(admin:, order:, reason:, client: …)` | `…, ip: nil` — attempt·failed·refund 감사 3종에 @ip |

## 감사 호출 12곳 전수표 (ip 전달 경로: 컨트롤러 `ClientIp.of(request)` → 서비스 → RecordService)
| # | 파일:근처 | action | 경로 |
|:--|:--|:--|:--|
| 1 | payments/record_service.rb audit_over_record | payment_over_recorded | app/payments#create → new(ip:) |
| 2 | admins/role_service.rb record_denied! | admin_console_denied 등 | admin/base_controller#require_owner → ip: |
| 3 | admins/role_service.rb change_role! 내 | admin_role_change | admin/admins#change_role |
| 4 | admins/role_service.rb unlock! 내 | admin_unlock | admin/admins#unlock |
| 5 | admins/role_service.rb create_admin! 내 | admin_create | admin/admins#create |
| 6 | admins/role_service.rb record_denial(인스턴스) | admin_*_denied | 3~5의 staff 거부 분기 — @ip 상속 |
| 7 | admins/member_admin_service.rb toggle_suspension! | member_suspend/unsuspend | admin/members#toggle_suspension |
| 8 | admins/member_admin_service.rb record_plan_change | member_plan_change | admin/members#change_plan(grant/extend/cancel 경유) |
| 9 | admins/account_purge_service.rb call | account_purge | admin/members#destroy |
| 10 | orders/refund_service.rb record_attempt_audit! | order_refund_attempt | admin/orders#refund |
| 11 | orders/refund_service.rb fail_with_audit | order_refund_failed | (동일, 실패·미정산 경로) |
| 12 | orders/refund_service.rb record_audit! | order_refund | (동일, 확정 경로) |

서비스 계층 전수 확인: `app/services` 내 `AuditLogs::RecordService.call` 13곳 중 12곳에 `ip:` 전달 완료. 나머지 1곳(`users/withdrawal_service.rb`)은 T3 소유 파일이라 미수정(별도 판단 필요 — 회원 본인 탈퇴라 관리자 IP 개념이 없는 경로).

## 테스트 (신규 11건)
- 서비스: payments 2(ip 기록·nil 하위호환) / role 3(변경·거부·nil) / member 2(정지·플랜) / purge 2(ip·nil) / refund 2(시도+완료·nil) — `ip: "203.0.113.7"` 단언.
- 컨트롤러 2건: members(정지 감사 ip == CF-Connecting-IP 헤더) / orders(환불 감사 ip == 헤더, with_portone_client 대역).

## 검증 결과
- `DATABASE_URL=sqlite3:tmp/parallel/T1/test.sqlite3 bin/rails test test/services/{payments,admins,orders}` → 107 runs 0 failures.
- 소유 컨트롤러 테스트(admins·members·orders·base_guard·audit_trail·payments 3종) → 0 failures(85+56 runs).
- 전체 소유 디렉터리 실행 시 `test/controllers/app/invoices_controller_test.rb` 1건 실패 — **타 태스크의 `test/fixtures/invoices.yml` 날짜 폭탄 상대값화(병렬 진행 중)로 인한 것으로 T1 무관**(만료 임박 표기 테스트, T1 소유 파일 아님·T1 변경 경로와 무관).
- `bin/rubocop` 소유 19파일 0 offenses · `bin/rails zeitwerk:check` 통과.

## 남은 우려
- `users/withdrawal_service.rb`의 감사 1곳은 T3 소유 — IP 개념 정합성(본인 탈퇴) 판단은 오케스트레이터 몫.
- 병렬 태스크의 fixture 상대값화로 만료 임박 관련 기존 테스트가 깨진 상태 — 통합 단계(3-S)에서 해당 태스크가 정합화해야 한다.
