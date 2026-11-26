# 수금 패스 발급 확정(F-PLAN — PLAN-4) — 주문(paid 전환)과 패스 발급을 한 트랜잭션으로 묶고
# with_lock + pending 재판정으로 직렬화한다. 콜백(PurchaseService)·웹훅(PortOneController) 어느
# 경로가 먼저 도착해도 발급은 정확히 1회다(SEC-5와 같은 멱등 원칙 — 이슈 #1·#4 회복 경로가
# 공유하는 확정점). 단건 결제의 paid 확정은 이 서비스 한 곳에서만 일어나며, 상태 변경 전에
# PortOne::PaymentVerifier로 실제 결제금액·채널 종류를 주문과 대조한다(재리뷰 R-1·R-2 —
# fail-closed. 이미 확정된 주문의 멱등 no-op 경로는 검증하지 않는다).
module Orders
  class FulfillPassService
    def initialize(order:, payment_id:, response: {})
      @order = order
      @payment_id = payment_id
      @response = response || {}
    end

    def call
      newly_paid = false
      @order.with_lock do
        next unless @order.reload.pending? # 이미 확정된 주문 — 무변경(멱등)

        # PLAN-5 결제 확정 검증 — 재조회한 결제 건(승인 응답은 pgTxId·paidAt만이라 검증 대상
        # 아니다)의 실제 결제금액(amount.paid)·채널 종류(channel.type)·통화(currency)가 주문과
        # 일치할 때만 paid로 바꾼다. 실패 시 아무것도 바꾸지 않고 VerificationError를 올린다
        # (트랜잭션 롤백 — 발급·발행 없음).
        PortOne::PaymentVerifier.verify!(@response, order_amount: @order.amount)

        newly_paid = true
        ActiveRecord::Base.transaction do
          @order.update!(status: :paid, paid_at: Time.current,
                         pg_payment_id: @payment_id, metadata: merged_metadata)
          # LEGAL-2 — 내용증명 양식 주문은 발급물(패스)이 없다: paid 확정만으로 충분하고
          # PDF 생성은 다운로드 시점(App::LegalDocumentsController#download)에 순수 수행한다.
          # TAX-1(Q21) — 세금계산서 수수료 주문도 발급물(패스)이 없다 — 외부 API 발행은
          # 트랜잭션 밖(fulfill_tax_invoice)에서 수행한다.
          issue_pass! unless @order.legal_doc? || @order.tax_invoice?
        end
      end
      # TAX-1 — 발행(바로빌 SOAP)은 결제 확정 트랜잭션 밖에서 수행한다(웹훅 경로와 동일).
      # newly_paid는 검증 통과 후의 pending→paid 전환에만 true이므로 검증 실패 시 발행은
      # 호출되지 않는다.
      fulfill_tax_invoice if newly_paid && @order.tax_invoice?
      @order
    end

    private

    # B-1(LEGAL-2·F-LEGAL Phase 6) — 결제 응답으로 metadata를 통째로 덮어쓰지 않는다.
    # legal_doc 주문은 orders.metadata["invoice_id"]가 청구 역참조의 유일 경로이므로
    # (App::LegalDocumentsController#order_invoice → download), 기존 metadata를 보존하고
    # 결제 응답을 병합한다. 덮어쓰면 paid 이후 다운로드가 영구 파탄난다.
    def merged_metadata
      (@order.metadata || {}).stringify_keys.merge(@response.stringify_keys)
    end

    # TAX-1(Q21) — 세금계산서 수수료 주문의 발행(FulfillTaxInvoiceService 단일 진입점 재사용 —
    # 콜백·웹훅 양 경로가 같은 확정점을 공유한다).
    def fulfill_tax_invoice
      Orders::FulfillTaxInvoiceService.new(order: @order.reload, payment_id: @payment_id,
                                           response: @response).call
    end

    # PLAN-4 — 수금 패스 발급: 10건, 발급 시점으로 90일 유효.
    def issue_pass!
      @order.user.payment_passes.create!(
        total_uses: PaymentPass::TOTAL_USES, remaining_uses: PaymentPass::TOTAL_USES,
        expires_at: PaymentPass::VALIDITY_DAYS.days.from_now
      )
    end
  end
end
