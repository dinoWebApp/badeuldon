# ADMIN-4·ADMIN-11(PLAN-9) — 결제·매출 관리. 주문 이력 목록·상세·결제 취소(환불) 실행.
# 실행은 Orders::RefundService가 수행하며(포트원 결제 취소·상품 되돌리기·감사 로그),
# 컨트롤러는 결과에 따라 303/422로만 응답한다. refund 액션은 owner 전용(ADMIN-1 가드 —
# require_owner는 BaseController의 protected 메서드).
class Admin::OrdersController < Admin::BaseController
  before_action :set_order, only: %i[show refund]
  before_action :require_owner, only: :refund

  def index
    # W-3 N+1 방지 — 행별 order.user.subscription(dunning 표기)까지 미리 로딩한다.
    @orders = filtered_orders.includes(user: :subscription).order(created_at: :desc).limit(100)
    @plan_counts = Subscription.group(:status).count
    @expiring_trials = Subscription.trialing.includes(:user) # W-3 N+1 방지
                                           .where(trial_ends_at: Time.current..7.days.from_now)
                                           .order(:trial_ends_at).limit(20)
  end

  def show
  end

  # ADMIN-11·PLAN-9 — 결제 취소(환불) 실행(사유 필수). 성공 시 303 + flash 요약,
  # 실패 시 422으로 show 재렌더(500 금지 — W-1. 실패는 서비스가 Result로 반환하고, 서비스를
  # 뚫고 나온 예외도 마지막 안전망으로 흡수한다 — PG 취소 뒤 500으로 새어 나가지 않게 함).
  def refund
    result = Orders::RefundService.new(admin: current_admin, order: @order,
                                       reason: refund_params[:refund_reason]).call
    result.success? ? refund_succeeded(result) : render_refund_failure(result.errors.first)
  rescue StandardError => e
    Rails.logger.error("[Admin::OrdersController#refund] #{e.class}: #{e.message}")
    render_refund_failure("환불 실행 중 오류가 발생했습니다. 포트원 콘솔에서 해당 결제의 취소 상태를 확인한 뒤 다시 실행해 주세요.")
  end

  private

  def refund_succeeded(result)
    redirect_to admin_order_path(@order), status: :see_other, notice: result.message
  end

  # W-1 — 실패 응답 공용(422 재렌더). 메시지에 스택·시크릿을 넣지 않는다.
  def render_refund_failure(message)
    flash.now[:alert] = message
    render :show, status: :unprocessable_entity
  end

  def set_order
    @order = Order.find(params[:id])
    # ADMIN-11 — 실행 폼 노출 플래그·환불 실행 정보를 @변수로 공급한다(뷰에서 모델 클래스
    # 메서드 호출 금지). show 렌더와 refund 실패 재렌더가 공용한다.
    @can_refund = current_admin.owner?
    @refund_info = (@order.metadata || {})["refund"]
  end

  def refund_params
    params.expect(order: [ :refund_reason ])
  end

  # 목록 필터 — status(paid/failed/cancelled)·환불 여부(refunded/not_refunded). 화이트리스트 방식.
  def filtered_orders
    scope = Order.all
    scope = scope.send(params[:status]) if %w[paid failed cancelled].include?(params[:status])
    scope = scope.send(params[:refund]) if %w[refunded not_refunded].include?(params[:refund])
    scope
  end
end
