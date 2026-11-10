require "test_helper"

# ADMIN-8 — Ticket 모델. 분류·상태 enum·제목 상한·상태 전이 guard
# (open→answered→open 복귀→closed·종료 후 재개 없음 — 사용자 종료 권한 없음은 PROMISE-7 준용).
class TicketTest < ActiveSupport::TestCase
  def ticket(status: :open)
    tickets_db = Ticket.create!(user: users(:gamma), title: "문의 제목", status:)
    tickets_db
  end

  test "category enum — 5종·기본값 etc (ADMIN-8)" do
    assert_equal "etc", Ticket.new.category
    assert_equal "open", Ticket.new.status

    t = Ticket.create!(user: users(:gamma), title: "분류 확인", category: :billing)
    assert t.billing?
    assert t.open?
  end

  test "title 필수·100자 상한 (ADMIN-8)" do
    assert Ticket.new(user: users(:gamma)).invalid?

    long = Ticket.new(user: users(:gamma), title: "a" * 101)
    assert long.invalid?
    assert_not_nil long.errors[:title]

    assert Ticket.new(user: users(:gamma), title: "a" * 100).valid?
  end

  # ── 상태 전이 guard ──

  test "mark_answered!는 open에서만 유효 — answered·closed에서 무시(멱등)" do
    t = ticket
    t.mark_answered!
    assert t.answered?

    t.mark_answered! # 재호출 — 상태 불변
    assert t.answered?

    closed = ticket(status: :closed)
    closed.mark_answered!
    assert closed.closed?, "closed에서 mark_answered!는 상태를 바꾸지 않는다"
  end

  test "reopen!는 answered에서만 open 복귀 — open·closed에서 무시" do
    t = ticket
    t.reopen!
    assert t.open?, "open에서 reopen!은 상태를 바꾸지 않는다"

    t.mark_answered!
    t.reopen!
    assert t.open?, "answered → open 복귀(스레드 보존)"

    closed = ticket(status: :closed)
    closed.reopen!
    assert closed.closed?, "종료 후 재개 경로 없음 (ADMIN-8)"
  end

  test "mark_closed!는 어느 상태에서든 가능·재호출 멱등 — 관리자만 종료 (ADMIN-8)" do
    t = ticket
    t.mark_closed!
    assert t.closed?
    t.mark_closed!
    assert t.closed?
  end

  test "사용자에게 종료 권한이 없다 — 종료 경로는 admin 컨트롤러뿐 (PROMISE-7 준용)" do
    # 모델 계층 확인: 사용자 향 서비스(FollowUpService)는 closed 진입 경로가 없다.
    refute Tickets::FollowUpService.instance_methods(false).include?(:close)
    assert Admin::TicketsController.instance_methods(false).include?(:close)
  end

  test "티켓 삭제 시 메시지 연쇄 삭제 (dependent)" do
    t = ticket
    t.ticket_messages.create!(sender: :user, body: "본문")
    assert_difference -> { TicketMessage.count }, -1 do
      t.destroy
    end
  end
end
