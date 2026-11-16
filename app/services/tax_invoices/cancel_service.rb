# TAX-1 — 발급 취소(사용자 확정 전제 — 취소도 과금 전제). ProcTaxInvoice(ISSUE_CANCEL — 국세청
# 전송 전에만 가능) 호출 후 레코드 상태만 canceled로 전환한다(레코드 유지 — P4·재발행은 후속
# 스코프로 canceled 후 발행 버튼 비활성·안내). 취소 실패(이미 국세청 전송 완료 등)는 명확한
# 예외로 올려 컨트롤러가 안내한다.
module TaxInvoices
  class CancelService
    NotCancelable = Class.new(StandardError)

    def initialize(tax_invoice:, client: BaroBill::ClientService.new)
      @tax_invoice = tax_invoice
      @client = client
    end

    def call
      raise NotCancelable, "이미 취소된 발행입니다." if @tax_invoice.canceled?

      @client.cancel_tax_invoice(corp_num: @tax_invoice.user.corp_num,
                                 mgt_num: @tax_invoice.mgt_num)
      @tax_invoice.update!(status: :canceled, barobill_state: 5031) # 5031 — 발급 후 공급자 취소
      @tax_invoice
    rescue BaroBill::ClientService::ApiError => e
      # Phase 6 W-5 — 상태별 문구 분리: 전송 계열("SOAP" — 일시 네트워크 오류)은 재시도를,
      # 바로빌 음수 코드(NotCancelable 규격 — 이미 국세청 전송 완료 등)는 정정 안내를 사용한다.
      if e.code == "SOAP"
        raise NotCancelable, "일시적인 오류로 발급 취소에 실패했습니다. 잠시 후 다시 시도해 주세요."
      end

      raise NotCancelable, "발급 취소에 실패했습니다(오류코드 #{e.code}). 국세청 전송이 완료된 계산서는 수정세금계산서로 정정해야 합니다."
    end
  end
end
