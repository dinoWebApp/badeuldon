# TAX-1 — 전자세금계산서 발행(Q21 — 결제 완료 주문 한정). 검증 사슬(전제·가드) → 휴폐업 조회
# → RegistAndIssueTaxInvoice 전송 → tax_invoices 기록(P4) → 상태 폴링 잡 인계. 모든 가드는
# 단일 진입점 #call에서 수행하며 위반은 GuardFailed 예외로 명확히 실패시킨다(컨트롤러가 문구로
# 안내). mgt_num은 24자 이내·회원사 단위 유니크("TI{user_id}I{invoice_id}") — 취소된 관리번호는
# 바로빌 규격상 재사용 불가(ProcTaxInvoice 문서)하나 이 채번은 청구 id 결정적이라 재발행 스코프
# 진입 시(후속) 별도 접미 채번이 필요하다.
module TaxInvoices
  class IssueService
    # 가드 위반 — message는 U1 안내 문구 그대로(컨트롤러·FulfillTaxInvoiceService가 소비).
    GuardFailed = Class.new(StandardError)

    def initialize(invoice:, order:, client: BaroBill::ClientService.new)
      @invoice = invoice
      @order = order
      @client = client
    end

    def call
      verify_guards!

      corp_state = @client.get_corp_state(corp_num: @invoice.user.corp_num,
                                          check_corp_num: @invoice.client.corp_num)
      raise GuardFailed, "거래처 사업자가 폐업 상태여서 발행할 수 없습니다." if corp_state[:state] == 3

      tax_invoice = nil
      # Phase 6 W-1 — 쓰기(create!)만 트랜잭션으로 감싸고 SOAP 호출은 밖에서 수행한다
      # (FulfillPassService의 트랜잭션-외부호출 분리 패턴 — 콜백 스레드의 커넥션 점유 방지).
      ActiveRecord::Base.transaction do
        @order.with_lock do
          tax_invoice = TaxInvoice.create!(
            invoice: @invoice, user: @invoice.user, mgt_num: generate_mgt_num,
            status: :pending, write_date: @invoice.settled_paid_on,
            supply_total: @invoice.subtotal, tax_total: @invoice.tax_amount,
            grand_total: @invoice.total_amount, order: @order
          )
        end
      end
      @client.regist_and_issue_tax_invoice(corp_num: @invoice.user.corp_num,
                                           invoice: build_tax_invoice_payload)

      TaxInvoices::PollStateJob.perform_later(tax_invoice.id)
      tax_invoice
    end

    private

    # 검증 사알 — 순서: ① U1 발행 설정 완료(공동인증서 포함) ② 거래처 사업자번호 ③ 결제 완료
    # ④ 1청구 1발행(tax_invoices 기존 레코드 없음 — canceled 포함).
    def verify_guards!
      raise GuardFailed, "전자세금계산서 발행 설정을 먼저 완료해 주세요." unless @invoice.user.tax_invoice_ready?
      raise GuardFailed, "거래처 사업자번호가 없어 발행할 수 없습니다(개인 거래처는 비대상입니다)." if @invoice.client.corp_num.blank?
      raise GuardFailed, "발행 수수료 결제가 완료되지 않았습니다." unless @order&.paid?
      raise GuardFailed, "이미 발행 요청된 청구서입니다." if TaxInvoice.for_invoice(@invoice).exists?
      raise GuardFailed, "수금이 마감된 청구서만 발행할 수 있습니다." unless @invoice.paid?
    end

    def generate_mgt_num
      "TI#{@invoice.user_id}I#{@invoice.id}" # 24자 이내 — user_id·invoice_id 정수 스케일로 여유
    end

    # TaxInvoice 구조체 구성(바로빌 규격 — /tmp/barobill_ti.txt 객체 정보). 하이픈 제외·특수문자
    # 처리("㈜"→"(주)") 등 스펙 변환은 이 서비스의 책임(래퍼는 전송만).
    def build_tax_invoice_payload
      invoicer = {
        MgtNum: generate_mgt_num, CorpNum: @invoice.user.corp_num,
        CorpName: sanitize_corp_name(@invoice.user.corp_name), CEOName: @invoice.user.ceo_name,
        Addr: @invoice.user.corp_addr, ContactID: @invoice.user.barobill_id,
        ContactName: @invoice.user.contact_name, TEL: "", HP: "", Email: @invoice.user.email
      }
      invoicee = {
        MgtNum: generate_mgt_num, CorpNum: @invoice.client.corp_num,
        CorpName: sanitize_corp_name(@invoice.client.name),
        CEOName: @invoice.client.ceo_name.to_s, Addr: @invoice.client.corp_addr.to_s,
        ContactName: @invoice.client.contact_name.to_s, TEL: "", HP: "",
        Email: @invoice.client.email.to_s
      }
      {
        InvoicerParty: invoicer, InvoiceeParty: invoicee,
        IssueDirection: 1, # 정발급
        TaxInvoiceType: 1, # 세금계산서
        TaxType: TAX_TYPE_BY_USER.fetch(@invoice.user.tax_type),
        PurposeType: 1,    # 영수(수금 마감 건 — PRD 확정)
        WriteDate: @invoice.settled_paid_on.strftime("%Y%m%d"),
        AmountTotal: @invoice.subtotal.to_s, TaxTotal: @invoice.tax_amount.to_s,
        TotalAmount: @invoice.total_amount.to_s,
        TaxInvoiceTradeLineItems: line_items
      }
    end

    TAX_TYPE_BY_USER = { "general" => 1, "simplified" => 2, "exempt" => 3 }.freeze

    # 품목 — invoice items 스냅샷(최대 99개 규격). 수량은 정수 저장 컬럼이라 "1" 고정 스케일.
    # Phase 6 C-3 — 행 금액은 정수 연산만 하고(부동소수 배제) Σ품목.Amount=AmountTotal·
    # Σ품목.Tax=TaxTotal이 되도록 마지막 행 잔액 조정을 둔다(바로빌은 항목 합계를 국세청 전송
    # 기준으로 사용). 별건 모드: 행 공급가액=qty×price·세액=10% 사사오입 / 포함 모드: 행 총액을
    # 11분해 — 공급가액=총액×10/11 사사오입·세액=총액−공급가액(Invoice.compute_amounts 산식과
    # 동일 정수 근사).
    def line_items
      rows = @invoice.items.map { |item| build_line_row(item) }
      adjust_last_row!(rows)
      rows.map do |row|
        {
          Name: row[:name], ChargeableUnit: row[:quantity].to_s,
          UnitPrice: row[:unit_price].to_s, Amount: row[:amount].to_s, Tax: row[:tax].to_s
        }
      end
    end

    def build_line_row(item)
      total = item.quantity * item.unit_price
      if @invoice.tax_mode.to_s == "separate"
        { name: item.description.to_s[0, 100], quantity: item.quantity,
          unit_price: item.unit_price, amount: total, tax: (total * 10 + 5) / 10 }
      else
        supply = (total * 10 + 5) / 11
        { name: item.description.to_s[0, 100], quantity: item.quantity,
          unit_price: item.unit_price, amount: supply, tax: total - supply }
      end
    end

    # 마지막 행에 행별 반올림 잔액을 반영해 총액 상위 필드(AmountTotal·TaxTotal)와 정확히 일치.
    def adjust_last_row!(rows)
      return if rows.blank?

      last = rows.last
      last[:amount] += @invoice.subtotal - rows.sum { |row| row[:amount] }
      last[:tax] += @invoice.tax_amount - rows.sum { |row| row[:tax] }
    end

    # CorpName 특수문자 불가 규격 — "㈜"를 "(주)"로 치환하고 나머지 특수문자는 제거한다.
    def sanitize_corp_name(name)
      name.to_s.gsub("㈜", "(주)").gsub(/[^\p{Han}\p{Alnum}\p{Space}()\[\].,-]/, "")[0, 200].to_s
    end
  end
end
