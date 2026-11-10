module NoticeReads
  # ADMIN-7 공지 읽음 기록 — find_or_create_by 멱등(02 확정 해석 1·SEC-5 성격).
  # 배너 닫기·팝업 확인·mark_read endpoint가 모두 이 진입점을 경유한다. 이미 읽었어도
  # 실패하지 않는다(재노출 방지가 목적 — 유니크 제약 위반을 애플리케이션에서 회피).
  class MarkService
    Result = Data.define(:notice_read, :created, :errors)

    def self.call(user:, notice:)
      notice_read = user.notice_reads.find_or_create_by!(notice: notice)
      Result.new(notice_read:, created: notice_read.previously_new_record?, errors: [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(notice_read: e.record, created: false, errors: e.record.errors.full_messages)
    end
  end
end
