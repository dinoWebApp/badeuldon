# TAX-2 — 전자세금계산서 상태 폴링(바로빌 웹훅 부재 → GetTaxInvoiceStateEX 폴링). 인자는
# 스칼라 id(규약), 멱등(이미 issued·canceled·failed면 no-op), retry_on 명시. 발급완료
# (BarobillState 3014) + 국세청 전송완료(NTSSendState 4)면 TAX-2 승인번호(NTSSendKey)를
# 캡처해 issued로 확정한다. 전송실패(NTSSendState 5)는 failed로 확정하고, 그 외 진행 중은
# 예외를 던져 retry_on 백오프로 재시도한다. 최대 재시도 소진 시에도 failed로 확정한다
# (Phase 6 C-4 — 영구 "발행 처리 중" 방지. 01_plan §4 상태 머신).
module TaxInvoices
  class PollStateJob < ApplicationJob
    # retry_on 블록은 재시도를 모두 소진한 시점에 실행된다 — failed 확정 후 예외를 재발생시켜
    # 잡 실패 기록을 유지한다(멱등 — 이미 종결 상태면 no-op).
    retry_on BaroBill::ClientService::ApiError, wait: :polynomially_longer, attempts: 10 do |job, error|
      tax_invoice = TaxInvoice.find_by(id: job.arguments.first)
      tax_invoice&.update!(status: :failed) unless tax_invoice.nil? || tax_invoice.issued? ||
                                                   tax_invoice.canceled? || tax_invoice.failed?
      raise error
    end
    discard_on ActiveRecord::RecordNotFound # 레코드 삭제된 폴링은 흡수

    ISSUED_STATE = 3014      # BarobillState — 발급완료
    CANCELED_STATE = 5031    # BarobillState — 발급 후 공급자 취소
    NTS_DONE = 4             # NTSSendState — 전송완료
    NTS_FAILED = 5           # NTSSendState — 전송실패

    def perform(tax_invoice_id)
      tax_invoice = TaxInvoice.find_by(id: tax_invoice_id)
      return if tax_invoice.nil? || tax_invoice.issued? || tax_invoice.canceled? || tax_invoice.failed?

      state = BaroBill::ClientService.new.get_tax_invoice_state(
        corp_num: tax_invoice.user.corp_num, mgt_num: tax_invoice.mgt_num
      )

      tax_invoice.update!(
        barobill_state: state[:barobill_state],
        nts_send_state: state[:nts_send_state],
        nts_send_key: state[:nts_send_key].presence
      )

      if state[:barobill_state].to_i == ISSUED_STATE && state[:nts_send_state].to_i == NTS_DONE
        tax_invoice.update!(status: :issued) # TAX-2 — 승인번호 수신 확정
      elsif state[:nts_send_state].to_i == NTS_FAILED
        tax_invoice.update!(status: :failed)
      else
        raise BaroBill::ClientService::ApiError.new(code: "PENDING",
                                                    message: "발행 진행 중 — 폴링 재시도")
      end
    end
  end
end
