# 구독 상태 전환(F-PLAN) — create: 체험 시작, update: 카드 등록(빌링키 발급 — 위젯 GET 콜백과
# 수동 PATCH가 발급 토큰 유무로 수렴), cancel: 해지(PATCH 전용). 흐름·가드는
# Subscriptions::UpgradeService가 담당하고 컨트롤러는 진입·응답만 한다.
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
  # 상태 변경으로 이어지지 않는다.
  def update
    Subscriptions::UpgradeService.new(user: Current.user, action: :register_card,
                                      issue_token: issue_token).call
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

  # 카드 인증 위젯이 돌려준 빌링키 발급 토큰(billingIssueToken) — 서버가 포트원
  # /billing-keys/confirm으로 빌링키를 발급한다. 전달 경로는 2종이다(C2): SDK 리다이렉트는
  # 응답 필드명 그대로 billingIssueToken 쿼리로, PC 위젯 Promise 폴백(JS 수동 이동)은
  # issue_token 쿼리로 온다.
  def issue_token
    params[:issue_token].presence || params[:billingIssueToken].presence
  end
end
