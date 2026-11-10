require "test_helper"

# ADMIN-8 — Tickets::CreateService. 티켓 헤더 + 첫 발화(sender=user) 1트랜잭션 생성,
# Result 성공/실패, 이미지 선택 첨부(검증은 TicketMessage 위임), 화이트리스트 밖 분류는
# 컨트롤러가 etc 귀속(서비스는 전달값 그대로).
class Tickets::CreateServiceTest < ActiveSupport::TestCase
  test "성공 — 티켓 open·첫 발화 sender=user 생성" do
    user = users(:gamma)

    assert_difference -> { Ticket.count } => 1, -> { TicketMessage.count } => 1 do
      result = Tickets::CreateService.call(user:, category: "bug", title: "버그 제보", body: "재현 절차…")

      assert result.success
      assert_empty result.errors
      assert result.ticket.open?
      assert result.ticket.bug?
      message = result.ticket.ticket_messages.sole
      assert message.user?
      assert_equal "재현 절차…", message.body
    end
  end

  test "이미지 첨부 선택 — 전달 시 첫 발화에 붙는다" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("\x89PNG\r\n\x1a\n" + ("0" * 64)),
      filename: "proof.png", content_type: "image/png"
    )
    result = Tickets::CreateService.call(user: users(:gamma), category: "bug",
                                         title: "첨부 문의", body: "내용", image: blob)
    assert result.success
    assert result.ticket.ticket_messages.sole.image.attached?
  end

  test "검증 실패 — Result failure·errors 적재·티켓 생성 안 됨" do
    user = users(:gamma)

    assert_no_difference -> { Ticket.count } do
      result = Tickets::CreateService.call(user:, category: "bug", title: "", body: "")

      assert_not result.success
      assert_predicate result.errors, :present?
    end
  end

  test "제목 101자·본문 2,001자는 실패 (ADMIN-8 상한)" do
    result = Tickets::CreateService.call(user: users(:gamma), category: "etc",
                                         title: "a" * 101, body: "b" * 2_001)
    assert_not result.success
    assert_predicate result.errors, :present? # 제목·본문 상한 검증 오류가 errors로 합쳐 반환된다
  end

  test "이미지 검증 실패(gif) 시에도 Result failure — 트랜잭션 롤백" do
    assert_no_difference -> { Ticket.count } do
      result = Tickets::CreateService.call(
        user: users(:gamma), category: "bug", title: "gif 첨부", body: "내용",
        image: ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("GIF89a" + ("0" * 12)), filename: "a.gif", content_type: "image/gif"
        )
      )
      assert_not result.success
      assert result.errors.any? { |e| e.include?("JPG") }
    end
  end
end
