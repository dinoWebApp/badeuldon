require "test_helper"
require_relative "../../test_helpers/solapi_stubbing"

# ADMIN-8 · REM-6 확장 · P4 — Tickets::NotifyAnswerService.
# sent/failed/skipped(NO_PHONE) 3분기 + 전 시도 MessageLog 기록(invoice nil·ticket_id·
# variables 스냅샷). 솔라피는 with_solapi_client로 차단 — 실호출 금지(AGENTS.md 테스트 전략).
# 티켓 알림은 PLAN-3 상한 집계 밖(SEQUENCE_TEMPLATE_KEYS 밖)·REM-3 창 제외(U1 향 즉시 발송).
class Tickets::NotifyAnswerServiceTest < ActiveSupport::TestCase
  include SolapiStubbing
  setup do
    @ticket = Ticket.create!(user: users(:gamma), title: "결제 문의") # gamma — phone 등록 완료
    @fake = Struct.new(:response, keyword_init: true) do
      def send_alimtalk(template_key:, to:, variables:)
        response
      end
    end.new(response: { messageId: "SOLAPI-123" })
  end

  test "성공 — :sent 반환·MessageLog sent 기록 (P4)" do
    result = nil
    assert_difference -> { MessageLog.count }, 1 do
      with_solapi_client @fake do
        result = Tickets::NotifyAnswerService.call(ticket: @ticket)
      end
    end

    assert_equal :sent, result
    log = MessageLog.last
    assert log.sent?
    assert_nil log.invoice_id
    assert_equal @ticket.id, log.ticket_id
    assert_equal @ticket.user_id, log.user_id
    assert_equal "user", log.recipient_role
    assert_equal "noti_ticket_reply", log.template_key
    assert_equal "010-9876-5432", log.phone # gamma phone 스냅샷
    assert_equal "SOLAPI-123", log.provider_message_id
    assert_not_nil log.sent_at
  end

  test "variables 스냅샷 — 사용자명·문의제목·url(스킴 없이 host부터)" do
    with_solapi_client @fake do
      Tickets::NotifyAnswerService.call(ticket: @ticket)
    end
    variables = MessageLog.last.variables
    assert_equal "감마스튜디오", variables["사용자명"]
    assert_equal "결제 문의", variables["문의제목"]
    assert_equal "badeuldon.kr#{Rails.application.routes.url_helpers.app_ticket_path(@ticket)}",
                 variables["url"]
  end

  test "솔라피 실패(ApiError) — :failed 반환·failed 기록·재시도 없음 (ADMIN-8 확정 해석)" do
    failing = Struct.new(keyword_init: true) do
      def send_alimtalk(template_key:, to:, variables:)
        raise Solapi::ApiError.new(status: 400, code: "E400", message: "잘못된 요청")
      end
    end.new

    result = nil
    assert_difference -> { MessageLog.count }, 1 do
      with_solapi_client failing do
        result = Tickets::NotifyAnswerService.call(ticket: @ticket)
      end
    end

    assert_equal :failed, result
    log = MessageLog.last
    assert log.failed?
    assert_equal "E400", log.error_code
    assert_equal "잘못된 요청", log.error_message
    assert_equal "010-9876-5432", log.phone
  end

  test "수신번호 미등록 — :skipped·NO_PHONE 기록·솔라피 호출 없음" do
    user = users(:alpha) # phone 미설정
    ticket = Ticket.create!(user:, title: "번호 없는 문의")
    no_call = Object.new
    def no_call.send_alimtalk(**)
      raise "솔라피 호출이 발생해서는 안 된다"
    end

    result = nil
    assert_difference -> { MessageLog.count }, 1 do
      with_solapi_client no_call do
        result = Tickets::NotifyAnswerService.call(ticket:)
      end
    end

    assert_equal :skipped, result
    log = MessageLog.last
    assert log.skipped?
    assert_equal "NO_PHONE", log.error_code
    assert_nil log.phone
  end

  test "티켓 알림은 PLAN-3 상한 집계 밖이다 (PLAN-3)" do
    with_solapi_client @fake do
      Tickets::NotifyAnswerService.call(ticket: @ticket)
    end
    invoice = invoices(:delta_overdue) # 시퀀스 상한 집계는 invoice 스코프 — 티켓 행(null) 배제 확인
    assert_equal 0, MessageLog.sequence_sent_count(invoice.id)
    refute_includes MessageLog::SEQUENCE_TEMPLATE_KEYS, "noti_ticket_reply"
  end
end
