# 1:1 문의 티켓 — U1 표면 ②(/app/tickets · ADMIN-8). 작성은 rate_limit 5회/시간(스팸 방지 —
# 뷰어 패턴 준용), 작성 화면에는 FAQ를 선노출한다(ADMIN-9 — 랜딩 _faq 파셜 재사용, 3-a 인계
# 사항 준용 — 파셜은 자기완결이라 수정 불요). 상세는 본인 티켓만(타인 티켓 404).
class App::TicketsController < App::BaseController
  # ADMIN-8 — 티켓 작성 스팸 방지(5회/시간·사용자 기준 — 뷰어 패턴 준용). 상태 변경이 아니라
  # 자원 생성의 남발 방지라 create 한정.
  rate_limit to: 5, within: 1.hour, by: -> { Current.user.id }, only: :create

  # 상태·분류 배지 표현 로직(뷰 표현 3줄+ 이관). app/helpers/admin/는 Admin 네임스페이스
  # 충돌(zeitwerk 실측)으로 금지 — 컨트롤러 helper_method 패턴 준용.
  helper_method :ticket_status_badge, :ticket_category_label

  def ticket_status_badge(ticket)
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

  def ticket_category_label(ticket)
    CATEGORY_LABELS.fetch(ticket.category)
  end

  def index
    @tickets = Current.user.tickets.ordered
  end

  def new
    @ticket = Ticket.new
  end

  def create
    permitted = params.expect(ticket: [ :category, :title, :body, :image ])
    result = Tickets::CreateService.call(
      user: Current.user,
      category: ticket_category_param(permitted[:category]),
      title: permitted[:title], body: permitted[:body], image: permitted[:image]
    )
    if result.success
      redirect_to app_ticket_path(result.ticket), status: :see_other, notice: "문의가 접수되었습니다."
    else
      @ticket = result.ticket || Ticket.new
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @ticket = Current.user.tickets.find(params[:id]) # 소유 스코프 — 타인 티켓 404
    @messages = @ticket.ticket_messages.with_attached_image.ordered # W-4(05_review) — attached? N+1 방지
  end

  # W-1(05_review) — 첨부 이미지 인증 서빙. AS 공개 리다이렉트(서명 URL·만료 없음) 대신
  # 티켓 소유 U1 세션으로만 스트리밍한다(CS 증빙 이미지 — 소량이므로 send_data).
  # 소유자 외(타 U1·비로그인)는 show와 동일 소유 스코프 경유 404/가드.
  def image
    message = Current.user.tickets.find(params[:ticket_id]).ticket_messages.find(params[:message_id])
    attachment = message.image
    raise ActiveRecord::RecordNotFound unless attachment.attached?

    send_data attachment.download, type: attachment.content_type,
              disposition: "inline", filename: attachment.filename.to_s
  end

  # 추가 질문(member POST) — 종료 전까지 가능(PRD ADMIN-8). closed는 안내 후 상세로 되돌린다.
  def follow_up
    @ticket = Current.user.tickets.find(params[:id])
    body = params.expect(ticket: [ :body ])[:body]
    result = Tickets::FollowUpService.call(user: Current.user, ticket_id: @ticket.id, body:)
    if result.success
      redirect_to app_ticket_path(@ticket), status: :see_other, notice: "추가 질문이 등록되었습니다."
    else
      redirect_to app_ticket_path(@ticket), status: :see_other, alert: result.errors.to_sentence
    end
  end

  private

  # enum 캐스팅 ArgumentError 방지 — 화이트리스트 밖 분류는 기타(etc)로 귀속시킨다.
  def ticket_category_param(raw)
    %w[billing support bug feature etc].include?(raw) ? raw : "etc"
  end
end
