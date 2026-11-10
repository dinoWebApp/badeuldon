# 1:1 문의 티켓 관리(ADMIN-8 — 표면 ④). 목록 필터·스레드 상세·답변(reply — 알림톡 발송
# NotifyAnswerService는 컨트롤러에서 호출)·종료(close — 감사 기록 ADMIN-2). 종료는 관리자만
# 가능하며 사용자에게 종료 권한은 없다.
class Admin::TicketsController < Admin::BaseController
  # 배지·분류 표현 로직(뷰 표현 3줄+ 이관). app/helpers/admin/ 금지(Admin 네임스페이스 충돌
  # — zeitwerk 실측)에 따라 컨트롤러 helper_method 패턴 준용.
  helper_method :admin_ticket_status_badge, :admin_ticket_category_label

  def admin_ticket_status_badge(ticket)
    {
      "open" => [ "접수", "bg-emerald-50 text-emerald-700" ],
      "answered" => [ "답변 완료", "bg-green-50 text-green-700" ],
      "closed" => [ "종료", "bg-stone-100 text-stone-500" ]
    }.fetch(ticket.status)
  end

  CATEGORY_LABELS = {
    "billing" => "결제", "support" => "이용 문의", "bug" => "버그 제보",
    "feature" => "기능 제안", "etc" => "기타"
  }.freeze

  def admin_ticket_category_label(ticket)
    CATEGORY_LABELS.fetch(ticket.category)
  end

  def index
    scope = Ticket.includes(:user).ordered
    scope = scope.where(status: params[:status]) if params[:status].in?(Ticket.statuses.keys)
    scope = scope.where(category: params[:category]) if params[:category].in?(Ticket.categories.keys)
    @tickets = scope.limit(100)
  end

  def show
    @ticket = Ticket.find(params[:id])
    @messages = @ticket.ticket_messages.with_attached_image.ordered # W-4(05_review) — attached? N+1 방지
  end

  # W-1(05_review) admin 측 — 첨부 이미지 인증 서빙(AS 공개 리다이렉트 대체). admin 가드
  # (require_admin_session) 하에서만 스트리밍하며 앱 측(App::TicketsController#image)과 동일
  # send_data 패턴이다. 첨부는 1장 한정이므로 소량 — send_data로 충분하다.
  def image
    message = Ticket.find(params[:ticket_id]).ticket_messages.find(params[:message_id])
    attachment = message.image
    raise ActiveRecord::RecordNotFound unless attachment.attached?

    send_data attachment.download, type: attachment.content_type,
              disposition: "inline", filename: attachment.filename.to_s
  end

  # 답변 등록 — admin 발화 추가 후 상태 answered 전환, 알림톡 발송(U1 즉시 — REM-3 창 밖).
  # 발송 결과(sent/failed/skipped)와 무관하게 답변 자체는 등록 완료로 처리한다.
  def reply
    ticket = Ticket.find(params[:id])
    body = params.expect(ticket_message: [ :body ])[:body]
    if body.blank?
      return redirect_to admin_ticket_path(ticket), status: :see_other, alert: "답변 내용을 입력해 주세요."
    end

    ActiveRecord::Base.transaction do
      ticket.ticket_messages.create!(sender: :admin, body:)
      ticket.mark_answered!
    end
    Tickets::NotifyAnswerService.call(ticket:) # ADMIN-8 — 답변 등록 시 알림톡(P4 모두 기록)
    redirect_to admin_ticket_path(ticket), status: :see_other, notice: "답변이 등록되었습니다."
  end

  # 종료 — 상태 전이라 member PATCH로 정당화. 감사 기록(ADMIN-2 — RecordService 단일 진입점).
  def close
    ticket = Ticket.find(params[:id])
    ticket.mark_closed!
    AuditLogs::RecordService.call(admin: Current.admin, action: "ticket_close", target: ticket,
                                  detail: "티켓 종료 — #{ticket.title}")
    redirect_to admin_tickets_path, status: :see_other, notice: "문의가 종료되었습니다."
  end
end
