require "test_helper"

# ADMIN-7 — NoticeReads::MarkService 멱등(SEC-5 성격): 동일 호출 2회에도 1건.
class NoticeReads::MarkServiceTest < ActiveSupport::TestCase
  test "읽음 기록을 생성하고 created 플래그를 돌려준다" do
    user = users(:gamma) # general_active는 미읽음(읽은 건 important_active 아님)
    notice = notices(:important_active)

    assert_difference -> { NoticeRead.count }, 1 do
      result = NoticeReads::MarkService.call(user:, notice:)
      assert result.created
      assert result.errors.empty?
    end
    assert user.notice_reads.exists?(notice_id: notice.id)
  end

  test "재호출은 멱등 — 레코드 1건 유지·created false (SEC-5·02 해석 1)" do
    user = users(:gamma)
    notice = notices(:important_active)

    NoticeReads::MarkService.call(user:, notice:)
    assert_no_difference -> { NoticeRead.count } do
      result = NoticeReads::MarkService.call(user:, notice:)
      assert_not result.created
    end
  end

  test "다른 사용자는 별도 읽음 레코드를 가진다 (ADMIN-7)" do
    NoticeReads::MarkService.call(user: users(:gamma), notice: notices(:general_active)) # fixture로 이미 존재
    assert_no_difference -> { NoticeRead.count } do
      NoticeReads::MarkService.call(user: users(:gamma), notice: notices(:general_active))
    end
    assert_difference -> { NoticeRead.count }, 1 do
      NoticeReads::MarkService.call(user: users(:delta), notice: notices(:general_active))
    end
  end
end
