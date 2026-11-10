require "test_helper"

# ADMIN-8 · ADMIN-9 — App::TicketsController 정식 컨트롤러 테스트(W-2 정식화).
# 작성 303·검증 실패 422·FAQ 선노출·소유 스코프 404·추가 질문(closed 거부 alert)·
# 분류 화이트리스트 밖 etc 귀속·rate_limit 미검증(429 — 실 스토어 주입 필요·격리 노트는
# 03_implementation §3-b 및 05_review §4-2 참조).
class App::TicketsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:gamma)
    sign_in_as @user
  end

  test "작성 성공 — 303 상세로 리다이렉트·open (ADMIN-8)" do
    assert_difference -> { Ticket.count }, 1 do
      post app_tickets_path, params: { ticket: { category: "billing", title: "결제 문의", body: "카드 등록 오류" } }
    end
    assert_response :see_other
    ticket = Ticket.last
    assert_redirected_to app_ticket_path(ticket)
    assert ticket.open?
    assert ticket.billing?
  end

  test "작성 화면에 FAQ가 선노출된다 (ADMIN-9)" do
    get new_app_ticket_path
    assert_response :success
    assert_match "자주 묻는 질문", response.body
  end

  test "검증 실패 — 422 재렌더·티켓 생성 안 됨 (응답 전략)" do
    assert_no_difference -> { Ticket.count } do
      post app_tickets_path, params: { ticket: { category: "bug", title: "", body: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "본문 2,001자·제목 101자는 422 (ADMIN-8 상한)" do
    post app_tickets_path, params: { ticket: { category: "bug", title: "a" * 101, body: "본문" } }
    assert_response :unprocessable_entity

    post app_tickets_path, params: { ticket: { category: "bug", title: "제목", body: "a" * 2_001 } }
    assert_response :unprocessable_entity
  end

  test "분류 화이트리스트 밖 값은 etc로 귀속된다 (enum ArgumentError 방지)" do
    post app_tickets_path, params: { ticket: { category: "hacking", title: "이상한 분류", body: "본문" } }
    assert_response :see_other
    assert Ticket.last.etc?
  end

  test "상세 — 본인 티켓은 200·스레드 발화 노출" do
    ticket = Ticket.create!(user: @user, title: "내 문의")
    ticket.ticket_messages.create!(sender: :user, body: "최초 문의")

    get app_ticket_path(ticket)
    assert_response :success
    assert_match "최초 문의", response.body
  end

  test "타인 티켓 상세는 404 — 소유 스코프 (격리)" do
    foreign = Ticket.create!(user: users(:delta), title: "타인 문의")

    get app_ticket_path(foreign)
    assert_response :not_found
  end

  test "추가 질문 — 303·발화 추가·answered 티켓은 open 복귀 (ADMIN-8)" do
    ticket = Ticket.create!(user: @user, title: "재질문", status: :answered)

    assert_difference -> { TicketMessage.count }, 1 do
      post follow_up_app_ticket_path(ticket), params: { ticket: { body: "추가 질문입니다" } }
    end
    assert_response :see_other
    assert ticket.reload.open?
  end

  test "closed 티켓 추가 질문은 거부 — alert 안내·발화 불변 (ADMIN-8)" do
    ticket = Ticket.create!(user: @user, title: "종료된 문의", status: :closed)

    assert_no_difference -> { TicketMessage.count } do
      post follow_up_app_ticket_path(ticket), params: { ticket: { body: "재개" } }
    end
    assert_response :see_other
    assert_redirected_to app_ticket_path(ticket)
    assert_includes flash[:alert], "종료된 문의"
  end

  test "비로그인 작성은 로그인 화면으로 리다이렉트 (AUTH-1)" do
    reset! # 세션 해제 — 비로그인 재현
    post app_tickets_path, params: { ticket: { category: "etc", title: "t", body: "b" } }
    assert_redirected_to new_session_path
  end
end
