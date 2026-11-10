# 구독 상태 전환(F-PLAN) — create: 체험 시작, update: 카드 등록(빌링키 발급 — 위젯 GET 콜백과
# 수동 PATCH가 발급 토큰 유무로 수렴)·쿠폰 적용(ADMIN-4 — 발급 토큰 없는 PATCH에 coupon_code),
# cancel: 해지(PATCH 전용). 흐름·가드는 Subscriptions::UpgradeService가 담당하고 컨트롤러는
# 진입·응답만 한다.
#
# 이슈 #5 — GET은 CSRF 검증 대상이 아니므로 상태 변경(해지)을 GET이 닿는 경로에 두지 않는다.
# card_callback(GET)은 카드 인증 결과(빌링키 발급 토큰) 수신 전용이고, 해지는 CSRF 토큰 검증
# 대상인 PATCH 전용 액션으로만 수행된다.
class App::SubscriptionsController < App::BaseController
  def create
    Subscriptions::UpgradeService.new(user: Current.user, action: :start_trial).call
    redirect_to app_billing_path, status: :see_other,
                notice: "Plus 14일 무료 체험이 시작되었습니다."
  rescue Subscriptions::UpgradeService::UpgradeError => e
    redirect_to app_billing_path, status: :see_other, alert: e.message
  end

  # 카드 등록 전용 — 발급 토큰 없는 요청(악성 GET 링크 포함)은 서비스 가드로 거부되며
  # 상태 변경으로 이어지지 않는다. 단, 발급 토큰 없는 PATCH에 coupon_code가 있으면 쿠폰 적용
  # 요청(ADMIN-4)으로 분기한다 — 신규 라우트 없이 기존 update 엔드포인트를 재사용한다.
  def update
    return apply_coupon if @issue_token.blank? && params[:coupon_code].present?

    Subscriptions::UpgradeService.new(user: Current.user, action: :register_card,
                                      issue_token: issue_token).call
    record_coupon_redeemed_audit
    redirect_to app_billing_path, status: :see_other,
                notice: "카드가 등록되어 Plus 이용이 활성화되었습니다."
  rescue Subscriptions::UpgradeService::UpgradeError => e
    redirect_to app_billing_path, status: :see_other, alert: e.message
  end

  # 해지(PLAN-5) — Plus 이용 중만 허용(이슈 #6 — Free 해지 불가). 기간 종료까지 이용 유지.
  def cancel
    Subscriptions::UpgradeService.new(user: Current.user, action: :cancel).call
    redirect_to app_billing_path, status: :see_other,
                notice: "Plus 구독이 해지되었습니다. 현재 결제 기간까지 이용할 수 있습니다."
  rescue Subscriptions::UpgradeService::UpgradeError => e
    redirect_to app_billing_path, status: :see_other, alert: e.message
  end

  private

  # 쿠폰 적용(ADMIN-4 — Q12) — 서버 검증(존재·활성·만료·한도·0원 방지)만 통과하면 구독에
  # 예약하고, 실제 소비(used_count 증가)는 Plus 첫 차감 성공 시점에 UpgradeService가 한다.
  # 이미 성공한 Plus 결제가 있으면 "첫 결제"가 아니므로 거부한다(적용 1회).
  def apply_coupon
    coupon = Coupon.find_by(code: normalized_coupon_code)
    message =
      if coupon.nil?
        [ :alert, "존재하지 않는 쿠폰 코드입니다. 코드를 확인해 주세요." ]
      elsif Current.user.orders.paid.plus_monthly.exists?
        [ :alert, "쿠폰은 Plus 첫 결제에만 사용할 수 있습니다." ]
      elsif coupon.redeemable?
        subscription.update!(coupon_id: coupon.id)
        [ :notice, coupon_applied_message(coupon) ]
      else
        [ :alert, "이 쿠폰은 사용할 수 없습니다 — #{coupon.unavailability_reason}" ]
      end
    redirect_to app_billing_path, status: :see_other, message[0] => message[1]
  end

  def normalized_coupon_code
    params[:coupon_code].to_s.strip.upcase
  end

  # 현재 구독 행(없으면 즉석 Free 생성 — billings_controller와 동일 폴백).
  def subscription
    Current.user.subscription || Current.user.create_subscription!(plan: :free)
  end

  def coupon_applied_message(coupon)
    discount = Subscription::PLUS_MONTHLY_PRICE - coupon.final_price_for(Subscription::PLUS_MONTHLY_PRICE)
    "쿠폰(#{coupon.code})이 적용되었습니다. Plus 첫 결제에 " \
      "#{ActiveSupport::NumberHelper.number_to_delimited(discount)}원이 할인됩니다."
  end

  # 구독 활성(카드 등록) 성공 + 쿠폰 예약 존재 시 coupon_redeemed 감사(ADMIN-4 추적 — 관리
  # 행위가 아니라 admin 부재로 기록). 실제 used_count 소비는 첫 차감 성공 시점이다.
  def record_coupon_redeemed_audit
    subscription = Current.user.subscription
    return if subscription.blank? || subscription.coupon_id.blank?

    AuditLogs::RecordService.call(action: "coupon_redeemed", target: subscription,
                                  detail: subscription.coupon.code)
  end

  # 카드 인증 위젯이 돌려준 빌링키 발급 토큰(billingIssueToken) — 서버가 포트원
  # /billing-keys/confirm으로 빌링키를 발급한다. 전달 경로는 2종이다(C2): SDK 리다이렉트는
  # 응답 필드명 그대로 billingIssueToken 쿼리로, PC 위젯 Promise 폴백(JS 수동 이동)은
  # issue_token 쿼리로 온다.
  def issue_token
    @issue_token ||= params[:issue_token].presence || params[:billingIssueToken].presence
  end
end
