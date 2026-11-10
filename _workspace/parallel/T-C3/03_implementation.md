# T-C3 구현 산출물 — 계정 삭제·데이터 파기(ADMIN-3 ④·AUTH-1.5 준용·Q13)

## 변경 목록
| 파일 | 변경 |
|---|---|
| app/services/admins/account_purge_service.rb | 신규 — 가드 2종(이메일 2중 확인·미수 차단) + 트랜잭션 내 감사 기록 선행 후 user.destroy! |
| app/controllers/admin/members_controller.rb | destroy 액션 추가(10줄·Service 위임) — 성공 303 → admin_members_path, 실패 303 alert → 상세 |
| app/views/admin/members/show.html.erb | 위험 구역 카드(붉은 톤) — 이메일 타이핑 확인 인풋 + form_with(method: :delete) + turbo_confirm |
| test/services/admins/account_purge_service_test.rb | 신규 4케이스(불일치 거부·미수 차단·연쇄 전수+감사 보존·완납/무효 허용) — 30 assertions 통과 |
| test/controllers/admin/members_controller_test.rb | 최소 회귀 2케이스 추가(정상 삭제 303·미수 차단 상세 복귀) |

## 삭제 불변식
1. 이메일 불일치 → Result 실패, 어떤 쓰기도 없음(user.email은 normalizes 적용값과 strip+downcase 비교).
2. `user.invoices.unsettled`(draft·paid·voided 제외) 존재 → 실패, 메시지에 미수 건수·합계 표기. 계정 유지.
3. 삭제는 단일 트랜잭션: 감사 기록(action `account_purge`, detail에 이메일 스냅샷) 선행 → destroy!. 실패 시 전체 롤백.
4. audit_logs 보존(Q13): admin_id FK만 존재(users 참조 없음 — db/schema.rb 실측, add_foreign_key "audit_logs","admins" 만 존재) → user 삭제로 소멸하지 않음.

## 연쇄 삭제 전수 실측
| 대상 | 경로 | 결과 |
|---|---|---|
| sessions | user.rb dependent: :destroy | 0건 실측(테스트 통과) |
| invoices | dependent: :destroy | 0건 실측 |
| clients | dependent: :destroy | 0건 실측 |
| items | dependent: :destroy | 0건 실측 |
| subscription | has_one dependent: :destroy | 0건 실측 |
| orders | dependent: :destroy + FK cascade | 0건 실측 |
| payment_passes | dependent: :destroy + FK cascade | 0건 실측 |
| notice_reads | dependent: :destroy + FK cascade | 0건 실측 |
| tickets | dependent: :destroy + FK cascade | 0건 실측 |
| message_logs | user에 has_many 없음 — invoices DB FK `on_delete: :cascade`로 invoices 삭제 시 SQL 연쇄. 미수 차단 가드로 발행 이력 있는 계정은 원천 차단되므로 발송 기록(P4) 소실은 초안 전용 계정(발송 이력 자체가 없음)에서만 발생 | 0건 실측 |
| audit_logs | admin 소유 — 보존 | 보존 실측(detail 이메일 스냅샷 검증) |

## 권한 판단(주석 반영)
staff도 실행 가능 — ADMIN-3 회원 관리 권한 선임. 운영 안전은 ①이메일 2중 확인 ②미수 차단 ③감사 기록으로 담보하고 별도 owner 전용 가드를 두지 않음.

## 자기 스코프 검증
- `bin/rubocop`(대상 4파일): no offenses.
- `bin/rails zeitwerk:check`: 통과.
- 서비스 테스트: 4 runs, 30 assertions, 0 failures — 통과.
- 컨트롤러 테스트 실행 보류: 병렬 태스크의 pending 마이그레이션(20261110040001_create_coupons — T-coupon 소유)으로 test 부트가 중단됨. 테스트 코드는 3-S 라우트 결선(`resources :members, only: %i[index show destroy]` 확장)과의 계약으로 작성 — 결선 후 통과 검증은 Phase 5 리뷰어/통합 실행 대상.
- 마이그레이션: 불요(dependent 연쇄 + 기존 FK로 충족 — 신규 생성 없음).
- 임시 레코드: 테스트 트랜잭션 롤백으로 정리 완료, 별도 잔존 없음.

## 라우트 계약(참고용 — routes.rb는 내 소유 아님·3-S 결선)
`resources :members, only: %i[index show destroy]` + 기존 member patches 유지, 헬퍼 DELETE admin_member_path(member). 컨트롤러·뷰·테스트는 이 계약과 일치.
