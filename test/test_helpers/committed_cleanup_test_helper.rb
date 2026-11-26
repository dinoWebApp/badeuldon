# 트랜잭션 없이(use_transactional_tests = false) 도는 테스트의 teardown용 정리 헬퍼(2026-11-26).
# User 삭제는 AUTH-1.5·Q33 파괴 콜백(prepend)이 결제 기록 사본을 withdrawn_payment_records에
# 남긴다 — 운영에서는 의도(5년 보존)지만 커밋 상태 테스트에서는 보관 테이블에 행이 실제로
# 남는다(회원 식별자가 없어 연쇄 삭제 대상이 아니다). 같은 워커에서 나중에 도는 전역 카운트
# 테스트(WithdrawnPaymentRecordTest 등)에 섞여 순서 의존 실패를 만든다.
# 그래서 주문 키를 먼저 뽑아 두고, 회원을 지운 뒤 그 키의 보관 행을 함께 지운다.
# 트랜잭션 없는 테스트에서 회원을 지울 때는 반드시 이 헬퍼를 쓴다.
module CommittedCleanupTestHelper
  def destroy_committed_user(user)
    return unless user

    pg_order_ids = user.orders.pluck(:pg_order_id)
    user.destroy
    WithdrawnPaymentRecord.where(pg_order_id: pg_order_ids).delete_all
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include CommittedCleanupTestHelper
end
