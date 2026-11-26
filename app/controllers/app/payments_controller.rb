# 입금 기록·마감(F-PAY) — U1이 원클릭 전액 마감(PAY-1)·부분입금(PAY-2)을 기록한다.
# 조회·기록은 현재 사용자의 청구서로 스코프해 소유권을 격리하며, 기록+전이 처리는
# Payments::RecordService(트랜잭션·잔액 재검증 — 결정 #3)가 단일 담당한다. 성공 303 /
# 실패 422(청구서 상세 재렌더 — 작성 중 값 보존).
class App::PaymentsController < App::BaseController
  # F-REM — 422 재렌더에 청구서 상세 템플릿이 필요로 하는 발송 이력·컨텍스트(RemindersContext).
  include RemindersContext

  before_action :set_invoice, only: %i[ create ]

  def create
    # 서비스 인스턴스를 유지한다 — post_paid_record?·over_amount는 Payment 모델이 아니라
    # RecordService의 공개 리더다(Q22 결과 분기 — success_notice 참조).
    @record_service = Payments::RecordService.new(
      invoice: @invoice, amount: payment_params[:amount], paid_on: payment_params[:paid_on],
      notify_thanks: payment_params[:send_thanks] != "0",  # PAY-4 — 체크 해제 시에만 끈다(기본 켬)
      ip: ClientIp.of(request)  # ADMIN-2·Q32 — 과다입금 감사 기록용
    )
    @payment = @record_service.call
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

  # PAY-4 — send_thanks는 마감 폼의 감사 알림 체크박스(기본 켬). 파라미터 미전송(구폼·직접 요청)
  # 도 켬으로 해석한다(nil != "0").
  def payment_params
    params.expect(payment: [ :amount, :paid_on, :send_thanks ])
  end

  # PAY-1/PAY-2 결과 안내 — 마감이면 완료 문구, 부분입금이면 재계산된 잔액을 안내한다.
  # Q22 — 과다입금 마감 시 초과분 비고 기록과 오프라인 환불 안내를, 마감 후 재입금 기록 시
  # 상태 유지 사실을 덧붙인다.
  def success_notice
    if @record_service.post_paid_record?
      "마감된 청구서에 입금을 추가 기록했습니다. 수금 상태는 수금완료로 유지됩니다."
    elsif @invoice.reload.paid?
      base = "수금을 마감했습니다. 수고하셨습니다!"
      base += " #{over_notice}" if @record_service.over_amount.positive?
      base
    else
      "부분입금을 기록했습니다. 남은 잔액은 #{delimited(@invoice.remaining_amount)}원입니다."
    end
  end

  # Q22 — 과다입금 초과분 안내. 환불은 자동 처리하지 않고 오프라인 조율로 안내한다.
  def over_notice
    "입금액이 남은 잔액을 #{delimited(@record_service.over_amount)}원 초과해 초과분은 마감 기록 비고에 남겼습니다. 환불은 거래처와 직접 조율해 주세요."
  end

  def delimited(amount)
    ActiveSupport::NumberHelper.number_to_delimited(amount)
  end

  # 실패 422 재렌더에 청구서 상세 템플릿이 필요로 하는 @변수 — App::InvoicesController와
  # 동일 구성(SHARE-3 열람 이력·F-PROMISE 응답 이력·F-PAY 입금 이력·입금 폼·F-REM 발송 이력).
  # 폼 객체는 컬렉션 분리형(App::InvoicesController#set_payments 주석 참조).
  def load_invoice_show
    @view_events = @invoice.view_events.order(:viewed_at, :id)
    @promises = @invoice.promises.order(created_at: :desc, id: :desc)
    @payments = @invoice.payments.order(paid_on: :desc, id: :desc)
    @payment ||= Payment.new(invoice_id: @invoice.id, paid_on: Date.current)
    set_message_logs       # REM-6 — 발송 이력(RemindersContext)
    set_reminder_context   # REM-8 — 수동 발송 표기 컨텍스트(RemindersContext)
  end
end
