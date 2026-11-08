# T4 — 거래처 삭제 시 발송 이력 보존(P4 가드) 구현 산출물

날짜: 2026-11-09 · 웨이브: 2차(T4) · 마이그레이션: 없음(모델 가드, 확정 설계 준수)

## 변경 파일

1. `app/models/client.rb` — `before_destroy :prevent_destroy_with_issued_invoices` 가드 추가
   - 발행 계열 청구(`Invoice.where(client_id: id).where.not(status: :draft).exists?`) 존재 시
     `errors.add(:base, "발행 이력이 있는 거래처는 삭제할 수 없습니다. 기록 보존을 위해 삭제가 차단됩니다")` + `throw(:abort)`
   - 초안(draft)만 보유 시: 초안을 `destroy_all`로 소거 후 삭제 허용
   - 주의: Client에는 `has_many :invoices` 연관이 없다(user 경유 삭제 순서 보장을 위해 선언 생략된 기존 구조).
     → FK 연쇄 삭제가 없어 초안 전용 거래처 삭제 시 FOREIGN KEY 제약이 실패한다. 이에 초안 소거를 가드 내에서
     수행한다(invocie.rb·마이그레이션 수정 없이 화이트리스트 내 해결). 초안은 INV-6상 삭제 가능 객체라 무해.
   - 사용자 탈퇴 연쇄(AUTH-1.5): user.rb 연관 선언 순서상 invoices가 clients보다 먼저 삭제되어
     가드 조건이 충족되지 않음 — 충돌 없음(테스트로 검증).
2. `app/controllers/app/clients_controller.rb` — `destroy`를 `destroy!` → `destroy` 분기로 변경
   - 성공: 기존대로 303 + notice "거래처가 삭제되었습니다."
   - 실패(가드 abort): 303 + `alert: errors.full_messages` (기존 redirect 응답 패턴 준용)
3. `test/models/client_test.rb` — 신규 4 케이스 + 헬퍼
   - 발행 계열(issued) 보유 거래처 삭제 차단 + base 오류 문구 검증
   - 초안 전용 거래처 삭제 성공
   - 청구서 없는 거래처 삭제 성공(정상 경로 유지)
   - 사용자 탈퇴 연쇄와 가드 무충돌(AUTH-1.5)
4. `test/controllers/app/clients_controller_test.rb` — 신규 2 케이스 + 헬퍼
   - 발행 이력 보유 거래처 DELETE → 303 + flash alert + 레코드 보존
   - 초안 전용 거래처 DELETE → 303 + notice + 레코드 제거

## 가드 조건

`status != :draft`인 Invoice가 1건이라도 존재하면 삭제 차단 — issued·viewed·overdue·promised·
partially_paid·paid·voided 전부 발행 계열(INV-6 VOIDABLE 정의와 동일 발행 분기)로 취급해
message_logs 보존(P4)을 보장한다.

## 자기 스코프 검증 결과

- `bin/rails test test/models/client_test.rb test/controllers/app/clients_controller_test.rb`:
  44 runs, 233 assertions, **6 failures, 0 errors**
  - T4 신규 6 케이스 + 기존 삭제·한도 회수·탈퇴 연쇄 테스트 전부 통과
  - 잔여 6 failures는 **선존 실패**(내 변경과 무관): 1차 웨이브 ko locale 작업물
    (`config/application.rb` + `config/locales/ko.yml`)이 검증 메시지를 공통 문구
    ("내용을 입력해 주세요"/"올바르지 않은 값입니다")로 덮어써 발생. stash 검증으로 확인 —
    해당 파일은 화이트리스트 밖이라 수정하지 않음(담당 태스크 스코프).
- `bin/rubocop` (4개 소유 파일): **no offenses**
- 마이그레이션·부트 체크: 스키마 변경 없음(모델 가드) — 불요
