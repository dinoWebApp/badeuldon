# 반복 청구 스케줄(INV-7) — U1의 월 1회 자동 발행 설정 CRUD + 일시중지·재개·해지. 조회·변경은
# 모두 Current.user.recurring_invoices로 스코프하며, 자동 발행 자체는 RecurringInvoices::IssueJob
# → IssueService가 담당한다(컨트롤러는 설정 관리만 — 발행 플로우 비포함). routes 결선(3-S)은
# resources only + member pause/resume/cancel(patch) 계약이다.
class App::RecurringInvoicesController < App::BaseController
  before_action :set_schedule, only: %i[ show pause resume cancel ]
  # W-3 — 위조 품목 id 방어(생성 전용·신규 스케줄은 보유 행이 없어 id가 지정된 행은 전부
  # 불일치). nested attributes 할당 전에 가드해 RecordNotFound(500)를 원천 차단한다.
  before_action :reject_forged_items, only: %i[ create ]

  def index
    @schedules = Current.user.recurring_invoices.includes(:client, :items).sorted_by_next_issue
  end

  def show; end

  def new
    @schedule = Current.user.recurring_invoices.build
    @schedule.items.build
    prepare_form_options
  end

  def create
    @schedule = Current.user.recurring_invoices.build(schedule_params.except(:items_attributes))
    @schedule.attributes = schedule_params.slice(:items_attributes)
    @schedule.initialize_next_issue_on!
    if @schedule.save
      redirect_to app_recurring_invoice_path(@schedule), status: :see_other,
                  notice: "반복 청구가 등록되었습니다. 매월 #{@schedule.day_of_month}일에 자동 발행됩니다."
    else
      prepare_form_options
      render :new, status: :unprocessable_entity
    end
  end

  # INV-7 — 일시중지·재개·해지. 해지는 상태 전이만(cancelled)이며 기록(last_issued_on·
  # 발행 이력)은 보존한다(P4). 전이는 상태 한정(W-1 — pause는 active만·resume는 paused만:
  # cancelled 재활성은 UI confirm·주석 불변식과 동일하게 서버에서도 금지, 재등록으로 대체).
  def pause
    return render_invalid_transition("일시중지는 이용 중인 스케줄만 가능합니다.") unless @schedule.active?

    if @schedule.update(status: :paused)
      redirect_to app_recurring_invoice_path(@schedule), status: :see_other,
                  notice: "반복 청구를 일시중지했습니다."
    else
      render_failure
    end
  end

  def resume
    return render_invalid_transition("해지된 반복 청구는 다시 활성화할 수 없습니다. 새로 등록해 주세요.") unless @schedule.paused?

    if @schedule.update(status: :active)
      redirect_to app_recurring_invoice_path(@schedule), status: :see_other,
                  notice: "반복 청구를 재개했습니다."
    else
      render_failure
    end
  end

  def cancel
    if @schedule.update(status: :cancelled)
      redirect_to app_recurring_invoices_path, status: :see_other,
                  notice: "반복 청구를 해지했습니다. 자동 발행이 중단됩니다."
    else
      render_failure
    end
  end

  private

  # W-3 — 위조 품목 id 검출: 신규 스케줄은 보유 행이 없어 id가 지정된 행은 전부 위조다.
  def reject_forged_items
    items = params[:recurring_invoice]&.dig(:items_attributes)
    return if items.blank? || items.values.none? { |v| v[:id].present? }

    @schedule = Current.user.recurring_invoices.build
    prepare_form_options
    flash.now[:alert] = "품목 정보를 저장할 수 없습니다. 다시 시도해 주세요."
    render :new, status: :unprocessable_entity
  end

  # W-1 — 불가 전이(active→pause 제외·paused→resume 제외)의 서버 가드 응답.
  def render_invalid_transition(message)
    redirect_to app_recurring_invoice_path(@schedule), status: :see_other, alert: message
  end

  def set_schedule
    @schedule = Current.user.recurring_invoices.find(params[:id])
  end

  def prepare_form_options
    @clients = Current.user.clients.order(:name)
  end

  # 실패 응답 — 상태 전환 실패는 검증 오류가 아니라 예외적이므로 422로 이전 화면 재렌더
  def render_failure
    flash.now[:alert] = @schedule.errors.full_messages.first.presence || "요청을 처리할 수 없습니다."
    render :show, status: :unprocessable_entity
  end

  def schedule_params
    params.expect(recurring_invoice: [
      :client_id, :day_of_month, :tax_mode, :withholding_enabled, :hold_if_unpaid,
      { items_attributes: [ [ :name, :quantity, :unit_price ] ] }
    ])
  end
end
