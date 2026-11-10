require "test_helper"

# ADMIN-8 — Tickets::FollowUpService. 종료(closed) 전까지 추가 질문 허용(PRD 원문 준용),
# answered → open 복귀(스레드 보존), open 유지, closed 거부, 타인 티켓은 소유 스코프로 nil.
class Tickets::FollowUpServiceTest < ActiveSupport::TestCase
  def make_ticket(status: :open)
    ticket = Ticket.create!(user: users(:gamma), title: "추가 질문 테스트", status:)
    ticket.ticket_messages.create!(sender: :user, body: "최초 문의")
    ticket
  end

  test "open 티켓 추가 질문 — 발화 추가·상태 open 유지" do
    ticket = make_ticket

    assert_difference -> { TicketMessage.count }, 1 do
      result = Tickets::FollowUpService.call(user: users(:gamma), ticket_id: ticket.id, body: "추가로 궁금합니다")
      assert result.success
      assert result.message.user?
    end
    assert ticket.reload.open?
  end

  test "answered 티켓 추가 질문 — open으로 복귀(스레드 보존 · ADMIN-8)" do
    ticket = make_ticket(status: :answered)

    result = Tickets::FollowUpService.call(user: users(:gamma), ticket_id: ticket.id, body: "답변 감사합니다. 추가 질문")
    assert result.success
    assert ticket.reload.open?
  end

  test "closed 티켓 추가 질문 거부 — 발화 불변 (ADMIN-8)" do
    ticket = make_ticket(status: :closed)

    assert_no_difference -> { TicketMessage.count } do
      result = Tickets::FollowUpService.call(user: users(:gamma), ticket_id: ticket.id, body: "재개 요청")
      assert_not result.success
      assert result.errors.any? { |e| e.include?("종료") }
    end
    assert ticket.reload.closed?
  end

  test "타인 티켓은 소유 스코프에서 찾을 수 없다 — 404 경로 (격리)" do
    ticket = make_ticket

    result = Tickets::FollowUpService.call(user: users(:delta), ticket_id: ticket.id, body: "타인 접근")
    assert_not result.success
    assert_no_difference -> { TicketMessage.count } do
      Tickets::FollowUpService.call(user: users(:delta), ticket_id: ticket.id, body: "재시도")
    end
  end

  test "본문 blank는 검증 실패 — Result errors" do
    ticket = make_ticket

    result = Tickets::FollowUpService.call(user: users(:gamma), ticket_id: ticket.id, body: "")
    assert_not result.success
    assert_predicate result.errors, :present?
  end

  test "본문 2,001자는 검증 실패 (ADMIN-8 상한)" do
    ticket = make_ticket

    result = Tickets::FollowUpService.call(user: users(:gamma), ticket_id: ticket.id, body: "a" * 2_001)
    assert_not result.success
  end
end
