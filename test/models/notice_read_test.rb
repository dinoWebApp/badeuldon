require "test_helper"

# ADMIN-7 — NoticeRead 복합 유니크([user_id, notice_id])와 멱등(SEC-5 성격).
# 실제 기록 경로는 NoticeReads::MarkService 단일 진입점 — 모델 계층에서는 제약·검증을 검증한다.
class NoticeReadTest < ActiveSupport::TestCase
  test "복합 유니크 — 동일 사용자·공지 재기록은 무효 (SEC-5)" do
    user = users(:gamma)
    notice = notices(:important_active) # gamma 미읽음 건
    NoticeRead.create!(user:, notice:)

    duplicate = NoticeRead.new(user:, notice:)
    assert duplicate.invalid?
    assert_not_nil duplicate.errors[:user_id]
  end

  test "다른 공지·다른 사용자 조합은 허용된다" do
    assert NoticeRead.new(user: users(:gamma), notice: notices(:important_active)).valid?
    assert NoticeRead.new(user: users(:delta), notice: notices(:general_active)).valid?
  end

  test "MarkService 경유 재호출은 레코드 1건 유지 — 모델 제약과 서비스 멱등의 이중 방어 (SEC-5)" do
    user = users(:gamma)
    notice = notices(:important_active)

    assert_difference -> { NoticeRead.count }, 1 do
      2.times { NoticeReads::MarkService.call(user:, notice:) }
    end
  end
end
