# 요금제 페이지(F-PLAN 표면 ②) — 현재 플랜·체험/주기 상태·보유 수금 패스 표시와
# Plus 체험 시작·카드 등록·해지·수금 패스 구매로의 분기 축. 표시에 필요한 @변수를
# 모두 적재하며 구독 행이 없는 기존 사용자도 즉석에서 Free 행을 만들어 일관되게 보여준다.
class App::BillingsController < App::BaseController
  def show
    @subscription = Current.user.subscription || Current.user.create_subscription!(plan: :free)
    @usable_passes = Current.user.payment_passes.usable.order(expires_at: :asc)
    # 수금 패스 결제 대기 주문(구매 버튼 → 위젯 체크아웃 전환) — 위변조 방지로 본인 pending만
    @checkout_order = Current.user.orders.pending.collection_pass
                                .find_by(toss_order_id: params[:checkout]) if params[:checkout].present?
    @toss_client_key = Rails.application.credentials.dig(:toss, :client_key)
  end
end
