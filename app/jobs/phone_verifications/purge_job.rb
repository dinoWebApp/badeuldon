# 휴대폰 인증 기록 파기 잡(AUTH-9 — 2026-11-26 PRD 구현 확정). 인증 기록 행
# (phone_verifications — 전화번호·코드)은 rate limit(1분·1시간)·가입 이중 검증(30분)·
# 코드 유효(5분) 창이 모두 지난 뒤 보존 목적이 없으므로(감사 대상 아님 — 단기 인증 용도
# 데이터, 개인정보 파기 의무 관점) 매일 새벽 생성 24시간 경과 행을 전량 삭제한다.
# PhoneVerification.purgeable 스코프가 기준의 단일 출처(PURGE_AFTER). delete_all 배치
# 삭제로 멱등 — 몇 번 다시 돌아도 이미 삭제된 행은 대상에서 제외된다.
module PhoneVerifications
  class PurgeJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::Deadlocked

    def perform
      deleted = PhoneVerification.purgeable.delete_all
      # P4 정신 — 운영 확인 가능하게 삭제 건수만 기록(개인정보 값·번호는 남기지 않는다).
      Rails.logger.info("[PhoneVerifications::PurgeJob] purged=#{deleted}")
      deleted
    end
  end
end
