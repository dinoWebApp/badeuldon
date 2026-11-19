# 전자세금계산서 발행 완료 알림톡(TAX-2 · NOTI-1 채널 · U1 이벤트 알림) — Tickets::
# NotifyAnswerService와 같은 1회성 전용 경로다(시퀀스성 아님 — PLAN-3 상한 집계 밖·REM-3
# 발송 창 밖, noti_* 계열과 동일 범주). 트리거는 TaxInvoices::PollStateJob의 pending→issued
# 전이 확정 시(nts_send_key 캡처 뒤) 1회 호출이며, 잡은 이 서비스 호출만 한다(발송 로직은
# 잡에 두지 않는다 — 규약). 템플릿 키(noti_tax_issued)가 credentials에 아직 없는 등록 전
# 공백기에는 MISSING_TEMPLATE를 failed가 아닌 skipped(NO_TEMPLATE)로 기록한다(NOTI-3 선례 —
# 등록 전 skip이 정상 경로). 폴링은 같은 건을 여러 번 실행할 수 있으므로 동일
# (invoice, template_key, status∈sent/skipped/failed) 이력이 존재하면 재발송하지 않는다
# (1회성 멱등 — MessageLog pending 슬롯 유니크와 무관한 애플리케이션 수준 가드).
module TaxInvoices
  class NotifyIssuedService
    # 알림톡 버튼 웹링크 호스트(Reminders::SendService::LINK_HOST와 같은 규격).
    LINK_HOST = "badeuldon.kr"
    TEMPLATE_KEY = "noti_tax_issued"

    # client — 솔라피 래퍼 주입 지점(테스트 stub — 실호출 금지 방어선).
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(tax_invoice:, client: nil)
      @tax_invoice = tax_invoice
      @client = client
    end

    # 반환: :sent / :skipped / :failed — 모든 시도는 MessageLog에 기록된다(P4).
    def call
      return :skipped if already_notified?

      user = @tax_invoice.invoice.user
      variables = nil # rescue 참조 지점의 정의 보장(조립 전 실패 시 nil 기록)
      log = MessageLog.create!(invoice_id: @tax_invoice.invoice_id, user_id: user.id,
                               recipient_role: :user, origin: :auto,
                               template_key: TEMPLATE_KEY, status: :pending)

      if user.phone.blank?
        log.update!(status: :skipped, error_code: "NO_PHONE")
        return :skipped
      end

      variables = build_variables
      response = client.send_alimtalk(template_key: TEMPLATE_KEY, to: user.phone,
                                      variables: variables)
      log.update!(status: :sent, sent_at: Time.current, phone: user.phone,
                  variables:, provider_message_id: provider_message_id(response))
      :sent
    rescue Solapi::ApiError => e
      # 템플릿 미등록(MISSING_TEMPLATE)은 등록 전 정상 경로 — skipped(NO_TEMPLATE).
      if e.code == "MISSING_TEMPLATE"
        log&.update!(status: :skipped, error_code: "NO_TEMPLATE",
                     error_message: e.message, phone: user&.phone, variables: variables)
        return :skipped
      end
      # 그 외 API 실패는 failed 기록 후 종료 — 검수중 등 어떤 경우에도 폴링 잡을 죽이지 않는다.
      log&.update!(status: :failed, error_code: e.code, error_message: e.message,
                   phone: user&.phone, variables: variables)
      :failed
    end

    private

    def client
      @client ||= Solapi::ClientService.new
    end

    # 1회성 멱등 — 같은 건·같은 템플릿의 확정 이력(sent/skipped/failed)이 있으면 재발송 없음.
    def already_notified?
      MessageLog.where(invoice_id: @tax_invoice.invoice_id, template_key: TEMPLATE_KEY,
                       status: [ :sent, :skipped, :failed ]).exists?
    end

    # ALIMTALK_TEMPLATES.md — #{발행인명}·#{거래처명}·#{금액}·#{승인번호}·버튼 url(청구서 상세).
    def build_variables
      {
        "발행인명" => @tax_invoice.invoice.user.display_name,
        "거래처명" => @tax_invoice.invoice.client.name,
        "금액" => ActiveSupport::NumberHelper.number_to_delimited(@tax_invoice.invoice.total_amount),
        "승인번호" => @tax_invoice.nts_send_key.to_s,
        "url" => "#{LINK_HOST}#{Rails.application.routes.url_helpers.app_invoice_path(@tax_invoice.invoice)}"
      }
    end

    def provider_message_id(response)
      response.is_a?(Hash) ? response[:messageId] || response["messageId"] : nil
    end
  end
end
