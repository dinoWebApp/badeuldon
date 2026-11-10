# 티켓 생성(ADMIN-8) — Ticket 헤더 + 첫 TicketMessage(sender=user)를 한 트랜잭션으로 만든다.
# U1 행위라 감사 로그 불요(ADMIN-2는 관리자 행위 대상). 검증 실패는 Result로 돌려 컨트롤러가
# 422 재렌더한다(응답 전략 — 폼 실패 422). 이미지는 첨부 선택(allow nil — TicketMessage 검증
# 이 위임).
module Tickets
  class CreateService
    Result = Data.define(:success, :ticket, :errors)

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(user:, category:, title:, body:, image: nil)
      @user = user
      @category = category
      @title = title
      @body = body
      @image = image
    end

    def call
      ticket = @user.tickets.build(category: @category, title: @title)
      message = ticket.ticket_messages.build(sender: :user, body: @body)
      message.image.attach(@image) if @image.present?

      ActiveRecord::Base.transaction do
        ticket.save!
        message.save!
      end
      Result.new(success: true, ticket:, errors: [])
    rescue ActiveRecord::RecordInvalid
      # 이미지 검증 실패 시 message에, 헤더 검증 실패 시 ticket에 오류가 적재된다 — 합쳐 반환.
      Result.new(success: false, ticket:,
                 errors: ticket.errors.full_messages + message.errors.full_messages)
    end
  end
end
