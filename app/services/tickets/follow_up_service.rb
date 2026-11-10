# 사용자 추가 질문(ADMIN-8) — 스레드에 user 발화를 추가한다. 종료(closed) 전까지 허용(PRD
# "종료 전까지 추가 질문 가능"): answered면 open으로 복귀(Ticket#reopen — 스레드 보존),
# open이면 상태 유지, closed는 거부(Result failure — 컨트롤러가 안내 플래시).
module Tickets
  class FollowUpService
    Result = Data.define(:success, :message, :errors)

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(user:, ticket_id:, body:)
      @user = user
      @ticket = user.tickets.find_by(id: ticket_id) # 소유 스코프 — 타인 티켓은 nil(404 경로)
      @body = body
    end

    def call
      return Result.new(success: false, message: nil, errors: [ "문의를 찾을 수 없습니다." ]) unless @ticket
      if @ticket.closed?
        return Result.new(success: false, message: nil,
                          errors: [ "종료된 문의에는 추가 질문을 할 수 없습니다." ])
      end

      message = @ticket.ticket_messages.create!(sender: :user, body: @body)
      @ticket.reopen!
      Result.new(success: true, message:, errors: [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, message: nil, errors: e.record.errors.full_messages)
    end
  end
end
