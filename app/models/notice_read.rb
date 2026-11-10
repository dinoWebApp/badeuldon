# 공지 읽음 기록(ADMIN-7). 복합 유니크 [user_id, notice_id] — 중복 읽음 POST에도
# 1건만 유지되는 멱등 설계(SEC-5 성격). 기록은 NoticeReads::MarkService 단일 진입점.
class NoticeRead < ApplicationRecord
  belongs_to :user
  belongs_to :notice

  validates :user_id, uniqueness: { scope: :notice_id }
end
