# 관리자 답변 등록 알림톡 발송(ADMIN-8 · REM-6 확장 · NOTI-1 채널 재사용) — Reminders::SendService를
# 재사용하지 않는 티켓 전용 경로다. SendService는 invoice 가드(수신거부·보류·종결·상태·자격·
# PLAN-3 상한·REM-3 창)와 sequence_step 판정이 얽혀 있어 결합이 오히려 위험하다. 티켓 알림은
# 자격·상한·수신거부 개념이 없고(시퀀스성 아님 — PLAN-3 상한 집계 밖, MessageLog::
# SEQUENCE_TEMPLATE_KEYS 밖), U1 향이라 REM-3 발송 창 제외다(PERF-1 성격 — 즉시 발송).
# variables 래핑(#{키} — Solapi::ClientService가 담당)과 MessageLog 기록 계약(P4)은 동일하게
# 준수한다. 재시도 불요(1회성) — 실패는 failed 기록 후 종료.
module Tickets
  class NotifyAnswerService
    # 솔라피 알림톡 버튼 웹링크 호스트 — 템플릿 버튼이 `https://#{url}` 규격이라 스킴 없이
    # host부터 전달한다(Reminders::SendService::LINK_HOST와 같은 패턴).
    LINK_HOST = "badeuldon.kr"
    TEMPLATE_KEY = "noti_ticket_reply"

    # client — 솔라피 래퍼 주입 지점(테스트 stub — 실호출 금지 방어선).
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(ticket:, client: nil)
      @ticket = ticket
      @client = client
    end

    # 반환: :sent / :failed / :skipped — 모든 시도는 MessageLog에 기록된다(P4).
    def call
      log = MessageLog.create!(invoice_id: nil, ticket_id: @ticket.id,
                               user_id: @ticket.user_id, recipient_role: :user,
                               origin: :auto, template_key: TEMPLATE_KEY, status: :pending)

      if @ticket.user.phone.blank?
        # 수신번호 미등록 — skipped 기록(NO_PHONE) 후 종료. 알림 실패가 답변 자체를 막지 않는다.
        log.update!(status: :skipped, error_code: "NO_PHONE")
        return :skipped
      end

      variables = build_variables
      response = client.send_alimtalk(template_key: TEMPLATE_KEY, to: @ticket.user.phone,
                                      variables: variables)
      log.update!(status: :sent, sent_at: Time.current, phone: @ticket.user.phone,
                  variables:, provider_message_id: provider_message_id(response))
      :sent
    rescue Solapi::ApiError => e
      log.update!(status: :failed, error_code: e.code, error_message: e.message,
                  phone: @ticket.user.phone, variables: variables)
      :failed # 1회성 — 재시도 없음(ADMIN-8 확정 해석)
    end

    private

    def client
      @client ||= Solapi::ClientService.new
    end

    # ALIMTALK_TEMPLATES.md B-4 — #{사용자명}·#{문의제목}·버튼 url(티켓 상세).
    def build_variables
      {
        "사용자명" => @ticket.user.display_name,
        "문의제목" => @ticket.title,
        "url" => "#{LINK_HOST}#{Rails.application.routes.url_helpers.app_ticket_path(@ticket)}"
      }
    end

    def provider_message_id(response)
      response.is_a?(Hash) ? response[:messageId] || response["messageId"] : nil
    end
  end
end
