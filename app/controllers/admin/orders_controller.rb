# ADMIN-4(T-B3) — 결제·매출 관리. 주문 이력 목록·상세·환불 사유 기록.
# 실제 PG 환불은 포트원 콘솔에서 수동 수행(PLAN-5)하며, mark_refunded는 그 결과를
# 서비스 측에 기록하는 절차다 — 감사 로그는 컨트롤러에서 AuditLogs::RecordService로 기록(ADMIN-2).
class Admin::OrdersController < Admin::BaseController
  before_action :set_order, only: %i[show mark_refunded]

  def index
    @orders = filtered_orders.includes(:user).order(created_at: :desc).limit(100) # W-3 N+1 방지
    @plan_counts = Subscription.group(:status).count
    @expiring_trials = Subscription.trialing.includes(:user) # W-3 N+1 방지
                                           .where(trial_ends_at: Time.current..7.days.from_now)
                                           .order(:trial_ends_at).limit(20)
  end

  def show
  end

  # ADMIN-4 — 환불 사유 기록(reason 필수). 성공 시 감사 로그(action order_refund)·실패 flash.
  def mark_refunded
    if @order.mark_refunded!(params.expect(order: [ :refund_reason ])[:refund_reason])
      AuditLogs::RecordService.call(admin: current_admin, action: "order_refund",
                                    target: @order, detail: @order.refund_reason)
      redirect_to admin_order_path(@order), status: :see_other, notice: "환불 사유를 기록했습니다."
    else
      flash.now[:alert] = "환불 기록에 실패했습니다. 사유를 입력했는지, 이미 환불 기록된 건인지 확인해 주세요."
      render :show, status: :unprocessable_entity
    end
  rescue ArgumentError => e
    # mark_refunded!의 blank 사유 거부(ArgumentError)를 422로 변환 — W-1(500 금지)
    flash.now[:alert] = e.message
    render :show, status: :unprocessable_entity
  end

  private

  def set_order
    @order = Order.find(params[:id])
  end

  # 목록 필터 — status(paid/failed)·환불 여부(refunded/not_refunded). 화이트리스트 방식.
  def filtered_orders
    scope = Order.all
    scope = scope.send(params[:status]) if %w[paid failed].include?(params[:status])
    scope = scope.send(params[:refund]) if %w[refunded not_refunded].include?(params[:refund])
    scope
  end
end
