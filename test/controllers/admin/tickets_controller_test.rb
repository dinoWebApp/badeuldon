require "test_helper"
require_relative "../../test_helpers/solapi_stubbing"

# ADMIN-8 · ADMIN-2 — Admin::TicketsController 정식 컨트롤러 테스트(W-2 정식화).
# 2FA 실로그인 경유(AUTH-7)·답변 reply(알림톡은 with_solapi_client 차단 — 실호출 금지)·
# blank 답변 거부·종료 close(closed 전환 + ticket_close 감사 1건)·상태·분류 필터·
# U1의 admin 경로 접근 불가(세션 비공유 — Admin::BaseController).
class Admin::TicketsControllerTest < ActionDispatch::IntegrationTest
  include SolapiStubbing
  setup do
    setup_admin_totp_secrets
    @admin = admins(:ops)
    @ticket = Ticket.create!(user: users(:gamma), title: "관리 확인용 문의", category: :billing)
    @ticket.ticket_messages.create!(sender: :user, body: "최초 문의 본문")
  end

  def admin_sign_in
    admin_login(@admin, at: Time.current)
  end

  test "비인증 admin 티켓 목록은 로그인 화면으로 303 리다이렉트 (AUTH-7)" do
    get admin_tickets_path
    assert_redirected_to new_admin_session_url
  end

  test "U1 세션으로는 admin 티켓 경로에 접근할 수 없다 — 세션 비공유 (AUTH-7)" do
    sign_in_as users(:gamma)
    get admin_tickets_path
    assert_redirected_to new_admin_session_url
  end

  test "관리자가 목록·상세를 열 수 있다 — 필터(상태·분류) 동작 (ADMIN-8)" do
    admin_sign_in

    get admin_tickets_path
    assert_response :success
    assert_match "관리 확인용 문의", response.body

    get admin_tickets_path(params: { status: "closed" })
    assert_response :success
    assert_no_match "관리 확인용 문의", response.body

    get admin_tickets_path(params: { category: "billing" })
    assert_match "관리 확인용 문의", response.body
  end

  test "답변 등록 — admin 발화 추가·answered 전환·알림톡 sent 기록 (ADMIN-8·REM-6 확장)" do
    admin_sign_in
    fake = Struct.new(keyword_init: true) do
      def send_alimtalk(template_key:, to:, variables:)
        { messageId: "SOLAPI-ADMIN-1" }
      end
    end.new

    assert_difference -> { TicketMessage.count }, 1 do
      assert_difference -> { MessageLog.count }, 1 do
        with_solapi_client fake do
          post reply_admin_ticket_path(@ticket), params: { ticket_message: { body: "확인했습니다. 답변드립니다." } }
        end
      end
    end

    assert_response :see_other
    assert_redirected_to admin_ticket_path(@ticket)
    assert @ticket.reload.answered?
    reply = @ticket.ticket_messages.ordered.last
    assert reply.admin?
    log = MessageLog.last
    assert log.sent?
    assert_nil log.invoice_id
    assert_equal @ticket.id, log.ticket_id
  end

  test "blank 답변은 거부 — alert·발화·상태 불변" do
    admin_sign_in

    assert_no_difference -> { TicketMessage.count } do
      post reply_admin_ticket_path(@ticket), params: { ticket_message: { body: "  " } }
    end
    assert_response :see_other
    assert_includes flash[:alert], "답변 내용"
    assert @ticket.reload.open?
  end

  test "종료 — closed 전환·ticket_close 감사 1건 (ADMIN-2)" do
    admin_sign_in

    patch close_admin_ticket_path(@ticket)
    assert_response :see_other
    assert_redirected_to admin_tickets_path
    assert @ticket.reload.closed?
    audit = AuditLog.where(action: "ticket_close").sole
    assert_equal "Ticket", audit.target_type
    assert_equal @ticket.id, audit.target_id
    assert_equal @admin.id, audit.admin_id
  end

  test "답변 전 강제 종료도 허용 — 운영 정책 (ADMIN-8)" do
    admin_sign_in
    assert @ticket.open?

    patch close_admin_ticket_path(@ticket)
    assert @ticket.reload.closed?
  end

  test "종료된 티켓 재종료(close)는 멱등 — 감사 중복은 상태가 closed라 재전환 없음" do
    admin_sign_in
    @ticket.mark_closed!
    patch close_admin_ticket_path(@ticket)
    assert @ticket.reload.closed?
  end

  test "admin 이미지 서빙 — 관리자 세션으로 200·비인증은 303 (W-1 admin 측)" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("\x89PNG\r\n\x1a\n" + ("0" * 64)),
      filename: "proof.png", content_type: "image/png"
    )
    message = @ticket.ticket_messages.create!(sender: :user, body: "증빙 첨부")
    message.image.attach(blob)

    get admin_ticket_message_image_path(@ticket, message)
    assert_redirected_to new_admin_session_url # 비인증 — admin 가드

    admin_sign_in
    get admin_ticket_message_image_path(@ticket, message)
    assert_response :success
    assert_equal "image/png", response.media_type
  end
end
