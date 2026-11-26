# 탈퇴 회원 결제 기록 비식별 사본의 보존 기간 만료 파기(AUTH-1.5·ADMIN-3 — 결정 기록 Q33,
# 2026-11-26). WithdrawnPaymentRecord는 5년(RETENTION — 법정 보존 가장 보수 기준)이 지난 뒤
# 파기 대상이 된다. WithdrawnPaymentRecord.expired 스코프가 기준의 단일 출처. delete_all 배치
# 삭제로 멱등 — 몇 번 다시 돌아도 이미 삭제된 행은 대상에서 제외된다. 매일 04:35 KST
# (config/recurring.yml — 04:30 휴대폰 인증 파기 잡과 5분 간격).
module WithdrawnPaymentRecords
  class PurgeJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::Deadlocked

    def perform
      deleted = WithdrawnPaymentRecord.expired.delete_all
      # P4 정신 — 운영 확인 가능하게 삭제 건수만 기록(개인정보·주문번호 값은 남기지 않는다).
      Rails.logger.info("[WithdrawnPaymentRecords::PurgeJob] purged=#{deleted}")
      deleted
    end
  end
end
