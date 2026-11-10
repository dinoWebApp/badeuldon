require "test_helper"

# W-1(05_review) — 티켓 첨부 이미지 인증 서빙 재현(Phase 7 정식 티켓 스위트는 W-2로 Tester 인계).
# ① 소유자 200 ② 타 U1 404 ③ 비로그인 302 — AS 공개 리다이렉트(/rails/active_storage/blobs/redirect)
# 대신 /app/tickets/:ticket_id/messages/:message_id/image(소유 스코프·send_data 스트리밍).
class App::TicketsImageServingTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:gamma)
    @ticket = Tickets::CreateService.call(
      user: @owner, category: "bug", title: "증빙 이미지 첨부 문의", body: "내용",
      image: upload_png
    ).ticket
    @message = @ticket.ticket_messages.ordered.last
    @other = users(:delta)
  end

  test "티켓 소유 U1은 첨부 이미지를 200으로 스트리밍받는다 (W-1)" do
    sign_in_as @owner
    get app_ticket_message_image_path(@ticket, @message)
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal @message.image.download.bytesize, response.body.bytesize
  end

  test "타 U1 세션은 타인 티켓 이미지 서빙을 404로 차단한다 (W-1)" do
    sign_in_as @other
    get app_ticket_message_image_path(@ticket, @message)
    assert_response :not_found
  end

  test "비로그인 요청은 로그인 화면으로 리다이렉트된다 (W-1·AUTH-1)" do
    get app_ticket_message_image_path(@ticket, @message)
    assert_redirected_to new_session_path
  end

  test "AS 공개 리다이렉트 URL은 더 이상 뷰에 노출되지 않는다 (W-1)" do
    sign_in_as @owner
    get app_ticket_path(@ticket)
    assert_response :success
    assert_no_match "/rails/active_storage/blobs/redirect/", response.body
    assert_match app_ticket_message_image_path(@ticket, @message), response.body
  end

  private

  # 최소 PNG 시그니처 바이트 — 서빙 스트리밍 재현용(포맷 검증은 CreateService가 담당).
  def upload_png
    io = StringIO.new("\x89PNG\r\n\x1a\n" + ("0" * 64))
    ActiveStorage::Blob.create_and_upload!(io:, filename: "proof.png", content_type: "image/png")
  end
end
