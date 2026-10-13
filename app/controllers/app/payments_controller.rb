# 입금 기록·마감(F-PAY) — U1이 원클릭 전액 마감(PAY-1)·부분입금(PAY-2)을 기록한다.
# 조회·기록은 현재 사용자의 청구서로 스코프해 소유권을 격리하며, 기록+전이 처리는
# Payments::RecordService(트랜잭션·잔액 재검증 — 결정 #3)가 단일 담당한다. 성공 303 /
# 실패 422(청구서 상세 재렌더 — 작성 중 값 보존).
class App::PaymentsController < App::BaseController
  before_action :set_invoice, only: %i[ create ]

  def create
    @payment = Payments::RecordService.new(
      invoice: @invoice, amount: payment_params[:amount], paid_on: payment_params[:paid_on]
    ).call
    redirect_to app_invoice_path(@invoice), status: :see_other, notice: success_notice
  rescue Payments::RecordService::InvalidPayment => e
    @payment = e.payment
    # base 오류(이미 마감·기록 불가 상태)는 플래시로, 금액·날짜 필드 오류는 폼 인라인으로 표시.
    flash.now[:alert] = @payment.errors.full_messages_for(:base).first
    load_invoice_show
    render "app/invoices/show", status: :unprocessable_entity
  end

  private

  # 소유권 격리 — 타인 청구서는 애초에 조회되지 않는다(404로 수렴).
  def set_invoice
    @invoice = Current.user.invoices.find(params[:invoice_id])
  end

  def payment_params
    params.expect(payment: [ :amount, :paid_on ])
  end

  # PAY-1/PAY-2 결과 안내 — 마감이면 완료 문구, 부분입금이면 재계산된 잔액을 안내한다.
  def success_notice
    if @invoice.reload.paid?
      "수금을 마감했습니다. 수고하셨습니다!"
    else
      "부분입금을 기록했습니다. 남은 잔액은 #{delimited(@invoice.remaining_amount)}원입니다."
    end
  end

  def delimited(amount)
    ActiveSupport::NumberHelper.number_to_delimited(amount)
  end

  # 실패 422 재렌더에 청구서 상세 템플릿이 필요로 하는 @변수 — App::InvoicesController와
  # 동일 구성(SHARE-3 열람 이력·F-PROMISE 응답 이력·F-PAY 입금 이력·입금 폼). 폼 객체는
  # 컬렉션 분리형(App::InvoicesController#set_payments 주석 참조).
  def load_invoice_show
    @view_events = @invoice.view_events.order(:viewed_at, :id)
    @promises = @invoice.promises.order(created_at: :desc, id: :desc)
    @payments = @invoice.payments.order(paid_on: :desc, id: :desc)
    @payment ||= Payment.new(invoice_id: @invoice.id, paid_on: Date.current)
  end
end
